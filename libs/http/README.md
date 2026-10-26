# Native HTTP client

`import "http";` (or `import "libs/http.flex";` from the repository root) provides
a native Linux x86-64 HTTP/1.1 client. Request generation, response parsing,
redirects, streaming, deadlines, cancellation and connection ownership are
Flexscript. There is no curl executable, libcurl, Python host or C HTTP shim.
The existing `lib/net.flex` system resolver and `lib/tls.flex` OpenSSL 3 bindings
provide DNS and TLS primitives. HTTPS uses system trust, peer verification,
DNS/IP identity verification, SNI for DNS names, and TLS 1.2 or newer.

```flexscript
import "http";

fn main() {
    let options=http_client_options();
    store64(options,10000); // one deadline for DNS, connect, TLS and response
    let request=http_client_start("GET","https://example.com/","",0,0,options);
    http_client_options_free(options);
    if !request {return 1;}
    let result=http_client_wait(request);
    let status=http_client_status(request);
    // Use response bytes/headers here, before freeing their owner.
    http_client_free(request);
    if result<0 || status!=200 {return 1;}return 0;
}
```

The [command-line example](../../examples/http-client.flex) writes the response
body to stdout. Compile it with the ordinary native compiler; both the native
IR and direct pipelines work. This library does not grant network capabilities
to restricted guests, and does not replace the older `lib/http.flex` downloader.

## Requests and options

`http_client_start(method,url,headers,body,size,options)` copies all inputs and
returns an owned request, or zero with `http_client_message` on validation or
startup failure. `body` is a pointer and `size` is an explicit byte count: uploads
can contain NUL bytes. A nonzero body pointer sends Content-Length even for an
empty body. Methods are case-sensitive tokens; CONNECT/upgrades are unsupported.

`headers` is a string of `Name: value` lines separated by CRLF, with an optional
final CRLF. Empty lines, folded lines, control bytes and invalid names are rejected.
The client supplies Host, Content-Length, Connection: close and
Accept-Encoding: identity; callers cannot override framing or connection headers.
It never adds credentials, cookies, proxy settings or authentication from the
environment. HTTP responses with non-2xx status codes are completed responses,
not transport errors; the application decides how to handle their status/body.

`http_client_options()` returns a zeroed 64-byte record with these defaults.
Set fields with `store64`; `http_client_options_free()` releases it after start.

| Offset | Meaning | Default / range |
| --- | --- | --- |
| 0 | Total timeout, milliseconds | 30,000; 1 to 3,600,000 |
| 8 | Maximum decoded response body bytes | 8 MiB; 0 to 64 MiB |
| 16 | Maximum automatic redirects | 0; 0 to 10 |
| 24 | Require HTTPS for the initial URL too | 0 |
| 32 | CA bundle filename pointer | 0: OpenSSL system trust, including SSL_CERT_FILE |
| 40 | Stop successfully with a truncated body at the limit | 0: fail on overflow |

Redirects are opt-in and limited to GET/HEAD without a body or Authorization,
Proxy-Authorization or Cookie headers. The library never automatically forwards
such credentialed requests. Relative, query, root-relative and scheme-relative
locations are resolved; HTTPS cannot redirect to HTTP. Userinfo in URLs is
rejected. IPv4, bracketed IPv6, DNS names, explicit ports and fragments work.
No request is automatically retried after a failed write or connection.

## Streaming and ownership

`http_client_step(request)` performs one bounded scheduling quantum and returns
0 while pending, 1 on completion, or -1 on failure. Call it for **each** active
request from the application's event loop. It never waits for a socket or DNS
reply. `http_client_wait(request)` is the synchronous convenience wrapper; it
sleeps between scheduling quanta. This API is intended for a single-threaded
native process, such as Collie's separate controller; it is not a threaded
resolver or a foreign-thread callback API.

- `http_client_data(request)`, `http_client_size(request)`: contiguous decoded
  body bytes available now, including partial SSE events. No chunk framing is
  exposed. The buffer has a trailing NUL; use the byte count for binary data.
- `http_client_status(request)`, `http_client_url(request)`: final status/URL;
  the status is zero until a status line has arrived.
- `http_client_header(request,name)`: first matching response header, ignoring
  name case, or zero. Interim headers and chunk trailers are not returned.
- `http_client_error(request)`: transport/protocol error, or zero.
- `http_client_truncated(request)`: whether intentional truncation occurred.
  Configure it through options; `http_client_allow_truncation(request,enabled)`
  also allows an embedding adapter to set the policy before receiving data.
- `http_client_cancel(request)`: closes the connection and cancels DNS, retaining
  an inspectable error/result. `http_client_free(request)` releases everything
  and also cancels unfinished work.

Response pointers are borrowed until `http_client_free`. Copy metadata/body
before retaining it elsewhere. Every request owns its buffers independently of
the application's arenas. Do not inspect the private request record directly.

## Limits and dependencies

Responses support Content-Length, chunked transfer coding (including bounded
extensions/trailers), HTTP/1.0 close-delimited bodies, informational responses,
and HEAD/204/304 body rules. Ambiguous framing, duplicate Content-Length,
premature EOF, malformed CRLF and unsupported transfer/content encodings fail.
The client requests identity encoding; gzip/Brotli, HTTP/2, HTTP/3, proxies,
connection pooling and automatic POST redirects are not implemented.

Headers/trailers total at most 64 KiB, individual lines 8 KiB, final response
headers 128 fields, and interim responses 8. URLs are at most 16 KiB, upload and
response bodies at most 64 MiB each, and per-request metadata at most 1 MiB.

DNS runs in an owned resolver helper, using the system's getaddrinfo. Only socket
addresses leave that helper. It closes inherited application descriptors, exits
when its parent dies, and is killed/reaped on cancellation, timeout or cleanup.
Callers must not independently reap that helper. Linux with close_range support
is required. Other I/O runs in the native caller; there are no helper executables
or interpreter processes. TLS uses OpenSSL 3/libcrypto; plain HTTP requires libc
for the resolver. Broken TLS writes do not change the process's SIGPIPE handler.

`FLEX_COMPILER=build/flex python3 scripts/test-http-client.py` tests against
private local HTTP/TLS peers, including fragmented framing, binary POST, streams,
redirect policies, verification failures, cancellation, peer resets and cleanup.
It runs the fixture through both native pipelines and checks descriptor/child
ownership. No live provider or production login is used.

## Opt-in live Responses test

`tests/collie/responses-live.flex` sends one small generation request through
Collie's actual native HTTP adapter. It checks incremental Responses SSE events,
HTTP 200, completion and the expected output, and reports timings/token usage.
It prints no credentials, raw event payloads or private reasoning. This test is
excluded from ordinary CI because it consumes real account usage.

```sh
build/collie-desktop/compiler --native-pipeline direct tests/collie/responses-live.flex -o build/responses-live
build/responses-live --api gpt-6.1-sol
# Or use a saved ChatGPT/Codex login:
build/responses-live /path/to/auth.json gpt-6.1-sol
```

`--api` reads OPENAI_API_KEY and uses `https://api.openai.com/v1/responses`.
The auth-file route uses Collie's `https://chatgpt.com/backend-api/codex/responses`
transport. These are distinct authentication routes; a successful Codex test
does not verify developer API-key access. See the
[official OpenAI streaming documentation](https://developers.openai.com/api/docs/guides/streaming-responses).
