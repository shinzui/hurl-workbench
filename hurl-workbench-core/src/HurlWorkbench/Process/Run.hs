-- | Own a POSIX process group independently of the lifetime of its leader.
module HurlWorkbench.Process.Run
  ( OwnedProcess (..),
    spawnGroup,
    terminateGroup,
    commandConfig,
    runCommand,
    CommandOutcome (..),
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, displayException, mask, onException, try)
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime, addUTCTime, getCurrentTime)
import HurlWorkbench.Prelude
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Workspace.Types (ServiceName)
import System.IO (Handle)
import System.IO.Error (isDoesNotExistError)
import System.Posix.Signals (nullSignal, sigKILL, sigTERM, signalProcessGroup)
import System.Posix.Types (ProcessID)
import System.Process.Typed
import System.Timeout qualified as Timeout

data OwnedProcess = OwnedProcess
  {process :: !(Process () () ()), processId :: !ProcessID}
  deriving stock (Generic)

data CommandOutcome = CommandPassed | CommandFailed | CommandTimedOut | CommandStartFailed | CommandSkipped | CommandCancelled
  deriving stock (Generic, Eq, Show)

commandConfig :: ResolvedCommand -> ProcessConfig () () ()
commandConfig command =
  setCreateGroup True
    . setStdin closed
    . setStdout nullStream
    . setStderr nullStream
    . setWorkingDir (command ^. #workingDirectory)
    . setEnv (command ^. #environment)
    $ proc (command ^. #executable) (command ^. #arguments)

spawnGroup :: ServiceName -> ProcessConfig () () () -> IO (Either ServiceError OwnedProcess)
spawnGroup name config = mask $ \_ -> do
  started <- try @IOException (startProcess config)
  case started of
    Left _ -> pure (Left (ServiceSpawnFailed "<redacted>" "process launch failed"))
    Right process ->
      getPid process >>= \case
        Just pid -> pure (Right (OwnedProcess process pid))
        Nothing -> do
          _ <- Timeout.timeout 1000000 (stopProcess process)
          pure (Left (ServiceProcessIdUnavailable name))

-- | TERM and KILL address the group even if the leader has already exited.
-- The finite budget includes leader reaping and typed-process finalization.
terminateGroup :: ServiceName -> NominalDiffTime -> OwnedProcess -> IO (Either ServiceError ())
terminateGroup name budget owned = do
  attempted <- try @IOException (terminate)
  pure (either (const (Left failure)) id attempted)
  where
    failure = ServiceShutdownFailed name (Just (owned ^. #processId)) "process group cleanup failed or timed out"
    terminate = do
      finished <- Timeout.timeout micros $ do
        term <- signal sigTERM
        began <- getCurrentTime
        gone <- waitGroup (addUTCTime (budget / 2) began)
        killed <- if gone then pure "" else signal sigKILL
        _ <- waitExitCode (owned ^. #process)
        stopProcess (owned ^. #process)
        pure (term <> killed)
      pure $ case finished of
        Just "" -> Right ()
        Just message -> Left (ServiceShutdownFailed name (Just (owned ^. #processId)) message)
        Nothing -> Left failure
    micros = max 1 (floor (budget * 1000000))
    signal sig = try @IOException (signalProcessGroup sig (owned ^. #processId)) <&> either (\err -> if isDoesNotExistError err then "" else Text.pack (displayException err)) (const "")
    waitGroup deadline = do
      alive <- try @IOException (signalProcessGroup nullSignal (owned ^. #processId))
      now <- getCurrentTime
      case alive of
        Left _ -> pure True
        Right () | now >= deadline -> pure False
        Right () -> threadDelay 10000 >> waitGroup deadline

-- | File handles live outside the process bracket; cancellation kills descendants
-- before the caller closes captures. No captured text is returned or replayed.
runCommand :: ServiceName -> NominalDiffTime -> ResolvedCommand -> Handle -> Handle -> IO (CommandOutcome, Maybe ServiceError)
runCommand name budget command stdout stderr = mask $ \restore -> do
  spawnGroup name (setStdout (useHandleOpen stdout) . setStderr (useHandleOpen stderr) $ commandConfig command) >>= \case
    Left _ -> pure (CommandStartFailed, Nothing)
    Right owned -> do
      let cleanupBudget = min 1 (budget / 4)
          cleanup = terminateGroup name cleanupBudget owned
      result <- restore (Timeout.timeout (max 1 (floor ((budget - cleanupBudget) * 1000000))) (waitExitCode (owned ^. #process))) `onException` void cleanup
      shutdown <- cleanup
      pure (case result of Just ExitSuccess -> CommandPassed; Just _ -> CommandFailed; Nothing -> CommandTimedOut, either Just (const Nothing) shutdown)
