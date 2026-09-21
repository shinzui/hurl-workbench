-- | Batch-ready Hurl requests. Bounded scheduling and result aggregation are
--   added by EP-4's second milestone; preparation already targets this type.
module HurlWorkbench.Run.Batch
  ( PositiveInt,
    positiveIntValue,
    BatchOptionError (..),
    mkPositiveInt,
    BatchOptions (..),
    BatchCase (..),
    SkipReason (..),
    CaseOutcome (..),
    CaseResult (..),
    BatchResult (..),
    runBatch,
    runBatchObserved,
  )
where

import Control.Concurrent.Async (replicateConcurrently_)
import Control.Concurrent.STM
  ( TQueue,
    TVar,
    atomically,
    modifyTVar',
    newTQueue,
    newTVar,
    readTVar,
    readTVarIO,
    tryReadTQueue,
    writeTQueue,
    writeTVar,
  )
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Time.Clock (NominalDiffTime)
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Prelude
import System.Exit (ExitCode (..))

newtype PositiveInt = PositiveInt Int
  deriving stock (Generic, Eq, Ord, Show)

positiveIntValue :: PositiveInt -> Int
positiveIntValue (PositiveInt value) = value

data BatchOptionError = NonPositiveJobs !Int
  deriving stock (Generic, Eq, Show)

mkPositiveInt :: Int -> Either BatchOptionError PositiveInt
mkPositiveInt value
  | value > 0 = Right (PositiveInt value)
  | otherwise = Left (NonPositiveJobs value)

data BatchOptions = BatchOptions
  { jobs :: !PositiveInt,
    failFast :: !Bool
  }
  deriving stock (Generic, Eq, Show)

data BatchCase = BatchCase
  { name :: !Text,
    artifactStem :: !FilePath,
    request :: !RunRequest
  }
  deriving stock (Generic, Eq)

instance Show BatchCase where
  show batchCase = "BatchCase " <> show (batchCase ^. #name) <> " <redacted request>"

data SkipReason
  = FailFastTriggered
  | BatchPrerequisiteFailed
  deriving stock (Generic, Eq, Show)

data CaseOutcome
  = CasePassed
  | CaseFailed !ExitCode
  | CaseStartFailed !RunStartError
  | CaseSkipped !SkipReason
  deriving stock (Generic, Eq, Show)

data CaseResult = CaseResult
  { name :: !Text,
    outcome :: !CaseOutcome,
    elapsed :: !(Maybe NominalDiffTime),
    outputPath :: !(Maybe FilePath),
    capturedOutput :: !(Maybe CapturedRunOutput)
  }
  deriving stock (Generic, Eq, Show)

data BatchResult = BatchResult
  { cases :: !(NonEmpty CaseResult),
    selectedExitCode :: !ExitCode
  }
  deriving stock (Generic, Eq, Show)

runBatch :: HurlRunner -> BatchOptions -> NonEmpty BatchCase -> IO BatchResult
runBatch runner options batchCases = runBatchObserved runner options batchCases (\_index _result -> pure ())

-- | Run a batch while publishing each completed case with its declaration
--   index. The observer lets orchestration retain completed outcomes if a
--   prerequisite failure asynchronously cancels the batch.
runBatchObserved :: HurlRunner -> BatchOptions -> NonEmpty BatchCase -> (Int -> CaseResult -> IO ()) -> IO BatchResult
runBatchObserved runner options batchCases observe = do
  queue <- atomically newTQueue
  results <- atomically (newTVar Map.empty)
  stopped <- atomically (newTVar False)
  let indexedCases = zip [0 ..] (NonEmpty.toList batchCases)
      workerCount = min (positiveIntValue (options ^. #jobs)) (length indexedCases)
  atomically (traverse_ (writeTQueue queue) indexedCases)
  replicateConcurrently_ workerCount (worker queue results stopped)
  completed <- readTVarIO results
  let ordered = NonEmpty.fromList (map (caseResult completed) indexedCases)
  pure
    BatchResult
      { cases = ordered,
        selectedExitCode = selectExitCode ordered
      }
  where
    worker queue results stopped =
      nextWork queue stopped >>= \case
        Nothing -> pure ()
        Just (caseIndex, batchCase) -> do
          result <- executeCase runner batchCase
          observe caseIndex result
          atomically $ do
            modifyTVar' results (Map.insert caseIndex result)
            when (options ^. #failFast && caseFailed result) (writeTVar stopped True)
          worker queue results stopped

    nextWork :: TQueue (Int, BatchCase) -> TVar Bool -> IO (Maybe (Int, BatchCase))
    nextWork queue stopped = atomically $ do
      shouldStop <- readTVar stopped
      if shouldStop then pure Nothing else tryReadTQueue queue

    caseResult completed (caseIndex, batchCase) =
      Map.findWithDefault (skippedCase batchCase FailFastTriggered) caseIndex completed

executeCase :: HurlRunner -> BatchCase -> IO CaseResult
executeCase runner batchCase = do
  executed <- runHurl runner (batchCase ^. #request)
  pure $ case executed of
    Left err ->
      CaseResult
        { name = batchCase ^. #name,
          outcome = CaseStartFailed err,
          elapsed = Nothing,
          outputPath = requestOutputPath (batchCase ^. #request),
          capturedOutput = Nothing
        }
    Right result ->
      CaseResult
        { name = batchCase ^. #name,
          outcome = case result ^. #exitCode of
            ExitSuccess -> CasePassed
            failed -> CaseFailed failed,
          elapsed = Just (result ^. #elapsed),
          outputPath = requestOutputPath (batchCase ^. #request),
          capturedOutput = result ^. #capturedOutput
        }

skippedCase :: BatchCase -> SkipReason -> CaseResult
skippedCase batchCase reason =
  CaseResult
    { name = batchCase ^. #name,
      outcome = CaseSkipped reason,
      elapsed = Nothing,
      outputPath = requestOutputPath (batchCase ^. #request),
      capturedOutput = Nothing
    }

requestOutputPath :: RunRequest -> Maybe FilePath
requestOutputPath request = case request ^. #outputPolicy of
  ResponseFile path -> Just path
  _ -> Nothing

caseFailed :: CaseResult -> Bool
caseFailed result = case result ^. #outcome of
  CasePassed -> False
  _ -> True

selectExitCode :: NonEmpty CaseResult -> ExitCode
selectExitCode results =
  fromMaybe fallback (firstFailure (NonEmpty.toList results))
  where
    fallback
      | all (not . caseFailed) results = ExitSuccess
      | otherwise = ExitFailure 3

    firstFailure = \case
      [] -> Nothing
      result : remaining -> case result ^. #outcome of
        CaseFailed exitCode -> Just exitCode
        CaseStartFailed _ -> Just (ExitFailure 3)
        CasePassed -> firstFailure remaining
        CaseSkipped _ -> firstFailure remaining
