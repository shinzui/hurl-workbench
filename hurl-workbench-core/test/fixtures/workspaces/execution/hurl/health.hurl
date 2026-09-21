GET {{baseUrl}}/health
HTTP 200
[Asserts]
body contains "ok"
