module HurlWorkbench.Parameter.GenerateTest (tests) where

import Control.Exception (AsyncException (ThreadKilled), throwIO, try)
import Data.Bits ((.&.))
import Data.ByteString qualified as BS
import Data.Generics.Labels ()
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Version (makeVersion)
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run (defaultHurlOptions)
import HurlWorkbench.Parameter.Generate
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Prepare
import HurlWorkbench.Run.Selection
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit

fixed :: GeneratorEnvironment
fixed = GeneratorEnvironment (pure (posixSecondsToUTCTime 1645557742.123)) (\n -> pure (BS.replicate n 255))

textValue :: Either Text HurlValueLiteral -> Either Text Text
textValue = fmap hurlValueLiteralText

tests :: TestTree
tests =
  testGroup
    "generated parameters"
    [ testCase "RFC UUID4 and UUID7 layouts use independent expected bytes" $ do
        fmap formatUuid (uuid4Bytes (replicate 16 255)) @?= Right "ffffffff-ffff-4fff-bfff-ffffffffffff"
        let expected = [1, 127, 34, 226, 121, 171, 127, 255, 191, 255, 255, 255, 255, 255, 255, 255]
        uuid7Bytes 1645557741995 (replicate 16 255) @?= Right expected
        uuid7Bytes (-1) (replicate 16 0) @?= Left "UUID7 timestamp outside 48-bit range"
        assertBool "overflow rejected" (isLeft (uuid7Bytes (2 ^ (48 :: Int)) (replicate 16 0))),
      testCase "TypeID big endian vector and leading zero bits" $ do
        encodeTypeId (replicate 16 255) @?= "7zzzzzzzzzzzzzzzzzzzzzzzzz"
        encodeTypeId (replicate 16 0) @?= Text.replicate 26 "0"
        result <- generateValue fixed (TypeId (TypeIdOptions "rcp"))
        case textValue result of
          Right value -> do
            let alphabet = "0123456789abcdefghjkmnpqrstvwxyz"
                number = foldl (\acc c -> acc * 32 + fromIntegral (fromMaybe (-100) (Text.findIndex (== c) alphabet))) (0 :: Integer) (Text.unpack (Text.drop 4 value))
            (number `div` (2 ^ (76 :: Int))) .&. 15 @?= 7
            (number `div` (2 ^ (62 :: Int))) .&. 3 @?= 2
          Left err -> assertFailure (Text.unpack err),
      testCase "prefix and length constraints" $ do
        for_ ["", "a", Text.replicate 63 "a", "a__z"] $ \p -> validateGenerator (TypeId (TypeIdOptions p)) @?= Right ()
        for_ ["_a", "a_", "A", "a1", Text.replicate 64 "a"] $ \p -> assertBool "bad prefix" (isLeft (validateGenerator (TypeId (TypeIdOptions p))))
        for_ [0, 4097] $ \n -> assertBool "bad length" (isLeft (validateGenerator (RandomAlphanumeric (RandomOptions n)))),
      testCase "all outputs are literals, timestamp has fixed milliseconds" $ do
        fmap textValue (generateValue fixed Rfc3339Now) >>= (@?= Right "2022-02-22T19:22:22.123Z")
        for_ [Uuid4, Uuid7, TypeId (TypeIdOptions ""), TypeId (TypeIdOptions (Text.replicate 63 "a"))] $ \g -> generateValue fixed g >>= assertBool "valid literal" . not . isLeft,
      testCase "random sampling rejects 248..255 and terminates for broken entropy" $ do
        let env = fixed {entropyBytes = \n -> pure (BS.pack (take n (cycle [248, 255, 0, 61, 62, 247])))}
        fmap textValue (generateValue env (RandomAlphanumeric (RandomOptions 4))) >>= (@?= Right "A9A9")
        generateValue fixed (RandomAlphanumeric (RandomOptions 1)) >>= assertBool "bounded" . isLeft,
      testCase "short entropy, IO failure, and cancellation" $ do
        for_ [fixed {entropyBytes = \_ -> pure BS.empty}, fixed {entropyBytes = \_ -> ioError (userError "sensitive bytes")}] $ \env -> do
          result <- generateValue env Uuid4
          assertBool "fails redacted" (isLeft result && not ("sensitive" `Text.isInfixOf` Text.pack (show result)))
        result <- try @AsyncException (generateValue (fixed {entropyBytes = \_ -> throwIO ThreadKilled}) Uuid4)
        case result of Left ThreadKilled -> pure (); _ -> assertFailure "cancellation swallowed",
      testCase "declarations reject committed values and suite command references" $ do
        context <- loadWorkspaceContext (ExplicitWorkspace "test/fixtures/workspaces/minimal/hurl-workbench.dhall") >>= either (assertFailure . show) pure
        let name = ParameterName "fresh"
            parameter = Parameter name Nothing (Generated Uuid7) Nothing Nothing
            literal = either (error . show) id (mkHurlValueLiteral "committed")
            base = context & #workspace . #parameters %~ (parameter :)
            workflow = Workflow (WorkflowName "generated") [FragmentName "health"] [name] Nothing
            recipe = Recipe (RecipeName "generated") (WorkflowName "generated") [] ReadOnly Nothing
            command = CommandSpec "true" [] Nothing Inherit [EnvironmentBinding "FRESH" name]
            service = Service (ServiceName "generated") command (HttpReadinessCheck (HttpReadiness "http://localhost/health" 200 10 1)) 1 Nothing
            manifest = base & #workspace . #workflows %~ (workflow :) & #workspace . #recipes .~ [recipe]
        for_
          [ context & #workspace . #parameters %~ ((parameter & #defaultValue .~ Just literal) :),
            manifest & #workspace . #recipes .~ [recipe & #bindings .~ [Binding name literal]],
            manifest & #workspace . #matrices .~ [Matrix (MatrixName "generated") (RecipeName "generated") [MatrixCase (MatrixCaseName "one") [Binding name literal]] False Nothing],
            context & #workspace . #parameters %~ ((parameter & #name .~ ParameterName "newUuid") :),
            base & #workspace . #services .~ [service],
            base & #workspace . #services .~ [service & #command . #environment .~ [] & #readiness .~ HttpReadinessCheck (HttpReadiness "http://localhost/{{fresh}}" 200 10 1)],
            base & #workspace . #parameters %~ map (\p -> if p ^. #name == name then p & #kind .~ Generated (TypeId (TypeIdOptions "Bad")) else p)
          ]
          $ \candidate -> validateWorkspace candidate >>= assertBool "invalid manifest" . isLeft,
      testCase "resolution generates once per name and overrides consume no entropy" $ do
        context <- loadWorkspaceContext (ExplicitWorkspace "test/fixtures/workspaces/minimal/hurl-workbench.dhall") >>= either (assertFailure . show) pure
        let parameter = Parameter (ParameterName "fresh") Nothing (Generated Uuid4) Nothing Nothing
        validated <- validateWorkspace (context & #workspace . #parameters %~ (parameter :) & #workspace . #workflows %~ map (\w -> w & #parameters %~ (ParameterName "fresh" :))) >>= either (assertFailure . show) pure
        calls <- newIORef (0 :: Int)
        let env = fixed {entropyBytes = \n -> do modifyIORef' calls (+ 1); count <- readIORef calls; pure (BS.replicate n (fromIntegral count))}
            resolve = resolveParametersWithGenerator env validated (Set.singleton (ParameterName "fresh"))
        first <- resolve emptyBindingInput >>= either (assertFailure . show) pure
        readIORef calls >>= (@?= 1)
        second <- resolve emptyBindingInput >>= either (assertFailure . show) pure
        assertBool "fresh executions" (first /= second)
        let literal = either (error . show) id (mkHurlValueLiteral "reproduce")
        third <- resolve (emptyBindingInput & #plainOverrides .~ Map.singleton (ParameterName "fresh") literal) >>= either (assertFailure . show) pure
        third ^. #variables @?= Map.singleton (ParameterName "fresh") literal
        readIORef calls >>= (@?= 2)
        show first @?= "ResolvedBindings <redacted>"
        failure <- resolveParametersWithGenerator (fixed {entropyBytes = \_ -> ioError (userError "private")}) validated (Set.singleton (ParameterName "fresh")) emptyBindingInput
        case failure of
          Left err -> assertBool "names kind, redacts cause" ("Uuid4" `Text.isInfixOf` renderBindingError err && not ("private" `Text.isInfixOf` renderBindingError err))
          Right _ -> assertFailure "expected generator failure"
        let broken = fixed {entropyBytes = \_ -> ioError (userError "private")}
            format = HurlfmtCapabilities (HurlfmtExecutable "unused") (makeVersion [8, 0, 1])
        preparation <- prepareSelectionWithGenerator broken (\_ _ -> pure (Right ())) format validated emptyBindingInput defaultHurlOptions (SelectWorkflow (WorkflowName "check-health"))
        assertBool "generation failure is a preparation failure before spawn" (isLeft preparation)
        withSystemTempDirectory "generated-overrides" $ \directory -> do
          let firstFile = directory </> "first.env"
              secondFile = directory </> "second.env"
          Text.IO.writeFile firstFile "fresh=first\n"
          Text.IO.writeFile secondFile "fresh=second\n"
          result <- resolveParametersWithGenerator broken validated (Set.singleton (ParameterName "fresh")) (emptyBindingInput & #variableFiles .~ [firstFile, secondFile]) >>= either (assertFailure . show) pure
          fmap hurlValueLiteralText (result ^. #variables) @?= Map.singleton (ParameterName "fresh") "second"
        resolve (emptyBindingInput & #secretEnvironmentOverrides .~ Map.singleton (ParameterName "fresh") "SECRET") >>= assertBool "secret channel rejected" . isLeft
    ]
  where
    isLeft (Left _) = True; isLeft _ = False
