let S = ../../schema/package.dhall
let workflow = S.Workflow::{ name = "recipient", fragments = [ "first", "second" ], parameters = [ "baseUrl", "recipientId", "uuid4", "uuid7", "now", "random" ] }
let recipe = S.Recipe::{ name = "recipient", workflow = "recipient", safety = S.Safety.ReadOnly }
in S.Workspace::{
 , schemaVersion = S.schemaVersion
 , parameters =
   [ S.Parameter::{ name = "baseUrl", defaultValue = Some "http://127.0.0.1:18080" }
   , S.Parameter::{ name = "recipientId", kind = S.ParameterKind.Generated (S.Generator.TypeId { prefix = "rcp" }) }
   , S.Parameter::{ name = "uuid4", kind = S.ParameterKind.Generated S.Generator.Uuid4 }
   , S.Parameter::{ name = "uuid7", kind = S.ParameterKind.Generated S.Generator.Uuid7 }
   , S.Parameter::{ name = "now", kind = S.ParameterKind.Generated S.Generator.Rfc3339Now }
   , S.Parameter::{ name = "random", kind = S.ParameterKind.Generated (S.Generator.RandomAlphanumeric { length = 24 }) }
   ]
 , fragments = [ S.Fragment::{ name = "first", path = "first.hurl" }, S.Fragment::{ name = "second", path = "second.hurl" } ]
 , workflows = [ workflow ]
 , recipes = [ recipe, recipe // { name = "recipient-second" } ]
 , matrices = [ S.Matrix::{ name = "recipients", recipe = "recipient", cases = [ S.MatrixCase::{ name = "one" }, S.MatrixCase::{ name = "two" } ] } ]
 , suites = [ S.Suite::{ name = "recipients", runs = [ S.RunReference.Recipe "recipient", S.RunReference.Recipe "recipient-second" ] } ]
 }
