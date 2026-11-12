GET {{apiUrl}}/api/v2/categories?first=100&status=all
Authorization: Bearer {{token}}
HTTP 200
[Asserts]
jsonpath "$.edges" count >= 1
