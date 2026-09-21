# Preserve a response whose bytes deliberately do not fit a typed JSON model.
GET {{baseUrl}}/raw-response
HTTP 200
[Asserts]
header "Content-Type" contains "application/octet-stream"
header "X-Raw" == "yes"
