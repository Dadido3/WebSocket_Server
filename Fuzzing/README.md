# Using `Autobahn|Testsuite` for automated websocket server testing

## How to do a `fuzzing` test

1. Get docker
2. Download docker image for websocket fuzzing and load testing: `docker pull crossbario/autobahn-testsuite`
3. Open cmd/shell/terminal inside of `.../WebSocket_Server/Fuzzying/`
4. Start the `Fuzzy_Server.pb` server
5. Run `docker run -it --rm -v "${PWD}/config:/config" -v "${PWD}/reports:/reports" --name fuzzing --entrypoint=/bin/bash crossbario/autobahn-testsuite`
6. Enter `/usr/local/bin/wstest --mode fuzzingclient --spec /config/fuzzing-pb.json`

## How to do a `massconnect` test

1. Get docker
2. Download docker image for websocket fuzzing and load testing: `docker pull crossbario/autobahn-testsuite`
3. Open cmd/shell/terminal inside of `.../WebSocket_Server/Fuzzying/`
4. Start the `Fuzzy_Server.pb` server
5. Run `docker run -it --rm -v "${PWD}/config:/config" -v "${PWD}/reports:/reports" --name fuzzing --entrypoint=/bin/bash crossbario/autobahn-testsuite`
6. Enter `/usr/local/bin/wstest --mode massconnect --spec /config/massconnect.json`
