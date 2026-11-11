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
      [ Schema.OkfBundle::{ name = "friction-log", path = "docs/friction-log", okfVersion = "0.2", profile = Some "docs/friction-log/profile.dhall", description = Some "Friction met while implementing plans" }
      , Schema.OkfBundle::{
        , name = "use-cases"
        , path = "docs/use-cases"
        , profile = Some "docs/use-cases/profile.dhall"
        , okfVersion = "0.2"
        , description = Some
            "JTBD use cases validating Hurl Workbench APIs and acceptance contracts"
        }
      , Schema.OkfBundle::{
        , name = "improvement-requests"
        , path = "docs/improvement-requests"
        , profile = Some "docs/improvement-requests/profile.dhall"
        , profileBinding = Some
            ( Schema.ProfileBinding.Published
                Schema.PinnedImport::{
                , publisher = "shinzui/okf-profiles"
                , publisherRef = Some
                    Schema.MoriRef::{ namespace = "shinzui", name = "okf-profiles" }
                , export = Some "coordination.improvementRequests"
                , version = Some "v0.18.0"
                , pin = Some
                    "sha256:7d3a4a22be12fd0e697d6012ed1eb2efe4cb5dc4700d08fd49aa5e4c0e523df8"
                }
            )
        , okfVersion = "0.2"
        , description = Some
            "Cross-repository improvement requests owned by hurl-workbench"
        }
      ]
    }
