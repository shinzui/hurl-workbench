let S = ../../schema/package.dhall
let p = \(name : Text) -> S.Parameter::{ name = name }
let binding = \(variable : Text) -> \(parameter : Text) -> S.EnvironmentBinding::{ variable = variable, parameter = parameter }
in S.Workspace::{ schemaVersion = 1
, parameters = [ p "cliFixture", p "apiUrl", p "cliFixtureId", p "apiFixtureId", S.Parameter::{ name = "token", kind = S.ParameterKind.Secret, environment = Some "PARITY_TOKEN" } ]
, fragments = [ S.Fragment::{ name = "before", path = "before.hurl" }, S.Fragment::{ name = "after", path = "after.hurl" }, S.Fragment::{ name = "mismatch", path = "mismatch.hurl" } ]
, workflows = [ S.Workflow::{ name = "before", fragments = [ "before" ], parameters = [ "apiUrl" ] }, S.Workflow::{ name = "after", fragments = [ "after" ], parameters = [ "apiUrl", "token" ] }, S.Workflow::{ name = "mismatch", fragments = [ "mismatch" ], parameters = [ "apiUrl", "token" ] } ]
, recipes = [ S.Recipe::{ name = "before", workflow = "before", safety = S.Safety.ReadOnly }, S.Recipe::{ name = "after", workflow = "after", safety = S.Safety.ReadOnly }, S.Recipe::{ name = "mismatch", workflow = "mismatch", safety = S.Safety.Mutating } ]
, checks = [ S.Check::{ name = "parity", command = S.CommandSpec::{ executable = "parity.py", arguments = [ "{{cliFixture}}", "{{apiUrl}}", "{{cliFixtureId}}", "{{apiFixtureId}}" ], environmentPolicy = S.EnvironmentPolicy.Clean [ "PATH" ], environment = [ binding "PARITY_TOKEN" "token" ] } } ]
, suites = [ S.Suite::{ name = "parity", runs = [ S.RunReference.Recipe "before", S.RunReference.Check "parity", S.RunReference.Recipe "after" ] }, S.Suite::{ name = "parity-mismatch", runs = [ S.RunReference.Recipe "mismatch", S.RunReference.Check "parity" ] } ]
}
