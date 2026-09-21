{- How to decide that a service is ready, for example
   `Schema.Readiness.Http Schema.HttpReadiness::{ url = "http://127.0.0.1:8080/health" }`.
-}
< Http : (./HttpReadiness.dhall).Type
| Command : (./CommandReadiness.dhall).Type
>
