GET {{base_url}}/health
Authorization: Bearer {{token}}
HTTP 200
[Asserts]
header "Content-Type" contains "text/plain"
body contains "ok"
