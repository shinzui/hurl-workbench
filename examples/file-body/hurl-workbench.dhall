let S = ../../schema/package.dhall
in S.Workspace::{
 , schemaVersion = S.schemaVersion
 , parameters = [ S.Parameter::{ name = "baseUrl", defaultValue = Some "http://127.0.0.1:18080" }, S.Parameter::{ name = "payloadRoot" } ]
 , fragments = [ S.Fragment::{ name = "request", path = "request.hurl" } ]
 , workflows = [ S.Workflow::{ name = "send-body", fragments = [ "request" ], parameters = [ "baseUrl" ] } ]
 , recipes = [ S.Recipe::{ name = "send-body", workflow = "send-body", safety = S.Safety.Mutating } ]
 , matrices = [ S.Matrix::{ name = "bodies", recipe = "send-body", cases = [ S.MatrixCase::{ name = "one" }, S.MatrixCase::{ name = "two" } ] } ]
 , suites =
   [ S.Suite::{ name = "bodies", runs = [ S.RunReference.Recipe "send-body" ] }
   , S.Suite::{ name = "parameter", fileRootParameter = Some "payloadRoot", runs = [ S.RunReference.Recipe "send-body" ] }
   ]
 }
