-- | POSIX process-group lifecycle and readiness probes for one managed
--   service. Cleanup always completes before callback exceptions are rethrown.
module HurlWorkbench.Service.Run
  ( ServiceHandle,
    serviceProcessId,
    withService,
  )
where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (race)
import Control.Exception (IOException, SomeException, displayException, mask, throwIO, try)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, diffUTCTime, getCurrentTime)
import HurlWorkbench.Prelude
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Workspace.Types (ServiceName (..))
import Network.HTTP.Client
  ( HttpException,
    Manager,
    Request (responseTimeout),
    defaultManagerSettings,
    httpNoBody,
    newManager,
    parseRequest,
    responseStatus,
    responseTimeoutMicro,
  )
import Network.HTTP.Types.Status (statusCode)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.Posix.Signals (sigKILL, sigTERM, signalProcessGroup)
import System.Posix.Types (ProcessID)
import System.Process.Typed
  ( Process,
    ProcessConfig,
    closed,
    getExitCode,
    getPid,
    proc,
    runProcess,
    setCreateGroup,
    setEnv,
    setStdin,
    setWorkingDir,
    startProcess,
    stopProcess,
    waitExitCode,
  )
import System.Timeout qualified as Timeout

data ServiceHandle = ServiceHandle
  { name :: !Text,
    processId :: !ProcessID
  }
  deriving stock (Generic, Eq, Show)

serviceProcessId :: ServiceHandle -> ProcessID
serviceProcessId = view #processId

data PreparedReadiness
  = PreparedHttpReadiness !Manager !Request !Int !Int !NominalDiffTime
  | PreparedCommandReadiness !ResolvedCommand !Int !NominalDiffTime

withService :: ResolvedService -> (ServiceHandle -> IO a) -> IO (Either ServiceError a)
withService service callback = mask $ \restore -> do
  ambient <- getEnvironment
  preparedReadiness <- prepareReadiness ambient (service ^. #readiness)
  case preparedReadiness of
    Left err -> pure (Left err)
    Right readiness -> do
      started <- try @IOException (startProcess (serviceProcessConfig ambient (service ^. #processConfig)))
      case started of
        Left err -> pure (Left (ServiceSpawnFailed (service ^. #processConfig . #executable) (Text.pack (displayException err))))
        Right process -> do
          processId <- getPid process
          case processId of
            Nothing -> do
              _ <- try @SomeException (stopProcess process)
              pure (Left (ServiceProcessIdUnavailable (service ^. #name)))
            Just pid -> do
              execution <- try @SomeException (restore (runLifecycle ambient service readiness process pid callback))
              shutdown <- shutdownService service process pid
              case execution of
                Left exception -> throwIO exception
                Right result -> pure $ case shutdown of
                  Left err -> Left err
                  Right () -> result

runLifecycle :: [(String, String)] -> ResolvedService -> PreparedReadiness -> Process () () () -> ProcessID -> (ServiceHandle -> IO a) -> IO (Either ServiceError a)
runLifecycle ambient service readiness process pid callback =
  awaitReadiness ambient service readiness process >>= \case
    Left err -> pure (Left err)
    Right () ->
      race
        (callback ServiceHandle {name = unServiceName (service ^. #name), processId = pid})
        (waitExitCode process)
        <&> \case
          Left value -> Right value
          Right exitCode -> Left (ServiceExitedDuringCallback (service ^. #name) exitCode)

prepareReadiness :: [(String, String)] -> ResolvedReadiness -> IO (Either ServiceError PreparedReadiness)
prepareReadiness _ambient (ResolvedHttpReadiness url expectedStatus interval timeout) = do
  parsed <- try @HttpException (parseRequest (Text.unpack url))
  case parsed of
    Left err -> pure (Left (ServiceReadinessInvalidUrl url (Text.pack (displayException err))))
    Right request -> do
      manager <- newManager defaultManagerSettings
      let withTimeout = request {responseTimeout = responseTimeoutMicro 1000000}
      pure
        ( Right
            ( PreparedHttpReadiness
                manager
                withTimeout
                expectedStatus
                interval
                timeout
            )
        )
prepareReadiness _ambient (ResolvedCommandReadiness command interval timeout) =
  pure
    ( Right
        ( PreparedCommandReadiness
            command
            interval
            timeout
        )
    )

awaitReadiness :: [(String, String)] -> ResolvedService -> PreparedReadiness -> Process () () () -> IO (Either ServiceError ())
awaitReadiness ambient service readiness process = do
  began <- getCurrentTime
  let deadline = addUTCTime (readinessTimeout readiness) began
  loop deadline
  where
    loop deadline = do
      getExitCode process >>= \case
        Just exitCode -> pure (Left (ServiceExitedBeforeReady (service ^. #name) exitCode))
        Nothing -> do
          now <- getCurrentTime
          if now >= deadline
            then pure (Left (ServiceReadinessTimedOut (service ^. #name)))
            else do
              attempted <- Timeout.timeout (remainingMicroseconds now deadline) (probeReadiness ambient readiness)
              case attempted of
                Nothing -> pure (Left (ServiceReadinessTimedOut (service ^. #name)))
                Just (Left err) -> pure (Left err)
                Just (Right True) -> pure (Right ())
                Just (Right False) -> threadDelay (readinessInterval readiness) >> loop deadline

probeReadiness :: [(String, String)] -> PreparedReadiness -> IO (Either ServiceError Bool)
probeReadiness _ambient (PreparedHttpReadiness manager request expected _interval _timeout) = do
  attempted <- try @HttpException (httpNoBody request manager)
  pure (Right (either (const False) ((== expected) . statusCode . responseStatus) attempted))
probeReadiness ambient (PreparedCommandReadiness command _interval _timeout) = do
  attempted <- try @IOException (runProcess (readinessProcessConfig ambient command))
  pure $ case attempted of
    Left err -> Left (ServiceReadinessProbeStartFailed (command ^. #executable) (Text.pack (displayException err)))
    Right ExitSuccess -> Right True
    Right (ExitFailure _) -> Right False

readinessInterval :: PreparedReadiness -> Int
readinessInterval = \case
  PreparedHttpReadiness _ _ _ interval _ -> interval
  PreparedCommandReadiness _ interval _ -> interval

readinessTimeout :: PreparedReadiness -> NominalDiffTime
readinessTimeout = \case
  PreparedHttpReadiness _ _ _ _ timeout -> timeout
  PreparedCommandReadiness _ _ timeout -> timeout

serviceProcessConfig :: [(String, String)] -> ResolvedCommand -> ProcessConfig () () ()
serviceProcessConfig ambient command =
  setCreateGroup True
    . setStdin closed
    . setWorkingDir (command ^. #workingDirectory)
    . setEnv (overlayEnvironment ambient (command ^. #environment))
    $ proc (command ^. #executable) (command ^. #arguments)

readinessProcessConfig :: [(String, String)] -> ResolvedCommand -> ProcessConfig () () ()
readinessProcessConfig ambient command =
  setStdin closed
    . setWorkingDir (command ^. #workingDirectory)
    . setEnv (overlayEnvironment ambient (command ^. #environment))
    $ proc (command ^. #executable) (command ^. #arguments)

overlayEnvironment :: [(String, String)] -> [(String, String)] -> [(String, String)]
overlayEnvironment ambient overrides =
  Map.toAscList (Map.fromList overrides `Map.union` Map.fromList ambient)

shutdownService :: ResolvedService -> Process () () () -> ProcessID -> IO (Either ServiceError ())
shutdownService service process pid = do
  alreadyExited <- getExitCode process
  case alreadyExited of
    Just _ -> finishCleanup
    Nothing -> do
      termSignal <- try @IOException (signalProcessGroup sigTERM pid)
      waited <- Timeout.timeout timeoutMicros (waitExitCode process)
      case waited of
        Just _ -> finishCleanup
        Nothing -> do
          killSignal <- try @IOException (signalProcessGroup sigKILL pid)
          killed <- Timeout.timeout timeoutMicros (waitExitCode process)
          case killed of
            Just _ -> finishCleanup
            Nothing ->
              pure
                ( Left
                    ( ServiceShutdownFailed
                        (service ^. #name)
                        (Just pid)
                        (signalDetails termSignal killSignal <> "service did not exit after SIGKILL")
                    )
                )
  where
    timeoutMicros = max 1 (floor ((service ^. #shutdownTimeout) * 1000000))
    finishCleanup = do
      cleaned <- try @SomeException (stopProcess process)
      pure $ case cleaned of
        Left err -> Left (ServiceShutdownFailed (service ^. #name) (Just pid) (Text.pack (displayException err)))
        Right () -> Right ()

signalDetails :: Either IOException () -> Either IOException () -> Text
signalDetails termSignal killSignal =
  Text.concat
    [ either (\err -> "SIGTERM failed: " <> Text.pack (displayException err) <> "; ") (const "") termSignal,
      either (\err -> "SIGKILL failed: " <> Text.pack (displayException err) <> "; ") (const "") killSignal
    ]

remainingMicroseconds :: UTCTime -> UTCTime -> Int
remainingMicroseconds now deadline = max 1 (floor (diffUTCTime deadline now * 1000000))
