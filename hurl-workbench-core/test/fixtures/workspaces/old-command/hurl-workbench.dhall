let Command = { executable : Text, arguments : List Text, workingDirectory : Optional Text, environment : List { variable : Text, parameter : Text } }
let Readiness = < Http : { url : Text, expectedStatus : Natural, intervalMilliseconds : Natural, timeoutSeconds : Natural } | Command : { command : Command, intervalMilliseconds : Natural, timeoutSeconds : Natural } >
let command = { executable = "/usr/bin/true", arguments = [] : List Text, workingDirectory = None Text, environment = [] : List { variable : Text, parameter : Text } }
let old = ../minimal-explicit/hurl-workbench.dhall
in old // { services = [ { name = "old", command = command, readiness = Readiness.Command { command = command, intervalMilliseconds = 10, timeoutSeconds = 1 }, shutdownTimeoutSeconds = 1, description = None Text } ] }
