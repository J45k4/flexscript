# Hello, world HTTP server

`examples/hello-http.flex` is a small HTTP server written entirely in Flexscript
0.0.1. The existing native compiler builds a standalone Linux x86-64 executable.
Networking uses raw Linux syscalls; no Rust, Python, libc, or external HTTP
library is needed to run the server.

Build and run from the project root:

```sh
mkdir -p build
build/downloaded/flexscript-0.0.1-linux-x86_64 examples/hello-http.flex -o build/hello-http
./build/hello-http
```

It listens on `127.0.0.1:8080`. From another terminal:

```sh
curl http://127.0.0.1:8080/
# Hello, world!
```

Choose a different port with `./build/hello-http 9090`. Ports must be decimal
integers from 1 to 65535. `--help` prints usage. Ctrl+C or SIGTERM stops the
process and releases the listener; a new instance can immediately reuse the
port. Only the loopback interface is bound.

`GET /` returns `Hello, world!` followed by a newline, with status 200,
`Content-Type: text/plain; charset=utf-8`, and the exact `Content-Length`.
A query string on `/` is also accepted. `HEAD` returns the same headers without
a body, including for unknown paths. Other paths return 404; unsupported
methods return 405 with `Allow: GET, HEAD`.

This is a minimal, sequential HTTP/1.0 and HTTP/1.1 example. Each response
closes its connection; there is no keep-alive, pipelining, TLS, or request-body
handling. HTTP/1.1 requests require exactly one nonempty Host header. Malformed
request lines or headers return 400. A nonzero Content-Length on GET/HEAD
returns 413; transfer encoding returns 501. Headers are limited to 8192 bytes
and must arrive within two seconds; violations return 431 or 408. Writes also
have a two-second deadline. A disconnected client does not stop the server.
The request parsing and response framing follow the relevant parts of
[HTTP/1.1 messaging](https://www.rfc-editor.org/rfc/rfc9112.html) and
[HTTP semantics](https://www.rfc-editor.org/rfc/rfc9110.html); this example is
not a complete implementation of those specifications.

Compile and run real loopback integration tests:

```sh
python3 scripts/test-http.py
```

Use `--compiler /path/to/flexscript` to choose another native compiler. Tests
use a temporary local port and exercise GET/HEAD, errors, fragmented headers,
timeouts, reset/disconnected clients, repeated requests, buffer and socket
cleanup, port conflicts, and restart. They stop the test server before exiting.
