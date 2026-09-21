# A bespoke two-entry investigation is clearer as native Hurl than as matrix data.
GET {{baseUrl}}/capture
Authorization: Bearer {{accessToken}}
HTTP 200
[Captures]
captureMarker: header "X-Fixture-Capture"
[Asserts]
body contains "capture-body"

GET {{baseUrl}}/odata/echo?scenario=co-buyer&marker={{captureMarker}}
Authorization: Bearer {{accessToken}}
HTTP 200
[Asserts]
jsonpath "$.query" contains "marker=captured-value"
