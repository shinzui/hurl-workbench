# Shared authentication entry. The captured token remains in this Hurl session.
POST {{baseUrl}}/oauth/token
[FormParams]
grant_type: client_credentials
client_id: {{clientId}}
client_secret: {{clientSecret}}
HTTP 200
[Captures]
accessToken: jsonpath "$.access_token"
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.token_type" == "Bearer"
