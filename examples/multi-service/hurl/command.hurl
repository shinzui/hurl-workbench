POST http://127.0.0.1:{{apiPort}}/command
HTTP 201
[Asserts]
body == "accepted"
