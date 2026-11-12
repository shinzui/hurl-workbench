GET http://127.0.0.1:{{stubPort}}/after
[Options]
retry: 100
retry-interval: 50ms
HTTP 200
[Asserts]
jsonpath "$.edges" count == 1
