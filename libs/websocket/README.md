# Native WebSockets

`import "websocket";` supplies RFC 6455 WebSocket support for Linux x86-64.
Framing, masking, fragmentation, UTF-8 checks and HTTP upgrades are native
Flexscript. OpenSSL 3 supplies SHA-1 for the handshake and verified TLS. No
JavaScript, Python service, curl process or HTTP shim is used at runtime.

The codec is incremental and independent of socket scheduling. The synchronous
TCP/TLS convenience client is separate; event loops can feed the codec from their
existing accepted sockets and TLS sessions. The HTTP client retains its current
request/response behavior; upgrades are explicit WebSocket operations.

```flexscript
import "websocket";
fn main() {
    let tls=websocket_tls_options(0,0,0); // system CA trust; no client identity
    let socket=websocket_connect("example.com","443","/socket","",
                                 10000,1048576,tls);
    websocket_tls_options_free(tls);
    if !socket {return 1;}
    if !websocket_stream_send(socket,1,"Hello",5,5000) {
        websocket_free(socket);return 1;
    }
    let event=websocket_stream_receive(socket,5000);
    // event=1 text, 2 binary, 8 close, 9 ping, 10 pong; -1 failure, 0 closed.
    // websocket_data/websocket_size expose length-bearing bytes, including NUL.
    websocket_free(socket);return event<0;
}
```

## TCP/TLS client

`websocket_connect(host, service, path, headers, timeout_ms, message_limit,
 tls_options)` owns its resulting socket. A zero TLS options handle selects plain
TCP; a nonzero record requires verified TLS. Options are borrowed only during
connect, then may be freed. Header lines must end in CRLF. Host, upgrade,
framing, extension and subprotocol overrides are rejected. Redirects and
compression/extensions/subprotocol negotiation are not supported.

`websocket_tls_options(ca_file, certificate_file, private_key_file)` selects a
custom CA PEM file or system trust (zero). Supplying a certificate/key pair
enables mutual TLS. Both must be present and match. Optional offset 24 selects
a verified TLS server-name override; the default is the connection host.
Hostname and IPv4/IPv6 identity verification are mandatory, with SNI for DNS
names and TLS 1.2 minimum. There is no disable-verification option.

Connect/upgrade and each send/receive have bounded I/O deadlines. System DNS
resolution uses the existing synchronous `tcp_connect` resolver; its time is not
interruptible. Network failures return zero for connect/send and -1 for receive.
Receive automatically answers ping and echoes close, while returning those
control events to the caller. Send a close frame (opcode 8, a valid two-byte
network-order status and optional UTF-8 reason), then receive the peer close for
a graceful shutdown. `websocket_free` releases the socket and all buffers; it
can also abort an unfinished connection. Call it after failures.

`websocket_stream_adopt(codec, fd, tls_session)` can transfer an existing TCP
socket (and optional `lib/tls.flex` session) into the stream adapter. The codec
then owns that connection; freeing it closes the adopted socket/session.

## Incremental codec and server upgrades

`websocket_new(server, message_limit)` creates a bounded codec: server=1 expects
masked client frames; server=0 expects unmasked server frames. Limits are
125 bytes through 16 MiB. Memory is approximately three times the configured
limit, allocated once and freed by `websocket_free`.

- `websocket_feed(codec, bytes, size)` returns bytes accepted, possibly less than
  supplied. Feed remaining input after draining events. Negative means failure.
- `websocket_input_capacity(codec)` gives remaining input capacity for bounded
  reads into an event loop. Drain buffered events before requesting more input.
- `websocket_next(codec)` returns the next complete text/binary/control opcode,
  zero when more input is needed or after close, and -1 on protocol failure.
- `websocket_data` and `websocket_size` expose event bytes until the next `next`
  call. Embedded NUL is supported. Incoming fragmented data is reassembled;
  control frames can occur between fragments. Text is checked after reassembly.
- `websocket_frame(codec, opcode, bytes, size)` builds one complete frame, using
  fresh OS randomness for client masks. `websocket_output` and
  `websocket_output_size` expose it until the next frame call. Copy or fully send
  it before constructing another frame. Outbound fragmentation is unnecessary;
  incoming fragmentation is accepted. The codec exposes ping/close to callers;
  event loops must answer them (the stream adapter does this automatically).
- `websocket_error(codec)` gives the error string, or use zero for the last
  constructor/connect error. `websocket_close_code` gives peer close or protocol
  failure status. Failed codecs must be freed rather than reused.

Use `websocket_client_key(out25)` to create a random handshake key.
`websocket_client_request(host, path, key, headers, out, capacity)` builds the
request. `websocket_client_verify(response, size, key)` returns its header size,
zero for incomplete input, or -1 for an invalid response. A verified response
can be followed by frame bytes; feed those remaining bytes to the codec.

`websocket_server_upgrade(request, size, out, capacity)` builds the 101 response
and returns its byte length, zero for incomplete input or -1 for an invalid
request/capacity. **Authorize the request before sending this response.** It
does not authenticate users or own the connection. Handshakes are bounded to
16 KiB, require HTTP/1.1, validate the key/version/connection headers, reject
ambiguous framing, and do not negotiate extensions. `websocket_header_size`
finds the header boundary. `websocket_accept_key(key, out29)` provides the
standalone RFC handshake calculation.

## Checks

Compile/run `libs/websocket/tests/core.flex` for native protocol checks.
Run `python3 scripts/test-websocket.py` for real native client/server exchanges
against independent Python WebSocket peers (`websockets` package required),
including binary/fragmented messages, ping/pong, close, trusted TLS, mutual TLS,
and rejection of wrong CA, wrong host and missing client certificates.
All services, certificates, ports and binaries in this suite are disposable.
