GET http://127.0.0.1:{{apiPort}}/read
[Options]
retry: 100
retry-interval: 10ms
HTTP 200
[Asserts]
body == "visible:1"
