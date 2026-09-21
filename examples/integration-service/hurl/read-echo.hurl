GET {{base_url}}/odata/echo?scope=default-safe
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.query" == "scope=default-safe"
