let S = ../../schema/package.dhall
let parameter = \(name : Text) -> \(environment : Text) -> S.Parameter::{ name = name, environment = Some environment }
let binding = \(variable : Text) -> \(parameter : Text) -> S.EnvironmentBinding::{ variable = variable, parameter = parameter }
let command = \(role : Text) -> \(port : Text) -> S.CommandSpec::{
    executable = "/usr/bin/env"
  , arguments = [ "python3", "launch.py", role ]
  , workingDirectory = None Text
  , environmentPolicy = S.EnvironmentPolicy.Clean [ "PATH" ]
  , environment = [ binding "FIXTURE_EXECUTABLE" "fixtureExecutable", binding "STATE_DIR" "stateDir", binding "ROLE_PORT" port ]
  }
let service = \(role : Text) -> \(port : Text) -> \(url : Text) -> S.Service::{
    name = role
  , command = command role port
  , readiness = S.Readiness.Http S.HttpReadiness::{ url = url, intervalMilliseconds = 10, timeoutSeconds = 5 }
  , shutdownTimeoutSeconds = 2
  }
let recipe = \(name : Text) -> \(workflow : Text) -> S.Recipe::{ name = name, workflow = workflow, safety = S.Safety.ReadOnly }
in S.Workspace::{
    schemaVersion = S.schemaVersion
  , parameters = [ parameter "fixtureExecutable" "HURL_WORKBENCH_FIXTURE_EXECUTABLE", parameter "stateDir" "HURL_WORKBENCH_STATE_DIR", parameter "apiPort" "HURL_WORKBENCH_API_PORT", parameter "stubPort" "HURL_WORKBENCH_STUB_PORT", parameter "workerPort" "HURL_WORKBENCH_WORKER_PORT" ]
  , fragments = [ S.Fragment::{ name = "command", path = "hurl/command.hurl" }, S.Fragment::{ name = "before", path = "hurl/before.hurl" }, S.Fragment::{ name = "after", path = "hurl/after.hurl" } ]
  , workflows = [ S.Workflow::{ name = "command", fragments = [ "command" ], parameters = [ "apiPort" ] }, S.Workflow::{ name = "before", fragments = [ "before" ], parameters = [ "apiPort" ] }, S.Workflow::{ name = "after", fragments = [ "after" ], parameters = [ "apiPort" ] } ]
  , recipes = [ S.Recipe::{ name = "submit", workflow = "command", safety = S.Safety.Mutating }, recipe "before" "before", recipe "after" "after", recipe "read1" "before", recipe "read2" "before", recipe "read3" "after", recipe "read4" "after" ]
  , services = [ service "stub" "stubPort" "http://127.0.0.1:{{stubPort}}/health", service "api" "apiPort" "http://127.0.0.1:{{apiPort}}/health", service "worker" "workerPort" "http://127.0.0.1:{{workerPort}}/health" ]
  , suites = [ S.Suite::{ name = "command-read", services = [ "stub", "api", "worker" ], setup = [ command "setup" "apiPort" ], teardown = [ command "teardown" "apiPort" ], runs = [ S.RunReference.Recipe "submit", S.RunReference.Recipe "before", S.RunReference.Service (S.ServiceStep.Restart "worker"), S.RunReference.Recipe "after" ] }, S.Suite::{ name = "read-barriers", services = [ "stub", "api", "worker" ], setup = [ command "setup" "apiPort" ], teardown = [ command "teardown" "apiPort" ], runs = [ S.RunReference.Recipe "read1", S.RunReference.Recipe "read2", S.RunReference.Service (S.ServiceStep.Restart "worker"), S.RunReference.Recipe "read3", S.RunReference.Recipe "read4" ] } ]
  }
