# TCP and HTTPS

Networking libraries are written in Flexscript. TCP socket operations use raw
Linux syscalls; hostname resolution uses the system's `getaddrinfo` through FFI.
TLS uses OpenSSL 3 through the same general FFI interface.

```flex
import "lib/net.flex";

fn main() {
    let socket = tcp_connect("example.com", "80", 5000);
    if socket < 0 { return 1; }
    let request = "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n";
    let deadline = net_now() + 5000;
    if !tcp_write(socket, request, net_length(request), deadline) {
        tcp_close(socket); return 1;
    }
    let buffer = alloc(4096);
    let count = tcp_read(socket, buffer, 4096, deadline);
    if count > 0 { syscall(1, 1, buffer, count, 0, 0, 0); }
    tcp_close(socket);
    return count < 0;
}
```

Import paths are relative to the source file: adjust the example's path to where
it is saved. `net_now()` returns monotonic milliseconds. Connect takes a relative
timeout; read/write/accept take an absolute deadline. The system resolver can
block independently of that timeout. The updater isolates downloads in a worker
process and applies a separate deadline to the entire operation.

| Function | Result |
| --- | --- |
| `tcp_connect(host, service, timeout_ms)` | Connected nonblocking socket or -1. |
| `tcp_listen(host, service, backlog)` | Nonblocking listener or -1; host may be zero for any address. |
| `tcp_accept(listener, deadline)` | Connected nonblocking socket or -1. |
| `tcp_read(socket, buffer, capacity, deadline)` | Byte count, zero at EOF, or -1. |
| `tcp_write(socket, buffer, size, deadline)` | 1 after all bytes are sent, or 0. |
| `tcp_close(socket)` | Raw close syscall result. |

Resolution tries available IPv4 and IPv6 addresses. Reads may be partial; writes
handle partial sends, interruption and backpressure. `net_message` contains a
static error string after a failure.

## TLS

Import `lib/tls.flex`. `tls_connect(host, service, timeout_ms)` returns a session
or zero. `tls_read(session, buffer, capacity)` returns a byte count, zero after a
clean TLS shutdown, or -1. `tls_write(session, buffer, size)` returns 1 or 0.
`tls_close(session)` frees the OpenSSL session/context and closes the socket.
The session's deadline applies throughout the connection.

TLS requires OpenSSL 3 (`libssl.so.3`) and trusted CA certificates. It verifies
the server's certificate chain and hostname, sends SNI, and requires TLS 1.2 or
newer. The default OpenSSL trust store is used, including OpenSSL's
`SSL_CERT_FILE` and `SSL_CERT_DIR` configuration. There is no insecure mode.

## HTTPS downloads

Import `lib/http.flex`. `https_get(url, max_bytes, timeout_ms)` returns 1 or 0.
On success, `http_output` points to the downloaded bytes and `http_size` is the
length. Data can contain zero bytes; use the length rather than string operations.

The client handles HTTP/1.0 and HTTP/1.1, Content-Length, chunked framing with
trailers, and clean close-delimited bodies. It follows up to five HTTPS redirects,
including root-relative redirects, and rejects redirects to HTTP. Metadata and
headers are bounded; truncated, ambiguous and oversized responses are rejected.
Scratch storage is reclaimed after each request. The returned body stays valid
until the next `https_get` or an explicit `https_free()` call. The maximum body
limit is 64 MiB. This first client uses direct connections,
DNS names or IPv4 URL hosts, and identity content encoding. IPv6 URL literals,
proxy configuration, HTTP/2, compression, interim responses and arbitrary relative
redirects are not implemented.

Build `build/tools` once using the [Flexscript tooling instructions](bootstrapping.md).

```sh
./build/flex examples/https-get.flex -o build/https-get
./build/https-get https://api.github.com/repos/J45k4/flexscript/releases/latest
build/tools/test-network build/flex
```

The test suite uses local TCP and TLS servers and checks certificate/hostname
rejection, framing, redirects, timeouts, fragmented responses and server sockets.
