-- | Acquire a POSIX group ID before any waiter can reap the leader. All owned
-- output handles are caller-managed files, so termination never waits on a pipe.
module HurlWorkbench.Process.Run
  ( OwnedProcess (..),
    spawnGroup,
    terminateGroup,
    commandConfig,
    runCommand,
    CommandOutcome (..),
    getExitCode,
    waitExitCode,
    getExitCodeSTM,
    waitExitCodeSTM,
  )
where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (Async, asyncWithUnmask, wait)
import Control.Concurrent.STM
import Control.Exception (IOException, displayException, mask, onException, try)
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime, addUTCTime, getCurrentTime)
import HurlWorkbench.Prelude
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Workspace.Types (ServiceName)
import System.Exit (ExitCode (..))
import System.IO (Handle, IOMode (ReadWriteMode), withBinaryFile)
import System.IO.Error (isDoesNotExistError)
import System.Posix.Signals (nullSignal, sigKILL, sigTERM, signalProcessGroup)
import System.Posix.Types (ProcessID)
import System.Process qualified as Process
import System.Timeout qualified as Timeout

data OwnedProcess = OwnedProcess
  { processId :: !ProcessID,
    completion :: !(TMVar (Either IOException ExitCode)),
    reaper :: !(Async ())
  }
  deriving stock (Generic)

data CommandOutcome = CommandPassed | CommandFailed | CommandTimedOut | CommandStartFailed | CommandSkipped | CommandCancelled
  deriving stock (Generic, Eq, Show)

commandConfig :: ResolvedCommand -> Process.CreateProcess
commandConfig command =
  (Process.proc (command ^. #executable) (command ^. #arguments))
    { Process.create_group = True,
      Process.std_in = Process.NoStream,
      Process.std_out = Process.NoStream,
      Process.std_err = Process.NoStream,
      Process.cwd = Just (command ^. #workingDirectory),
      Process.env = Just (command ^. #environment)
    }

spawnGroup :: ServiceName -> Process.CreateProcess -> IO (Either ServiceError OwnedProcess)
spawnGroup name config = mask $ \_ -> do
  -- createProcess_ leaves UseHandle inputs open in the parent. No pipe handles
  -- or background waiter exist until the immutable group ID has been captured.
  started <- try @IOException $ withBinaryFile "/dev/null" ReadWriteMode $ \nullHandle -> do
    let output stream = case stream of Process.NoStream -> Process.UseHandle nullHandle; other -> other
    (_, _, _, handle) <-
      Process.createProcess_
        "owned process"
        config
          { Process.create_group = True,
            Process.std_out = output (Process.std_out config),
            Process.std_err = output (Process.std_err config)
          }
    pure handle
  case started of
    Left _ -> pure (Left (ServiceSpawnFailed "<redacted>" "process launch failed"))
    Right handle ->
      Process.getPid handle >>= \case
        Nothing -> do
          _ <- Timeout.timeout 1000000 (Process.terminateProcess handle >> Process.waitForProcess handle)
          pure (Left (ServiceProcessIdUnavailable name))
        Just pid -> do
          completion <- newEmptyTMVarIO
          reaper <- asyncWithUnmask $ \unmask -> do
            result <- try @IOException (unmask (Process.waitForProcess handle))
            atomically (putTMVar completion result)
          pure (Right (OwnedProcess pid completion reaper))

waitExitCodeSTM :: OwnedProcess -> STM ExitCode
waitExitCodeSTM owned = readTMVar (owned ^. #completion) >>= either throwSTM pure

getExitCodeSTM :: OwnedProcess -> STM (Maybe ExitCode)
getExitCodeSTM owned = tryReadTMVar (owned ^. #completion) >>= traverse (either throwSTM pure)

waitExitCode :: OwnedProcess -> IO ExitCode
waitExitCode = atomically . waitExitCodeSTM

getExitCode :: OwnedProcess -> IO (Maybe ExitCode)
getExitCode = atomically . getExitCodeSTM

-- | TERM and KILL address the group even if the leader has already exited.
-- The finite budget includes leader reaping and joining its one waiter.
terminateGroup :: ServiceName -> NominalDiffTime -> OwnedProcess -> IO (Either ServiceError ())
terminateGroup name budget owned = do
  attempted <- try @IOException terminate
  pure (either (const (Left failure)) id attempted)
  where
    failure = ServiceShutdownFailed name (Just (owned ^. #processId)) "process group cleanup failed or timed out"
    terminate = do
      finished <- Timeout.timeout micros $ do
        term <- signal sigTERM
        began <- getCurrentTime
        gone <- waitGroup (addUTCTime (budget / 2) began)
        killed <- if gone then pure "" else signal sigKILL
        _ <- waitExitCode owned
        wait (owned ^. #reaper)
        pure (term <> killed)
      pure $ case finished of
        Just "" -> Right ()
        Just message -> Left (ServiceShutdownFailed name (Just (owned ^. #processId)) message)
        Nothing -> Left failure
    micros = max 1 (floor (budget * 1000000))
    signal sig =
      try @IOException (signalProcessGroup sig (owned ^. #processId)) >>= \case
        Right () -> pure ""
        Left err | isDoesNotExistError err -> pure ""
        Left err -> do
          -- Darwin can report EPERM while an empty group is disappearing. Only
          -- suppress the failed signal once ESRCH positively confirms absence;
          -- a group that still exists or remains uncertain is a cleanup failure.
          vanished <- Timeout.timeout (max 1 (min 10000 (micros `div` 4))) confirmAbsent
          pure $ if vanished == Just True then "" else (if sig == sigTERM then "SIGTERM: " else "SIGKILL: ") <> Text.pack (displayException err)
    confirmAbsent =
      try @IOException (signalProcessGroup nullSignal (owned ^. #processId)) >>= \case
        Left err | isDoesNotExistError err -> pure True
        Left _ -> threadDelay 1000 >> confirmAbsent
        Right () -> threadDelay 1000 >> confirmAbsent
    waitGroup deadline = do
      alive <- try @IOException (signalProcessGroup nullSignal (owned ^. #processId))
      now <- getCurrentTime
      case alive of
        Left err | isDoesNotExistError err -> pure True
        Left _ -> pure False
        Right () | now >= deadline -> pure False
        Right () -> threadDelay 10000 >> waitGroup deadline

runCommand :: ServiceName -> NominalDiffTime -> ResolvedCommand -> Handle -> Handle -> IO (CommandOutcome, Maybe ServiceError)
runCommand name budget command stdout stderr = mask $ \restore -> do
  spawnGroup name (commandConfig command) {Process.std_out = Process.UseHandle stdout, Process.std_err = Process.UseHandle stderr} >>= \case
    Left _ -> pure (CommandStartFailed, Nothing)
    Right owned -> do
      let cleanupBudget = min 1 (budget / 4)
          cleanup = terminateGroup name cleanupBudget owned
      result <- restore (Timeout.timeout (max 1 (floor ((budget - cleanupBudget) * 1000000))) (waitExitCode owned)) `onException` void cleanup
      shutdown <- cleanup
      pure (case result of Just ExitSuccess -> CommandPassed; Just _ -> CommandFailed; Nothing -> CommandTimedOut, either Just (const Nothing) shutdown)
