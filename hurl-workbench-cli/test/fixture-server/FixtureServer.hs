module FixtureServer
  ( application,
    runFixtureServer,
    runFixtureRole,
  )
where

import Control.Concurrent (forkIO, killThread, myThreadId, threadDelay, throwTo)
import Control.Exception (AsyncException (UserInterrupt), bracket, bracket_)
import Control.Monad (forever, when)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as Char8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.IORef (atomicModifyIORef', newIORef)
import Network.HTTP.Types
  ( hContentType,
    methodDelete,
    methodGet,
    methodPost,
    status200,
    status201,
    status404,
    status405,
    status409,
    status503,
  )
import Network.Wai
  ( Application,
    pathInfo,
    queryString,
    requestMethod,
    responseLBS,
    strictRequestBody,
  )
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import System.Directory (doesFileExist, renameFile)
import System.FilePath ((</>))
import System.Posix.Process (getProcessID)
import System.Posix.Signals (Handler (Catch), installHandler, sigTERM)

runFixtureServer :: Int -> IO ()
runFixtureServer port =
  runSettings (setPort port (setHost "127.0.0.1" defaultSettings)) application

-- | Deterministic roles for the public orchestration example. Only the worker
-- writes visibility; the API accepts one command and exposes read-only polling.
runFixtureRole :: String -> Int -> FilePath -> IO ()
runFixtureRole role port root = do
  mainThread <- myThreadId
  _ <- installHandler sigTERM (Catch (throwTo mainThread UserInterrupt)) Nothing
  pid <- getProcessID
  appendFile (root </> "pids") (show pid <> "\n")
  generation <-
    if role == "worker"
      then do
        exists <- doesFileExist (root </> "generation")
        previous <- if exists then read . Char8.unpack <$> ByteString.readFile (root </> "generation") else pure (0 :: Int)
        writeFile (root </> "generation") (show (previous + 1))
        pure (previous + 1)
      else pure 0
  firstHealth <- newIORef True
  let event label = appendFile (root </> "events") (role <> "-" <> label <> "\n")
      project = forever $ do
        accepted <- doesFileExist (root </> "accepted")
        when accepted $ do
          writeFile (root </> "visible.tmp") ("visible:" <> show generation)
          renameFile (root </> "visible.tmp") (root </> "visible")
        threadDelay 10000
      serve request respond = case (requestMethod request, pathInfo request) of
        (method, ["health"]) | method == methodGet -> do
          first <- atomicModifyIORef' firstHealth (\value -> (False, value))
          when first (event "ready")
          respond (responseLBS status200 [] "ok")
        (method, ["command"])
          | role == "api",
            method == methodPost -> do
              exists <- doesFileExist (root </> "accepted")
              if exists
                then respond (responseLBS status409 [] "duplicate")
                else do
                  _ <- strictRequestBody request
                  writeFile (root </> "accepted") "accepted"
                  event "mutation"
                  respond (responseLBS status201 [] "accepted")
        (method, ["read"])
          | role == "api",
            method == methodGet -> do
              event "read"
              exists <- doesFileExist (root </> "visible")
              if exists
                then do
                  visible <- ByteString.readFile (root </> "visible")
                  respond (responseLBS status200 [] (LazyByteString.fromStrict visible))
                else respond (responseLBS status503 [] "pending")
        _ -> respond (responseLBS status404 [] "not found")
      run = runSettings (setPort port (setHost "127.0.0.1" defaultSettings)) serve
  bracket_ (event "start") (event "stop") $
    if role == "worker" then bracket (forkIO project) killThread (const run) else run

application :: Application
application request respond = case (requestMethod request, pathInfo request) of
  (method, ["health"])
    | method == methodGet ->
        respond (text status200 "ok\n")
  (method, ["oauth", "token"])
    | method == methodPost ->
        respond (json status200 "{\"access_token\":\"fixture-token\",\"token_type\":\"Bearer\"}\n")
  (method, ["odata", "echo"])
    | method == methodGet ->
        respond (json status200 (LazyByteString.fromStrict (showQuery (queryString request))))
  (method, ["capture"])
    | method == methodGet ->
        respond (responseLBS status200 [("Content-Type", "text/plain"), ("X-Fixture-Capture", "captured-value")] "capture-body\n")
  (method, ["raw-response"])
    | method == methodGet ->
        respond (responseLBS status200 [("Content-Type", "application/octet-stream"), ("X-Raw", "yes")] "raw\NULbytes\n")
  (method, ["mutating"]) | method == methodPost || method == methodDelete -> do
    body <- strictRequestBody request
    respond (responseLBS status201 [(hContentType, "application/octet-stream")] body)
  (_method, ["mutating"]) ->
    respond (text status405 "method not allowed\n")
  _ -> respond (text status404 "not found\n")
  where
    text status = responseLBS status [(hContentType, "text/plain; charset=utf-8")]
    json status = responseLBS status [(hContentType, "application/json")]

showQuery :: [(ByteString.ByteString, Maybe ByteString.ByteString)] -> ByteString.ByteString
showQuery query =
  "{\"query\":\""
    <> ByteString.intercalate
      "&"
      [name <> maybe "" ("=" <>) value | (name, value) <- query]
    <> "\"}\n"
