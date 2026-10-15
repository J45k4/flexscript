# Native ESP32 ATT/GATT server

The server implements service/characteristic discovery, reads, writes, long
values, prepared writes, per-connection subscriptions, notifications and
indications. The protocol core is allocation-free Flexscript; the original
ESP32 adapter uses the existing bare-metal BLE controller/ACL path. FreeRTOS is
not required. The native/Xtensa core harness passes24 checks with3965 independent
ATT reference/guard cases; the integrated vendor/ABI suite passes1119 checks.

Physical phone read/change verification remains T138 in
[the backlog](../esp32_todo.md). Earlier BLE probes initialized the host and
advertised, and two reported connection events, but the laptop did not complete
an application exchange. T191 remains open. The complete demo physically boots, initializes its database and enables
advertising with50080 SDK bytes free. The independent BlueZ client then timed
out during discovery. The full original4MiB firmware was restored/checksum
verified and reset; its discovery lease was released. Software/emulator and boot
results do not establish physical GATT interoperability.

## Firmware example

[esp32-ble-gatt.flex](../examples/esp32-ble-gatt.flex) builds a complete server:

- Standard GAP Device Name/Appearance and GATT Service Changed characteristics.
- Custom service `c70a0001-19ad-4fe0-a8df-ea860185b3d1`.
- Read/write/notify/indicate value `c70a0002-19ad-4fe0-a8df-ea860185b3d1`,
  initially `hello`, with capacity240 bytes and reliable-write support.
- Complete connectable advertising under the short name `FlexGATT`, explicit
  restart after disconnect, and UART connection/write/confirmation diagnostics.

Build with the explicit compiler, GNU tools and pinned radio inputs used in
[vendor integration](esp32-vendor.md):

```sh
build/build-esp32-radio --compiler /path/to/flexscript \
  --source examples/esp32-ble-gatt.flex --kind bluetooth \
  --vendor /path/to/esp32/libs --rom /path/to/rom-symbols \
  --ld /path/to/xtensa-esp32-elf-ld --gcc /path/to/xtensa-esp32-elf-gcc \
  --output build/esp32-ble-gatt.bin
```

The example advertises public access. A BLE GATT client can discover the custom
service, read or change its value, and enable notifications or indications on
its CCCD. Writes update the actual stored value. The example sends the current
value after subscription/write; if it exceeds the negotiated notification
payload, the example sends its prefix and the full value remains readable.
Pairing requests are explicitly declined by the example until T139 supplies
SMP, authenticated identity, key sizes and persistent bonds. Values in this demo
are RAM state and are not persistent settings.

## ESP32 adapter

[esp32-gatt.flex](../lib/platform/esp32-gatt.flex) reserves an SDK workspace and
uses the same single application task as [BLE](esp32-ble.md). Start BLE and
initialize its clocks/SDK/controller first, while no connection or advertising
is active:

```flexscript
let r = esp_gatt_init(24, 2048, 247);
```

Arguments are attribute capacity, copied value-pool bytes and maximum ATT MTU.
Build the database with the core functions below, then call `esp_gatt_start()`
and start connectable advertising. `esp_gatt_poll()` advances BLE, connection
state, ATT input/output, deadlines and disconnect cleanup. Continue draining
`esp_ble_event()` / `esp_ble_consume_event()` for radio lifecycle events.

- `esp_gatt_set(handle,bytes,size)` changes a server-owned value.
  `esp_gatt_value(handle)` returns1 and exposes `ga_value_data/ga_value_size`.
- `esp_gatt_notify(token,handle,bytes,size,indicate)` copies one notification or
  indication. Zero selects notification, one selects indication. The client must
  have enabled the corresponding CCCD bit. Oversized payloads are rejected;
  the adapter does not silently truncate them.
- `esp_gatt_subscriptions(token,value_handle)` returns CCCD bits1 notification,
  2 indication. A fresh unbonded connection starts at zero.
- `esp_gatt_service_changed(token,start,end)` queues a Service Changed
  indication when standard services were added and the client subscribed.
  Supply service-definition boundary handles for the changed range.
- `esp_gatt_event(token)` returns1 for an owned application event; release it
  with `esp_gatt_consume_event(token)`. Globals expose kind, handle, byte offset,
  copied data/size and status. Kind1 is a written value/descriptor fragment,
  2 a CCCD fragment,3 indication confirmation,4 bearer failure.

Direct-write events retain a copied value until consumption. An executed
prepared transaction exposes its copied fragments in their original order;
all database changes are already committed before the first event is visible.
Pending write events apply backpressure to later writes instead of replacing
their data. Consume events promptly. An ATT request, blocked input or
indication cannot wait beyond30 seconds; failure closes that bearer and the
adapter requests a BLE disconnect. Other connections can continue.

Incoming CID4 belongs to GATT. CID5 signaling belongs to the BLE adapter. CID6
belongs to the application's security manager; until SMP is implemented an
application must process/decline it, as the example does, so it cannot block
later ATT traffic. The adapter does not claim an authenticated security context:
it currently knows controller encryption only, and has no verified key size or
MITM/bond identity. Protected characteristics requiring those properties remain
unavailable through the adapter until T139 integrates the real security state.

`esp_gatt_state` is0 uninitialized,1 building,2 running,6 failed.
`esp_gatt_error` retains a global failure. Calls from another SDK task or during
a reentrant operation return-16. `esp_gatt_deinit()` releases an idle database;
`esp_gatt_stop()` shuts down radio, host and database together. See
[radio lifecycle](esp32-radio-lifecycle.md) for ordering and ownership.

## Portable database and protocol core

[gatt-server.flex](../lib/net/gatt-server.flex) owns no allocator, radio or clock.
`ga_size(attributes,links,value_bytes)` returns required storage:

```
512 + attributes*128 + align8(value_bytes) + links*4096
```

Limits are1..64 attributes,1..4 connections, at most65536 value-pool bytes,
23..517 ATT MTU and512 bytes per attribute value. Supply an eight-byte-aligned
buffer to `ga_init(work,capacity,attributes,links,value_bytes,mtu)`.
The example's24 attributes,2048 value bytes and one connection use9728 bytes,
in addition to the BLE host, transport and controller SDK allocations.

Builder functions copy UUIDs and initial values. UUIDs use two-byte or
sixteen-byte Bluetooth wire order. `ga_uuid16(number)` supplies short-lived
scratch bytes for a16-bit UUID.

- `ga_standard_services(name,size,appearance)` adds the nine standard GAP/GATT
  attributes to an empty database, validating the Device Name as UTF-8.
- `ga_service(uuid,size,primary)` starts a service and returns its handle.
  `ga_include(service_handle)` includes an already completed service definition.
- `ga_characteristic(uuid,uuid_size,properties,permissions,value,size,capacity)`
  returns the value handle. It creates the declaration, a CCCD when needed and
  a read-only Extended Properties descriptor for reliable writes when bit128
  is requested. Writable User Description descriptors also require that bit.
- `ga_descriptor(uuid,uuid_size,permissions,value,size,capacity)` adds an
  ordinary descriptor. Reserved declaration and auto-owned descriptor types
  cannot be inserted through this path.
- `ga_permissions(handle,bits,min_key_size)` sets access policy before sealing.
  `ga_fixed(handle,1)` makes an initialized value fixed length; capacity and
  initial length must match. Short writes preserve its remaining bytes.
- `ga_seal()` finalizes service ranges. Database structure is immutable afterward;
  value updates remain supported through `ga_set`.

Properties use standard GATT bits: read2, write-command4, write-request8,
notify16, indicate32 and extended128. Broadcast and authenticated signed-write
properties are rejected because those paths are not implemented.
Permissions are read1, write2, encrypted-read4, encrypted-write8,
authenticated-read16/write32, and authorized-read64/write128.
Encrypted/authenticated policies default to a minimum seven-byte key;
`ga_permissions` can require up to16 bytes. Authorization is independent of
link encryption unless both are explicitly required.

`ga_open(token)` creates per-connection state for an increasing positive token;
`ga_close(token)` invalidates it and clears its CCCDs, queued writes and packets.
`ga_input(token,pdu,size,security,monotonic_ms)` accepts one complete ATT PDU.
The caller supplies the security snapshot associated with that received PDU:
encrypted1, authenticated2, authorized4, and key size in bits8..15. It must come
from trusted controller/SMP/application state. `ga_security(token,context)` sets
the current outbound context separately; an old incoming snapshot cannot
upgrade or downgrade current notification authorization.

`ga_next_packet(token)` exposes a stable response or server-event packet through
`ga_packet`, size, kind and generation. Call `ga_packet_sent(token,now)` after
the transport accepts a copy. Busy submission preserves ownership. Pending
responses take priority over notifications. One indication may await confirmation
per bearer. Unsent notifications are cancelled when CCCD, security or MTU changes
make them invalid; stale views cannot acknowledge another packet.
`ga_cancelled_notifications` counts those cancellations.

Prepared writes use a32-record/1024-byte queue per connection, enough for a
512-byte write at the default MTU. Prepare validates handles, permissions and
queue capacity while deferring offset/value checks to Execute. Execute validates
all records before changing any value and clears the queue on failure/cancel.
Fragments commit in order. Offset-zero writes replace a variable-length value;
nonzero writes update its existing prefix/range and may extend it. Fixed values
retain their length. Copied transaction events remain owned until consumed.

Supported ATT methods include MTU exchange, Find Information, Find By Type Value,
Read By Type/Group Type, Read/Blob, Read Multiple/Multiple Variable, Write Request/
Command, Prepare/Execute, notifications, indications and confirmations. UUID16
and equivalent Bluetooth-base UUID128 comparisons work across encodings.
Long discovery replies retain correct full-length/grouping semantics. Signed
writes, EATT, dynamic database mutation, robust caching/Database Hash, persistent
CCCD/bond restoration and a GATT client are not provided by this server.

## Verification

```sh
flexscript scripts/test-esp32-gatt.flex -o build/test-esp32-gatt
build/test-esp32-gatt --compiler /path/to/flexscript \
  --ld /path/to/xtensa-esp32-elf-ld --rom /path/to/rom-symbols \
  --qemu /path/to/qemu-system-xtensa --report build/gatt-wire-reference.json
```

The independent Python reference uses a copied attribute database and atomic
copy-on-commit transactions. The3965 cases include1855 exact protocol sequences,
7 strict transport/input failures,55 PDU prefixes and2048 mutations. The native
oracle guards input and workspace with inaccessible pages and checks internal
output, value, prepare/event and CCCD boundaries with canaries. The core runtime
also runs from cached flash on Xtensa and covers subscription/security
cancellation, per-client state, prepared security changes and deadlines.

The vendor/ABI harness's GATT fixture invokes the actual C callback bridge and
BLE host, captures raw H4 ACL fragments independently, and checks exact220-byte
writes,221-byte reads and223-byte notifications/indications. It verifies copied
event backpressure, cancellation before HCI handoff, prepare/execute and reconnect
with cleared CCCDs. These are controller-model/emulator tests, not RF or phone
verification. The complete radio demo also links with the pinned vendor archives.

Protocol references: [Bluetooth SIG ATT](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host/attribute-protocol--att-.html)
and [GATT](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host/generic-attribute-profile--gatt-.html).
