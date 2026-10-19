# Native ESP32 networking

Original ESP32 firmware now has a reusable station lifecycle, Ethernet packet
bridge and a native Flexscript IPv4 core. No FreeRTOS, ESP-IDF application or
application C sources are introduced. Optional TLS links separately built
Mbed TLS vendor archives through native Flexscript hooks. GNU ld links the same pinned vendor
radio archives described in [vendor integration](esp32-vendor.md).

A physical original ESP32 joined the supplied Wi-Fi network, received Ethernet
frames, disconnected and reconnected. A network probe obtained an IPv4 lease,
renewed it, resolved `example.com`, echoed an exact UDP payload to the Linux
host and answered host ICMP echo requests. Original flash was restored and its
entire 4 MiB checksum verified after both probes. Evidence is under
`build/esp32-goal-verification/`; no credentials are stored there.

Repeated network firmware initially failed with handshake timeout or UART
provisioning stalls. The original-chip UART count mask included receiver-state
bits, allowing reads from an empty FIFO while the next byte arrived. An
independent register fixture reproduces the old driver failure; the corrected
adapter passes. The same corrected image then passed private provisioning
integrity, DHCP acquisition/renewal, DNS, UDP echo and ping twice. Both runs
restored and checksum-verified the original 4 MiB image. Moving callbacks into
SRAM was an unsuccessful diagnostic and remains outside production.

## Station and packet APIs

Station stop/start/deinit and resource ownership are described in
[radio lifecycle](esp32-radio-lifecycle.md).

Import `lib/platform/esp32-wifi.flex`. Initialize the radio clock, SDK arena
and task runtime as in `examples/esp32-wifi-connect.flex`, then call
`esp_wifi_station_init()` and wait for `esp_wifi_started`. Call
`esp_wifi_join(ssid,ssid_size,password,password_size,auth)` with explicit byte
lengths. Supported authentication thresholds are open (0), WPA-PSK (2),
WPA2-PSK (3), WPA/WPA2 (4), WPA3-PSK (6), and WPA2/WPA3 (7); physical verification
used WPA2. The pinned vendor library performs authentication. Credentials stay
in RAM, and the facade clears/frees its temporary configuration after the
vendor call. Firmware examples receive credentials over UART without echo.
Do not put passwords into source, command-line arguments or log output.

Call `esp_wifi_poll()` regularly. A disconnect schedules retries outside the
vendor callback; `esp_wifi_retry_policy(base_ms,max_ms,attempt_limit)` controls
capped exponential backoff. Defaults are 250 ms, 8 seconds and eight attempts;
a zero attempt limit explicitly selects unlimited retries. Individual
connection attempts time out after 20 seconds. `esp_wifi_disconnect()` cancels
retry intent; `esp_wifi_reconnect()` reuses the configuration already in RAM.
`esp_wifi_linked`, `esp_wifi_reason` and `esp_wifi_last_error` expose status.

Join, connect/reconnect, disconnect and polling share one control-operation
lease. A concurrent control call, lifecycle transition, ISR or already masked
caller returns -16 before changing retry intent. Stop/start/deinit also return
-16 while a control call owns its vendor frame or temporary configuration.
Vendor config/connect/disconnect calls run unmasked, including while another
task executes packet TX/RX. Retry policy updates and event state publication
use a short saved interrupt mask.

Inline or asynchronous connected/disconnected/stopped events advance the link
generation. An older connect/disconnect/timeout call only commits its synchronous
state result if that generation still matches. Its return value remains the
vendor result, so it can report an error while a newer connected event has
already published a valid link; inspect the current state separately. A timeout
schedules its retry from the completed disconnect call, while a newer disconnect
event retains the deadline it published. A stopped event clears the connection
deadline. Poll rechecks retry eligibility atomically before starting another
attempt. Failed or overlapping calls leave the control lease recoverable; join
clears all 184 temporary configuration bytes before freeing them on success,
validation failure and vendor failure.

An independent windowed-C peer verifies real preempted config/connect/disconnect
frames, event injection before return, credential lifetime/clearing, timeout
backoff and allocation rollback. Six forced windows and eighteen isolated
defects exercise admission, policy/event/retry publication and stale returns.
These checks use existing QEMU; physical preemptive RF operation remains open.

The Ethernet RX callback copies into four bounded 1536-byte slots and releases
the vendor buffer outside the critical section, including on overflow. No
per-packet allocation occurs. A producer reservation protects its slot while an
application consumer drains older frames. A callback activity count stays held
through the vendor free call, even when a dropped frame never entered the ring.
Callbacks received during lifecycle operations drop their frame and release its
vendor buffer. The vendor must deliver callbacks in its normal unmasked task
context. Driver deinitialization remains responsible for quiescing future
callbacks before its resources disappear.

`esp_wifi_receive(buffer,capacity)` returns the frame length, zero for empty,
or -90 without consuming an oversized frame. One consumer owns an RX copy;
an overlapping consumer, ISR use or a lifecycle transition returns -16. Slot
copying runs outside the adapter's interrupt mask, while head/count publication
is atomic. The application owns its output buffer through the return.

`esp_wifi_transmit(buffer,size)` returns -107 before association and -16 during
lifecycle operations or when called from an ISR/critical section. Concurrent
application TX calls retain separate activity references through vendor return.
The [pinned internal TX API](https://github.com/espressif/esp-idf/blob/v5.5.1/components/esp_wifi/include/esp_private/wifi.h)
copies the supplied data; the caller retains its input through the call and may
reuse it after return. Successful-send counters update under the interrupt mask.
The vendor TX and RX-free calls remain unmasked so their mutex paths can run.
`esp_wifi_rx_dropped` counts rejected incoming frames. The IPv4 facade still
requires one application consumer on CPU0.

Station stop/start/deinit return -16 while packet copies or vendor frames hold
activity references. If a callback enters during vendor stop and its free call
is still active when stop returns, the native state records the stopped driver
and retains its allocations. Retry the lifecycle call after the callback exits.
The final activity check, domain release and ring removal are atomic. Atomic
ring construction also rejects a second constructor without leaking an arena
allocation. Independent C TX/free rendezvous, ten forced transaction windows
and seventeen isolated defects verify these rules on existing QEMU. These
software checks do not establish physical preemptive RF operation; the wider
radio audit remains open, and examples retain cooperative startup.

## IPv4, DHCP, DNS, UDP and TCP

Import `lib/platform/esp32-ip.flex` and call `esp_ip_init()` after station
initialization. Call `esp_ip_poll()` from one application task. It drives
connection retries, frame delivery, DHCP and DNS, and flushes pending output.
`en_ip`, `en_mask`, `en_gateway` and `en_dns` are network-order IPv4 integers.
Zero `en_ip` means there is no configured address. Link/address changes discard
old UDP data; an active DNS lookup keeps failure state3/error-107 after link
or address loss. Cached answers and their expiry are invalidated on a new link.

- Ethernet, an eight-entry expiring ARP cache, IPv4 header validation, ICMP echo
  replies, and UDP pseudo-header checksums are implemented. Reassembly accepts
  one fragmented datagram up to 1500 IP bytes in a separate 2048-byte arena.
  Reordering is supported; overlaps poison that datagram until its fixed
  60-second deadline. Timeout replies quote fragment zero when permitted.
  Reassembly state is discarded on address or link changes.
- DHCP supports discover/offer/request/acknowledgment, NAK restart, T1 renewal,
  T2 rebinding, lease expiry, option-overload fields and server/transaction/MAC
  correlation. The facade enables address-conflict detection: three randomized
  ARP probes before publishing an address, two announcements and ongoing
  monitoring. Conflicts immediately relinquish the address, send DHCPDECLINE
  and wait at least10 seconds before restarting; repeated conflicts impose a
  one-minute acquisition limit. Unchanged-address renewal skips re-probing.
  `esp_ip_dhcp_renew()` requests an early renewal of a bound lease.
- `esp_ip_resolve(name,size)` starts an IPv4 A lookup. Poll until `dn_state` is
  2 (answer in `dn_result`) or 3 (failure in `dn_last_error`). The resolver checks
  peer, transaction and question, bounds compressed names, follows CNAMEs
  independent of answer order, and limits retries and the total lookup time.
- `esp_ip_udp_bind(port)` selects one application port. Four datagrams can be
  queued; queue memory is allocated at the first bind. `esp_ip_udp_receive(buffer,capacity,metadata)` returns the payload
  length, including zero for an empty datagram, or -11 when empty. Metadata is
  three 64-bit words: source IPv4 address, source port and destination port.
  Too-small output returns -90 without consuming the datagram.
- `esp_ip_udp_send(ip,port,buffer,size)` uses the bound local port. -11 means
  output is busy or ARP resolution is pending; keep the data and poll/retry.
  The maximum UDP payload is 1472 bytes; queue overflow increments
  `esp_ip_event_dropped`. Hardware and application errors remain visible.

This is an initial IPv4 implementation. Optional authenticated TLS and the
HTTP/1.1 client have independent OpenSSL/QEMU and physical ESP32 verification.
The [MQTT client](esp32-mqtt.md) is also verified against an independent broker
natively, in cached-flash Xtensa/QEMU and on the original ESP32 over TCP/TLS. See
[TLS configuration and verification](esp32-tls.md). There
is no IPv6, AAAA lookup or DNSSEC validation. Those limitations
must not be treated as complete general network support. The supplied examples
use cooperative scheduling and require regular polling; there is one network
interface and one bound application UDP port. The shared station facade now has
an S3 adapter and typed vendor-ABI/lifecycle checks. Full S3 vendor startup reaches
a PHY-ready register missing from stock QEMU; S3 radio/network operation still
requires physical verification. See [vendor integration](esp32-vendor.md).

## DNS over TCP

A correlated UDP reply with its TC flag set requests a TCP retry. The facade
allocates a private DNS connection on demand: 4096 bytes of TCP storage, two
512-byte connection snapshots and a 4098-byte framing buffer. It preserves
the application TCP connection across input, polling, errors and shutdown.
`esp_ip_resolve_tcp(name,size)` selects TCP immediately when desired. Both
resolver entry points use the same `dn_state`, result/error and ten-second
lookup deadline.

The two-byte network-order DNS length prefix can arrive separately from the
body. Replies are bounded to4096 DNS bytes, validate the transaction, question,
compressed names and every record before publishing an answer, and support
persistent TCP connection reuse. Malformed lengths, premature EOF, connect
failure and timeout yield explicit errors. A partially transmitted query is
abandoned before another lookup can reuse the connection. The application
connection is independently cancelled only when the interface/address is lost.

For a standalone caller, `dn_start_tcp` starts a direct TCP lookup and
`dn_transport==1` signals UDP truncation fallback. Initialize `dt_init` with
caller-owned TCP4096/context512/application512/receive4098 buffers, call
`dt_input(now_ms)` before the application TCP input and call `dt_poll` after
`dn_poll`. Drain pending Ethernet output between protocol connections.
Only one lookup is active at a time; oversized replies fail with -90 rather
than allocating unbounded memory. This resolver does not implement EDNS,
DNSSEC, AAAA, or concurrent query pipelining.

See [DNS transport over TCP, RFC 7766](https://www.rfc-editor.org/rfc/rfc7766).

## TCP streams

The facade allocates a 4096-byte TCP workspace on the first open. There is one
connection, a 2048-byte receive window and at most one outstanding segment.
`esp_ip_tcp_connect(ip,port,local_port)` starts an active open;
`esp_ip_tcp_listen(port)` accepts one inbound connection. Keep calling
`esp_ip_poll()`. State `tc_state==4` means established; 7 means the peer closed
its sending direction; 11 means failure in `tc_error`. Peer address/port are
`tc_remote_ip` and `tc_remote_port`.

`esp_ip_tcp_send(buffer,size)` copies and accepts a prefix, returning its byte
count. Keep the remainder and retry after polling; -11 means backpressure.
`esp_ip_tcp_receive(buffer,capacity)` returns stream bytes, -11 when empty,
or zero after peer FIN and draining queued bytes (also for zero capacity).
`esp_ip_tcp_close()` requests FIN after accepted output is acknowledged.
Continue polling through shutdown; state0 is closed and state10 retains the
connection in TIME-WAIT. Link or address loss cancels an active connection
with error-107.

The core validates checksums and options, handles sequence wrap and partial
ACKs, bounds receive memory, rejects out-of-window/reset spoofing, and follows
exponential retransmission backoff with RTT sampling. It retains queued data
across zero-window probes. Fresh outgoing data carries pending receive/window ACKs, so
reading input cannot repeatedly postpone an accepted write. In-flight data
still receives standalone ACKs, and zero peer windows retain persist behavior. Initial/minimum RTO is one second, capped at60
seconds; eight retransmissions cause an explicit timeout. FIN-WAIT-2 has a
60-second resource timeout and TIME-WAIT lasts240 seconds. Out-of-order data
is acknowledged and discarded for retransmission. Window scaling, SACK,
timestamps and a separate urgent-data API are not implemented. Throughput is
conservative; this does not provide multiple simultaneous sockets.

The standalone packet core uses caller-owned storage via `tc_init(work,4096)`
and `tc_connect`/`tc_listen`, `tc_send`, `tc_receive`, `tc_close`, `tc_poll`.
Pass each `en_input` result6 to `tc_input(now_ms)` and drain `en_tx_size`.
Independent TCP fixtures cover active/passive/simultaneous opens, sequence
wrap, partial ACK/retransmit, duplicate/overlapping data, window exhaustion,
persist probes, FIN states, TIME-WAIT reset protection and timeout. Another
4096 mutated/truncated TCP frames run against guarded input and workspace.
The ESP32 QEMU image runs the same behavioral fixtures.

Protocol references: [TCP, RFC 9293](https://datatracker.ietf.org/doc/html/rfc9293),
[retransmission timers, RFC 6298](https://www.rfc-editor.org/rfc/rfc6298), and
[congestion control, RFC 5681](https://www.rfc-editor.org/rfc/rfc5681).

## Build and verification

Build either example with the existing radio builder's `--source` option:
`examples/esp32-wifi-connect.flex` or `examples/esp32-wifi-network.flex`.
`examples/esp32-wifi-tcp.flex` instead listens on TCP port4243 and echoes one
connection through orderly close. A physical8192-byte binary echo and host
EOF passed with zero retransmissions or RX drops. A later probe opened an
active DNS TCP connection, reused it for two real queries and transferred an
exact8192-byte application stream on an independent TCP connection, again
with zero retransmissions or RX drops. UDP-truncation fallback is independently
fixture/QEMU verified; the physical DNS probe selects TCP directly. Original
full4MiB flash was restored, checksum verified and reset after the probe.
The network example obtains/renews a lease, resolves a name and runs a UDP echo
service on port 4242 for 30 seconds. Supply SSID and password as separate UART
lines after the corresponding prompts; neither is echoed.

The linker suite includes an independent windowed-C ABI fixture for station
configuration, events, retry limits, RX ownership, queue wrap/overflow and
transmit guards. `scripts/test-esp32-network.flex` runs independent generated
wire fixtures on Linux and in cached-flash ESP32 firmware under QEMU. A native
guard-page test exercises 1024 mutated/truncated frames and a guarded reassembly
workspace. The network harness passes 118 checks, including reassembly on the
native host and cached-flash ESP32 QEMU; the vendor-linking suite passes 1004. Python is used only
to generate independent packet/reference bytes under `tests/esp32/`. DNS/TCP
coverage includes split framing, persistent reuse, independent application
traffic, timeout/EOF/malformed replies, a maximum-size4096-byte message and
4096 guarded mutations; the same behavior suite runs from flash in QEMU.

The standalone Ethernet core enables reassembly with
`en_fragment_init(workspace,2048)` after `en_init`; call
`en_fragment_expire(now_ms)` even when no packets arrive. Packet views from
reassembly refer to this workspace and expire on the next input operation.
The ESP32 facade initializes and polls this automatically.

Protocol references: [IPv4, RFC 791](https://datatracker.ietf.org/doc/html/rfc791),
[host reassembly, RFC 1122 section 3.3.2](https://www.rfc-editor.org/rfc/rfc1122#section-3.3.2), [ARP, RFC 826](https://www.rfc-editor.org/rfc/rfc826),
[address conflict detection, RFC 5227](https://www.rfc-editor.org/rfc/rfc5227),
[DHCP, RFC 2131](https://www.rfc-editor.org/rfc/rfc2131),
[DHCP options, RFC 2132](https://www.rfc-editor.org/rfc/rfc2132), and
[DNS, RFC 1035](https://www.rfc-editor.org/rfc/rfc1035).

## HTTP framing core

`lib/net/http.flex` implements bounded HTTP/1.1 request construction and response
framing, following [RFC9112](https://www.rfc-editor.org/rfc/rfc9112.html).
The ESP32 client facade below owns transport and upload scheduling. The
[MQTT client](esp32-mqtt.md) provides the other application protocol under T136.

`hp_init(work,6144)` uses caller-owned storage: 2048 bytes for request headers,
2048 for response headers and trailers together, 1024 for queued response body,
and 1024 for chunk-size/trailer lines. It performs no allocation or device I/O.
The default decoded-body limit is16MiB; `hp_set_limit(bytes)` changes it while
inactive, up to2147483647 bytes. Header blocks permit64 fields, at most8 interim
responses, and16384 cumulative header/trailer bytes across a response.

| API | Behavior |
| --- | --- |
| `hp_begin(method,n,target,n,body_length,keep_alive)` | Begin a new transaction after the prior body queue drains. Length-1 selects chunked request framing. |
| `hp_host(host,n,port)` | Add the managed Host field; required exactly once. |
| `hp_add_header(name,n,value,n)` | Add a validated application header; managed framing fields cannot be overridden. |
| `hp_finish_request()` | Finalize `hp_request`/`hp_request_size`; the transport must transmit these bytes and frame the request body. |
| `hp_feed(bytes,size)` | Consume response bytes, returning the count accepted or a negative error. A full body queue can leave input unconsumed. |
| `hp_read(out,capacity)` | Drain body bytes; -11 means waiting, zero means the complete body has drained, and other negative results are failures. |
| `hp_field(name,n,occurrence,trailer)` | Return a field-value pointer and set `hp_field_size`; zero means absent. Headers and trailers remain separate. |
| `hp_eof()` | Complete an EOF-delimited response or report truncation for unfinished fixed/chunked framing. |

Response states are0 idle,1 headers,2 fixed-length body,3 EOF-delimited body,
4 chunk size,5 chunk data,6 chunk terminator,7 trailers,8 complete and9 failed.
`hp_status`, `hp_error`, `hp_received`, `hp_final_headers` and `hp_reusable`
expose the result. Partial body bytes can precede an error; check state8 before
publishing a completed download. Reuse additionally requires the transport to
remain open and the request body to have been sent completely. Metadata and
returned pointers are valid until the next transaction or reinitialization.
Input/output buffers must not alias the core workspace.

The core handles fixed-length, chunked and EOF-delimited responses, HEAD,
no-body statuses, informational responses, duplicate identical Content-Length
values, chunk extensions and bounded trailers. It rejects conflicting lengths,
combined Transfer-Encoding/Content-Length, unsupported transfer codings,
obsolete folded fields, malformed CRLF/chunks, forbidden framing trailers,
truncation and unsolicited bytes after a completed response. CONNECT, protocol
upgrades, Expect-driven request scheduling and HTTP/2 are outside this core.
Redirect and authentication fields are exposed for caller policy.

`scripts/test-esp32-http.flex` runs native tests and the same core from cached
flash in Espressif QEMU. The independent Python `http.client.HTTPResponse`
reference corpus covers12 valid forms,33 strict-profile failures, every prefix
of representative fixed/chunked messages,512 mutations and multiple input
fragment sizes. Guard pages protect the wire input and complete workspace;
canaries also check internal buffer boundaries. Current validation reports816
wire/reference/guard checks and24 core compiler/runtime harness checks. With
`--vendor`, `--tls` and `--prefix`, the harness additionally runs five independent
OpenSSL cases for29 total harness checks. See the facade verification below.


## ESP32 HTTP/1.1 client

Import `lib/platform/esp32-http.flex`. The native client uses an8 KiB retained
workspace including the6 KiB framing core, a1 KiB upload queue,512 bytes of
receive staging and the hostname. HTTPS additionally uses the TLS adapter's
8 KiB workspace and its SDK allocations. Response bodies stream through the
bounded queue; a large download does not allocate its complete body.

Initialize Wi-Fi, IPv4 and the application TCP workspace, wait for DHCP and
resolve the server's IPv4 address first. HTTPS also requires an explicit CA and
trusted UTC anchor through `esp_tls_add_ca` and `esp_tls_set_time`. All calls
belong to the same cooperative application task.

| API | Behavior |
| --- | --- |
| `esp_http_connect(ip,port,local_port,host,n,secure,timeout_ms)` | Connect to the resolved IPv4 address; secure1 selects authenticated TLS and secure0 plain TCP. The hostname supplies Host and TLS identity. Zero means connection started. |
| `esp_http_poll()` | Advance transport, request output, response framing and close; keep polling and draining body data. |
| `esp_http_begin(method,n,target,n,body_length,keep_alive)` | Build a request once ready or after draining a reusable response. Length-1 selects chunked upload. |
| `esp_http_header(name,n,value,n)` | Add a validated application header before ending headers. Host, framing and connection headers are managed. |
| `esp_http_end_headers()` | Queue the completed request headers for transmission. |
| `esp_http_write(bytes,n)` | Accept upload bytes, returning the count accepted. Retry the remainder; -11 means backpressure. Chunked writes accept up to1000 payload bytes per queued chunk. |
| `esp_http_end_body()` | Verify a fixed upload's declared byte count or queue the final zero chunk. Retry -11 after polling. Fixed bodies finish automatically when the declared count is accepted; chunked bodies require this call. |
| `esp_http_read(out,capacity)` | Drain decoded response-body bytes. -11 means waiting, zero means complete and drained, and other negative values are errors. |
| `esp_http_field(name,n,occurrence,trailer)` | Return a field pointer; `hp_field_size` holds its length. Set trailer1 for trailers. Pointers expire at the next request. |
| `esp_http_set_limit(bytes)` | Set the decoded response-body bound while no transaction is active; defaults to16 MiB and permits up to2147483647 bytes. |
| `esp_http_close()` / `esp_http_abort()` | Gracefully close a completed transaction or cancel active work. Poll through state7 before starting another connection. |

`esp_http_state` is0 idle,1 connecting,2 ready,3 building,4 transaction,
5 response complete,6 closing,7 closed or8 failed. Status, negative failure,
decoded byte count and reuse permission are exposed through `esp_http_status`,
`esp_http_error`, `esp_http_received` and `esp_http_reusable`. State5 can still
have unread body bytes. Drain them before beginning another request. A4xx/5xx
HTTP status is a valid response, not a transport failure. Buffered prefix data
can precede a framing/transport failure; require state5 for a complete download.

The timeout is1..300000 ms. Upload/response progress refreshes the transaction
inactivity deadline; connection and shutdown also have deadlines. An early
final response stops unsent upload data and disables reuse. Completed downloads
can reuse a persistent connection only when the request has fully drained,
framing permits reuse and the peer remains open. A reset of the TLS session
retains the configured CA and seeded RNG for another connection; call
`esp_tls_deinit` after closing when those resources should also be released.

The shared stream grants one protocol exclusive ownership of the application
TCP connection. Raw TCP/TLS or another protocol already using it causes-16.
After closing, TCP retains its240-second TIME-WAIT protection, which can delay
a fresh connection; a reusable HTTP connection avoids that shutdown. Continue
calling `esp_ip_poll()` whenever the HTTP client is idle or closed so DHCP,
TCP timers and other network housekeeping progress. HTTP polling services the
network while it owns an active stream. HTTP pipelining, HTTP/2, CONNECT,
upgrades and Expect-based upload scheduling are not implemented. Redirects,
authentication and Content-Encoding decompression are caller policy.

The OpenSSL peer verifies exact GET, fixed137-byte POST and chunked3137-byte
POST requests, a4200-byte chunked response with trailers, persistent reuse and
a second authenticated connection using the retained trust setup. Additional
cases cover conflicting response lengths, early413 during upload, inactivity
timeout and cancellation. TLS BIO writes are fragmented into17-byte steps with
backpressure; tests assert exclusive ownership and release all TLS SDK bytes.
These are emulator tests with an independent TLS/HTTP peer, not radio tests.

Separate physical original-ESP32 probes use the production HTTP facade over
plain TCP and certificate-verified HTTPS to request `example.com`. Both return
HTTP200 and validate a nonempty decoded body, byte accounting, Content-Type,
clean ownership release and TLS allocation cleanup. An additional plain-TCP
probe sends1787 bytes of request headers with a1400-byte TCP MSS, verifying
partial header output and backpressure against the live peer; it also returns
HTTP200 with zero dropped Wi-Fi frames. Each probe restores and
checksum-verifies the original full4 MiB firmware. Uploads, persistent HTTP
reuse, negative protocol cases and S3 networking remain covered only at the
scopes described above; physical S3 radio verification is still outstanding.
