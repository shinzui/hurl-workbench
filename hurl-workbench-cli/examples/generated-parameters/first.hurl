GET {{baseUrl}}/odata/echo?id={{recipientId}}
HTTP 200
[Captures]
firstId: jsonpath "$.query"
[Asserts]
jsonpath "$.query" == "id={{recipientId}}"
