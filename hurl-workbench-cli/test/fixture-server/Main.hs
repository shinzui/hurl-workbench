module Main (main) where

import FixtureServer (runFixtureServer)
import System.Environment (getArgs, lookupEnv)
import Text.Read (readMaybe)

main :: IO ()
main = do
  arguments <- getArgs
  environmentPort <- lookupEnv "PORT"
  case parsePort arguments environmentPort of
    Left message -> ioError (userError message)
    Right port -> runFixtureServer port

parsePort :: [String] -> Maybe String -> Either String Int
parsePort arguments environmentPort = case arguments of
  [] -> maybe (Right 18080) readPort environmentPort
  ["--port", value] -> readPort value
  _ -> Left "usage: hurl-workbench-fixture-server [--port PORT]"
  where
    readPort value = case readMaybe value of
      Just port | port > 0 && port <= 65535 -> Right port
      _ -> Left ("invalid port: " <> value)
