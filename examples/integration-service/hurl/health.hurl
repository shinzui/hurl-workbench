GET {{base_url}}/health
HTTP 200
[Asserts]
header "Content-Type" contains "text/plain"
body contains "ok"
