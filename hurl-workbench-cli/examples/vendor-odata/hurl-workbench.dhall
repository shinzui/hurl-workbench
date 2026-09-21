let Schema = ../../schema/package.dhall

let authParameters = [ "baseUrl", "clientId", "clientSecret" ]

let queryParameters = [ "mls", "resource", "filter", "select", "orderby", "top" ]

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , parameters =
      [ Schema.Parameter::{ name = "baseUrl" }
      , Schema.Parameter::{ name = "clientId", defaultValue = Some "fixture-client" }
      , Schema.Parameter::{
        , name = "clientSecret"
        , kind = Schema.ParameterKind.Secret
        , environment = Some "VENDOR_ODATA_CLIENT_SECRET"
        }
      , Schema.Parameter::{ name = "mls" }
      , Schema.Parameter::{ name = "resource" }
      , Schema.Parameter::{ name = "filter" }
      , Schema.Parameter::{ name = "select" }
      , Schema.Parameter::{ name = "orderby" }
      , Schema.Parameter::{ name = "top", defaultValue = Some "10" }
      ]
    , fragments =
      [ Schema.Fragment::{
        , name = "oauth-client-credentials"
        , path = "fragments/oauth-client-credentials.hurl"
        }
      , Schema.Fragment::{ name = "odata-query", path = "fragments/odata-query.hurl" }
      , Schema.Fragment::{ name = "co-buyer-capture", path = "fragments/co-buyer-capture.hurl" }
      , Schema.Fragment::{ name = "raw-decoding-response", path = "fragments/raw-decoding-response.hurl" }
      ]
    , workflows =
      [ Schema.Workflow::{
        , name = "odata-query"
        , fragments = [ "oauth-client-credentials", "odata-query" ]
        , parameters = authParameters # queryParameters
        }
      , Schema.Workflow::{
        , name = "co-buyer-investigation"
        , fragments = [ "oauth-client-credentials", "co-buyer-capture" ]
        , parameters = authParameters
        }
      , Schema.Workflow::{
        , name = "raw-decoding-investigation"
        , fragments = [ "raw-decoding-response" ]
        , parameters = [ "baseUrl" ]
        }
      ]
    , recipes =
      [ Schema.Recipe::{
        , name = "properties"
        , workflow = "odata-query"
        , bindings =
          [ Schema.Binding::{ parameter = "mls", value = "NORTHWEST" }
          , Schema.Binding::{ parameter = "resource", value = "Property" }
          , Schema.Binding::{ parameter = "filter", value = "Status%20eq%20Closed" }
          , Schema.Binding::{ parameter = "select", value = "ListingKey,ListPrice,Status" }
          , Schema.Binding::{ parameter = "orderby", value = "ModificationTimestamp%20desc" }
          ]
        , safety = Schema.Safety.ReadOnly
        }
      , Schema.Recipe::{
        , name = "members"
        , workflow = "odata-query"
        , bindings =
          [ Schema.Binding::{ parameter = "mls", value = "NORTHWEST" }
          , Schema.Binding::{ parameter = "resource", value = "Member" }
          , Schema.Binding::{ parameter = "filter", value = "MemberStatus%20eq%20Active" }
          , Schema.Binding::{ parameter = "select", value = "MemberKey,MemberFullName" }
          , Schema.Binding::{ parameter = "orderby", value = "MemberFullName" }
          ]
        , safety = Schema.Safety.ReadOnly
        }
      , Schema.Recipe::{
        , name = "offices"
        , workflow = "odata-query"
        , bindings =
          [ Schema.Binding::{ parameter = "mls", value = "NORTHWEST" }
          , Schema.Binding::{ parameter = "resource", value = "Office" }
          , Schema.Binding::{ parameter = "filter", value = "OfficeStatus%20eq%20Active" }
          , Schema.Binding::{ parameter = "select", value = "OfficeKey,OfficeName" }
          , Schema.Binding::{ parameter = "orderby", value = "OfficeName" }
          ]
        , safety = Schema.Safety.ReadOnly
        }
      ]
    , matrices =
      [ Schema.Matrix::{
        , name = "property-by-mls"
        , recipe = "properties"
        , cases =
          [ Schema.MatrixCase::{
            , name = "northwest"
            , bindings = [ Schema.Binding::{ parameter = "mls", value = "NORTHWEST" } ]
            }
          , Schema.MatrixCase::{
            , name = "metro"
            , bindings = [ Schema.Binding::{ parameter = "mls", value = "METRO" } ]
            }
          , Schema.MatrixCase::{
            , name = "mlspin-sold"
            , bindings =
              [ Schema.Binding::{ parameter = "mls", value = "MLSPIN" }
              , Schema.Binding::{ parameter = "filter", value = "Status%20eq%20Sold" }
              ]
            }
          ]
        }
      ]
    }
