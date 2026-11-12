POST {{baseUrl}}/markers
Content-Type: application/json
X-Test-Token: {{token}}
{
  "marker": "{{marker}}"
}
HTTP 201

GET {{baseUrl}}/markers
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.marker" == "{{marker}}"
jsonpath "$.count" == 1
