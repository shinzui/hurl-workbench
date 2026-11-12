-- | One execution with file captures and bounded process-group cleanup.
module HurlWorkbench.Check.Run
  ( CheckOutcome (..),
    CheckResult (..),
    runCheck,
    runCheckObserved,
    runCheckObservedWith,
    checkPassed,
    checkExitCode,
    checkStatus,
    skippedCheck,
  )
where

import Control.Exception (IOException, SomeException, mask, throwIO, try)
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime, diffUTCTime, getCurrentTime)
import HurlWorkbench.Check.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Process.Run
import HurlWorkbench.Service.Resolve (ServiceError)
import HurlWorkbench.Workspace.Types (CheckName (..), ServiceName (..))
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (Handle, hClose)
import System.Posix.Files (ownerReadMode, ownerWriteMode, setFileMode, unionFileModes)
import System.Posix.IO (OpenFileFlags (..), OpenMode (WriteOnly), defaultFileFlags, fdToHandle, openFd)
import System.Process qualified as Process
import System.Timeout qualified as Timeout

data CheckOutcome = CheckPassed | CheckMismatch | CheckTimedOut | CheckSignalled | CheckCancelled | CheckStartFailed | CheckSkipped !Text
  deriving stock (Generic, Eq, Show)

data CheckResult = CheckResult
  { name :: !CheckName,
    outcome :: !CheckOutcome,
    expectedStatus :: !Int,
    actualStatus :: !(Maybe Int),
    elapsed :: !(Maybe NominalDiffTime),
    stdoutPath :: !(Maybe FilePath),
    stderrPath :: !(Maybe FilePath),
    cleanupDiagnostics :: ![Text]
  }
  deriving stock (Generic, Eq, Show)

-- | Paths are suite-relative; no output, argv, environments or exception text.
skippedCheck :: Text -> ResolvedCheck -> CheckResult
skippedCheck reason check = CheckResult (check ^. #name) (CheckSkipped reason) (check ^. #expectedStatus) Nothing Nothing Nothing Nothing []

checkPassed :: CheckResult -> Bool
checkPassed result = result ^. #outcome == CheckPassed && null (result ^. #cleanupDiagnostics)

checkStatus :: CheckResult -> Text
checkStatus result = case result ^. #outcome of
  CheckPassed | not (null (result ^. #cleanupDiagnostics)) -> "cleanup-failed"
  CheckPassed -> "passed"
  CheckMismatch -> "failed"
  CheckTimedOut -> "timed-out"
  CheckSignalled -> "signalled"
  CheckCancelled -> "cancelled"
  CheckStartFailed -> "start-failed"
  CheckSkipped reason -> reason

checkExitCode :: CheckResult -> ExitCode
checkExitCode result = case result ^. #outcome of
  CheckPassed -> if null (result ^. #cleanupDiagnostics) then ExitSuccess else ExitFailure 3
  CheckMismatch -> ExitFailure (max 1 (fromMaybe 1 (result ^. #actualStatus)))
  CheckTimedOut -> ExitFailure 124
  CheckSignalled -> ExitFailure (128 + abs (fromMaybe 0 (result ^. #actualStatus)))
  CheckCancelled -> ExitFailure 130
  CheckStartFailed -> ExitFailure 3
  CheckSkipped _ -> ExitSuccess

runCheck :: FilePath -> ResolvedCheck -> IO CheckResult
runCheck root check = runCheckObserved root check (const (pure ()))

runCheckObserved :: FilePath -> ResolvedCheck -> (CheckResult -> IO ()) -> IO CheckResult
runCheckObserved root check = runCheckObservedWith (terminateGroup (ServiceName (unCheckName (check ^. #name))) 10) root check

-- | The cleanup action is injectable for fault tests. Production always uses
-- the common ten-second TERM/KILL/reap policy, also after normal leader exit.
runCheckObservedWith :: (OwnedProcess -> IO (Either ServiceError ())) -> FilePath -> ResolvedCheck -> (CheckResult -> IO ()) -> IO CheckResult
runCheckObservedWith cleanup root check observe = mask $ \restore -> do
  began <- getCurrentTime
  let relative = "checks" </> unpackName (check ^. #name)
      out = relative </> "stdout"
      err = relative </> "stderr"
      initial = (skippedCheck "cancelled" check) {outcome = CheckCancelled}
      finish outcome actual diagnostics artifacts = do
        ended <- getCurrentTime
        let result = initial {outcome, actualStatus = actual, elapsed = Just (diffUTCTime ended began), stdoutPath = if artifacts then Just out else Nothing, stderrPath = if artifacts then Just err else Nothing, cleanupDiagnostics = diagnostics}
        observe result
        pure result
  -- O_EXCL creates 0600 files atomically and refuses a replaced capture path.
  allocated <- try @IOException $ do
    stdout <- capture (root </> out)
    stderr <- capture (root </> err) `onIoFailure` hClose stdout
    pure (stdout, stderr)
  case allocated of
    Left _ -> finish CheckStartFailed Nothing [] False
    Right (stdout, stderr) -> do
      let close = hClose stdout >> hClose stderr
      started <- spawnGroup (ServiceName (unCheckName (check ^. #name))) (commandConfig (check ^. #processConfig)) {Process.std_out = Process.UseHandle stdout, Process.std_err = Process.UseHandle stderr}
      case started of
        Left _ -> close >> finish CheckStartFailed Nothing [] True
        Right owned -> do
          now <- getCurrentTime
          let remaining = max 1 (floor (((check ^. #timeout) - diffUTCTime now began) * 1000000))
          executed <- try @SomeException (restore (Timeout.timeout remaining (waitExitCode owned)))
          cleaned <- cleanup owned
          close
          let diagnostics = either (const ["process-group-cleanup-failed"]) (const []) cleaned
          case executed of
            Left exception -> do
              _ <- finish CheckCancelled Nothing diagnostics True
              throwIO exception
            Right Nothing -> finish CheckTimedOut Nothing diagnostics True
            Right (Just status) ->
              let actual = case status of ExitSuccess -> 0; ExitFailure code -> code
                  outcome
                    | actual < 0 = CheckSignalled
                    | actual == check ^. #expectedStatus = CheckPassed
                    | otherwise = CheckMismatch
               in finish outcome (Just actual) diagnostics True
  where
    unpackName = Text.unpack . unCheckName
    capture path = do
      fd <- openFd path WriteOnly defaultFileFlags {creat = Just (ownerReadMode `unionFileModes` ownerWriteMode), exclusive = True, nofollow = True}
      handle <- fdToHandle fd
      setFileMode path (ownerReadMode `unionFileModes` ownerWriteMode)
      pure handle
    onIoFailure action cleanupAction = do
      result <- try @IOException action
      case result of Left exception -> cleanupAction >> throwIO exception; Right value -> pure value
