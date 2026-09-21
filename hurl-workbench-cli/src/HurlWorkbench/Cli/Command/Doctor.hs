module HurlWorkbench.Cli.Command.Doctor
  ( runDoctor,
    runDoctorWith,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import Data.Version (showVersion)
import HurlWorkbench.Cli.Output (CommandResult (..))
import HurlWorkbench.Hurl.Capabilities
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Prelude
import System.Exit (ExitCode (..))

runDoctor :: IO CommandResult
runDoctor = runDoctorWith detectHurlCapabilities

runDoctorWith :: IO (Either DependencyError HurlCapabilities) -> IO CommandResult
runDoctorWith detectCapabilities =
  detectCapabilities <&> \case
    Left err ->
      CommandResult
        { stdoutLines = [],
          stderrLines = ["error: " <> renderDependencyError err],
          exitCode = ExitFailure 3
        }
    Right capabilities ->
      CommandResult
        { stdoutLines =
            [ "hurl: "
                <> Text.pack (capabilities ^. #hurlExecutable)
                <> " ("
                <> Text.pack (showVersion (capabilities ^. #hurlVersion))
                <> ", supported)",
              "hurlfmt: "
                <> Text.pack (capabilities ^. #hurlfmt . #executable . #unHurlfmtExecutable)
                <> " ("
                <> Text.pack (showVersion (capabilities ^. #hurlfmt . #version))
                <> ", supported)"
            ],
          stderrLines = hurlCapabilityWarnings capabilities,
          exitCode = ExitSuccess
        }
