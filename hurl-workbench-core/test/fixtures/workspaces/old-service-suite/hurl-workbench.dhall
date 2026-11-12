-- Frozen pre-lifecycle schema records and union, without completion defaults.
let old = ../old-http/hurl-workbench.dhall
in old // { suites = [ { name = "old-service", runs = [ < Workflow : Text | Recipe : Text | Matrix : Text >.Workflow "check-health" ], service = Some "old", failFast = False, description = None Text } ] }
