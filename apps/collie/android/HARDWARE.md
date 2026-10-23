# Android hardware adapter implementation and verification

Objective: implement every app-accessible adapter in the hardware inventory,
with ordinary Flexscript functions, first-use Collie/Android permissions and
minimal platform transport code. This file is a completion checklist, not a
claim that all listed features already work.

A feature requires actual calls to Android, typed results/errors, bounded I/O,
resource cleanup, permission denial/revocation handling and appropriate tests.
A platform-unavailable result is valid only for a real hardware/OS restriction;
it does not count as an implementation of an otherwise available adapter.

| Family | Required operations | Implementation | Verification |
| --- | --- | --- | --- |
| Networks | enumerate/info/events, Wi-Fi/Ethernet/cellular selection, per-network DNS, TCP/client/server, UDP, HTTP(S), model transport selection | implemented; model route UI validation in progress | selected-network TCP/UDP/HTTP/listener and event I/O passed on emulator; multiple physical transports pending |
| Wi-Fi | scans, connection requests/suggestions, Direct, Aware, local-only hotspot, RTT | status/scans, scoped network requests/suggestions and local-only hotspot SDK adapter implemented; Direct channel/group/service/socket bindings implemented with integration in progress; RTT AP and Aware attachment/discovery/message/data-path/peer RTT SDK bindings implemented; Aware radio integration pending | virtual-AP scans, actual precise Location/Nearby consent and TCP through an approved request passed; hotspot error callback passed, successful AP/device checks pending; orphan recovery after actual process death passed; P2P discovery/pairing/TCP/UDP passed in earlier headless runs, DNS-SD exchange unresolved; RTT unsupported/validation checks passed, measured distance pending; 10 Aware permission/unsupported/ownership/API-reference checks passed, NAN radio proof pending |
| Network services | DNS-SD discovery/advertising, approved VPN IP transport | implemented | actual Android DNS-SD over virtual Wi-Fi and approved foreground TUN read/write/protection/teardown passed; encrypted mesh/gateway is separate work |
| Cellular diagnostics | subscriptions, signal/service/cell data with platform permissions | implemented; read-only diagnostics, separate cellular + location gates | 19 headless Android scenarios passed, including real runtime prompts, NR cell data, refresh, roaming callbacks and both grants; physical SIM/multi-SIM/radio checks pending |
| USB | descriptors, open/permission, interface claim/release, control/bulk/interrupt, accessory mode, disconnect handling | implemented; device consent and transfers need a real fixture | UsbManager inventory/events, missing devices, invalid arguments and wrong handle types passed on emulator; physical device approval/transfers/detach pending |
| USB serial | CDC ACM, FTDI, CP210x and CH34x setup/read/write through USB primitives | implemented in Flexscript; common variants supported, older/unsupported variants return errors | native, interpreter and JIT protocol fixtures passed; actual Android guest preload passed; physical loopback fixtures pending |
| Bluetooth Classic | adapter/discovery/bonding, RFCOMM connect/listen/read/write, disconnect handling | SDK adapter implemented with Android-owned enable/discoverable/pairing consent | 16 baseline SDK/VM/consent checks passed on the current server APK; secure and insecure outgoing RFCOMM 32 KiB exchanges passed against a controlled Netsim peer; incoming payload, explicit bond/discoverability and physical-device checks pending |
| BLE | scan, connect/services/read/write/subscribe, advertise, GATT server | raw scan, legacy advertising, GATT client and GATT server SDK bindings implemented; extended/periodic advertising pending | client/server byte I/O verified against controlled Netsim peers; current artifact audit and remaining BLE/physical gates are detailed below |
| Bluetooth HID | register descriptors, paired-host connect, reports, foreground lifecycle | public Classic HID device SDK bindings implemented; remaining verification gates below | encrypted510-byte control/interrupt report exchange, registration ownership and reconnect verified against a controlled host; public unplug callback gate remains failing on this emulator |
| NFC | reader mode, NDEF, technology transceive, ISO-DEP/APDU, tag loss | pending | pending |
| NFC emulation | host APDU services and supported HCE-F; OS-controlled routing | pending | pending |
| Secure elements | OMAPI readers/sessions/channels/APDUs with real access-control errors | pending | pending |
| UWB | supported-device sessions and ranging events through supported APIs | pending | pending |
| Infrared | capabilities/carrier ranges/transmit | implemented | emitter absence correctly reported on emulator; real IR fixture pending |
| MIDI | enumerate/open/ports/messages/events | implemented, including byte-stream/UMP inventory and known-address BLE-MIDI open | Android virtual-service loopback passed, including 32 KiB binary payloads, timestamps, exclusivity, flush and child cleanup; physical USB/BLE/UMP fixtures pending |
| Location | location providers/updates/status, GNSS satellites/raw measurements/navigation messages | implemented | actual Android runtime prompt and injected GPS callback passed; raw GNSS device data pending |
| Sensors | enumerate/capabilities/subscriptions, motion/environment/activity and available health sensors | subscriptions, triggers and paged static/dynamic inventory implemented | actual accelerometer callback passed; activity/health device checks pending |
| Camera | devices/characteristics, capture/frames/video, supported manual/RAW/depth controls, torch | pending | pending |
| Audio | input/output devices, PCM capture/playback/routing, recording | PCM16 mono/stereo streams, metadata, route preference, control and events implemented | actual AudioRecord/AudioTrack calls and runtime microphone consent passed; onStop closes capture and blocks background opens; physical inputs/output routes pending |
| Input | delivered touch/stylus/key/mouse/gamepad events | pending | pending |
| Haptics | capabilities/effects/waveforms/cancel | implemented | actuator inventory passed; effect/cancel checks pending |
| Device status | battery/charging/electrical data, thermal state/headroom/events | implemented | battery/thermal status and subscriptions passed; thermal-change injection pending |
| Biometrics | system authentication result only | pending | pending |
| Keystore | scoped aliases, hardware-backed key generation/sign/verify/encrypt/decrypt/delete | implemented | actual Android EC/RSA/HMAC/AES operations, independent JCA checks, required backing, full-size frames and isolation passed; physical secure-processor attestation pending |
| Screen capture | explicit MediaProjection consent, frames/recording/session lifecycle | pending | pending |
| Accessibility | explicitly enabled service, exposed UI tree/actions/gestures/events | pending | pending |
| Storage | app-private filesystem, user-granted documents/folders/media/removable storage | private files/pickers exist; persisted tree access pending | existing tests; tree tests pending |
| Privileged/vendor tier | identify unsupported raw radio/monitor mode/gadget/internal buses/clocks/charging/routing operations; implement documented privileged integration only where genuinely available | pending capability reporting | pending |

Cross-cutting requirements:

- [x] Shared operation/permission registry and typed value/error transport, including checked 64-bit integers and binary data.
- [ ] Hardware capability discovery distinguishes implemented/supported/available.
- [x] Runtime permission consent happens on first use, outside the VM lock (GPS verified).
- [ ] USB/device/system picker consent for the remaining adapters.
- [ ] Opaque resource handles are scoped to a workspace, invalidated on close,
      disconnect, process restart and permission revocation as appropriate.
- [ ] Bounded asynchronous event queues; no callbacks into paused guest memory.
- [ ] VM checkpoints preserve guest state, not live operating-system resources.
- [x] Permission settings migrate existing conversations without enabling hardware.
- [ ] Model bootstrap/API reference covers the actual implemented operations.
- [ ] Native protocol and negative-path tests plus headless Android integration.
- [ ] Physical-device checks distinguish actual I/O from advertised feature flags.

Ongoing work is published through a draft PR on `codex/collie-hardware-adapters`.
Keep the PR in draft until the inventory and verification gates are satisfied.
No merge to master or phone deployment is implied.

## Current build and repeatable checks

Worktree: `build/collie-android`, branch `codex/collie-hardware-adapters`.
Hardware output: `build/android-hardware`; compiler: `build/flex-hardware`.

```sh
build/flex-hardware apps/collie/tests/hardware-core.flex -o build/test-hardware-core
build/test-hardware-core
python3 scripts/build-collie-android.py --compiler build/flex-hardware \
  --out build/android-hardware --debug --java-home /path/to/jdk-17
python3 scripts/test-collie-hardware-android.py --out build/android-hardware \
  --serial emulator-5580
```

The 38-scenario hardware run covers real local TCP/UDP/HTTP peers, per-network
binding and DNS, network events, handle ownership/revocation, battery and thermal
subscriptions, accelerometer events, lazy network grants, and actual Android
location consent followed by an injected GPS fix, plus USB inventory/events and
structured negative paths. Keystore cases include EC/RSA/HMAC signatures,
independent JCA verification, authenticated AES-GCM with full-size binary frames,
workspace isolation, required backing, alias protection and cleanup. It does not
verify the still missing adapters or physical USB/NFC/Bluetooth/IR devices.
Audio/MIDI, DNS-SD and the separate 8-scenario VPN run are documented below.

The native codec test crosses the actual JSON wire representation, including
19-digit signed integers, exact floating-point bits and all 32,768 binary bytes.

Implementation boundaries:

- `core/hardware.flex`: operation schema, permission bindings, typed wire codec.
- `guest/hardware.flex`: ordinary functions inside the sole Flexscript tool.
- `guest/usb-serial.flex`: serial discovery, control protocols, framing and buffering.
- `android/HardwareKeystore.java`: Android Keystore objects and crypto operations.
- `android/HardwareAudio.java`, `HardwareMidi.java`: audio/MIDI objects, streams, routes and callbacks.
- `android/HardwareNsd.java`: Android DNS-SD objects and copied events.
- `android/HardwareCellular.java`: Android subscriptions, radio/service callbacks and bounded cell snapshots.
- `android/HardwareWifi.java`: Wi-Fi services/callbacks, scoped leases and platform-persistent suggestion recovery.
- `android/HardwareVpn.java`, `CollieVpnService.java`: validated VPN configuration, owned TUN resources, socket protection and foreground lifecycle.
- `android/VmHardware.java`: bounded I/O workers, scoped handles and event queues.
- `android/HardwareConsent.java`: asynchronous Android runtime and per-device USB dialogs.
- `android/HardwareUsb.java`, `UsbConsentReceiver.java`: USB objects, transfer/attach/detach transport and a private immutable approval callback.
- `android/HardwareNetwork.java`: Network/socket objects and model connection leases.
- `android/HardwareSensors.java`, `HardwareStatus.java`, `HardwareLocation.java`:
  platform services and copied callback data.
- The JNI endpoint is trusted host operation 3003; guest raw FFI remains disabled.

Compiler dependency: full UI source export exhausted the former 50M transform
fuel allowance. It now has a bounded 100M allowance with the existing 5-second
deadline and explicit diagnostics for fuel, memory, output and deadline failures.

Android 16 health sensors use granular permissions and the app exposes a shared
privacy-rationale view via Android's required permission-usage activity alias.
See [Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-16)
and [health permission rationale](https://developer.android.com/health-and-fitness/health-connect/get-started).


## USB API and limits

`usb_list(offset, limit)` returns `devices`, `next`, and `total`; the page limit is
1..32 and `next == -1` ends enumeration. `usb_info(id)` returns identifiers,
class/subclass/protocol, names and Android permission state. Configuration and
interface pages use `usb_configurations(id, offset, limit)` and
`usb_interfaces(id, configuration_id, offset, limit)` with limits 1..8.
Interface descriptions include alternate settings and endpoint addresses,
directions, transfer types, packet sizes and intervals.

`usb_open(id)` asks for Collie USB access, then Android's permission for that
specific device. Opening never implies an interface claim. Use
`usb_claim(handle, interface_id, alternate, force)` and `usb_release`; force is
explicitly 0 or 1. `usb_configure` requires releasing interfaces first.
`usb_descriptors` returns a blob. `usb_control_in/out` take a direction-consistent
request type, request, value, index, byte limit/blob, and 1..8000 ms timeout.
`usb_transfer_in/out` take a claimed endpoint address, byte limit/blob, and timeout.
Bulk and interrupt transfers preserve binary values and report actual byte counts;
isochronous endpoints report an explicit unsupported-operation error.

`usb_accessories()` inventories Android accessory-mode peers, and
`usb_accessory_open(id)` returns a stream for `device_read/write`. These are
Android Accessory Protocol peers, not arbitrary USB gadget emulation.
`usb_watch()` is a bounded attach/detach event resource. Close every handle with
`device_close`. Detach, Collie revocation, conversation closure and process death
invalidate handles; Android grants are checked again on each operation. A timed-out
interrupt request closes its device handle so a late completion cannot be mistaken
for the next transfer. USB resources consume the common 32-handle workspace limit.

The emulator has no attached USB target. No claim is made yet about physical
control/bulk/interrupt/accessory traffic or Android's actual USB consent dialog.
The development tests restore both conversation grants and Android location
runtime grants/location-switch state after exercising first-use GPS consent.


## USB serial

The guest preloads `serial_ports(id)`, `serial_open(id, port, force)`,
`serial_configure(state, baud, data_bits, parity, stop)`, `serial_lines(state, dtr, rts)`,
`serial_break(state, enabled)`, `serial_read/write`, `serial_status`, `serial_info`
and `serial_close`. A port description identifies the configuration, data/control
interfaces and alternate setting; `serial_port(driver, configuration, data_interface,
control_interface, alternate)` constructs an explicit description for a customized
VID/PID. The host still validates every handle, interface and endpoint. Discovery
recognizes common FTDI/CP210x/CH340/CH341 IDs and CDC ACM interfaces; a CDC Union
descriptor supplies the actual control association when opening.

Parity values are 0 none, 1 odd, 2 even, 3 mark and 4 space. Stop values are 0 one,
1 one-and-a-half, 2 two; one-and-a-half requires five data bits. Requested baud must
be representable within three percent; a driver/device may reject a narrower
range. CH34x versions before 0x30 are limited to 8N1; older FTDI AM/SIO protocols
and newer WCH families using a different protocol are explicitly outside these
profiles. FTDI uses its standard 3 MHz baud clock, including on H-series devices;
rates above 3 Mbaud and hardware/software flow-control configuration remain
outside this API. Open initializes no-handshaking mode, 9600 8N1 and asserted
DTR/RTS; callers can change framing/lines afterwards.

Reads fetch whole USB packets, buffer excess data, and strip FTDI's status header
from every packet. Small reads do not discard the rest of a received packet.
Buffered data is delivered only after checking the live Android handle. Writes
return the actual transferred byte count; callers must handle partial writes.
State can be held in ordinary lists or FlexDB, but a saved OS handle is stale
after a process restart and must be reopened.

`apps/collie/tests/usb-serial.flex` checks setup traces against wire protocol
values, multi-port FTDI baud addressing, CDC unions, all 256 binary values,
small-read buffering, short/error responses, cleanup and stale ownership. It runs
natively, in the interpreter, and with JIT; CI includes native/interpreter checks.
No physical serial loopback has been measured yet.

Protocol references: [Silicon Labs AN571](https://www.silabs.com/documents/public/application-notes/AN571.pdf),
[FTDI baud documentation](https://ftdichip.com/Documents/AppNotes/AN_120_Aliasing_VCP_Baud_Rates.pdf),
[WCH's CH341 driver](https://github.com/WCHSoftGroup/ch341ser_linux), and the
[Linux CH341 protocol register reference](https://github.com/torvalds/linux/blob/master/drivers/usb/serial/ch341.c).

## Android Keystore

`key_generate(alias, kind, backing)` supports `ec_p256`, `rsa2048`, `hmac_sha256`
and `aes256`. Backing is `any`, `hardware`, or `strongbox`; a hardware requirement
never silently accepts software. `key_info` reports Android's actual key metadata,
including security level. Emulator metadata is not proof of a physical secure
processor. `key_list(offset, limit)` pages the current workspace's aliases and
`key_delete(alias)` deletes explicitly. Generating an existing alias fails rather
than replacing it; each workspace has a 32-key limit and a separate hashed alias
namespace. Keys are durable and survive VM program boundaries. Revoking permission
blocks further operations without silently deleting the keys.

`key_sign`/`key_verify` use ECDSA-SHA256, RSA-PKCS1-SHA256, or HMAC-SHA256 according
to the key type. `key_public` exports only X.509 SPKI public keys; symmetric and
private key bytes are never exported. These keys do not require biometric
confirmation; biometric-bound keys are not part of this API.

`key_encrypt(alias, data, aad)` uses AES-256-GCM with a platform-generated nonce and
returns `nonce` and `ciphertext` blobs. `key_decrypt(alias, nonce, ciphertext, aad)`
verifies the tag and returns plaintext, or `authentication_failed`. Plaintext plus
additional authenticated data is limited to 32752 bytes so the 16-byte tag fits
the 32 KiB binary limit. Signing accepts 32 KiB messages; verification signatures
are limited to 1024 bytes. Malformed signatures return false. No unverified
plaintext is returned. See the [Android Keystore documentation](https://developer.android.com/privacy-and-security/keystore).


The shared guest copy routine now copies complete words when safe, with a byte
remainder and preserved overlap behavior. Alignment/canary tests cover lengths
0..65 and every 0..7 source/destination offset in native code and the checked VM.
An isolated eight-by-32-KiB copy benchmark reduced interpreter steps from
6,291,701 to 885,117 before a final early-return guard was added. The actual
full-size crypto workload passes Android with the existing 4M instruction and
1-second CPU deadline limits; no production limit was raised for this change.


## Audio and MIDI

`audio_devices(offset, limit)` returns `devices`, `next`, `total`, with page limits
1..16. Each row describes direction, Android device type, name, sample rates,
channel counts and encodings. The current stream format is PCM16 little-endian,
mono/stereo, at requested rates 8000..192000 Hz; Android may reject unsupported
combinations. Use `audio_input_open(device, rate, channels)` or
`audio_output_open(device, rate, channels)`, selecting an inventory ID or `default`.
`device_read` and `device_write` transfer whole sample frames and return actual
byte counts; writes can be partial. These are PCM recording/playback streams;
compressed media/container encoding is not performed by the platform adapter.

`audio_control(handle, action)` supports `start`, `pause`, and playback-only
`flush` while paused. `audio_volume(handle, permille)` controls only that output
stream, without changing global system volume. `audio_route` requests a preferred
input/output device; `device_info` reports the actual routed device, format,
position/timestamp (when available), underruns and input silencing state.
`audio_watch` reports device additions/removals; stream event queues report route
changes. Losing an explicitly selected device closes that stream.

Microphone access asks for the Collie grant and then Android `RECORD_AUDIO`.
Capture requires a visible Collie activity. Hiding the activity closes microphone
resources; opening an input while hidden fails with `foreground_required`.
Resource publication rechecks this lifecycle constraint under the registry lock,
so a capture opened concurrently with `onStop` cannot escape cleanup. No
microphone foreground service or background recording is introduced here.

`midi_list(offset, limit)`, `midi_info(id)` and `midi_ports(id, offset, limit)`
expose available MIDI devices and numbered ports. Page limits are 1..32.
Byte-stream and UMP devices are inventoried on API33+; older versions use byte
streams. Transport/protocol metadata tells the guest which wire representation
to send. `midi_watch` reports device additions/removals and open-port status.

`midi_open(id)` returns a parent device handle; `midi_port_open(device, direction,
number)` uses `send` for a device input, and `receive` for a device output.
`midi_send(port, data, timestamp_ns)` and `device_write` send binary messages;
`device_wait` returns receive events with a data blob and exact timestamp.
Timestamp 0 is immediate; future timestamps use Android's monotonic nano clock
and are bounded to 60 seconds. UMP writes require complete 32-bit words, including
when partitioned for the Android input-port packet limit. `midi_flush` forwards a
flush event. Closing or losing a parent closes all its ports. Failed/late async
opens release their Android objects; these resources are never restored from
checkpointed handle text.

`midi_bluetooth_open(address)` connects a known uppercase MAC using Android's
BLE-MIDI service, with lazy Nearby devices consent on API31+. It neither scans nor
turns on Bluetooth. Actual BLE/USB/UMP instruments remain physical test gates.

The debug APK includes a private virtual loopback MIDI service to test actual
Android framework ports. Release packaging excludes its class, XML and service
manifest entry; `build/android-hardware/packaging-report.json` records those
checks and exact APK hashes/sizes. The emulator runs with host audio disabled;
playback tests send silence, and capture tests verify Android PCM delivery and
lifecycle rather than claiming a physical microphone was measured. Platform
permission grants, the location switch, saved conversations and fixture files
are restored after the checks.

References: [AudioRecord](https://developer.android.com/reference/android/media/AudioRecord),
[AudioTrack](https://developer.android.com/reference/android/media/AudioTrack),
[MidiManager](https://developer.android.com/reference/android/media/midi/MidiManager),
[MidiDeviceService](https://developer.android.com/reference/android/media/midi/MidiDeviceService).


Earlier audio/MIDI baseline: **35 headless Android hardware scenarios**
passed, plus **10 native lazy-permission regression groups**. Debug APK:
6,407,185 bytes (6.407 MB); non-debug APK: 6,374,338 bytes (6.374 MB).
The report `build/android-hardware/hardware-android-report.json` binds the Android
checks to debug APK SHA-256
`6a7b369289274452ea8e8985c6353d13fab1e1bbc34d9f3362e7f588cb27d8ed`.
The packaging report separately verifies that the non-debug APK has no MIDI test
class, resource or service entry. No phone deployment or Git publication was done.


## DNS-SD and VPN packet transport

`nsd_browse(type, network)` creates a discovery resource for a DNS-SD type such as
`_http._tcp.`. Network selectors are the existing default/transport/network-ID
selectors. Selected-network operations require API33+; on older versions only
`default` is accepted. DNS-SD needs a LAN transport. The test emulator initially
had only cellular connectivity; connecting its built-in `AndroidWifi` access
point allowed Android's mDNS service to create a LAN socket. This is a deliberate
lab setup change inside the headless emulator, not a phone/host network change.

`nsd_register(name, type, port, attributes, network)` advertises a service. TXT
attributes are `[key, text]` pairs, limited to 255 bytes per record and 1300 bytes
total; the public Android setter supports UTF-8 text values, so encode arbitrary
binary values as base64 text. Resolved TXT values are returned as blobs. Names
use 1..63 UTF-8 bytes; keys are unique case-insensitive ASCII tokens.

Discovery events include `started`, `found`, `lost`, and `error`; registrations
emit `registered` or an Android error. Found service IDs belong to that browser.
`nsd_services(browser, offset, limit)` pages its bounded 128-entry cache (page
limits 1..32), `nsd_resolve` returns addresses/port/TXT, and
`nsd_watch_service` monitors updates on API34+. Closing a browser closes its child
watches. Closing a registration unregisters the service. RPCs never hand the guest
Android object references.

VPN routing is a separate **28th permission category**. Missing saved VPN policy
migrates to Ask. Its grant never follows from allowing ordinary network calls.
`vpn_open(name, addresses, routes, dns, mtu, apps, network)` additionally yields
for Android's system VPN approval, then starts an Android foreground service.
`addresses`/`routes` are lists of `[numeric IP, prefix length]`; route host bits
must be zero. DNS servers are numeric IP strings. MTU is 576..32768, at least1280
for IPv6. App package names must be installed and visible to Collie. An empty app
list means only Collie; `["*"]` explicitly selects all apps, and `!package`
entries form an exclusion list. Allow and exclusion lists cannot be mixed.

Only one Collie VPN lease may be active. Startup must occur while Collie is
visible. The foreground notification provides Disconnect; OS revocation, closing
the handle/owner conversation, activity destruction, or process death disposes of
the interface. Always-on restart is explicitly disabled: no guest program or OS
handle is silently recreated at boot. The service is protected by
`BIND_VPN_SERVICE` and uses the actual active-VPN `systemExempted` foreground type.

`device_read` returns one complete raw IP packet and requires a buffer at least
the configured MTU; `device_write` injects one packet into Android. `device_info`
reports addresses, routes, DNS, app scope and `encrypted=false`. The adapter
provides **raw IP transport**, with no gateway, mesh pairing or encryption
protocol. Those require a separate authenticated encrypted transport implementation.

`vpn_protect(vpn, socket)` protects an owned TCP/UDP/listener handle from VPN
routing. `net_tcp_open` lets guest code obtain an unconnected TCP handle, protect
it, then use `net_tcp_dial` before ordinary reads/writes. `vpn_underlying` updates
the selected physical transport. Model connections using Auto select a physical
network outside Collie's own tunnel; another app's VPN is respected when Collie
has no active tunnel.

The VPN emulator fixture obtains the real Android approval, reads a real kernel
UDP packet in Flexscript, swaps IP addresses/ports and computes an IP checksum in
Flexscript, injects a reply, and verifies every byte independently from Java.
Bounded UDP retries avoid assuming the first startup datagram is delivered.
It also tests protect-before-dial, model-connection bypass, actual network removal
before force-stop cleanup, and restoration of temporary Android authorization.
No remote gateway or physical peer is used.

Repeatable checks after installing the debug APK on the headless test emulator:

```sh
/opt/android-sdk/platform-tools/adb -s emulator-5580 shell cmd wifi connect-network AndroidWifi open
python3 scripts/test-collie-hardware-android.py --out build/android-hardware --serial emulator-5580
python3 scripts/test-collie-vpn-android.py --out build/android-hardware --serial emulator-5580
python3 scripts/test-collie-android-packaging.py \
  --debug build/android-hardware/collie.apk \
  --release build/android-hardware-release/collie.apk
```

The DNS-SD/VPN baseline reports proved **38 Android hardware scenarios + 8 Android VPN
scenarios**, plus **10 native lazy-permission groups** (including the new VPN
gate) and **10 shared UI groups** (including all three VPN permission choices).
The APK packaging verifier checks the compiled manifest, actual DEX/resource
contents, VPN binding/type/always-on metadata, and APK hashes. These tests do not
replace the outstanding adapters or physical-device gates in the main table.

References: [Android NSD](https://developer.android.com/develop/connectivity/wifi/use-nsd),
[VPN lifecycle](https://developer.android.com/develop/connectivity/vpn), and
[foreground-service types](https://developer.android.com/develop/background-work/services/fgs/service-types).


## Cellular diagnostics

The new `cellular` permission is the **29th category**. Old conversations ask on
first use. It controls diagnostics separately from network sockets or model
traffic. Android `READ_PHONE_STATE` is requested only after the first Collie
approval. Cell/service operations also require the independent `location` grant,
Android precise Location and the Android Location switch. First-use checkpoints
request each grant separately before Android I/O; a denied Android dialog updates
only its matching Collie permission. Hardware denials now provide the same typed
`device_error() = [code, message]` shape as SDK errors, with the existing human
readable `db_error()` text preserved.

- `cellular_subscriptions(offset, limit)` returns `subscriptions/next/total` and
  default/data/voice subscription IDs; page limits are 1..16. Subscription fields
  include slot/carrier/name/country/MCC/MNC and supported embedded/opportunistic
  flags. No phone number, ICCID, IMSI or IMEI is exported.
- `cellular_info(subscription)` returns SIM/radio/operator and cached signal
  data. Use an active subscription ID from inventory, or `-1` for default.
  `cellular_watch` streams signal/data changes and `cellular_watch_subscriptions`
  reports subscription changes. Re-enumerate after changes; an inactive SIM ID
  yields `disconnected` rather than silently selecting another SIM.
- `cellular_service` and `cellular_watch_service` return explicit service-state
  fields/events. Android registration objects and their `toString` output are
  never exported.
- `cellular_cells(subscription, refresh)` returns a snapshot handle. Mode 0 uses
  Android's cache; mode 1 requests a fresh update on API29+. Android can rate limit
  or reject updates. `device_wait` reports `cells` or `error`; a missing callback
  becomes an error after 20 seconds. Closing/revoking ignores late callbacks.
- `cellular_cell_page(snapshot, offset, limit)` returns `cells/next/total` plus
  `reported_total/truncated`, with page limits 1..8 and at most128 retained cells.
  GSM/WCDMA/TD-SCDMA/CDMA/LTE/NR use typed technology-specific identities and signal
  values. `CellInfo.UNAVAILABLE` integer sentinels become null values; timestamps
  are elapsed-realtime nanoseconds. Cached timestamps may be old. LTE timing
  advance is included only with location-authorized cell snapshots.

Cell/service handles carry **both** grants. Every handle operation checks both;
revoking either closes the handle. Android runtime permissions and active SIM
status are rechecked before reading data or events. VM checkpoints preserve only
guest values: live Android watches and snapshot handles must be reopened after
process restart. Callback queues and resources share the normal 128-event and
32-handle bounds. Legacy Android uses PhoneStateListener on the event Looper;
API31+ uses TelephonyCallback with only the interfaces needed by each watch.

The adapter provides no phone calls, SMS, SIM modification or raw modem control.
Physical radio/multi-SIM behavior remains a device-verification gate.

```sh
python3 scripts/test-collie-cellular-android.py \
  --out build/android-hardware --serial emulator-5580
```

References: [TelephonyManager](https://developer.android.com/reference/android/telephony/TelephonyManager),
[SubscriptionManager](https://developer.android.com/reference/android/telephony/SubscriptionManager),
and [TelephonyCallback](https://developer.android.com/reference/android/telephony/TelephonyCallback).


Cellular verification: **19 headless Android scenarios passed** through compiled
Flexscript/JNI and actual Android services, including phone-state denial and
approval, additional location denial/approval, independent SDK comparisons,
NR cell identity and timestamp preservation, asynchronous explicit refresh,
initial and injected-roaming service callbacks, dual-grant handle checks,
revocation, the Location switch and cleanup. The final script restores simulated
voice state, Android grants/user consent flags and the original conversation.
The same build passed **11 native lazy-permission groups**, including independent
checkpoints for a multi-grant operation, **10 shared UI groups** and **9 shared
core groups**. Debug APK: 6,489,105 bytes (6.489 MB); non-debug APK: 6,439,874 bytes
(6.440 MB). Debug SHA-256:
`b4d45700fc455f7bd0d91ae3bc7eb99e7c034c60e32462327906afd3e93c1fb5`.
The actual APK packaging verifier passed for both packages. The non-debug package
is development-signed; it is not a published production release.

Final cellular build regression audit: **38 existing hardware + 8 VPN + 19 cellular
= 65 Android scenarios passed**, all three reports bound to the exact debug APK
hash above. Emulator only; the remaining adapter families and physical-device
gates in the inventory remain outstanding. No Git publication or phone deployment.


## Wi-Fi infrastructure and local-only hotspot

The guest now has `wifi_info`, `wifi_watch`, `wifi_connection`, `wifi_scan`,
`wifi_scan_page`, `wifi_request`, `wifi_suggest`, `wifi_hotspot` and
`wifi_hotspot_config`. `HardwareWifi.java` owns Android service objects/callbacks;
operation signatures and all Collie permission decisions remain in Flexscript.
The existing `wifi` category is reused; there is no new model tool or raw FFI.

`wifi_info` returns radio state and SDK-reported feature support without SSID,
BSSID or device MAC. `wifi_watch` reports ready/state/scan-availability events.
`wifi_connection` reads the **primary** Wi-Fi connection, including Android's
quoted SSID form, BSSID, signal/link values and supported security metadata.
It does not change model routing or select a different transport.

Scan/identity/request/hotspot operations require both Wi-Fi and Location grants.
Actual scan/identity data also requires Android precise Location and its Location
switch; API33+ requests/hotspots additionally request Android Nearby Wi-Fi on
first use. A denied Nearby dialog updates only the Wi-Fi grant. A Location denial
updates only Location. This app can expose location-bearing Wi-Fi data, so its
Nearby permission does not make a `neverForLocation` assertion.

`wifi_scan(0)` snapshots the Android cache. `wifi_scan(1)` asks Android to scan
and yields a copied `scan` event, or an explicit throttle/error. It has a20-second
completion deadline and unregisters the broadcast receiver on completion/close.
Scan broadcasts are platform-wide and have no per-request identity: `updated`
reports Android's freshness flag, not a guarantee that this request caused it.
Use `wifi_scan_page(handle, offset, limit)` with limits1..16; at most128 APs are
retained and `reported_total/truncated` make bounds explicit. Scan timestamps
are elapsed-realtime **microseconds**, unlike cell-data nanoseconds. API33+
returns raw SSID bytes as a blob as well as the platform display string.
Both grants are rechecked on snapshot operations; revoking either closes it.

`wifi_request(ssid, security, password, bssid, hidden, timeout_ms)` uses Android's
Wi-Fi Network Specifier on API29+. Security is open/OWE/WPA2-personal/WPA3-personal;
SSID1..32 UTF-8 bytes, BSSID is an exact unicast MAC or empty, hidden0/1, timeout
1000..120000 ms. Open/OWE uses an empty password; personal passphrases require
8..63 printable ASCII characters. The Android-owned picker can ask the user to
select/approve the exact network. Android can remember this approval for later
requests. The test selects only the emulator's built-in `AndroidWifi`; an Android
picker approval may remain in the lab emulator, like a manually selected network.
No physical phone/host Wi-Fi settings are changed.

A request returns a **lease**, not a connected socket. `device_wait` reports
available/link_changed/lost/unavailable events. The available event and
`device_info` return a network selector for existing `net_*` APIs. Its network
has no requested Internet capability and is intended for local peer traffic.
The app/model process is never rebound. Closing/revoking the lease unregisters
its callback; a late callback cannot republish a closed lease. Existing system
Wi-Fi connections are not promised to disconnect when Collie closes its own
request. Start requests and hotspots while Collie is visible.

`wifi_suggest(ssid, security, password, hidden, metered, autojoin)` adds one Android
network suggestion on API29+ and returns a Wi-Fi-owned lease. Its `accepted` event
means the SDK accepted the configuration; it is **not** proof of approval or
connection. API31+ approval events carry the actual Android status. Android
controls per-app user approval and network choice. `autojoin=0` requires API30+.
Credentials are not echoed through metadata/events. Suggestions consume a global
32-entry recovery bound as well as the common32-handle workspace bound.

Closing/revoking/conversation closure removes the exact suggestion from Android.
Android otherwise persists suggestions after process death, so a bounded atomic
app-private journal is written **before** adding. It stores the configuration
(including its passphrase) outside all guest workspace roots; app backup is off.
Startup uses a single bounded background recovery worker, keeping SDK recovery
off the model worker. Later Wi-Fi calls also retry orphan cleanup. Live leases
from any workspace are excluded. Cleanup failures remain in the journal and
surface on later Wi-Fi access; no false removal success is returned. A cancelled
suggestion call rechecks its operation before writing/adding after recovery.

`wifi_hotspot()` uses Android LocalOnlyHotspot and emits started/error/stopped.
A started hotspot is local only, with no Internet tethering. Metadata/events omit
the passphrase; `wifi_hotspot_config(handle)` explicitly returns credentials.
Only one active/pending Collie request is permitted. Android has no public API
to cancel a pending request before its callback: closing marks the guest handle
closed, retains that pending lease, and immediately closes any late reservation.
Once the SDK reports failure/stop or releases the reservation, the slot is freed.

**24 headless Android Wi-Fi scenarios passed**, including actual precise Location
and Nearby consent/denial, scan cache/broadcasts, typed raw SSID/timestamps,
dual-grant checks, exact suggestion installation/removal, the Android picker,
TCP over the approved lease with all256 byte values, and an injected radio-state
change through the actual state broadcast. The process-death case
kills Collie with a live suggestion, restarts it, and independently checks both
the actual Android network store and the private journal after automatic recovery.
The local-hotspot test verified Android's real failure callback on this emulator;
**successful AP creation, credential delivery and peer traffic remain unverified**
and need an AP-capable fixture. This Wi-Fi-only snapshot predates the Direct and
RTT additions described below. The Aware adapter was added after this snapshot; see its separate audit below.

```sh
python3 scripts/test-collie-wifi-android.py \
  --out build/android-hardware --serial emulator-5580
```

The same build passed **11 lazy-permission groups** (now10 independent first-use
capability probes), **10 shared UI groups**, **9 shared-core groups** and the shared
binary hardware codec checks. APK packaging verification passed: debug6,538,257 bytes
(6.538 MB), non-debug6,472,642 bytes (6.473 MB). Debug SHA-256:
`09798d46e4daa9fe1afcf9b121cd1e2f3fe642e6c1637f4f45a59d2bcb559b78`.
No Git publication or phone deployment was performed.

References: [Wi-Fi permissions](https://developer.android.com/develop/connectivity/wifi/wifi-permissions),
[network requests](https://developer.android.com/develop/connectivity/wifi/wifi-bootstrap),
[network suggestions](https://developer.android.com/develop/connectivity/wifi/wifi-suggest),
and [local-only hotspot](https://developer.android.com/develop/connectivity/wifi/localonlyhotspot).

Earlier Wi-Fi-only build audit: **38 existing hardware +19 cellular +8 VPN +24 Wi-Fi
=89 Android scenarios passed** on the exact debug APK above. The four report hashes
were compared directly to the APK bytes. Remaining adapters and physical-device
gates in the inventory are still outstanding; this does not complete the full
hardware objective.


## Wi-Fi Direct integration

`p2p_open()` creates a channel with both Wi-Fi and Location grants and Android
Nearby/precise Location consent. Peer IDs belong to that channel. Peer paging,
PBC/display/keypad connection, cancellation, group creation/removal, configured
API29+ ephemeral groups, and connection/group inspection use WifiP2pManager.
Existing groups require explicit `p2p_group_attach()` for data access. Attaching
does not grant group-removal rights or owner credentials. Only an owned local
group owner can return `p2p_group_credentials()`; events omit its passphrase.

DNS-SD/UPnP advertisements and service requests have child handles. Closing a
child removes exactly its registration; rejecting a duplicate cannot remove a
live registration. `p2p_dns_sd_browse(channel,type)` accepts an empty type for an
all-services query. Type-specific PTR browsing and
`p2p_dns_sd_txt(channel,instance,type)` are separate Android requests. Copied
service/TXT/UPnP/raw response events arrive on the parent channel.

TCP listeners/clients and UDP endpoints bind to the actual group interface.
Numeric unicast destinations must belong to that interface's subnet; foreign
IPv6 zones and subnet broadcast addresses are rejected. Group loss/replacement
invalidates sockets. Channel closure removes its own discovery/registrations
and matching owned group. Android26 has no public Channel.close; cleanup closes
its own operations and drops references, while API27+ also closes the SDK channel.

Earlier two-emulator runs verified real peer discovery, configured groups and
owner credentials, Android PBC invitation consent, explicit incoming-group
attachment, 32KiB TCP/UDP roundtrips with all bytes verified in both VMs, and
actual group teardown invalidating sockets. These earlier runs are not a passing
report for the current APK. **Reliable DNS-SD/TXT exchange remains unresolved**;
a successful registration/discovery request is not treated as received data.
UPnP/raw response exchange and physical peers also remain unverified.

```sh
python3 scripts/test-collie-p2p-android.py --out build/android-hardware \
  --serial emulator-5580 --peer emulator-5582
# Independent service diagnosis, still requiring real received PTR and TXT:
python3 scripts/test-collie-p2p-android.py --out build/android-hardware \
  --serial emulator-5580 --peer emulator-5582 --services-only --query-all
```

## Wi-Fi RTT AP ranging

`wifi_rtt_info()` reports actual support/availability and Android's peer/burst
limits. `wifi_rtt_watch()` returns an availability subscription with a Wi-Fi
grant. `wifi_rtt_range(scan,bssids,burst)` selects distinct BSSIDs from an owned,
completed `wifi_scan` snapshot and requires both Wi-Fi and Location grants plus
Android precise Location/Nearby consent. Start ranging while Collie is visible
with Android Location on. Burst0 uses the platform default; custom burst sizes
require API31+. Only APs advertising 802.11mc or API35+ 802.11az NTB responder
support can be selected. Aware peers use the owned discovery session via `aware_rtt`, described below.

A range handle emits one `ranging` event containing peer status and, only for
successful peers, distance/stddev in millimetres, RSSI, attempted/successful
measurement counts and the elapsed-realtime timestamp. API35+ LCI/LCR reports
are copied with explicit truncation beyond512 bytes each. Whole-request failure
and the30-second deadline emit structured errors. Android's public app API has
no request-cancellation primitive: closing/revoking discards late callbacks and
removes the deadline; it does not claim to cancel the radio operation.

The headless Wi-Fi suite now includes actual RTT hardware-feature comparison,
empty/duplicate-target rejection through a real scan handle, and structured
unsupported results for an emulator lacking RTT. **No measured distance or RTT
radio callback has been verified on this emulator.** A capable phone and AP are
required for successful/failed peer results, availability changes, timeout and
late-callback/close tests.

## Polling memory and live revocation

The JNI byte-array bridge now allocates the actual returned length plus its NUL
terminator, retaining the2MiB reply cap. Previously every reply allocated2MiB,
including each small permission preflight and hardware poll. The shared hardware
operation registry is also cached only within one native invocation, and reset
with other native globals. One VM now completes100 actual hardware polls within
the unchanged256MiB memory cap. These changes do not cache grant decisions.

Allow-to-Ask/Deny changes cancel an executing native program before closing its
resources, preventing reuse of the old configuration snapshot to reopen devices.
An independent headless fixture has verified a real Wi-Fi watcher opening during
a long-running VM, UI permission revocation cancelling that program, closure of
the watcher, and structured denial on the next program. It preserves the original
conversation and permissions and needs no location/runtime grants:

```sh
python3 scripts/test-collie-revocation-android.py \
  --out build/android-hardware --serial emulator-5580
```


## Earlier P2P/RTT build audit

Debug APK SHA-256:
`67774785e192ed7a95dfd192c83d154fd63e4fa6807688c806bd7cccef33dc52`.
Non-debug APK SHA-256:
`7da5fe7e4cde4eb49b1929b5520a3a387ca9971aaf6a269104a937461bcf2d86`.
Packaging checks verified protected VPN metadata and the absence of debug fixture
classes/resources from the non-debug APK. Sizes are6,587,409 and6,538,178 bytes.

**103 Android checks passed on this exact debug APK:**38 existing hardware,
27 Wi-Fi/RTT,19 cellular,8 VPN,6 live revocation, and5 file/image-viewing checks.
Every report's APK digest was compared with the actual APK bytes; the index is
`build/android-hardware/hardware-audit.json`. Image tests crossed JNI and opened
actual text/image previews, checked snapshot replacement/invalid images, and
used the current collapsed Thinking and Allow/Deny controls. No live vision/model
request, gallery or camera picker was needed for these regressions. The shared
codec,9 core,11 lazy-permission and10 UI groups also passed.

This audit does not include a passing full P2P suite. Both typed and all-services
DNS-SD requests were accepted by Android and found the virtual peer, but delivered
no service/TXT replies during these runs. The test continues to fail until actual
service and correlated TXT events are received. Aware was implemented after this snapshot. Its radio verification and the other
unfinished families in the table remain required; the hardware goal is active.


## Wi-Fi Aware SDK adapter and draft PR baseline

`aware_info()` exposes actual support/availability and device limits.
`aware_watch()` subscribes to availability. `aware_open()` returns an attachment;
wait for `attached` before starting `aware_publish` or `aware_subscribe`, then
wait for `started`. Both grants and Android Nearby/precise Location consent are
required for discovery, data paths and ranging. Start these operations while the
app is visible. Availability disruption, attachment loss or revocation releases
discovery children; late callbacks cannot resurrect closed sessions.

Publish/subscribe accept a service name, typed information blob, binary match
filters, kind0/1, and TTL0 for no expiry or1..86400 seconds. Publish can enable
ranging; subscribe can set minimum/maximum distances (use-1 to omit each).
Each discovery session owns up to128 opaque peer IDs, paged by `aware_peers`.
Service and message events copy bounded binary data and explicit truncation.
IDs expire when the service is lost or its session closes. Updates are
asynchronous with one outstanding update and a15-second deadline. Sending uses
strictly increasing message IDs and at most32 outstanding acknowledgements with
10-second deadlines. `message_failed` never claims successful delivery.

`aware_network` requests a peer-specific Android data path with open, passphrase
or32-byte PMK security. API33+ callers may select a supported NCS_SK128/256 cipher;
older supported releases use the platform default. Keys are never echoed.
Passphrases require valid UTF-8. Only secured publishers advertise port/protocol
metadata. A lease emits available/peer_info/lost/unavailable; metadata includes
the Android network selector and peer IPv6 endpoint. Existing `net_*` operations
use that selector with their separate Network grant; the model/process is not
rebound. Both peers must request compatible links. Closing the lease unregisters
its request. Starting and closing cannot race past registration.

`aware_rtt(discovery,peer_ids,burst)` uses actual discovered Android PeerHandles
and the existing bounded RTT result path. Results identify the original opaque
peer IDs. Losing a peer or parent closes its data/ranging children; RTT close
continues to discard late results rather than claiming to cancel radio requests.
No live OS handles survive saved VM/process state. Aware pairing administration
and newer optional discovery modes are not exposed by these functions.

The draft PR baseline debug APK was
`4042ce7269319f77ac1b7b397d51260d50b86aff58c19a4904553e37550834de`;
the non-debug APK is
`48c13018861e87c462d48b15acd2d12d4a2eb362c5e8478b800f6ae034fdc0f2`.
On this debug APK, **43 Android checks passed**:10 Aware,27 Wi-Fi/RTT and6 live
revocation. Aware tests exercise real VM checkpoints, independent Wi-Fi/Location
denial, actual absence of NAN hardware, structured unsupported errors, rejection
of wrong adapter handles, unchanged Android runtime grants, and the generated
API reference. They do not manufacture sessions/peers or prove radio behavior.
Earlier103-check baseline evidence is recorded with its distinct APK hash above.
Shared validation also passed:153 compiler-transform checks, the binary codec,
USB-serial protocols, unaligned/overlap copy checks in native/interpreted code,
11 lazy-permission groups (including both Aware grants),9 core groups,10 Collie
UI groups and6 portable UI groups matching Linux to production Android ARM64.

**Aware positive attach/discovery/message exchange, data-path establishment and
TCP/UDP traffic, peer ranging and real asynchronous loss/timeout cleanup remain
unverified without NAN-capable devices.** Android36 headless emulators here do
not advertise `android.hardware.wifi.aware`; unsupported results are not counted
as radio proof. Wi-Fi Direct DNS-SD/TXT exchange also remains unresolved.

```sh
python3 scripts/test-collie-aware-android.py \
  --out build/android-hardware --serial emulator-5580
```


## Bluetooth Classic adapter

The Classic adapter exposes ordinary `bt_*` Flexscript functions. `bt_info`,
`bt_watch`, and paged `bt_bonded(offset,limit)` use the Bluetooth grant and actual
Android CONNECT permission on API 31+. Inventory does not request Location or
SCAN: `scan_mode` and `discovering` remain null until SCAN is granted. No local
hardware address is exported. `bt_device(address)` creates a workspace-owned
cached device handle without connecting. Its info and events carry name, type,
bond state and class. `bt_uuids(device,refresh)` optionally starts actual SDP;
the later `uuids` event carries the refreshed cache.

`bt_request_enable()` and `bt_request_discoverable(seconds)` suspend the VM for
Android's own confirmation, outside the VM lock. Discoverability accepts 1..300
seconds and requires ADVERTISE/SCAN. Its timer is global and controlled by
Android; there is no public SDK operation to cancel it on handle close.
`bt_bond(device)` starts Android pairing; observe bond events for its outcome.
Neither pairing confirmation nor removal of saved pairings is bypassed.

`bt_scan(duration_ms)` additionally needs the independent Location grant,
Android SCAN/precise Location and the enabled Location switch. It runs a real
Classic inquiry, capped at 30 seconds, 128 peers and 16 records per page. A single
Collie inquiry lease refuses existing discovery; it cancels only after its own
request was accepted. The finished snapshot remains permission-gated until
closed. Close/revocation unregister receivers and discard retained data.

`bt_rfcomm_listen(name,uuid,secure)` registers actual Android SDP, with one
Collie listener per canonical UUID. `bt_rfcomm_accept(listener,timeout_ms)`
returns an already connected stream or a structured timeout (1..8000ms), leaving
the listener usable. Closing a listener does not close accepted sockets.
`bt_rfcomm_connect(device,uuid,secure,timeout_ms)` returns a pending socket;
wait for `connected` or `error` before I/O. At most two connections may be
pending in the app. Its1..120-second deadline allows time for Android pairing.

Use `device_read/write` with at most 32768 bytes. A read timeout closes its
stream to prevent a late read consuming future data. Writes have an 8-second
cap and may have partially completed when interrupted. EOF, Classic ACL loss
and adapter shutdown close the endpoint; error events remain readable until
explicit close. Handles are scoped to their conversation and Bluetooth grant,
and do not survive process snapshots. Bluetooth capability reporting now
separates SDK implementation, hardware support and actual availability.

The Bluetooth debug APK is
`323723905dc10663ba4a5ea28b453c88e1aea2ff7aef20d844df0fd8494e61f7`
(**6,669,329 bytes**). The corresponding non-debug APK is
`06cdf06f137b270585c2138bb74637b6fd210192d190c25950fef323a2a010ee`
(**6,587,330 bytes**). Packaging verification confirms that test fixtures remain
excluded from the non-debug build. Earlier checks above belong to their stated
APK digests, not automatically to this build.

On this exact debug APK, **49 Android checks passed**: 15 Bluetooth baseline,
5 insecure peer, 5 secure peer, 8 VPN, 10 Aware and 6 live revocation. The two peer
reports independently record their security mode and observed encryption.
Shared validation passed the hardware codec/registry, 9 core groups and 11 lazy
permission groups, now including Bluetooth denial and its separate Location gate.

The baseline 15-check suite uses actual Android consent denial/approval, radio
enable confirmation, Classic inquiry, adapter/watch/bonded inventory, cached
device/UUID handles, input validation, secure SDP listener registration,
duplicate UUID preservation, actual accept timeout, foreign-workspace rejection
and revocation/reopen. It preserves the original conversation, grants and radio
state. The shared native tests additionally exercise Bluetooth first-use denial
and separate Bluetooth/Location checkpoints.

The controlled peer fixture uses Google's `bumble[android]==0.0.236` stack
through the SDK's local Netsim. It is a host-only test dependency and adds no
Python or libraries to the APK. Outgoing secure and insecure RFCOMM each
transferred 32768 bytes in both directions. The VM and independent peer byte
oracle validate the payload. Secure-mode verification also observes actual
link encryption. A real empty read timeout closes the SDK stream and reaches
the peer as channel closure. Pairing confirmation uses Android's UI for the
unique fixture name; cleanup checks its exact address before forgetting it
and then confirms the unpaired state through the actual BluetoothDevice SDK.
These are virtual-controller results, not physical radio evidence.

**Still unverified:** incoming RFCOMM payload/accepted-child lifetime, explicit
`bt_bond` and discoverability confirmation paths, radio/ACL loss during pending
I/O, and physical devices. BLE scan/GATT/client/server/advertising and Bluetooth
HID remain separate pending adapters. P2P DNS-SD/TXT and Aware radio gates remain
open as documented above.

```sh
python3 scripts/test-collie-bluetooth-android.py \
  --out build/android-hardware --serial emulator-5580
# Read the running emulator's grpc.port from $XDG_RUNTIME_DIR/netsim.ini.
# In a separate host virtual environment: pip install 'bumble[android]==0.0.236'
# Start a fresh uniquely named peer for each --secure 0 / --secure 1 run:
python scripts/fixtures/collie-bluetooth-peer.py \
  --transport android-netsim:127.0.0.1:PORT,name=collie-test-UNIQUE \
  --out build/android-hardware/bluetooth-peer.json \
  --uuid ed079c58-e558-4256-b89b-69adadbfdf8c
python3 scripts/test-collie-bluetooth-peer-android.py \
  --out build/android-hardware --serial emulator-5580 \
  --peer-state build/android-hardware/bluetooth-peer.json --secure 1
```


## BLE discovery and legacy advertising

`ble_info()` reports actual controller features. The `bluetooth_le_scan` and
`bluetooth_le_advertise` capability rows describe only these implemented
bindings. Discovery availability accounts for Android CONNECT/SCAN/precise
Location and the Location switch; advertising accounts for CONNECT/ADVERTISE.
When the controller cannot be queried while off or without CONNECT, advertising
support is null with `support_known=false`, rather than a false hardware-absence
claim. Capability discovery itself needs neither a Collie grant nor an Android
runtime prompt.

`ble_scan(service,address,duration_ms,mode)` requires independent Bluetooth and
Location grants, Android CONNECT/SCAN/precise Location, the Location switch and
a visible start. Empty service/address omit their filters. A canonical UUID
matches either an advertised service UUID list or service-data UUID; an optional
address filter is ANDed with either form. Mode0/1/2 selects low-power/balanced/
low-latency and duration is1000..30000ms. Android can pause unfiltered scans when
the screen is off. The adapter requests both legacy and extended scan results;
only legacy PDUs have been positively verified so far.

Each `found` event copies raw advertisement bytes for Flexscript protocols to
parse. Metadata includes address, SID, RSSI, monotonic timestamp, connectable,
legacy, PHY, completeness/data status, TX power and periodic interval. At most128
address/SID records are retained; `ble_scan_page` returns up to16 per page and
reports omitted records. A deadline or radio shutdown stops only this callback,
emits `finished`, and retains the permission-gated snapshot. SDK scan failures
emit an error with Android's numeric status. Close/revocation erases the data.

`ble_advertise(service,service_data,manufacturer,manufacturer_data,connectable,
power,mode,duration_ms)` opens an owned legacy advertiser. Empty UUID omits the
service; an empty service-data blob advertises its UUID list, otherwise it
advertises service data. Manufacturer-1 omits that field. Each byte field is at
most27 bytes, power0..3, mode0..2 and connectable0/1. Android's31-byte radio limit
includes field headers and flags, so a combination of individually valid fields
may still fail; its actual error callback is preserved. No device name or local
hardware MAC is included automatically. Duration0 lasts until close;1..180000ms
sets a deadline. Wait for `started`/`error`. Close, grant revocation and adapter
shutdown stop the owned SDK registration; late success cannot revive it.

The BLE debug APK is
`05a3675864a5608d2b46ff3cefc76847f26f8f0f6de0a34c34be970d0f1d754e`
(**6,702,097 bytes**). Its non-debug build is
`c721b403d44badafc103a67ddc28da85b488f3c5ded7b0aa01fe8e8291d6653e`
(**6,620,098 bytes**). Packaging checks passed with test fixtures excluded.

On this exact debug build, **12 BLE transport checks passed**. A controlled
host-only Bumble/Netsim peer emits an independently constructed raw packet
containing zero/high-bit service-data bytes; Flexscript checks the actual SDK
scan payload. The peer separately parses Collie's actual outgoing UUID/data
advertisement and verifies that its packets stop after close. Tests also cover
permission-free capability queries with both grants denied and Android runtime
permissions absent, invalid arguments, bounded pages/deadline, wrong handle
types, actual `ADVERTISE_FAILED_DATA_TOO_LARGE`, and independent Bluetooth and
Location denial despite existing Android runtime access. Original conversations,
runtime grants/flags and Location state are restored; test workspaces are
removed. No synthetic ScanResult or advertisement-success callback is used.
Shared codec/registry,9 core and11 lazy-permission groups also passed, including
both Bluetooth and Location checkpoints for BLE scans.

**Pending:** GATT connection/service enumeration/characteristic and descriptor
I/O, notifications/indications, GATT server requests/responses, extended/periodic
advertising controls, and positive extended-scan, manufacturer-data, radio-loss,
live-revocation and physical-device verification. This is not completion of the
BLE family or the full hardware objective. The earlier49-check Classic snapshot
above remains a separate APK, not a claim about these current bytes.

The Classic CI run `39959157664` timed out during dependency installation before
compiler tests ran: Azure's package mirror spent over11 minutes fetching the
61.2MB CJK font archive. CI now selects Ubuntu's main archive on mirrorlist-based
runners, retaining all packages and checks. The replacement run `39962130928` passed on the BLE commit `d608635`, including the full compiler/application suite. The GATT additions below require their own CI run.

```sh
# Use a separate virtual environment with bumble[android]==0.0.236.
python scripts/fixtures/collie-ble-peer.py \
  --transport android-netsim:127.0.0.1:PORT,name=collie-test-UNIQUE \
  --out build/android-ble/ble-peer.json
python3 scripts/test-collie-ble-android.py \
  --out build/android-ble --serial emulator-5580 \
  --peer-state build/android-ble/ble-peer.json
```


## BLE GATT client

`ble_connect(address,connect_timeout_ms,operation_timeout_ms)` opens an actual
asynchronous Android LE GATT client to an explicit address. Both deadlines are
1000..120000ms. It requires Bluetooth/Android CONNECT and a visible start;
it neither scans nor asks for Location. Wait for `connected` or `error` before
operations. SDK connections are workspace-owned resources; saved guest strings
do not restore them after a process restart.

`ble_gatt_discover(connection,id)` requests real service discovery. Subsequent
`ble_gatt_items(connection,parent,offset,limit)` pages up to16 records: empty
parent lists services, a service ID lists characteristics, a characteristic ID
lists descriptors. Up to4096 records are accepted. IDs are opaque and owned by
that connection; repeated UUIDs remain distinct. Every discovery attempt and
service-change event invalidates old IDs. Records include parent/kind/UUID/
revision and actual SDK instance, properties, permissions and service type.

All asynchronous request IDs are0..2147483647 and strictly increase within a
connection. Only one request may be outstanding. A request ID is consumed on
begin, including an immediate SDK refusal; `device_info` exposes
`last_request_id`, `pending_id`, `pending_operation` and `last_result`. The last
completion is retained separately from the bounded event queue so an overflow
does not erase the latest request result. Notifications retain attribute IDs
and revisions. Check `db_kind(event)==5` after polling: timeout returns a typed
`db_null`, and it is not safe to treat its word as a text pointer.

`ble_gatt_read(connection,attribute,id)` accepts a characteristic or descriptor
and emits a copied `read` event with ID, attribute, status and actual value blob
on success. Failed reads carry no fabricated bytes. `ble_gatt_write(connection,
attribute,bytes,kind,id)` emits write status. Values are at most512 bytes; write
kind1 is no-response,2 acknowledged and4 signed. Descriptors require kind2.
No-response/signed payloads must fit the observed ATT MTU minus3/15. The initial
23-byte bound is conservative; `mtu_observed` becomes true only on an actual
successful SDK MTU callback. A no-response write callback alone is not proof of
peer delivery. API33+ uses copied-value callbacks and byte-array write APIs;
older versions use the compatibility SDK object values, copied on callback
entry. That older-SDK path has not been positively exercised here.

`ble_gatt_local_notify(connection,characteristic,enabled)` controls only Android
notification routing. Flexscript configures the discovered CCCD descriptor
`00002902-0000-1000-8000-00805f9b34fb` separately: bytes `[1,0]` for notification,
`[2,0]` for indication, `[0,0]` to disable, followed by an acknowledged write and
its real success event. Protocol bytes and subscription policy stay in the VM.
Copied `notification` events cover both SDK notification and indication updates;
the public callback does not distinguish the two. Android handles indication
confirmation, which the independent peer test observes.

`ble_gatt_mtu`, `ble_gatt_rssi`, `ble_gatt_phy_read` and `ble_gatt_phy` use the
same serialized event channel. PHY masks1/2/4 select1M/2M/Coded. MTU requests
accept23..517; callers must use the actual reported result (Android14+ may
negotiate517 for a first request for64 and ignore later requests).
`ble_gatt_priority(connection,0..2)` requests balanced/high/low-power priority;
SDK acceptance does not prove changed radio parameters.

An operation timeout closes the SDK client, unregisters callbacks and discards
its attributes. Late callbacks cannot complete a different request. Adapter
shutdown, disconnect, callback mismatch and service change during a pending
request similarly fail the endpoint; its final error remains readable until
explicit close. With no pending operation, service change emits
`services_changed` and requires rediscovery. Close/revocation releases the
owned SDK connection; no operating-system objects are snapshotted by the VM.

The GATT debug APK is
`afe6721ac05c34b28f37ac074963b3a0afa0b7424bdd6a81a26235abb75dd746`
(**6,718,481 bytes**); its non-debug counterpart is
`6488c4ff41efcc9c96743d4db2f1889e06ebf43f025ceb2f42ced9644030439e`
(**6,636,482 bytes**). Packaging checks passed with debug fixtures excluded.
On these exact debug bytes, **26 Android checks passed**:14 GATT client plus12
scan/advertising regressions. The GATT peer is a controlled host-only
Bumble/Netsim server, with no Python added to the APK. It independently verifies
512-byte acknowledged/no-response writes, emits matching notifications and
confirmed indications, serves binary descriptors and duplicate-UUID values,
returns a real ATT authorization error8 and deliberately delays a read. Tests
observe request serialization, peer disconnection before that delayed response,
and preservation of the timeout afterward. Two real SDK clients reject each
other's attribute IDs; closing one preserves the other. Runtime SCAN/ADVERTISE
and Location remain denied throughout GATT I/O. Test conversations, grants/flags
and resources are restored or removed afterward.

Shared validation also passed:9 core and12 lazy-permission groups. The new native
check proves direct GATT connect checkpoints only Bluetooth and, after approval,
reaches the actual non-Android host boundary despite Location denial. It is not
substituted for the Android connection proof above.

**At this client-only checkpoint, still pending:** the GATT server adapter (added below), reliable-write transactions,
included-service links, PHY-set/radio-loss/service-change/queue-overflow/live
revocation fixtures, older-SDK compatibility and physical peripherals. Extended/
periodic advertising and the rest of the hardware inventory also remain open.
This client batch does not complete the BLE family or the overall objective.

```sh
# Host-only venv dependency: bumble[android]==0.0.236.
python scripts/fixtures/collie-gatt-peer.py \
  --transport android-netsim:127.0.0.1:PORT,name=collie-test-UNIQUE \
  --out build/android-gatt/gatt-peer.json
python3 scripts/test-collie-gatt-android.py \
  --out build/android-gatt --serial emulator-5580 \
  --peer-state build/android-gatt/gatt-peer.json
```


## BLE GATT server and shared event timers

`ble_server_open(response_timeout_ms)` opens a real Android SDK GATT server.
The timeout is1000..25000ms. A visible start, Collie Bluetooth and Android
CONNECT are required; Location, SCAN and ADVERTISE are not. Advertising uses
its separate `ble_advertise` function and permission. Guest snapshots preserve
ordinary values and IDs, never live SDK registrations.

`ble_server_add(server,uuid,type,definitions)` registers a primary(type0) or
secondary(type1) service asynchronously. Wait for `service_added` with status0
before advertising it or using its children. Only one registration may be
pending, with a15-second deadline. Definitions are typed lists of
`[uuid,properties,permissions,descriptors]`, and each descriptor is
`[uuid,permissions]`. `ble_define_characteristic` and `ble_define_descriptor`
append these rows to ordinary `db_list()` values. Property bits1..128 and
Android read1/2/4, write16/32/64/128/256 permissions are checked before any
registration state changes. Android enforces encryption/authentication flags.
Limits are32 services,128 characteristics per addition,16 descriptors per
characteristic and4096 total nodes.

`ble_server_items(server,parent,offset,limit)` pages at most16 services for an
empty parent, or children of an owned service/characteristic. Rows carry opaque
IDs, UUIDs, kind, parent, properties/permissions/type and active state. Duplicate
UUIDs remain distinct. `ble_server_remove` removes an owned service and
invalidates its descendants; finish registration, unanswered requests and
outgoing operations first.

`ble_server_peers(server,offset,limit)` lists at most32 connected peers with
opaque connection IDs, actual address, conservative initial MTU23,
`mtu_observed`, outgoing request state and the last completion. Incoming
`request` events carry `kind`(read/write/execute), peer, attribute (null for
execute), offset, prepared/execute/response_needed flags, copied byte value and
an opaque token when Android needs a response. `ble_server_requests` pages up
to128 unanswered requests independently of the bounded event queue.

`ble_server_respond(server,token,status,offset,bytes)` accepts ATT status0..255,
offset0..512 and at most512 bytes. Invalid arguments do not consume a live
request. A token is server/peer/request-owned and single-use; reply attempts
consume it even if Android refuses the response. Expired tokens are invalid.
An unanswered request receives ATT Unlikely Error14 at its real deadline and
emits `request_expired`; an SDK response failure closes the registration.
No-response write commands carry null tokens, create no pending response and
receive no automatic acknowledgement. Oversized SDK values and exhausted
request capacity produce explicit ATT errors where a response is required.

The VM owns attribute values, read slicing, authorization, CCCD subscription
state and prepared-write staging/commit/cancel. Java transports Android's
callbacks and responses; it neither commits values nor accepts valid writes
on behalf of the VM. The generated model API reference describes this contract.

`ble_server_notify(server,peer,characteristic,bytes,confirm,id)` uses the actual
SDK notification/indication API. The characteristic must declare the chosen
property; bytes must fit both512 and the peer's observed MTU minus3. A request
ID strictly increases per peer (0..2147483647). Wait for `notification_sent`
with that ID, attribute, confirm flag and actual SDK status. This completion
is retained on the peer as well as emitted. Flexscript separately decides
whether its CCCD state allows an update. `ble_server_phy_read` and
`ble_server_phy` share this one-outgoing-operation-per-peer channel; their
positive SDK callback fixtures remain pending.

`ble_server_disconnect` explicitly requests peer disconnection. A timeout or
peer disconnection during an outgoing operation fails the entire server
registration: Android's notification completion has no attribute/request ID,
so a late callback must not be reassigned to new work. Close releases owned
pending responses/timers, receiver and SDK registration. It does not cancel
all physical links: Android may share a connection between registrations or
apps. The two-server test closes one registration while the other continues
real ATT I/O. Radio-off and permission/lifecycle cleanup use the existing
workspace-owned handle boundary; remaining targeted revocation/radio tests
are still listed below.

Server integration exposed a shared timer bug: `HardwareSensors.events()`
created a new Handler on each access, so `removeCallbacks` targeted a different
Handler from the one that posted the timeout. It now returns one cached
Handler. Classic and GATT client connect deadlines also check their pending
state before failing. The Android check posts a real delayed callback and
cancels it through another accessor call; server registration and client
connection tests remain usable beyond their15-second connection/registration
deadlines. Wi-Fi and cellular regressions cover other users of this handler.

The independent server fixture uses a host-only Bumble client and localhost
Netsim. It discovers the Android advertisement from actual raw packets and
uses real ATT requests to verify512-byte long reads before MTU negotiation,
duplicate UUIDs, binary descriptors, prepared commit/cancel, invalid fragments,
unanswered request expiry, notifications, confirmed indications and no-response
writes. All application values and prepared buffers are in Flexscript/DB.
The test runs bounded VM batches and resumes from DB state while the owned SDK
server stays open; it does not enlarge or reset one running program's CPU
budget through progress checkpoints. A single endless VM handler is not implied.

The six Bluetooth/Wi-Fi/cellular scripts in this batch now compare the installed APK
bytes to the reported artifact before effects and after cleanup. A mismatch
fails the test rather than attributing an older installation's results to a
new file on disk. These host-only checks are excluded from the app. The Wi-Fi
fixture also revokes/restores the entire declared Nearby group for its consent
checks, and clears an abandoned emulator Settings picker before starting.
Android groups Wi-Fi and Bluetooth runtime consent together, while Collie
retains separate operation grants. See the [Android permission contract](https://developer.android.com/develop/connectivity/wifi/wifi-permissions).

The current debug APK is
`8710651d96bf2b9a978bf5770ea4e70b3c83e55d20af612ad4141620fc8cbc33`
(**6,751,249 bytes**,6.751 MB/6.438 MiB). The non-debug APK is
`e248c8f1499b8b56dc4014a9766efe569c008616757e6f8ce06027ac141aa5fa`
(**6,669,250 bytes**,6.669 MB/6.360 MiB). Packaging checks verified both
hashes and exclusion of debug fixtures from the non-debug app.

On these exact installed debug bytes, **107 Android checks passed**:18 server,
15 client,12 BLE discovery/advertising,16 Classic Bluetooth,27 Wi-Fi/RTT and19
cellular. Each report names that digest. The server test proves foreign,
expired and replayed token rejection, invalid status256 without consuming a
live request, closing a separate SDK server without breaking the owner's
connection, and cleanup after peer disconnect/removal. Runtime SCAN and
Location stay denied throughout server I/O; only the advertisement asks for
ADVERTISE. Native validation passed the shared32 KiB codec/registry checks,
12 lazy-permission groups (including server/client Bluetooth gates despite
Location denial) and9 shared-core groups. Test state/resources are restored
or removed; this remains emulator evidence, not physical-device verification.

**Still pending:** server-initiated outgoing connections, included-service
links, client reliable-write helpers, server PHY callbacks and PHY setting,
security/bonded access, explicit radio loss, service change, event overflow,
targeted live revocation and older-SDK/physical fixtures. Extended/periodic
advertising, Bluetooth HID and all other unfinished inventory families remain
in scope. This server batch does not complete BLE or the hardware objective.

```sh
python3 scripts/test-collie-gatt-server-android.py \
  --out build/android-gatt-server --serial emulator-5580 \
  --netsim-port PORT
# Uses build/bluetooth-fixture-env/bin/python (bumble[android]==0.0.236).
# The script owns its uniquely named local peer and cleans it up afterward.
```


## Classic Bluetooth HID device

`hid_open(name,description,provider,subclass,descriptor,in_qos,out_qos,timeout)`
requests the public Android9+ HID device profile and registers an owned app.
It requires Collie Bluetooth, Android CONNECT and a visible Activity. It does
not scan or ask for Location/SCAN/ADVERTISE. Wait for the actual `registered`
event before connecting or sending. The name/description/provider each require
1..50 UTF-8 bytes without NUL; subclass is0..255; the report descriptor is an
opaque1..2048-byte blob. Descriptors, report encoding, values, key state and
application policy remain in Flexscript. This is Classic HID, separate from
USB gadget support and custom BLE GATT services.

QoS arguments are empty `db_list()` values for Android defaults, or
`hid_qos(service,rate,bucket,peak,latency,variation)`. Service types are0..2;
the remaining fields accept unsigned32-bit values or-1 for MAX. A timeout of
1000..25000ms bounds registration, connection/disconnection and unanswered
control requests. SDK acceptance of a command is separate from its callback
or peer receipt. Failed registrations expose actual errors rather than a
synthetic supported device.

Android permits one registered HID app system-wide and disables its HID host
profile while that registration is active. Collie reserves one registration
across workspaces until teardown is confirmed. An unconfirmed unregister keeps
new Collie registrations blocked; its diagnostic state indicates that SDK
confirmation or app restart is needed. A late callback cannot register or
unregister a newer endpoint. Background entry closes the active registration
and removes all published HID handles, including error handles left when
Android automatically unregisters before Activity `onStop`. SDK profile
connections and registrations are never snapshotted by the VM.

`hid_connect(endpoint,bt_device_handle)` requires an explicitly paired device.
Use `bt_bond` and Android's pairing UI first; the HID call does not approve
pairing. Its return is an owned pending peer ID. Observe actual `connected`,
`connection_state` or `disconnected` events. `hid_peers(endpoint,offset,limit)`
pages up to8 owned peer records with address, SDK state0disconnected/
1connecting/2connected/3disconnecting, and protocol0boot/1report. Report mode
is the SDK's documented default. IDs expire on disconnect and cannot control
a new connection. `hid_disconnect` requests actual SDK disconnection; closing
an endpoint unregisters its app and stops its owned control/report transport.

`hid_send(endpoint,peer,report_id,bytes)` sends an input report; bytes exclude
the report ID (0 if the descriptor has none). Collie bounds the entire HIDP
packet to Android16's default512-byte HID MTU: up to510 data bytes with a
nonzero report ID,511 with ID0. Oversized replies/reports fail before SDK I/O.
The public proxy does not expose the negotiated peer MTU, so capability data
explicitly says `mtu_known=false`; these are transport bounds, not a claimed
measurement. SDK command acceptance does not prove delivery. The independent
host oracle verifies actual received bytes.

Incoming `request` events contain kind(get_report/set_report), owned peer,
report_type(1input/2output/3feature), report_id, requested buffer_size, copied
value/null and an opaque response token. `hid_requests` pages unanswered
controls separately from the bounded event queue. `hid_reply(endpoint,token,
bytes)` answers GET_REPORT, with no report ID in the byte blob. Flexscript
validates/stores a SET_REPORT and acknowledges it with `hid_error(...,0)`;
other handshake codes are1notReady,2invalidReportId,3unsupported,
4invalidParameter and14unknown. Invalid arguments leave a live request intact;
reply attempts consume it. Tokens are endpoint/peer-owned and single-use.
The SDK exposes no control transaction IDs, so overlapping requests or an
unanswered deadline close the registration to discard ambiguous late replies.

Interrupt output arrives as `output_report` with copied bytes and no response
token. `protocol` events report Android-acknowledged boot/report changes;
Flexscript adapts its own encoding. `virtual_cable_unplug` forwards the actual
public callback, including null identity if Android omits it. Collie does not
infer an unplug event from generic disconnection. The public SDK has no app
unplug method, so none is invented.

The debug APK is
`bc32bcd03b15996081fb581c79a0010eaed0771a35429f1ea88880c798a53423`
(**6,767,633 bytes**,6.768 MB/6.454 MiB). The non-debug APK is
`d6bd988c59907e0acf733516e1b62d17091246657efc4a455fd2618b34bc7e34`
(**6,702,018 bytes**,6.702 MB/6.392 MiB). Both packaging checks passed,
including debug-fixture exclusion and protected VPN service metadata.

On the exact installed debug bytes, **17 HID assertions passed**, including
real SDK registration/unregistration/reopening, single-owner rejection,
unpaired-host rejection, Android-confirmed pairing, actual encrypted
control/interrupt channels,510-byte feature/output/input reports, explicit
SET_REPORT acknowledgements, error handshakes, replay/invalid-argument checks,
boot/report protocol changes, disconnect/reconnect with expired peer IDs,
actual foreground cleanup and conversation/permission/pairing restoration.
The tests use a controlled localhost Netsim/Bumble host and vendor reports;
no reports are injected into the user's desktop. Application values stay in
Flexscript/DB between bounded VM batches. Runtime SCAN/ADVERTISE and Location
remain denied throughout. Shared32 KiB codec/registry,12 native lazy-permission
and9 shared-core groups also passed.

**The strict HID suite still exits nonzero.** Its report has `ok=false` and
`missing_gates=["public virtual-cable unplug callback"]`. The host's actual
unplug packet closes both channels, but Android does not deliver the public
unplug callback in this emulator run. Temporary HidDeviceService diagnostics
observed its ordinary disconnect/protocol callbacks but no unplug callback;
the prior log setting was restored. Generic disconnection is not substituted
for the missing SDK event. The adapter forwards that callback when delivered,
but this path is not claimed as positively verified. The other assertions and
foreground cleanup run independently of that gate so their evidence is retained.

On the same final debug APK, **34 regressions passed**:18 GATT server and16
Classic Bluetooth checks. These are separate from the17 partial HID assertions
and do not turn the failing strict HID gate into a pass.

**Remaining HID gates:** public virtual-cable callback, timeout/overlapping
control transactions, targeted permission revocation and radio/service loss,
custom QoS, ID0/no-report-ID descriptors, keyboard/mouse OS integration,
older-SDK compatibility and physical hosts. This batch does not complete the
HID family or the full hardware inventory.

Primary contracts: [HID device API](https://developer.android.com/reference/android/bluetooth/BluetoothHidDevice.html),
[callbacks](https://developer.android.com/reference/android/bluetooth/BluetoothHidDevice.Callback),
[SDP settings](https://developer.android.com/reference/android/bluetooth/BluetoothHidDeviceAppSdpSettings),
and [Android16 HID transport constants](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/android16-release/system/internal_include/bt_target.h).

```sh
# Host-only fixture dependency: bumble[android]==0.0.236, excluded from the APK.
python3 scripts/test-collie-hid-android.py \
  --out build/android-hid --serial emulator-5580 --netsim-port PORT
# Strict: remains nonzero if Android omits its public unplug callback.
# hid-android-report.json records partial passes with ok=false and missing_gates.
```
