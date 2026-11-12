POST http://127.0.0.1:{{stubPort}}/api/v2/notes
Authorization: Bearer {{token}}
{"anchor":{"target":{"type":"topic","id":"{{topic}}"},"parent":null},"format":"markdown","content":"# Workbench lifecycle\n","tags":["workbench-{{variant}}"]}
HTTP 201

GET http://127.0.0.1:{{stubPort}}/api/v2/notes?tag=workbench-{{variant}}&first=10
[Options]
retry: 100
retry-interval: 50ms
HTTP 200
[Asserts]
jsonpath "$.edges" count == 1
