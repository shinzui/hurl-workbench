let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/3522f4a51181d73c9c90fc27a7c0838bd29ae95f/package.dhall
        sha256:dcb19e2312e790bad14e622cc98a1281cd2298c5b564a2f0d0534d3c718d8803

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "hurl-workbench"
      , namespace = "shinzui"
      , stableId = Some "project_01m2tt3p4ces0a17b8jtsgsezp"
      , type = Schema.PackageType.Application
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , description = Some
          "A Haskell-powered Hurl workbench for composing, exploring, executing, and testing reusable API workflows without duplicating request templates."
      }
    , repos =
      [ Schema.Repo::{
        , name = "hurl-workbench"
        , github = Some "shinzui/hurl-workbench"
        }
      ]
    , okfBundles =
      [ Schema.OkfBundle::{
        , name = "use-cases"
        , path = "docs/use-cases"
        , profile = Some "docs/use-cases/profile.dhall"
        , okfVersion = "0.2"
        , description = Some
            "JTBD use cases validating Hurl Workbench APIs and acceptance contracts"
        }
      ]
    }
