module FixtureServer
  ( application,
    runFixtureServer,
  )
where

import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Network.HTTP.Types
  ( hContentType,
    methodDelete,
    methodGet,
    methodPost,
    status200,
    status201,
    status404,
    status405,
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

runFixtureServer :: Int -> IO ()
runFixtureServer port =
  runSettings (setPort port (setHost "127.0.0.1" defaultSettings)) application

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
