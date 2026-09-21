# One reusable OData-shaped query entry. Query values come from recipes and cases.
GET {{baseUrl}}/odata/echo?mls={{mls}}&resource={{resource}}&filter={{filter}}&select={{select}}&orderby={{orderby}}&top={{top}}
Authorization: Bearer {{accessToken}}
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.query" contains "mls="
jsonpath "$.query" contains "resource="
