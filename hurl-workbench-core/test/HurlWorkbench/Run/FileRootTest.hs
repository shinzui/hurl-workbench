module HurlWorkbench.Run.FileRootTest (tests) where

import Control.Exception (bracket_)
import HurlWorkbench.Prelude
import HurlWorkbench.Run.FileRoot
import System.Directory (canonicalizePath, createDirectory, createDirectoryLink, removeDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (setFileMode)
import System.Posix.User (getEffectiveUserID)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "file roots"
    [ testCase "validates relative Unicode and symlink roots and redacts Show" $
        withSystemTempDirectory "file-root" $ \base -> do
          let path = base </> "private 雪 payload"
          createDirectory path
          createDirectoryLink path (base </> "alias")
          root <- validateFileRoot base (Just "alias") >>= either (assertFailure . show) pure
          canonicalizePath path >>= (@?= fileRootPath root)
          show root @?= "FileRoot <redacted>"
          checkFileRootOutputs root [base </> "separate"] >>= (@?= Right ())
          for_ [path, path </> "new/report", base, base </> "alias/new"] $ \target ->
            checkFileRootOutputs root [target] >>= assertBool "overlap refused" . isLeft,
      testCase "missing, file, and empty roots fail" $
        withSystemTempDirectory "file-root" $ \base -> do
          writeFile (base </> "file") "payload"
          for_ ["missing", "file", ""] $ \path ->
            validateFileRoot base (Just path) >>= assertBool "root refused" . isLeft,
      testCase "effective read and search permissions are required" $
        withSystemTempDirectory "file-root" $ \base -> do
          uid <- getEffectiveUserID
          if uid == 0
            then putStrLn "UNSUPPORTED: root bypasses permission denial; public CLI check uses an unprivileged identity"
            else for_ [0o300, 0o600] $ \mode ->
              bracket_ (setFileMode base mode) (setFileMode base 0o700) $
                validateFileRoot base (Just base) >>= assertBool "permission refusal" . isLeft,
      testCase "default root permits workspace reports and retains a snapshot" $
        withSystemTempDirectory "file-root" $ \base -> do
          root <- validateFileRoot base Nothing >>= either (assertFailure . show) pure
          checkFileRootOutputs root [base </> "report"] >>= (@?= Right ())
          let child = base </> "ephemeral"
          createDirectory child
          selected <- validateFileRoot base (Just child) >>= either (assertFailure . show) pure
          removeDirectory child
          assertBool "retains selected root without recreating it" (not (null (fileRootPath selected)))
    ]
  where
    isLeft (Left _) = True
    isLeft _ = False
