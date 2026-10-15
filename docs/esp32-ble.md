# Native BLE host and controller transport

The original ESP32 has physically verified standalone BLE scanning and
advertising. The new connection/ACL host core and ordered VHCI transport are
implemented in Flexscript and have native, independent wire-model and Xtensa
emulator coverage. The platform connection/control adapter is integrated and
software tested. Physical connection events have been observed, while complete
independent-peer connection/data exchanges remain open under T137 in
[the backlog](../esp32_todo.md).
The [ATT/GATT server](esp32-gatt.md) is integrated and software tested.
Pairing and bonding remain separate work. Wi-Fi and Bluetooth still use
separate firmware images; coexistence is not implemented.

## Host core

[ble-host.flex](../lib/net/ble-host.flex) is allocation-free and independent of
hardware, clocks and the transport. The caller supplies `4096 + 2320*links`
bytes for one to four connections:6416 bytes for one,13376 for four.
Each link has bounded1024-byte L2CAP receive/transmit bodies, including separate
storage for each direction. Eight copied control events and one stable outgoing
H4 packet use the shared workspace. Original Bluetooth firmware has a small
native bump heap; its platform adapter must reserve this workspace from the SDK
arena instead of assuming that native `alloc` can hold the whole runtime.

Initialize with `bh_init(work,capacity,links)` and set the controller's actual
ACL packet length/count using `bh_set_buffers(mtu,count)` before accepting
connections. `bh_set_host_flow(1)` is optional, and may only be used after the
controller accepts Host Buffer Size and controller-to-host ACL flow control.
The effective transmitted fragment limit is at most1024 bytes.

Feed complete H4 events/data to `bh_input(packet,size,monotonic_ms)` in receipt
order; call `bh_tick(monotonic_ms)` for partial-reassembly deadlines. The core
handles legacy/enhanced LE connections, disconnects, connection updates,
encryption events, remote features, data-length events and completed-packet
credits. Application connection tokens increase each time a new link is
created; a reused controller handle cannot revive an old token.

- `bh_send(token,cid,body,size)` copies an outbound L2CAP PDU. One pending PDU
  per link is supported; a full slot returns-11.
- `bh_next_packet()` returns a stable H4 packet through `bh_packet` and
  `bh_packet_size`. Retry without changing it when transport submission is busy.
  Call `bh_packet_sent()` only after the transport accepts/copies it. HCI ACL
  credits are spent then and returned by controller completion/disconnect events.
  Optional host-completed acknowledgments do not consume ACL or ordinary command
  credits, and alternate with available ACL output to avoid starving it.
- `bh_message(token)` returns1 and exposes `bh_message_cid`, `bh_message_data`,
  `bh_message_size` and `bh_message_encrypted`; zero means no complete message.
  Consume the copied PDU with `bh_consume(token)`. An unread PDU makes another
  first fragment return-11: retain that input packet and retry after consumption.
- `bh_message_encrypted` records controller encryption at the first fragment,
  including an empty first fragment. Later encryption changes do not relabel old
  data. This flag does not establish authenticated pairing, MITM protection or
  bonding; those require the pending security implementation.
- `bh_next_event()` exposes a stable copied event view; release it with
  `bh_consume_event()`. Event kinds are1 connection,2 disconnection,3 connection
  update,4 encryption,5 remote features,6 data length,7 other HCI/LE event,
  8 fatal controller error and9 per-link framing/timeout failure. Raw H4 bytes,
  connection token, status and event-specific detail accompany the view.

Message views are valid only until consumption, disconnect or reinitialization.
Event views last until event consumption or reinitialization. Check each API's
return before reading its output globals. `bh_error` is fatal host/controller
state; `bh_last_error` and `bh_fault_connection` also describe per-link faults.
Malformed L2CAP framing or a10-second partial timeout closes the affected link
for new sends, while other links can progress. The platform must issue the
actual disconnect. Event overflow and invalid controller-credit accounting are
fatal; do not continue with uncertain state.

Fixed CIDs4/5/6 and raw dynamic CIDs64..127 are transported. Dynamic channel
negotiation, LE credit-based channel flow control, GATT and SMP policy are not
provided by this core. Unsupported CIDs are streamed/discarded without allocating
the advertised body. Fragmented Basic Headers, binary data, empty fragments and
L2CAP payloads through1024 bytes are covered by the wire reference.

## VHCI transport

[esp32-bluetooth.flex](../lib/platform/esp32-bluetooth.flex) supplies bounded,
separate event and ACL rings plus isolated command responses. Every valid
received packet has a monotonically increasing receipt sequence, including
command responses and packets subsequently dropped for capacity.
`esp_bt_hci_peek_packet()` returns the older ring head through `esp_bt_packet`,
`esp_bt_packet_size`, `esp_bt_packet_kind` and `esp_bt_packet_sequence`.
`esp_bt_hci_consume_packet()` checks ownership/sequence before releasing it;
stale or double consumption returns-16. Appending newer packets cannot overwrite
a retained head. One application consumer owns the stream; do not mix merged
consumption with the legacy event or ACL consumers.

`esp_bt_hci_send_packet(pointer,size)` accepts host ACL frames and the special
Host Number Of Completed Packets command. It copies into retained transport
storage and returns0, or returns-11 when unavailable without changing that
storage. A send-ready callback releases transport ownership; Number Of Completed
Packets events separately replenish the core's ACL credits. Host-completed
acknowledgments can bypass an ordinary in-flight HCI command, but cannot reuse
in-flight send storage. Other raw commands are rejected; use the command API.
The consumer must monitor both overflow counters and recover after packet loss.
No packet path allocates memory.

## Platform connection API

[esp32-ble.flex](../lib/platform/esp32-ble.flex) reserves the HCI stream for one
application SDK task. Initialize production radio clocks, the SDK heap/tasks and
interrupts first, then call `esp_ble_start(links)`. It configures the controller's
connection limit and initializes the host. If the controller is already freshly
initialized, `esp_ble_init(links)` initializes just the host; pending packets,
prior loss, in-flight transport ownership or an active host are rejected.
One to four links are accepted, with actual multi-link RF behavior unverified.
The adapter uses `bh_size(links)+768` SDK bytes,7184 for one connection, in
addition to the controller, queues and shared SDK services.

Startup resets the controller, enables lifecycle/security/credit event masks,
reads its actual LE ACL size/count and public address, and falls back to shared
BR/EDR buffers if the controller reports no separate LE buffers. Optional host
receive flow control is enabled only after successful Host Buffer Size and
Set Controller To Host Flow Control commands. Unsupported commands retain the
bounded-queue fallback; other errors fail initialization. `esp_ble_address`
points to six bytes in HCI wire order.

- `esp_ble_advertise(data,size,scan_response,scan_size,interval)` configures and
  starts legacy connectable public-address advertising. Each data block is at
  most31 bytes. Interval units are0.625ms, range32..16384. Reconfigure while
  stopped; `esp_ble_advertise_enable(0/1)` stops/restarts the saved configuration.
  Connection establishment stops the advertising flag; restart explicitly after
  a disconnect if desired.
- `esp_ble_connect(peer,address_type,min_interval,max_interval,latency,timeout,
  connect_ms)` starts an asynchronous central connection to a six-byte wire-order
  address. Address type0 is public,1 random. Connection interval and supervision
  units are1.25ms and10ms respectively. The initiation timeout is1..300000ms.
  `esp_ble_connecting` is0 idle,1 initiating,2 awaiting cancellation completion.
  `esp_ble_cancel()` requests cancellation; late successful connections after
  cancellation/timeout are immediately closed. Check connection events and
  `esp_ble_connect_error`; successful command submission is not a connection.
- `esp_ble_disconnect(token,reason)` issues HCI Disconnect and stops new sends.
  The token remains assigned until the actual disconnection event. Repeating an
  already-issued disconnect does not send another command.
- `esp_ble_update(token,min,max,latency,timeout)` submits LE Connection Update;
  the subsequent update event determines completion. Closing/stale tokens are
  rejected. Controller/link support determines whether the request is accepted.
- `esp_ble_poll()` drains up to16 ordered received packets and submits up to16
  outgoing packets. Continue polling and consuming application messages/events.
  Receive backpressure retains the queued frame; an abandoned view initiates
  disconnect after10 seconds so it cannot block the entire stream forever.
- `esp_ble_send(token,cid,data,size)`, `esp_ble_message(token)` and
  `esp_ble_consume(token)` wrap copied L2CAP output and the core's message view.
  CID5 belongs to the adapter. `esp_ble_event()` and
  `esp_ble_consume_event()` expose/release the core's copied events.

The adapter answers LTK requests negatively until security/key handling is
implemented. It accepts valid controller connection-parameter requests and
rejects invalid parameters. LE signaling uses a23-byte MTU and one command per
PDU: a Central can accept a valid peripheral parameter request and submit the
HCI update, while a Peripheral rejects the wrong direction. Unknown commands
receive Command Reject; malformed signaling closes the affected link. GATT,
SMP, bonded keys and dynamic-channel negotiation remain separate work.

Ordinary HCI commands spend controller-granted command credits, including grants
from status-less NOP Command Complete events. Host-completed acknowledgments use
the separate special path; their error responses cannot steal an ordinary
response or grant/remove its credits. Such acknowledgment errors are fatal to
the stateful adapter. Transport errors, lost packets and invalid host accounting
also fail closed. `esp_ble_state` is0 uninitialized,1 active,6 failed;
`esp_ble_error` retains fatal errors. Positive controller statuses are exposed
as `-4096-status`, and the raw status is in `esp_ble_last_status`.
Initialization failure can leave resources reserved if rollback fails.
Use `esp_ble_stop()` or, with GATT, `esp_gatt_stop()` to shut down and release
resources; see [radio lifecycle](esp32-radio-lifecycle.md). APIs reject a
different SDK task or a reentrant operation.

## Verification

Run the native core, guarded independent Python wire reference and cached-flash
Xtensa fixture with explicit installed tools:

```sh
flexscript scripts/test-esp32-ble.flex -o build/test-esp32-ble
build/test-esp32-ble --compiler /path/to/flexscript \
  --ld /path/to/xtensa-esp32-elf-ld --rom /path/to/rom-symbols \
  --qemu /path/to/qemu-system-xtensa --report build/ble-wire-reference.json
```

The core harness passes24 checks, including1438 independent wire/reference cases
(339 valid,25 strict failures,50 prefixes and1024 mutations). Guard pages and
internal canaries protect input, workspace, events and RX/TX boundaries. The
same lifecycle/credit/fragmentation scenarios run natively and on Xtensa.
The vendor-link harness additionally exercises the real Flexscript C-callback
bridge against a test-only C VHCI oracle, including split-queue capacity,
retained sends, merged encryption/fragment order, disconnect/handle reuse and
stale consumption after ring wrap. Its coupled host/transport fixture executes
from cached flash, matching production code placement.

These are software proofs. They do not establish physical BLE connections or
radio coexistence. The controller buffer/mask setup, central/peripheral connection APIs, mandatory
controller/signaling responses and application ownership/backpressure are now
integrated. The full vendor/ABI suite passes1119 checks, including independent
C-controller fixtures for dedicated/shared buffers, optional receive-flow fallback,
zero ordinary command credits, cancellation races, receive deadlines and
special-acknowledgment errors. Physical independent-peer ACL exchange remains
unverified: the board has reported a real connection event, but laptop setup
has timed out or returned a connection error before application data. Fresh
advertisements were received at-91dBm; controller TX settings already report
level7(+9dBm), so a missing software power setting is not established. The RF
connection cause remains unresolved. All five completed temporary probes restored
and checksum-verified the original full4MiB firmware.
GATT discovery/read/write/notification is software tested under T192; its
physical phone read/change gate remains T138. Authenticated persistent pairing
remains T139. Keep those backlog gates open until their stated tests pass.

Protocol references: [Bluetooth SIG HCI specification](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host-controller-interface/host-controller-interface-functional-specification.html)
and [LE signaling specification](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host/logical-link-control-and-adaptation-protocol-specification.html).
