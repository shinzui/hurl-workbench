-- | POSIX process-group lifecycle and readiness probes for one managed
--   service. Cleanup always completes before callback exceptions are rethrown.
module HurlWorkbench.Service.Run
  ( ServiceHandle,
    serviceProcessId,
    withService,
    freezeService,
    awaitService,
    prepareCommand,
  )
where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (race)
import Control.Exception (SomeException, finally, mask, throwIO, try)
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, diffUTCTime, getCurrentTime)
import HurlWorkbench.Prelude
import HurlWorkbench.Process.Run
import HurlWorkbench.Service.Environment (selectEnvironment)
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Workspace.Types (EnvironmentPolicy (..), ServiceName (..))
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
import System.Posix.Types (ProcessID)
import System.Process.Typed
  ( Process,
    getExitCode,
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
  case prepareCommand ambient (service ^. #name) "command" (service ^. #processConfig) of
    Left err -> pure (Left err)
    Right command -> do
      preparedReadiness <- prepareReadiness ambient (service ^. #name) (service ^. #readiness)
      case preparedReadiness of
        Left err -> pure (Left err)
        Right readiness -> launch restore command readiness
  where
    launch restore command readiness = do
      spawnGroup (service ^. #name) (commandConfig command) >>= \case
        Left err -> pure (Left err)
        Right owned -> do
          execution <- try @SomeException (restore (runLifecycle service readiness (owned ^. #process) (owned ^. #processId) callback))
          shutdown <- terminateGroup (service ^. #name) (service ^. #shutdownTimeout) owned
          case execution of
            Left exception -> throwIO exception
            Right (Left err) -> pure (Left err)
            Right (Right value) -> pure (value <$ shutdown)

awaitService :: ResolvedService -> OwnedProcess -> IO (Either ServiceError ())
awaitService service owned = do
  prepared <- prepareReadiness [] (service ^. #name) (service ^. #readiness)
  case prepared of
    Left err -> pure (Left err)
    Right readiness -> awaitReadiness service readiness (owned ^. #process)

runLifecycle :: ResolvedService -> PreparedReadiness -> Process () () () -> ProcessID -> (ServiceHandle -> IO a) -> IO (Either ServiceError a)
runLifecycle service readiness process pid callback =
  awaitReadiness service readiness process >>= \case
    Left err -> pure (Left err)
    Right () ->
      race
        (callback ServiceHandle {name = unServiceName (service ^. #name), processId = pid})
        (waitExitCode process)
        <&> \case
          Left value -> Right value
          Right exitCode -> Left (ServiceExitedDuringCallback (service ^. #name) exitCode)

prepareReadiness :: [(String, String)] -> ServiceName -> ResolvedReadiness -> IO (Either ServiceError PreparedReadiness)
prepareReadiness _ambient _name (ResolvedHttpReadiness url expectedStatus interval timeout) = do
  parsed <- try @HttpException (parseRequest (Text.unpack url))
  case parsed of
    Left _ -> pure (Left (ServiceReadinessInvalidUrl "<redacted>" "URL could not be parsed"))
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
prepareReadiness ambient name (ResolvedCommandReadiness command interval timeout) =
  pure ((\prepared -> PreparedCommandReadiness prepared interval timeout) <$> prepareCommand ambient name "readiness command" command)

prepareCommand :: [(String, String)] -> ServiceName -> Text -> ResolvedCommand -> Either ServiceError ResolvedCommand
prepareCommand ambient name phase command =
  case selectEnvironment (command ^. #environmentPolicy) ambient (command ^. #environment) of
    Left missing -> Left (ServiceEnvironmentMissing name phase missing)
    Right selected -> Right (command & #environment .~ selected & #environmentPolicy .~ Clean [])

freezeService :: [(String, String)] -> ResolvedService -> IO (Either ServiceError ResolvedService)
freezeService ambient service = case prepareCommand ambient (service ^. #name) "command" (service ^. #processConfig) of
  Left err -> pure (Left err)
  Right command ->
    prepareReadiness ambient (service ^. #name) (service ^. #readiness)
      <&> fmap
        ( \prepared ->
            service & #processConfig .~ command & #readiness .~ case prepared of
              PreparedCommandReadiness probe interval timeout -> ResolvedCommandReadiness probe interval timeout
              PreparedHttpReadiness {} -> service ^. #readiness
        )

awaitReadiness :: ResolvedService -> PreparedReadiness -> Process () () () -> IO (Either ServiceError ())
awaitReadiness service readiness process = do
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
              attempted <- Timeout.timeout (remainingMicroseconds now deadline) (probeReadiness readiness)
              case attempted of
                Nothing -> pure (Left (ServiceReadinessTimedOut (service ^. #name)))
                Just (Left err) -> pure (Left err)
                Just (Right True) ->
                  getExitCode process <&> \case
                    Just exitCode -> Left (ServiceExitedBeforeReady (service ^. #name) exitCode)
                    Nothing -> Right ()
                Just (Right False) -> threadDelay (readinessInterval readiness) >> loop deadline

probeReadiness :: PreparedReadiness -> IO (Either ServiceError Bool)
probeReadiness (PreparedHttpReadiness manager request expected _interval _timeout) = do
  attempted <- try @HttpException (httpNoBody request manager)
  pure (Right (either (const False) ((== expected) . statusCode . responseStatus) attempted))
probeReadiness (PreparedCommandReadiness command _interval timeout) = mask $ \restore -> do
  spawnGroup (ServiceName "readiness") (commandConfig command) >>= \case
    Left _ -> pure (Left (ServiceReadinessProbeStartFailed "<redacted>" "process launch failed"))
    Right owned -> do
      exitCode <- restore (waitExitCode (owned ^. #process)) `finally` void (terminateGroup (ServiceName "readiness") (min 1 timeout) owned)
      pure (Right (exitCode == ExitSuccess))

readinessInterval :: PreparedReadiness -> Int
readinessInterval = \case
  PreparedHttpReadiness _ _ _ interval _ -> interval
  PreparedCommandReadiness _ interval _ -> interval

readinessTimeout :: PreparedReadiness -> NominalDiffTime
readinessTimeout = \case
  PreparedHttpReadiness _ _ _ _ timeout -> timeout
  PreparedCommandReadiness _ _ timeout -> timeout

remainingMicroseconds :: UTCTime -> UTCTime -> Int
remainingMicroseconds now deadline = max 1 (floor (diffUTCTime deadline now * 1000000))
