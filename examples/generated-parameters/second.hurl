GET {{baseUrl}}/odata/echo?id={{recipientId}}
HTTP 200
[Asserts]
jsonpath "$.query" == "{{firstId}}"
jsonpath "$.query" == "id={{recipientId}}"
