POST {{base_url}}/mutating
Content-Type: application/json
{
  "fixture": "write"
}
HTTP 201
[Asserts]
header "Content-Type" contains "application/octet-stream"
body contains "\"fixture\": \"write\""
