# Obtain an access token once; later entries use {{access_token}}.
POST {{auth_url}}/oauth/token
[FormParams]
grant_type: client_credentials
client_id: {{client_id}}
client_secret: {{client_secret}}
HTTP 200
[Captures]
access_token: jsonpath "$.access_token"
