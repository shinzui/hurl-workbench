-- | Dynamic group membership is the monitor generation. Removing an entry and
-- observing its exit happen in one STM transaction; no stale monitor can target
-- a replacement acquired by Restart.
module HurlWorkbench.Service.Group
  ( ServiceGroup,
    LifecycleOutcome (..),
    newServiceGroup,
    startNamed,
    startNamedObserved,
    stopNamed,
    applyServiceStep,
    applyServiceStepObserved,
    watchServices,
    cleanupServices,
  )
where

import Control.Concurrent.Async (race)
import Control.Concurrent.STM
import Control.Exception (mask)
import Data.Generics.Labels ()
import Data.Time.Clock (NominalDiffTime, diffUTCTime, getCurrentTime)
import HurlWorkbench.Prelude
import HurlWorkbench.Process.Run
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Service.Run (awaitService)
import HurlWorkbench.Workspace.Types (ServiceName (..), ServiceStep (..))
import System.Process.Typed (getExitCodeSTM, waitExitCodeSTM)

-- Newest acquisition first, including services still in readiness.
data Entry = Entry !ResolvedService !OwnedProcess !Bool

newtype ServiceGroup = ServiceGroup (TVar [Entry])

data LifecycleOutcome = LifecycleOutcome
  { name :: !ServiceName,
    action :: !Text,
    status :: !Text,
    elapsed :: !NominalDiffTime,
    failure :: !(Maybe ServiceError)
  }
  deriving stock (Generic, Eq, Show)

newServiceGroup :: IO ServiceGroup
newServiceGroup = ServiceGroup <$> newTVarIO []

unexpected :: ServiceGroup -> STM ServiceError
unexpected (ServiceGroup entries) = do
  active <- readTVar entries
  foldr
    orElse
    retry
    [ ServiceExitedDuringCallback (service ^. #name) <$> waitExitCodeSTM (owned ^. #process)
    | Entry service owned True <- active
    ]

watchServices :: ServiceGroup -> IO (Either ServiceError a) -> IO (Either ServiceError a)
watchServices group action = race (atomically (unexpected group)) action <&> either Left id

startNamed :: ServiceGroup -> ResolvedService -> IO (Either ServiceError ())
startNamed group service = startNamedObserved group service (const (pure ()))

startNamedObserved :: ServiceGroup -> ResolvedService -> (LifecycleOutcome -> IO ()) -> IO (Either ServiceError ())
startNamedObserved group@(ServiceGroup entries) service observe = mask $ \restore -> do
  began <- getCurrentTime
  let emit action began_ result = do
        ended <- getCurrentTime
        observe (LifecycleOutcome (service ^. #name) action (either (const "failed") (const "passed") result) (diffUTCTime ended began_) (either Just (const Nothing) result))
  spawnGroup (service ^. #name) (commandConfig (service ^. #processConfig)) >>= \case
    Left err -> emit "start" began (Left err) >> pure (Left err)
    Right owned -> do
      -- Ownership is registered before readiness becomes interruptible.
      atomically (modifyTVar' entries (Entry service owned False :))
      emit "start" began (Right ())
      readyBegan <- getCurrentTime
      result <- restore (watchServices group (awaitService service owned))
      emit "readiness" readyBegan result
      case result of
        Left err -> pure (Left err)
        Right () -> do
          atomically (modifyTVar' entries (map (markReady (owned ^. #processId))))
          pure (Right ())
  where
    markReady pid entry@(Entry definition process _) =
      if process ^. #processId == pid then Entry definition process True else entry

stopNamed :: ServiceGroup -> ServiceName -> IO (Either ServiceError ())
stopNamed (ServiceGroup entries) name = mask $ \_ -> do
  retired <- atomically $ do
    active <- readTVar entries
    -- Check every current leader before retiring the intentional generation.
    exits <- for active $ \(Entry service owned ready) -> do
      exitCode <- getExitCodeSTM (owned ^. #process)
      pure [ServiceExitedDuringCallback (service ^. #name) code | ready, Just code <- [exitCode]]
    case concat exits of
      err : _ -> pure (Left err)
      [] -> case [entry | entry@(Entry service _ _) <- active, service ^. #name == name] of
        [] -> pure (Left (ServiceShutdownFailed name Nothing "service is not running"))
        entry : _ -> do
          -- Keep ownership until termination finishes, but retire the monitor.
          modifyTVar' entries (map (\entry_@(Entry service owned _) -> if service ^. #name == name then Entry service owned False else entry_))
          pure (Right entry)
  case retired of
    Left err -> pure (Left err)
    Right (Entry service owned _) -> do
      result <- terminateGroup name (service ^. #shutdownTimeout) owned
      case result of
        Left err -> pure (Left err)
        Right () -> do
          atomically (modifyTVar' entries (filter (\(Entry _ process _) -> process ^. #processId /= owned ^. #processId)))
          pure (Right ())

applyServiceStep :: ServiceGroup -> [ResolvedService] -> ServiceStep -> IO (Either ServiceError ())
applyServiceStep group definitions operation = applyServiceStepObserved group definitions operation (const (pure ()))

applyServiceStepObserved :: ServiceGroup -> [ResolvedService] -> ServiceStep -> (LifecycleOutcome -> IO ()) -> IO (Either ServiceError ())
applyServiceStepObserved group definitions operation observe = case operation of
  Stop name -> watchServices group (stop name)
  Start name -> watchServices group (start name)
  Restart name ->
    watchServices group $
      stop name >>= \case
        Left err -> pure (Left err)
        Right () -> start name
  where
    stop name = do
      began <- getCurrentTime
      result <- stopNamed group name
      ended <- getCurrentTime
      observe (LifecycleOutcome name "stop" (either (const "failed") (const "passed") result) (diffUTCTime ended began) (either Just (const Nothing) result))
      pure result
    start name = case filter ((== name) . view #name) definitions of
      service : _ -> startNamedObserved group service observe
      [] -> pure (Left (ServiceProcessIdUnavailable name))

cleanupServices :: ServiceGroup -> IO [LifecycleOutcome]
cleanupServices (ServiceGroup entries) = do
  active <- readTVarIO entries
  results <- for active $ \(Entry service owned _) -> do
    began <- getCurrentTime
    result <- terminateGroup (service ^. #name) (service ^. #shutdownTimeout) owned
    ended <- getCurrentTime
    pure (LifecycleOutcome (service ^. #name) "cleanup" (either (const "failed") (const "passed") result) (diffUTCTime ended began) (either Just (const Nothing) result))
  atomically (writeTVar entries [])
  pure results
