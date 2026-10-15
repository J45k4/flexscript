# MQTT3.1.1 wire and session cores

`lib/net/mqtt.flex` implements the client packet codec and
`lib/net/mqtt-client.flex` adds session and delivery state. Both are native
Flexscript, allocation-free and independent of sockets, clocks and hardware.
The original ESP32 TCP/TLS facade is implemented below and verified against an
independent broker in software and on the physical board. S3 radio integration
and the other ESP32 backlog requirements remain separate.

The protocol reference is the [OASIS MQTT3.1.1 standard](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html),
particularly sections2/3 for packet validation and4.3/4.4 for delivery and
persistent reconnect. MQTT5 and WebSocket transport are outside this profile.

## ESP32 TCP/TLS client API

Import `lib/platform/esp32-mqtt.flex` on the original ESP32. Initialize the
production radio clock, station/IP runtime and application task as in
[ESP32 networking](esp32-network.md). Resolve the broker IPv4 address before
connecting. Secure connections additionally require `esp_tls_set_time` with a
trusted UTC anchor and explicit CA trust through `esp_tls_add_ca`.

`esp_mqtt_init()` retains16 KiB of native storage: the12800-byte session engine,
512-byte receive staging, hostname/client identity and copied authentication
and Will buffers. TLS additionally retains its8 KiB native workspace plus SDK
allocations. There are no message-sized SDK allocations. Check-12 allocation
failures when combining retained clients within the native heap bound.

| API | Behavior |
| --- | --- |
| `esp_mqtt_configure(client,n,clean,keepalive_seconds)` | Copy a UTF-8 client ID, clean-session policy and0..65535-second keepalive while inactive. IDs are bounded to255 bytes. |
| `esp_mqtt_auth(user,n,password,n)` | Copy optional credentials; length-1 means absent. Username/password bytes together are bounded to1024. Input can be released afterward. |
| `esp_mqtt_will(topic,n,payload,n,qos,retain)` | Copy a Last Will while inactive; all-zero arguments disable it. Topic/payload bytes together are bounded to1024. The complete CONNECT must still fit the codec packet bound. |
| `esp_mqtt_retry_policy(first_ms,max_ms,attempts)` | Set exponential reconnect delay and a0..255 consecutive-attempt limit. Zero disables automatic retry; delay bounds are1..300000 ms. |
| `esp_mqtt_connect(ip,port,local_port,host,n,secure,timeout_ms)` | Start the transport to an explicit IPv4 address; secure1 uses authenticated TLS, secure0 plain TCP. Hostname supplies TLS identity. Zero means started, possibly in scheduled retry. |
| `esp_mqtt_poll()` | Advance network service, handshake, partial output, bounded input, protocol exchanges, keepalive, retry and close. Poll regularly from one application task. |
| `esp_mqtt_publish(topic,n,payload,n,qos,retain)` | Queue a binary message when ready. Return zero for QoS0 or a positive packet ID for QoS1/2; -11 means queue backpressure. |
| `esp_mqtt_subscribe(filter,n,qos)` / `esp_mqtt_unsubscribe(filter,n)` | Queue one filter and return its positive packet ID. |
| `esp_mqtt_message()` | Return1 when a copied application message is ready and publish the view fields below. |
| `esp_mqtt_consume()` | Release the application message so the next delivery can advance. |
| `esp_mqtt_disconnect()` | Queue MQTT DISCONNECT after pending output; retry-11 after polling. Continue polling through offline state5. |
| `esp_mqtt_abort()` | Cancel connection, retry or active work, release owned transport and retain persistent QoS state. Reports cancellation-125 without automatic retry. |

`esp_mqtt_state` is0 idle,1 transport connecting,2 awaiting CONNACK,3 ready,
4 closing,5 offline,6 retry/waiting for network or7 failed. Inspect
`esp_mqtt_error` for a negative failure, `esp_mqtt_refused` for a broker refusal
code and `esp_mqtt_tls_flags` for retained certificate verification flags.
`esp_mqtt_session_present`, `esp_mqtt_connections`, `esp_mqtt_reconnects` and
`esp_mqtt_attempts` expose connection progress. Successful CONNACK resets the
consecutive-attempt budget and delay; connection counters remain cumulative.

When a message is ready, `esp_mqtt_topic`/`esp_mqtt_topic_size` and
`esp_mqtt_payload`/`esp_mqtt_payload_size` expose its stable copied bytes.
`esp_mqtt_qos`, `esp_mqtt_retain`, `esp_mqtt_dup` and `esp_mqtt_message_id` carry
metadata. Consume each message before expecting another. A zero-length payload
is valid; use readiness rather than its length. Completion fields are
`esp_mqtt_last_puback`/`esp_mqtt_puback_count` and
`esp_mqtt_last_suback`/`esp_mqtt_suback_count`/`esp_mqtt_sub_result`.

Configuration is copied and cannot change while connecting, ready, closing or
scheduled to retry. Persistent incomplete transactions prevent changing client
identity with clean0. The shared stream reserves owner2 exclusively for MQTT;
existing HTTP, raw TCP or raw TLS ownership returns-16 without taking it over.
Do not mix direct `mc_*`/`mp_*` use with an active platform client. Caller
buffers must not alias the retained workspace.

Automatic retry handles link loss, resets, timeouts and transient refusal.
Certificate/protocol errors and authentication/authorization refusals fail
visibly. Retry attempts use fresh local ports and preserve clean0 QoS exchanges
and TLS trust/RNG state. Polling continues while waiting for Wi-Fi/IP or another
stream owner; those unavailable-resource waits do not spend connection attempts.
The supplied broker address is retained; DNS changes require resolving and
supplying a fresh address. TCP's240-second TIME-WAIT protection is retained.

A normal TLS close authenticates the peer's close-notify and sends the local
notification. `esp_mqtt_close_flags` bit0 records the local notification and
bit1 the authenticated peer notification;3 means both. A late peer TCP reset
is accepted only after both notifications during shutdown, with no pending
application output. Other errors, including TCP timeouts and unauthenticated
EOF, remain failures. Inactive TLS session cleanup retains CA/RNG state; call
`esp_tls_deinit()` after the client is offline to release those SDK allocations.


## Client/session API

`mc_init(work,12800)` uses caller-owned storage for the4 KiB codec, one2 KiB
retained outgoing QoS1/2 packet, two2 KiB incoming QoS2 transactions, a2 KiB
application delivery slot, a255-byte client identity and slot metadata. It
allocates no body-sized buffers. Client identifiers are limited to255 UTF-8
bytes; an empty identifier requires a clean session. Outgoing packet bodies
are at most2043 bytes, incoming remaining-length bodies at most2048 bytes.
An oversized packet is an explicit-90 error. Input/output buffers cannot alias
the complete workspace. Use a single application task for all operations.

| API | Behavior |
| --- | --- |
| `mc_auth(user,n,password,n)` | Configure optional credentials while inactive. Length-1 means absent; a password requires a username. Username is UTF-8; password is binary. Buffers are borrowed until each `mc_begin` copies a CONNECT packet. |
| `mc_set_timeout(ms)` | Set CONNECT/PING response timeout while inactive; defaults to10000 and permits1..300000 ms. |
| `mc_begin(client,n,clean,keepalive_seconds,now_ms)` | Queue CONNECT after a fresh underlying stream is ready. Clean0 retains incomplete QoS exchanges for the same client across reconnects; clean1 discards previous protocol state. |
| `mc_tick(now_ms)` | Advance a received packet, acknowledgments, CONNECT timeout and keepalive. Times must be monotonic. |
| `mc_feed(bytes,n)` | Feed network input; return consumed bytes. Stop at one complete packet until tick processes it. Zero consumption means backpressure. |
| `mc_tx_consume(n,now_ms)` | Tell the core how many bytes the transport accepted from `mp_tx+mp_tx_pos`; retry any remainder. |
| `mc_publish(topic,n,payload,n,qos,retain)` | Queue a binary message. Return its positive packet ID for QoS1/2, zero for QoS0, or a negative error. One outgoing QoS1/2 exchange is retained until acknowledged. |
| `mc_subscribe(filter,n,qos,unsubscribe)` | Queue one filter; unsubscribe1 selects removal. Return the packet ID. One subscription request may await acknowledgment at a time. |
| `mc_message_consume()` | Release the current application message after reading its view; -11 means absent. |
| `mc_disconnect()` | Queue DISCONNECT. Continue sending until state4, then close the transport. |
| `mc_transport_lost(error,now_ms)` | Discard partial wire data and retain persistent QoS state for a later fresh stream. This does not open/retry a connection itself. |

States are0 idle,1 awaiting CONNACK,2 connected,3 disconnecting,4 offline and
5 failed. `mc_error` exposes a negative failure, `mc_refused` the broker's
CONNACK refusal code, and `mc_session_present` the accepted session flag.
The first server packet must be CONNACK; clean sessions reject Session Present.
The transport must drain CONNECT before a response can complete the handshake.

When `mc_message_ready` is1, `mc_message_topic`/`mc_message_topic_size` and
`mc_message_payload`/`mc_message_payload_size` expose the copied message.
`mc_message_qos`, `mc_message_retain`, `mc_message_dup` and `mc_message_id`
carry metadata. Views remain valid until consume/reset. A zero-length payload
is a valid message. Delivery backpressure leaves the next packet pending;
QoS1/2 data is not acknowledged and silently dropped when the application slot
is full. Two incoming QoS2 exchanges can be retained concurrently. Exceeding
that bound fails with-105, preserving already retained transactions for
persistent reconnect; configure the peer's inflight limit accordingly.

QoS2 data is delivered at PUBREL, once. Duplicate PUBLISH repeats PUBREC,
duplicate/unknown PUBREL repeats PUBCOMP, and completed data is not redelivered.
For outgoing QoS2, duplicate PUBREC repeats PUBREL with its required fixed flags.
A persistent reconnect resends the retained PUBLISH with DUP or the pending
PUBREL with the original ID. Packet IDs avoid both outstanding publish and
subscription transactions across16-bit wrap. ACK completion is exposed by
`mc_last_puback`/`mc_puback_count`, and subscription completion by
`mc_last_suback`/`mc_suback_count`/`mc_sub_result`. SUBACK128 is a valid rejected
subscription; invalid grants or mismatched subscription acknowledgments fail.

Keepalive0 disables periodic PING. Otherwise accepted output refreshes the
last-transmit time; idle clients queue PINGREQ and require its response before
the configured timeout. A stalled output queue also has a keepalive bound.
QoS delivery acknowledgments do not have a separate deadline or retry on a
live connection: callers may close/reconnect according to their application
policy. Retained session state is RAM state across network connections; reboot
persistence requires storage integration and is not provided by these cores.

## Packet codec

`mp_init(work,4096)` divides storage into2048-byte TX and RX buffers. Do not
initialize it independently while the session engine owns the same globals.
`mp_feed` accepts fragmented server packets; `mp_state`3 exposes one complete
view and `mp_consume` releases it. State4 carries `mp_error`. `mp_eof` rejects
truncated headers/bodies. Receive views include type/flags, identifier, QoS,
retain/DUP, topic and binary payload, CONNACK/session fields and SUBACK grants.

Builders are `mp_connect`, `mp_publish`, `mp_ack`, `mp_control` and the
`mp_sub_begin`/`mp_sub_add`/`mp_sub_end` sequence, which permits multiple filters
per wire packet. `mp_sub_cancel` cancels unfinished construction. Builders
reject busy TX with-11; transmit `mp_tx+mp_tx_pos` and report progress using
`mp_tx_consume`. `mp_set_will(topic,n,payload,n,qos,retain)` configures borrowed
Will buffers for CONNECT; all-zero arguments disable it. Keep credential/Will
buffers valid for every connection where they are used.

The codec validates reserved flags, allowed client receive directions,
nonzero identifiers, remaining length, exact packet shapes, CONNACK fields,
SUBACK codes, topic/filter wildcard placement and UTF-8. It rejects NUL,
overlong UTF-8, surrogates and values beyond U+10FFFF; BOM bytes are preserved.
Binary passwords, Will bodies and publish payloads are not UTF-8 constrained.
Nonminimal remaining-length encodings are rejected by this strict profile.

## Verification

Build and run `scripts/test-esp32-mqtt.flex` with the explicit installed/compiler
override, GNU linker/ROM inputs and Espressif QEMU, as for the other ESP32
harnesses. `--report FILE` preserves the independent wire report. The default
suite runs the codec and session behavior both natively and from cached-flash
Xtensa firmware:47 harness checks. It also runs2322 packet/reference/guard
checks covering81 valid cases,286 strict failures, all35 prefixes of selected
packets and1024 mutations. Guard pages bound complete workspaces and input;
Python's strict Unicode decoder and a separate struct-based MQTT reference
check decoded views and binary bodies.

An optional `--broker /path/to/mosquitto` adds one check for48 total and runs
`tests/esp32/mqtt-broker-interop.py` against an explicitly supplied real broker.
The helper starts a temporary loopback-only listener, never a host service.
A Linux socket test adapter for the same native core sends at most17 bytes and
receives at most31 per operation. Mosquitto2.0.22 independently verifies QoS0/1/2
publishes and looped-back deliveries, subscription/unsubscription, PING and a
second connection with Session Present. Four exact binary message bodies,
three completed outgoing QoS1/2 transactions and all acknowledgments pass.
This is native core/broker evidence, not ESP32 radio or Mbed TLS evidence.

The tested broker was separately built from the official2.0.22 source archive,
SHA256 `2f752589ef7db40260b633fbdb536e9a04b446a315138d64a7ff3c14e2de6b68`.
The harness does not download or install it. The optional full suite also supplies `--tls`, `--vendor`, `--prefix` and
`--password-tool` for the explicit Mosquitto password utility. It runs actual
Xtensa firmware and Mbed TLS against the authenticated TLS broker through a
UART BIO transport, covering transactions, refusals, hostname verification,
cancellation, retry exhaustion, retained QoS reconnect, owned configuration,
allocation failure, Last Will/retained delivery and shutdown regressions.
QEMU models only the missing radio transport; its fixture initializes the same
80 MHz APB clock as production before starting the SDK microsecond timer.
The full harness passes60 checks, including the12 Xtensa TLS/broker cases,
alongside2322 wire/reference/guard checks. Shared TLS84 and HTTP29/816 wire
regressions also pass. Shutdown cases require production close-notify parsing
without a fixture reading alerts on its behalf; authenticated late reset is
accepted, while a TCP timeout stays visible. An old-driver control fails the
close case, and an unrestricted-error control fails the timeout case.

The physical original-ESP32 probe completes six exact binary publishes and
looped-back deliveries at QoS0/1/2 over both native TCP and authenticated
TLS1.3. Payloads are137,168 and1900 bytes; the largest spans TCP segments.
Mosquitto independently records the exchanges, subscription/unsubscription and
PING traffic. Plain TCP abort releases ownership, and final MQTT DISCONNECT
completes with both TLS close notifications. TLS SDK allocations return to zero
and Wi-Fi reports zero dropped frames. The helper restores and checksum-verifies
the original full4 MiB firmware, then resets the board. Physical automatic
reconnect and negative certificate cases are not claimed; they have the
independent TLS/broker emulator coverage described above.
