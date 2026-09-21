GET {{base_url}}/not-found
HTTP 404
[Asserts]
header "Content-Type" contains "text/plain"
body contains "not found"
