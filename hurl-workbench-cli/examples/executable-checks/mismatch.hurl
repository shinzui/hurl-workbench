POST {{apiUrl}}/facts
Authorization: Bearer {{token}}
Content-Type: application/json
[
  {"key": "parity", "value": "deliberately different"}
]
HTTP 204
