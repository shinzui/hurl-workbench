module Main (main) where

import FixtureServer (runFixtureRole, runFixtureServer)
import System.Environment (getArgs, getEnvironment, lookupEnv)
import Text.Read (readMaybe)

main :: IO ()
main = do
  arguments <- getArgs
  case arguments of
    ["--role", role, "--port", value, "--state-dir", root] | role `elem` ["api", "stub", "worker"] ->
      case readMaybe value of
        Just port | port > 0 && port <= 65535 -> runFixtureRole role port root
        _ -> ioError (userError "invalid role port")
    _ -> runDefault arguments

runDefault :: [String] -> IO ()
runDefault arguments = do
  if arguments == ["--assert-clean"]
    then do
      environment <- getEnvironment
      if filter (/= "__CF_USER_TEXT_ENCODING") (map fst environment) == ["PORT"] then pure () else ioError (userError "unexpected clean fixture environment names")
    else pure ()
  environmentPort <- lookupEnv "PORT"
  case parsePort arguments environmentPort of
    Left message -> ioError (userError message)
    Right port -> runFixtureServer port

parsePort :: [String] -> Maybe String -> Either String Int
parsePort arguments environmentPort = case arguments of
  ["--assert-clean"] -> maybe (Right 18080) readPort environmentPort
  [] -> maybe (Right 18080) readPort environmentPort
  ["--port", value] -> readPort value
  _ -> Left "usage: hurl-workbench-fixture-server [--port PORT]"
  where
    readPort value = case readMaybe value of
      Just port | port > 0 && port <= 65535 -> Right port
      _ -> Left ("invalid port: " <> value)
