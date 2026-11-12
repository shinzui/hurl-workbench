let S = ../../../../schema/package.dhall

in  S.Workspace::{
    , schemaVersion = 1
    , parameters =
      [ S.Parameter::{ name = "baseUrl" }
      , S.Parameter::{ name = "marker" }
      , S.Parameter::{ name = "token", kind = S.ParameterKind.Secret }
      ]
    , fragments = [ S.Fragment::{ name = "write", path = "hurl/write.hurl" } ]
    , workflows =
      [ S.Workflow::{ name = "write", fragments = [ "write" ], parameters = [ "baseUrl", "marker", "token" ] } ]
    , recipes =
      [ S.Recipe::{ name = "write", workflow = "write", safety = S.Safety.Mutating } ]
    , matrices =
      [ S.Matrix::{ name = "writes", recipe = "write", cases = [ S.MatrixCase::{ name = "first" }, S.MatrixCase::{ name = "second" } ] } ]
    , suites =
      [ S.Suite::{ name = "independent-writes", runs = [ S.RunReference.Matrix "writes" ], isolation = S.IsolationPolicy.IndependentState } ]
    }
