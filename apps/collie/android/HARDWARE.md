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
| NFC | reader mode, NDEF, technology transceive, ISO-DEP/APDU, tag loss | SDK reader/technology/NDEF bindings implemented; portable NDEF codec in Flexscript | actual emulator adapter absence, NDEF compatibility, bounds and first-use consent verified; RF discovery/read/write/loss and physical fixtures pending |
| NFC emulation | host APDU services and supported HCE-F; OS-controlled routing | public ISO-DEP other/payment and NFC-F service, routing, command/reply and lifecycle SDK bindings implemented; polling/observe extensions and background operation pending | 62 actual Android service/VM and explicitly constructed Binder-peer checks passed; SDK adapter absence is real, successful registration/routing/RF/physical checks remain unverified |
| Secure elements | OMAPI readers/sessions/channels/APDUs with real access-control errors | SDK service/readers/sessions/channels and extended APDU byte transport implemented | actual independent service bindings, empty reader inventory, owned asynchronous shutdown and first-use consent verified; real applet/channel/APDU and access-control fixtures pending |
| UWB | supported-device sessions and ranging events through supported APIs | Android16 public raw-session, capability, peer and interval bindings implemented; older SDK integration pending | actual two-emulator measurements and SDK peer callbacks verified; strict effective-interval check remains failing; physical/older-device checks pending |
| Infrared | capabilities/carrier ranges/transmit | implemented | emitter absence correctly reported on emulator; real IR fixture pending |
| MIDI | enumerate/open/ports/messages/events | implemented, including byte-stream/UMP inventory and known-address BLE-MIDI open | Android virtual-service loopback passed, including 32 KiB binary payloads, timestamps, exclusivity, flush and child cleanup; physical USB/BLE/UMP fixtures pending |
| Location | location providers/updates/status, GNSS satellites/raw measurements/navigation messages | implemented | actual Android runtime prompt and injected GPS callback passed; raw GNSS device data pending |
| Sensors | enumerate/capabilities/subscriptions, motion/environment/activity and available health sensors | subscriptions, triggers and paged static/dynamic inventory implemented | actual accelerometer callback passed; activity/health device checks pending |
| Camera | devices/characteristics, capture/frames/video, supported manual/RAW/depth controls, torch | Camera2, typed request/result metadata, bounded JPEG/YUV/SDK planes, MediaRecorder and owned torch SDK bindings implemented; per-physical overrides and additional metadata types pending | actual headless JPEG/YUV bytes, applied manual ISO/exposure, silent/audio video, consent, callback delays, capacity and revocation passed; RAW/depth, torch, physical/older-device and remaining lifecycle gates below |
| Audio | input/output devices, PCM capture/playback/routing, recording | PCM16 mono/stereo streams, metadata, route preference, control and events implemented | actual AudioRecord/AudioTrack calls and runtime microphone consent passed; onStop closes capture and blocks background opens; physical inputs/output routes pending |
| Input | delivered touch/stylus/key/mouse/gamepad events | SDK inventory/ranges/key query and passive own-Activity event bindings implemented | 24 input checks passed: real emulator events, kernel keyboard add/remove and filtering, copied SDK history, bounds, ownership and live revocation; physical devices, actual device-changed callbacks and older Android pending |
| Haptics | capabilities/effects/waveforms/cancel | implemented | actuator inventory passed; effect/cancel checks pending |
| Device status | battery/charging/electrical data, thermal state/headroom/events | implemented | battery/thermal status and subscriptions passed; thermal-change injection pending |
| Biometrics | system authentication result only | SDK availability, owned system prompts and cancellation implemented | 51 enrolled/unenrolled SDK checks passed, including real fingerprint/PIN success, cancellation, expiry, late success and live revocation; physical/older-device checks pending |
| Keystore | scoped aliases, hardware-backed key generation/sign/verify/encrypt/decrypt/delete | implemented | actual Android EC/RSA/HMAC/AES operations, independent JCA checks, required backing, full-size frames and isolation passed; physical secure-processor attestation pending |
| Screen capture | explicit MediaProjection consent, frames/recording/session lifecycle | pending | pending |
| Accessibility | explicitly enabled service, exposed UI tree/actions/gestures/events | pending | pending |
| Storage | app-private filesystem, user-granted documents/folders/media/removable storage | private files/attachments and persisted SAF tree, document, byte-stream and typed-stream SDK bindings implemented | 29 real Android picker/provider/lifecycle checks passed; full-size binary data, asset byte ranges, restart and both revocation layers verified; provider copy/move/remove, actual virtual conversion and physical removable/cloud providers pending |
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
- `guest/nfc.flex`: portable NDEF record validation, encoding and chunk reassembly.
- `android/HardwareNfc.java`: NFC reader, tag technology, copied events and SDK NDEF transport.
- `android/HardwareSecureElement.java`: owned OMAPI services/readers/sessions/channels and raw APDU transport.
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

## NFC reader, portable NDEF and OMAPI

`nfc_info()`/`nfc_watch()` use actual adapter state. `nfc_reader(flags,delay)`
requests foreground reader mode with explicit technology and SDK option flags;
`reader_requested` does not assert that any RF discovery happened. One app-owned
reader holds up to16 tag references with omission counts. `nfc_tags` pages their
opaque IDs, binary UID and SDK technologies. `nfc_connect` opens one technology
per tag; `device_info` exposes actual protocol metadata and transceive limits.
Raw transceive/ISO-DEP bytes, supported timeouts and MIFARE authentication use
SDK technology methods. Cached discovery NDEF is distinct from a fresh read.
NDEF read/write/format/read-only operations pass encoded blobs to Android;
format/read-only can permanently change a real tag. Ignore acceptance is distinct
from the actual tag-removal callback. Close, backgrounding, radio loss and expired
SDK tags invalidate their owned resources. Failed writes report uncertain
completion instead of replaying them. At that reader checkpoint, HCE/HCE-F was
still pending; its later service-transport batch is recorded below.

`guest/nfc.flex` owns the portable record/codec logic. `ndef_record` builds a
four-field typed record, `ndef_encode` writes canonical short/long message lengths
and optional binary IDs, and `ndef_parse` validates headers/bounds and reassembles
chunked payloads. Pure computation needs no NFC, secure-element or database grant.
Native and interpreter tests cover independent wire vectors, binary bytes, chunk
IDs, malformed messages and the complete32768-byte message boundary. Android's
independent `NdefMessage` parser cross-checks actual guest-generated bytes; this is
codec evidence, not RF tag I/O.

`se_open` binds a real Android OMAPI service asynchronously; each binding owns its
reader IDs, sessions and channels. SDK reader presence is not inferred from
feature flags. Applet certificate/access rules stay under Android/secure-element
control. `se_transmit` returns actual data and raw status words; extended commands
use sequential `se_command`/`se_command_write`/`se_send`, up to65544 bytes.
`se_response` pages a cached response up to65538 bytes without repeating a command.
Response IDs reject another exchange's data; applet selection cannot overlap an
in-flight exchange. Interrupted commands are never automatically replayed.

Local close invalidates handles immediately. SDK close/shutdown may wait for an
APDU and runs on bounded background cleanup workers. The8-service lease and
16-session/32-channel per-service limits include pending cleanup; vendor calls
that have not returned do not free a slot prematurely. Timeout invalidates the
entire owned service because OMAPI provides no reliable per-call interruption.
Tests deliberately block one cleanup task, close on the actual Android UI thread,
then verify a second actual SDK service before and after the first shuts down.
Byte-buffer fixtures are explicitly separate from SDK APDU evidence.

The headless emulator has no NFC reader adapter and reports zero OMAPI readers.
Physical discovery/transceive/NDEF mutation/tag-loss, actual applet access-control
failures, sessions/channels/APDUs and older-device behavior remain unverified.
Normal manifest NFC permission does not replace the conversation's lazy NFC gate;
secure-element access has its own first-use gate and real Android applet rules.

### Bounded API documentation

The detailed hardware reference now exceeds the single-value32768-byte bound.
`hardware_api()` returns a compact signature index; `hardware_api_page(offset,
limit)` returns `{text,total,next}`, where limit is1..32768 and next=-1 means EOF.
Both are available without hardware grants. The reference verifier reads every
actual generated byte through VM RPC, checks the maximum-size page, and rejects
invalid bounds rather than silently truncating documentation. The bootstrap and
older Aware reference test use the paged contract.

```sh
build/flex-hardware apps/collie/tests/nfc.flex -o build/test-collie-nfc
build/test-collie-nfc
build/flex-hardware run --interpret --fuel=10000000 apps/collie/tests/nfc.flex
python3 scripts/test-collie-hardware-reference.py --out build/android-nfc
python3 scripts/test-collie-nfc-android.py --out build/android-nfc \
  --serial emulator-5580
```

Primary SDK contracts: [reader mode](https://developer.android.com/reference/android/nfc/NfcAdapter#enableReaderMode(android.app.Activity,android.nfc.NfcAdapter.ReaderCallback,int,android.os.Bundle)),
[NDEF messages](https://developer.android.com/reference/android/nfc/NdefMessage),
[OMAPI service](https://developer.android.com/reference/android/se/omapi/SEService),
and [OMAPI channels](https://developer.android.com/reference/android/se/omapi/Channel).

### NFC batch artifact evidence

The final debug APK `build/android-nfc/collie.apk` is **6,849,553 bytes**
(6.850 MB /6.532 MiB), SHA-256
`1bd228a3b8cad609ce952c409c4e73d6e7b4dc006868925ebbaa4b338680d38e`.
The non-debug `build/android-nfc-release/collie.apk` is **6,767,554 bytes**
(6.768 MB /6.454 MiB), SHA-256
`aa5b8b893b2483ce903ebc5f9c712fb8bd809513d10d618a5b8663943c3abe12`.
Packaging checks exclude all debug fixtures from the non-debug APK and retain
protected VPN binding/foreground metadata.

On that exact installed debug artifact, **77 Android checks passed**:33 NFC/OMAPI,
10 Aware,16 Classic Bluetooth and18 GATT server. Each report records that digest.
The NFC suite preserves the original conversation, distinguishes its deliberately
denied codec workspace from allowed SDK fixtures, and uses actual accessibility
buttons for both first-use grants. It explicitly reports `radio_verified=false`
and `apdu_io_verified=false`.

The same guest/core source passed native/interpreter NDEF vectors,4 paged-reference
checks (all42,867 detailed bytes,7,926 index bytes, full32768-byte page and invalid
bounds),13 lazy-permission and9 shared-core groups. The full hardware objective
remains open. The earlier HID artifact's strict missing public unplug callback
remains a separate failing gate; these passes do not override it.


## Input devices and delivered events

`input_devices(offset,limit1..16)`, `input_info(id)`,
`input_ranges(id,offset,limit1..16)` and `input_has_keys(id,key_codes)` use
Android's actual InputManager/InputDevice metadata. Device IDs are transient
integers. `input_watch(device,mask,axes,history_limit)` returns a workspace-owned
handle. Device-1 means all; mask bits are1 touch,2 key,4 generic mouse/joystick
motion,8 device inventory changes. At most16 distinct axis codes and0..8
historical samples are requested. Pointer rows are
`[pointer_id,tool_type,axis_values]` in the requested axis order, with db_real
values, uptime timestamps, source/action/button/meta data and explicit
history/pointer omission counts. Historical rows retain the containing event's
action. SDK event objects are copied before Android can recycle them. Legacy
key characters are bounded to4096 UTF-16 units without splitting surrogate
pairs, with an explicit `characters_truncated` field.

The Activity hooks preserve normal Android dispatch and observe only events
actually delivered to Collie. Other apps' input is not visible. The VM receives
no input-injection or global-capture API. Software keyboards can commit text
without KeyEvents. The new Input grant defaults to Ask, including migrated
conversations; malformed policies still deny. No separate Android runtime
permission is required for the app's own events. Streams use the bounded common
queue, close on background/conversation change/revocation, and selected-device
streams close on removal. The8-subscription app limit includes SDK listeners.
Keyboard/navigation configuration changes preserve the Activity instead of
recreating it and losing live subscriptions during attachment.

### Input and cross-platform UI verification

The **24 input checks** distinguish these evidence sources:

- Actual emulator delivery: touch/F1, stylus-source taps, fractional mouse
  scrolling, joystick axes and gamepad trigger events cross the SDK/VM boundary.
- A temporary kernel-backed keyboard produces actual Android add/remove
  callbacks, inventory changes and F1 down/up events. A selected-device stream
  excludes another keyboard's events whose delivery is independently observed
  by an all-device stream. Removal closes only the selected stream; the global
  watcher remains usable. The helper uses the emulator shell's existing uinput
  access, lives outside the APK, and is removed afterward. Collie gains no new
  platform privilege. The driver requires an x86_64 emulator and bounds helper
  lifetime, commands and cleanup.
- Clearly marked SDK-constructed fixtures verify four historical samples/two
  pointer IDs and tools, exact fractional bits/timestamps after MotionEvent
  recycling, event-category filtering, a150-event burst bounded to128 with22
  dropped, and Unicode truncation. These are not physical stylus/controller or
  OS batching evidence.
- A different actual VM workspace cannot use the handle. A live VM is observed
  waiting in hardware I/O before the real UI settings path changes Input to
  Deny. That cancels the running program, closes its SDK listener and prevents
  a subsequent program from reopening it. Explicit close, background/reopen,
  capacity/release and original-conversation cleanup also pass.

The input integration exposed an existing Android UI issue: every text editor
forced sentence capitalization, including search and model identifiers. The
portable input property `autocapitalize` now selects none/sentences/words/
characters. Flexscript declares None for search/model and Sentences for chat;
Android maps it to editor flags and the DOM adapter to its native hint. Desktop
committed text is unchanged. The compiler rejects the property on non-input
widgets. Controlled updates retain keyboard configuration, focus and drafts.
Real Android widget checks and five full navigation groups verify this behavior;
Chromium verifies the same compiler-produced hints and view transitions.
Permission-summary fixtures now include the30th grant instead of asserting the
old29-entry schema. The optional Android UI adapter test restores preferences
and removes its private workspace, with before/after APK guards.

**Remaining Input gates:** actual device-changed callbacks, older Android,
physical multi-touch/stylus/mouse/controllers. Kernel/emulator/constructed fixtures do not
substitute for those physical checks. The full hardware objective remains open,
including the earlier separate strict HID missing-unplug-callback failure.

```sh
python3 scripts/test-collie-input-android.py --out build/android-input \
  --serial emulator-5580
# gcc is used only for the emulator fixture; no C helper ships in the APK.
```

SDK contracts: [input devices](https://developer.android.com/reference/android/view/InputDevice),
[motion events](https://developer.android.com/reference/android/view/MotionEvent),
[device listeners](https://developer.android.com/reference/android/hardware/input/InputManager.InputDeviceListener),
and [kernel uinput](https://docs.kernel.org/input/uinput.html).

### Input batch artifacts

Debug `build/android-input/collie.apk`: **6,865,937 bytes**
(6.866 MB /6.548 MiB), SHA-256
`9b7c7bc2c0d6c525f11acc772470e22f67ae43e64e67e261bf35a9b748705d65`.
Non-debug `build/android-input-release/collie.apk`: **6,767,554 bytes**
(6.768 MB /6.454 MiB), SHA-256
`a716f016b1b7cd9d7c430ac864f37a408c758b0c10fb6dee41ff7946be012cc2`.
Packaging verifies that HardwareInputChecks and every other debug fixture are
excluded from the non-debug APK and protected VPN metadata is retained.

On those installed debug bytes, **91 hardware checks passed**:24 Input,33 NFC/
OMAPI,16 Classic Bluetooth and18 GATT server. Five navigation groups also
record and verify that installed digest. NFC RF and real secure-element
APDU I/O remain explicitly unverified. Shared checks passed7 portable UI groups
(including actual Android widgets),10 complete Collie UI groups,4 bounded
reference checks,13 lazy-permission groups (14 first-use gates), and9 core groups.
The same portable patches passed headless Chromium and60 native SDL desktop
checks using the dummy video driver. Local mapped X11 testing was unavailable
because xvfb-run is not installed; CI runs that explicit X11 variant. Historical
checks on other APK digests remain under their own artifacts above.

## System biometric and device-credential authentication

`biometric_info(authenticators)` reports the actual Android SDK availability
value (or an explicit unknown on older APIs), device-lock configuration and
feature flags. Availability and enrollment never imply successful authentication.
`biometric_auth(title,subtitle,description,authenticators,confirmation,timeout_ms)`
starts Android's system-owned prompt from a visible Activity and returns an
opaque workspace handle. Android keeps biometric templates, images, PINs,
patterns and passwords. Only a real successful SDK callback produces an
`authenticated` event. The raw SDK authentication type distinguishes biometric
from device credential on Android11+. This result is neither cryptographic
attestation nor a Keystore authorization token.

Authenticator masks are15 strong/Class3,255 weak/Class2-or-better,32768 device
credential, and32783/33023 biometric-or-credential. Android16 additionally accepts
its optional Identity Check bit65536; Android controls its policy and enforcement.
Android9 exposes only the default weak prompt and confirmation1; Android10 also
supports weak-or-credential and the configurable confirmation hint. Other strength
requests fail explicitly on those releases. Nothing silently weakens a requested
class. The timeout is500..120000ms. Title, subtitle and description have explicit
UTF-16 limits200/400/2000; the title must not be blank.

`device_wait` yields copied requested/help/not_recognized/authenticated/error
and cancellation events through the common bounded queue. A requested event says
the SDK call was made, not that the prompt was displayed or authentication passed.
`device_info` exposes state, sdk_requested, sdk_terminal, late_success_rejected
and cleanup_pending. The late-success flag records a real SDK success callback
that was refused after cancellation/expiry; authenticated remains false.
`biometric_cancel` returns a typed1 for a new request or typed0 if already finishing;
an operation error is the separate bare0/db_error path. Cancellation keeps the
handle observable; `device_close` invalidates it immediately. The global single
prompt lease remains held until the actual terminal SDK callback, or confirmation
that no SDK request was ever started. Another workspace cannot inspect or cancel
the handle. Revocation and conversation/process teardown cancel owned requests.

SDK start and signal cancellation both run on the Android main queue. Deadlines
use elapsed time and are checked independently of the scheduled timeout task,
including before accepting a success callback. Blocked UI/callback queues cannot
turn an expired request into success. Cancellation and timeout reject late
success; local cancellation is distinct from confirmation that Android finished.
Android owns prompt background cancellation and credential fallback. No enrollment
or lock setting is changed by the adapter. USE_BIOMETRIC is a normal manifest
permission; the separate conversation grant remains lazy Ask/Allow/Deny.

The optional enrolled test uses only the separately owned headless
`Collie_Biometrics_API36` AVD, configured through real Android enrollment with a
public fixture PIN and virtual fingerprint1. Virtual fingerprint2 is deliberately
not enrolled. The unenrolled test never changes its emulator's security settings.
Both preserve the original conversation and permissions, clean private fixture
workspaces, and guard the installed APK digest before and after the run. SDK and
emulator evidence do not prove physical fingerprint/face/iris behavior, vendor
confirmation UI, real lockout, Identity Check policy or older-SDK compatibility.

```sh
python3 scripts/test-collie-biometrics-android.py --out build/android-biometrics \
  --serial emulator-5580
# Only for the separately owned, already enrolled test AVD:
python3 scripts/test-collie-biometrics-android.py --out build/android-biometrics \
  --serial emulator-5582 --enrolled --fixture-pin 135790
```

SDK contracts: [system prompt](https://developer.android.com/reference/android/hardware/biometrics/BiometricPrompt),
[authenticator masks](https://developer.android.com/reference/android/hardware/biometrics/BiometricManager.Authenticators),
and [availability](https://developer.android.com/reference/android/hardware/biometrics/BiometricManager).


### Biometric batch artifact evidence

Debug `build/android-biometrics/collie.apk`: **6,898,705 bytes**
(6.899 MB /6.579 MiB), SHA-256
`2f1d9ffff34a372cbc09bb27e09a34fe0ac67078e3529ec9ab9c1f5cb0e51692`.
Non-debug `build/android-biometrics-release/collie.apk`: **6,783,938 bytes**
(6.784 MB /6.470 MiB), SHA-256
`b87854334d49c82bc7d5ad8a4eb7e52b3f9eb127094fee87db196f43f2c295e8`.
Packaging verifies USE_BIOMETRIC and protected VPN metadata in both APKs, and
excludes HardwareBiometricChecks and all other debug fixtures from non-debug.

On those installed debug bytes, **108 Android checks passed**:36 enrolled
biometric,15 unenrolled biometric,24 Input and33 NFC/OMAPI. The two biometric
reports separately retain physical_authentication_verified=false. Actual
first-use approval resumes the interrupted call; metadata agrees with independent
SDK queries. The original emulator remains unenrolled and without a device PIN;
its actual no-biometric11/no-credential14 error callbacks are verified. A separate
owned AVD provides real Android fingerprint enrollment and PIN authentication.
An unregistered virtual finger yields a nonterminal failed-attempt callback,
then the registered finger succeeds with authentication_type2. Entering only the
public fixture PIN through SystemUI succeeds with authentication_type1.

Explicit cancel receives SDK error5, the actual negative Button invokes its
SDK callback, and Home receives SDK user-cancel10. Active timeout waits for SDK
teardown. Controlled main/callback queues verify cancellation before SDK start
and elapsed-time expiry despite blocked scheduled tasks. Closing an active
request while its SDK callback executor is held invalidates the local handle
but preserves the global busy lease until the actual callback runs. Another
actual VM workspace cannot inspect or cancel it. Revoking the grant through the
real permission-save path cancels a program already observed waiting in hardware
I/O, closes the request and prevents a later program from reopening biometrics.

For the late-success race, the actual callback/deadline executor is held while
the host observes the unique SystemUI prompt and delivers its enrolled virtual
finger before expiry. It releases the queue after the elapsed deadline. The
actual successful SDK callback is then rejected: the VM observes timeout,
late_success_rejected=true, authenticated=false, no authenticated event and a
released prompt lease. No authentication callback is manufactured by the tests.

The same source passed shared hardware codec/registry checks,4 paged-reference
checks (47,754 detailed bytes and8,211 index bytes),13 native lazy-permission
groups covering15 first-use gates, and9 shared-core groups. Earlier Bluetooth,
UI and compiler evidence remains attached to its own artifacts. The separate
strict HID missing public-unplug-callback failure remains open. Physical/vendor
biometrics, face/iris, real lockout, confirmation/Identity Check policy and older
SDKs still require appropriate fixtures. The full hardware inventory remains open.

## Public UWB ranging

`uwb_info()` returns `{sdk,feature,public_ranging_api,snapshot}` and
`uwb_watch()` observes actual Android16 RangingManager capabilities. The separate
Collie UWB grant is lazy; Android's RANGING runtime permission is unnecessary
for capability queries and requested only when a program starts ranging.
Availability comes from the actual SDK callback:0 unsupported,1 user-disabled,
2 regulatory-disabled,3 enabled,4 user-restrictions. Feature flags and enabled
state do not prove a measurement. Each capability list has at most256 values.
Global capability discovery reports availability unknown, rather than inferring
it from a feature flag; explicit snapshots/observers provide actual state.

`guest/uwb.flex` contains portable typed constructors, without platform effects.
`uwb_peer(uuid,session_id,config_id,local_address,peer_address,channel,preamble,
rate,slot,key,sub_session_id,sub_key)` constructs12 fields. Addresses are2/8-byte
blobs; keys are bounded32-byte blobs, with empty meaning unset. IDs preserve
unsigned32-bit values; sub-session-1 means unset. SDK profiles1..6 differ from
older Jetpack profile numbering. The caller negotiates matching addresses,
channels, security and sessions in Flexscript; the adapter does not substitute
weaker profiles or replay uncertain requests. `uwb_options` carries angles,
measurement limit0..65535, fusion, notification mode0..3, near/far0..20000cm,
and a500..120000ms opening deadline. Native/interpreter tests exercise exact
IDs, binary fields, the12-argument record and its complete codec round trip.

`uwb_range(role,peers,options)` uses Android's public raw configuration and
returns an owned pending handle. An initiator(role1) accepts1..8 peer records;
a responder(role0) accepts exactly1. SDK callbacks yield opened, started,
ranging, stopped, open_failed and closed. A session-open event is distinct from
measured distance. Ranging events retain peer UUID, technology0, elapsed-time
millisecond timestamps, nullable measurement/confidence objects for distance
in meters and azimuth/elevation in degrees, and nullable RSSI. Measurement
values use the explicit bit-preserving db_real transport. Confidence values
remain the actual SDK0/1/2. Invalid nonfinite measurements are rejected.
`device_info` also exposes the current elapsed-time clock, known peer UUIDs,
state and cleanup status. A configured UUID is not proof of connection.

After opened, `uwb_add`, `uwb_remove` and `uwb_interval(skip0..255)` request SDK
changes. The session retains at most8 known UUIDs, including removed ones, to
bound identity history and reject unknown late peers. SDK method acceptance is
not proof of a radio change. onOpenFailed after a session already opened is
reported as operation_failed and does not free an existing session prematurely.
`uwb_stop` keeps the handle observable until actual SDK terminal confirmation;
`device_close` invalidates locally and schedules SDK stop. Actual closed events
or confirmation that no radio request started release a slot. A returned SDK
close call is distinct from the actual terminal callback. Pending vendor cleanup
and errors retain their leases instead of claiming teardown completed.

There are8 observer and8 session leases globally. Both include pending cleanup.
Two bounded SDK cleanup workers keep close/revocation off the Android UI thread.
Controlled queue tests verify that local close returns on the real UI thread
while cleanup workers are held. Opening deadlines use elapsed time independently
of the scheduled callback queue; delayed opened callbacks cannot revive an
expired request. A different workspace cannot inspect/stop a handle. The actual
permission-save path cancels a VM already observed waiting in hardware I/O,
closes its request and prevents subsequent reopening. Android controls supported
background behavior and radio/system-policy restrictions. No SDK resource is
snapshotted into guest state.

Android16's framework RangingSessionManager retains its session map. Each owned
resource therefore gets an independent SDK service cache using a scoped Context;
actual SDK identity checks verify it is separate from the app-global manager.
The scoped manager is dropped after confirmed teardown. No hidden UwbManager,
raw host FFI, new model tool or bundled Android framework is introduced.

**Older SDK integration remains unimplemented.** Android12..15 UWB access through
Jetpack/Play services is separate work; this public Android16 binding does not
complete that requirement. On older devices, uwb_info explicitly reports
public_ranging_api=false/older_binding_implemented=false and other UWB operations
reject the missing binding. Physical devices, distance/angle accuracy, nonzero
position oracles, background support, vendor radios and the remaining profile/
security/extended-address configurations still need appropriate fixtures.

The emulator peer suite remains strict about effective interval reconfiguration.
The SDK accepts skip1 and Android logs the request through RangingSession,
UwbAdapter and UwbSessionManager, but observed SDK timestamps remain about201ms
apart before/after. The report retains ok=false with
missing_gates=["effective_interval_reconfiguration"], while independently testing
peer changes and cleanup. A successful SDK method return is not substituted for
the missing timing effect. The separate older HID missing-unplug-callback failure
also remains open. These are independent gates, not passes hidden by compiler CI.

The two headless peers use actual SDK controller/responder sessions with mirrored
binary addresses and matching explicit session/security values. Both deliver
0.0m in the current virtual setup. This proves copied SDK measurement transport,
not physical ranging accuracy or an independently controlled virtual distance.
Netsim's installed frontend GetVersion/ListDevice return UNIMPLEMENTED, so its
positions are not claimed as an independently verified oracle. A clearly labelled
constructed SDK Parcelable tests fractional binary64 bits through the VM; no
successful SDK ranging callback is manufactured for that fixture. A configured
extra virtual peer yields actual started/stopped callbacks, while the original
peer keeps measuring; no third physical device is claimed.

```sh
build/flex-hardware apps/collie/tests/uwb.flex -o build/test-collie-uwb
build/test-collie-uwb
build/flex-hardware run --interpret --fuel=10000000 apps/collie/tests/uwb.flex
python3 scripts/test-collie-uwb-android.py --out build/android-uwb \
  --serial emulator-5580
# Separately owned peer AVD, already unlocked and installed with the same APK:
python3 scripts/test-collie-uwb-peer-android.py --out build/android-uwb \
  --serial emulator-5580 --peer-serial emulator-5582
# Strict peer suite remains nonzero until its effective-interval gate passes.
```

SDK contracts: [ranging module](https://developer.android.com/develop/connectivity/ranging),
[manager](https://developer.android.com/reference/android/ranging/RangingManager),
[session](https://developer.android.com/reference/android/ranging/RangingSession),
[UWB parameters](https://developer.android.com/reference/android/ranging/uwb/UwbRangingParams),
and [Android16 framework lifecycle](https://android.googlesource.com/platform/packages/modules/Uwb/+/refs/heads/android16-release/ranging/framework/java/android/ranging/RangingSessionManager.java).


### UWB batch artifacts and verification

Debug `build/android-uwb/collie.apk`: **6,947,857 bytes**
(6.948 MB /6.626 MiB), SHA-256
`ad58f7374b84877a48da841887c46aa40728b7e4cb6b8eea235a52f4f513deaf`.
Non-debug `build/android-uwb-release/collie.apk`: **6,816,706 bytes**
(6.817 MB /6.501 MiB), SHA-256
`5c8c98f1079b2d579655cedaa1462d7855a26bf6f9a24d79ab93994bc203f9fb`.
Packaging verifies RANGING/USE_BIOMETRIC, optional UWB hardware, protected VPN
metadata and exclusion of HardwareUwbChecks and all debug fixtures from non-debug.

On those installed debug bytes, **150 SDK/regression assertions passed**:
42 UWB baseline,36 enrolled biometric,15 unenrolled biometric,24 Input and33
NFC/OMAPI. The UWB baseline includes independent real SDK capabilities and
manager identities, actual radio-off/on callbacks, first-use Collie consent,
actual Android Nearby denial/approval, opened/closed callbacks, eight-observer
capacity/release, foreign-workspace rejection, controlled blocked callback and
cleanup queues, fractional SDK Parcelable transport and live UI revocation.
It records ranging_io_verified=false separately from the peer suite.

The strict peer suite separately records actual two-emulator measurement I/O
and dynamic peer started/stopped callbacks, while retaining its failing
**effective_interval_reconfiguration** gate. Its partial passes are not added
to the150 baseline/regression assertions or described as a passing suite.
Reports preserve original conversations, runtime grants/user flags, radio state
and temporary fixture ownership and guard the installed APK before/after.
Physical/position-oracle evidence remains false.

Native/interpreter pure UWB records, shared hardware codec/registry,4 complete
reference checks (52,386 detailed bytes/8,548 index bytes),13 lazy-permission
groups covering16 first-use gates, and9 shared-core groups also passed. CI now
runs the portable UWB record test in native and interpreter modes. Earlier
Bluetooth, editor/UI and other artifact evidence remains under its own digests.
The complete hardware goal, older UWB binding and separate HID failure stay open.


## Persisted document folders

`document_pick(ticket, writable)` uses Android's actual folder picker, after the
conversation's separate `documents` first-use grant. `writable` is0 or1. Each
selection uses a new1..64-character ticket (letters/digits/dot/underscore/hyphen).
Tickets preserve their selected or cancelled result, so replay after a VM
checkpoint cannot open a second picker. At most16 tickets may be saved per
conversation and128 per app; explicitly forget unused selections/cancellations. Use `document_trees(offset,limit1..16)`
to list this workspace's durable selections and actual Android read/write flags.
`document_forget(grant)` removes that selection, closes its live resources and
releases only OS grant bits unused by another saved selection. The picker owns
which locations may be approved: Android11+ restricts volume roots, the Download
root and Android/data/obb. No broad storage permission is declared.

`document_tree_open(grant)` returns an owned tree handle. The initial document
token is `root`. `document_info(tree,token)` and
`document_children(tree,token,offset,limit1..16)` query the actual provider.
Metadata includes name, MIME type, provider flags and nullable size/modified time;
pages include documents/next/total/loading. Tokens are issued only for documents
returned by that provider and belong to one live tree; no host path or raw URI is
accepted. Eight trees may be open app-wide, with1024 known tokens per tree.
Close/reopen a tree for a fresh traversal. Only the selected grant IDs survive a
process restart; live handles and document tokens must be reopened/enumerated.

`document_create(tree,parent,name,mime)` creates an actual provider document;
use `vnd.android.document/directory` for a folder. `document_rename`,
`document_delete`, `document_copy`, `document_move` and `document_remove` use the
provider's operations within the selected tree. Remove detaches a parent link;
delete removes the document. Provider support/flags and access rules still apply.
The selected root cannot be renamed/deleted/copied/moved/removed. Successful
mutations invalidate old non-root tokens and close streams; enumerate again.
A timed-out mutation can have uncertain completion and is never replayed.

`document_file_open(tree,token,mode)` opens SDK modes r/w/wt/wa/rw/rwt; w truncation
is provider-dependent, wt/rwt request truncation. Use bounded `device_read/write`
(max32768 bytes), actual partial write counts, `document_seek(file,absolute)` and
`device_close`. EOF is db_null; nonseekable streams report unsupported_operation.
`document_types` queries up to64 advertised conversion types and
`document_typed_open` opens a read-only converted/virtual stream. Typed reads
respect the SDK asset's offset and declared length. Read-only selections reject
all mutations and writable opens even if another selection gave this app broader
OS permission for the same URI. Every operation checks the actual persisted OS
grant; closing a tree or revoking the conversation grant closes children.

The Java adapter owns only SDK URIs, cursors, descriptors, OS grants and their
lifecycle. The common permission schema, operation registry, sole-tool wrappers
and API reference remain Flexscript. Actual Android16 headless integration passed29 checks on the artifact below.
The real system picker (including Android's root restriction), first-use Collie
approval, completed-ticket replay and picker cancellation were exercised through
actual Activity results. Independent ContentResolver queries matched provider
metadata and verified every byte of the VM-written32791-byte file. Tests cover
32768-byte frames, short reads/EOF, seek, read-only stream and selection rules,
foreign-workspace denial, rename/delete/folders, eight-tree capacity and cleanup.

A real provider typed stream passed ordinary-file I/O. A separately labeled,
SDK-constructed asset slice over that same provider file verified a17-byte offset,
257-byte declared length and exact EOF; it is not evidence of actual virtual-file
conversion. Two independently approved conversations shared one actual URI grant.
Forgetting one preserved the other; forgetting the last writable selection
released Android's write bit while retaining the remaining read-only selection.
Actual process death invalidated handles and a persisted selection reopened.
Changing Documents to Deny on the real UI thread cancelled a VM observed waiting
in hardware I/O, closed its tree and blocked reopening. Independently releasing
Android's persisted URI grant closed existing access and blocked the durable ID.
The test restored original conversations, permissions and preexisting saved
selections and removed only its uniquely owned folder, grants and workspaces.

Provider-dependent copy/move/remove calls are bound but their successful effects
remain unverified. Actual virtual conversion, pipe/disconnect behavior, offline
cloud/removable providers, older Android and physical devices remain open gates.
No successful provider effects were synthesized to replace those checks.

### Document batch artifacts

Debug `build/android-documents/collie.apk`: **6,997,009 bytes**
(6.997MB/6.673MiB), SHA-256
`201e67030508ae73fd403b7b1fda5b3dca67efdd802989e26729745c2c440146`.
Non-debug `build/android-documents-release/collie.apk`: **6,865,858 bytes**
(6.866MB/6.548MiB), SHA-256
`a8387a16a5e5879c16aabf8085efa2d37159da089959f2d153e87e5d580531df`.
Both builds and package checks passed. HardwareDocumentChecks and every other
debug fixture are absent from non-debug. No storage permission was added.
Shared hardware codec/registry,9 shared-core groups,13 native lazy-permission
groups covering17 first-use gates, and4 full reference checks passed. The detailed
reference is55,743 bytes and the function index9,124 bytes, verified through the
actual VM's bounded pages with all capabilities denied.

`documents-android-report.json` records29 passing assertions on the exact installed
debug digest, checked before and after the suite. The prior UWB/HID strict failures
and their distinct artifact evidence remain above; this batch does not turn those
suites or any physical-device requirement into a pass.

References: [Android SAF](https://developer.android.com/guide/topics/providers/document-provider),
[document/folder access restrictions](https://developer.android.com/training/data-storage/shared/documents-files),
[DocumentsContract](https://developer.android.com/reference/android/provider/DocumentsContract).

On the same installed document APK,36 enrolled biometric SDK checks and10
Android lazy-permission groups passed. The settings regression now waits for the
actual persisted policy after Android's posted click callback and requires every
unrelated grant to remain unchanged. These reports retain their installed digest
and restore the original conversation/permissions. Physical biometric success
remains unverified.

The existing8-scenario Android VPN suite also passed on the same document APK,
including actual system consent through the shared Activity-result dispatcher,
foreground TUN establishment, binary UDP response I/O, protected TCP, model-route
selection and SDK/kernel teardown. The report records the same debug digest.

Initial document CI [40029985779](https://github.com/J45k4/flexscript/actions/runs/40029985779)
failed on stale UI fixtures expecting30 permissions. The new schema has31, with
Documents initially Ask. Fixtures for portable/ARM64, full Collie UI, desktop,
browser and older Android permission/worker scripts now expect that actual total.
Locally,6 portable UI groups,10 complete Collie UI groups (Linux/ARM64 agreement),
60 native SDL dummy-driver checks and the actual isolated headless Chromium
suite passed; browser and native permission screenshots were inspected. This
fixture-only follow-up does not change the APK bytes or reuse the UI failure as
evidence about physical hardware. CI's mapped X11 check remains a separate gate.


## Camera2, retained frames and recording

Twenty-five ordinary Flexscript functions expose the public Camera2 SDK. The
existing Camera permission remains a lazy per-conversation Ask/Allow/Deny grant;
the permission schema stays at31 entries. Public device/characteristic inventory
does not require Android CAMERA. Opening a camera or torch asks for that runtime
grant and requires a visible Collie Activity. Audio recording separately requires
Collie Microphone and Android RECORD_AUDIO. The human take-photo attachment
action has its own Android consent and never enables the agent Camera grant.
No new model tool, arbitrary host method, broad filesystem grant or Android
framework dependency is introduced.

`camera_list/info/keys/value/formats/output_sizes` page actual SDK metadata.
Request/result values preserve signed integer64 and binary floating-point bits;
explicit typed codecs cover primitive/array, rational, rectangle/size/range,
metering, color transform/RGGB/tonemap and user-supplied geotag values. Lens
shading gains are paged. Unimplemented SDK value classes are identified as
`unsupported_sdk_type`, a software coverage gap rather than hardware absence.
Physical output selection uses Android9+ public APIs; per-physical request-key
overrides remain unimplemented. No camera geometry is silently substituted.

`camera_open(id,timeout_ms)` returns an owned pending handle. Wait for the actual
`opened` callback, configure1..3 `camera_output` / `camera_physical_output` records,
and wait for actual `configured` before submitting a capture. Templates1..6,
advertised typed settings and one-shot/repeating requests use the real SDK.
Returned sequence IDs may be zero. `capture_completed` reports its actual SDK
sequence ID, frame number, sensor timestamp and retained result ID. Up to16
submitted sequences may await actual terminal callbacks and8 result snapshots
are retained. Metadata is available through `camera_result_keys/value`.

SDK images and ByteBuffers stay outside VM memory. Each output retains at most2
frames and each camera at most6; eviction invalidates old opaque IDs. The128MiB
image budget includes pending SDK close. `camera_frame_info` exposes actual
format/dimensions/crop/timestamp and per-plane byte length, row stride and pixel
stride. Read all bytes through `camera_frame_read` pages of at most32768 bytes;
`next=-1` ends a plane. Padding/strides are significant. JPEG bytes are encoded;
YUV/RAW/depth follow the actual SDK format. PRIVATE surfaces have no CPU planes
and are rejected by the frame reader; recording uses its own SDK surface.
Reconfiguration, close or permission revocation invalidates frame/result IDs.

Capture/torch ownership is bounded to4 camera IDs, including cleanup; availability
and torch observation has8 leases. SDK stop/close/unregister work runs off the UI
thread, with separate bounded image cleanup workers. Elapsed-time startup guards
reject expired opens/configuration even while the callback queue is blocked.
`camera_shutdown` preserves state/events so callers can wait for actual
`sdk_terminal` and `lease_released`; `device_close` invalidates immediately. A late
SDK callback cannot reopen a closed or expired resource. Camera resources close
when the Activity is hidden or the relevant conversation permission is revoked.
No live SDK resource survives VM snapshots or process death.

`camera_video_start` records silent MPEG4; `camera_video_audio_start` also records
microphone audio. Options select an advertised recorder size,1..120fps,64k..50M
bitrate,500..120000ms,65536..67108864 bytes, and default/H264/HEVC/Android14+ AV1.
Unsupported combinations fail in the actual SDK. Pause/resume and asynchronous
stop use MediaRecorder; only a successfully finalized `stopped` resource is
readable with `device_read` / `camera_video_seek`. SDK duration/size notifications
alone are not proof of a finalized container. A private SDK-owned temporary spool
has no guest-selected host path. Two recording/spool slots include finalized
bytes and pending cleanup; close the video handle to delete its spool and release
the slot. Persist larger output through an approved document stream. Before the
first recorder in a new process, recovery deletes only this adapter's interrupted
private spool names. Actual crash/recovery and automatic limit tests remain open.

`camera_torch_open` uses real public mode/strength APIs and rejects absent flash
or unsupported/out-of-range strength. Its observer distinguishes global SDK
mode/unavailability from physical LED evidence. If a confirmed-on torch is lost,
closing that old owner does not turn off a replacement request.

Java owns CameraManager/CameraDevice/session/readers/planes/recorder objects,
explicit SDK value codecs, callbacks and lifecycle. Operation schema, typed RPC,
permission policy, guest functions and complete paged API reference stay in
Flexscript. No UI or worker scheduling logic moved into the adapter.

### Camera verification and remaining gates

The owned Android16 headless emulator delivered real JPEG and YUV420 frames.
An independent JPEG decoder verified actual dimensions, and SDK buffer lengths
and per-page Adler32 checks verified every YUV byte and stride, including a plane
larger than32768 bytes. The exact manual-template result confirmed requested ISO,
exposure and disabled auto-exposure, correlated by its SDK sequence ID. This is
emulator sensor evidence, not an independent physical exposure measurement.

Actual silent and microphone recordings passed independent MediaExtractor
dimensions/track/sample checks. Every finalized container byte crossed the VM and
matched independent whole-file length/Adler32; EOF, seek bounds, read-only access
and actual private-spool deletion were checked. Tests use the real Android camera
and microphone dialogs and the real system take-photo app, not synthesized
success callbacks or photo Activity results. Tests preserve original conversations
and OS permission choices and remove only uniquely owned workspaces/artifacts.

Delayed callback/deadline queues, UI-thread close, actual terminal lease release,
sixteen submitted requests, observer capacity, workspace isolation and revocation
of a VM observed waiting in camera I/O are covered. The original whole-plane
checksum fixture exhausted the production VM instruction budget; it was changed
to verify every bounded page in separate programs, without increasing that budget.

Still open: per-physical setting overrides, further public SDK metadata codecs,
actual RAW/depth capture and combinations, logical/multi-camera output, physical
focus/exposure/flash/torch-strength oracles, front/rear/vendor/older Android
coverage, disconnect/hotplug and resource-pressure fixtures, background/process
death and interrupted-spool recovery, retained-spool capacity, automatic duration/
size limits and codec/rate combinations. An advertised capability or accepted
request does not close any of those gates. The full inventory above and the
separate strict UWB interval/HID virtual-cable-unplug failures remain open.


### Camera batch artifacts

Debug `build/android-camera/collie.apk`: **7,095,313 bytes**
(7.095MB/6.767MiB), SHA-256
`0a16e460ad9aaeacc31fd8dc1ec2eaa059b7fd9490cb57d4a367c01c19c0e2c1`.
Non-debug `build/android-camera-release/collie.apk`: **6,931,394 bytes**
(6.931MB/6.61MiB), SHA-256
`b314d4f61b6b408a79d3192c5f7298ef1c3b623d576d666ca0eae55f06d4222d`.
Both builds and packaging passed. Camera features remain optional; CAMERA is
declared for lazy runtime consent. HardwareCameraChecks and all other debug
fixtures are absent from non-debug. Native engine/generated Flexscript bytes
match between both outputs.

`camera-android-report.json` records **55 passing checks** on that exact
installed debug digest; `camera-manual-android-report.json` records **4** actual
manual-photo checks on the same digest. Both guard installed bytes before/after
and restore original conversation/permission choices. The camera report records
`manual_sensor_verified=true`, `physical_devices_verified=false`.

Shared32KiB hardware codec/registry,9 core groups,14 native lazy-permission
groups covering18 first-use gates and4 complete API-reference checks passed.
The full reference is62,680 bytes and the index10,219 bytes; every
reference byte crosses actual bounded VM pages with every grant denied. The
additional audio-video probe verifies Camera then Microphone checkpoint/denial.
No camera-specific permission schema entry or UI count changed.

On the same camera APK,10 Android lazy-permission groups and8 VPN scenarios
passed, including the actual shared system-consent dispatcher, foreground TUN
and binary kernel packet response. Those suites restored original conversation/
permission choices and removed their temporary VPN authorization. No phone was
deployed. Compiler/application CI for this batch is recorded in the PR.


## NFC host card emulation and NFC-F

Eleven ordinary Flexscript functions bind Android's public emulation SDK:
`hce_info`, `hce_open`, `hcef_open`, `hce_request`, `hce_reply`, `hce_unhandled`
and `hce_shutdown`, plus `hce_request_read` and staged `hce_reply_begin/write/commit`.
They use the existing lazy NFC grant and sole VM tool; no
permission schema entry, raw host method or model tool is added. Java owns the
Android service/manager/Binder objects, copied command buffers and lifecycle.
AID/packet protocols and response policy remain Flexscript code.

`hce_info()` reports independent device/adapter support for ISO-DEP and NFC-F,
actual radio/foreground state, interrupted-component recovery and OS category
selection/default policy. `hce_open(category,aids,reply_timeout_ms)` chooses
category0 other or1 payment and1..32 distinct5..16-byte hexadecimal AIDs. The
SDK controls optional prefix*/subset# support. Separate service metadata preserves
Android's actual payment/non-payment routing policy; no default wallet is silently
changed. `hcef_open(system_code,nfcid2,reply_timeout_ms)` accepts system codes
4000..4FFF excluding4*FF, and a16-digit hexadecimal NFCID2 beginning02FE. Android
may reject unsupported identity/routing choices or NFC settings.

Open returns an owned registering handle. Startup has a10-second elapsed guard;
wait for the actual SDK registration/preference `ready` or `error` event. The
newly enabled component and NFC's package scan are asynchronous, so the same
owned registration can retry idempotently for at most3 seconds before reporting
routing denial. Registration acceptance and foreground preference are distinct
from a reader exchange. Android's category conflicts and unlock rules still apply.
Both ISO-DEP services require device unlock in compiled metadata. All three
services are disabled by default and protected by BIND_NFC_SERVICE. NFC-F has
no static system code or NFCID2.

Reader mode and all three emulation modes share one exclusive Collie lease.
Emulation requires a resumed Activity. Activity-scoped foreground selection and
removal serialize with pause, including NFC-F's requirement that disableService
receive a still-resumed Activity. Route/component removal uses a bounded SDK
worker. Leaving the Activity, radio loss or NFC revocation invalidates commands
and closes resources. Only owned components/routes are modified. Startup and
service-created recovery remove interrupted queryable registrations and reset all
private components to their disabled defaults; live handles never survive process
death. A failure for one component does not prevent disabling the others.

A `command` event carries `request={id,data,deadline_elapsed_ms,reply_queued}`.
Commands are copied raw APDUs4..65544 bytes, or complete NFC-F packets2..255
bytes including their leading length. `request.bytes` is the actual total; `data`
is inline up to32768 bytes and null above that. `hce_request_read` pages the whole
command with at most32768 bytes per frame, exact EOF and no reissued reader request. The SDK callback never runs guest code or
waits for a model response. `hce_request(session)` retrieves the currently pending
command if its event was missed. Only one command is pending; a later command
supersedes the earlier token. Events use the shared128-entry bounded queue.
Use a running Flexscript loop for protocol responses; a model round trip can
exceed the selected20..5000ms command deadline.

`hce_reply(session,request_id,blob)` queues an APDU response of2..32768 bytes
(including guest-chosen status bytes), or an NFC-F packet2..255 bytes with its
exact leading length. `reply_submitted` means the public SDK send call returned,
not that a reader received it. For a full extended response, use
`hce_reply_begin(session,id,total2..65538)`, contiguous nonempty
`hce_reply_write(session,id,offset,blob_max32768)` chunks and `hce_reply_commit`.
Repeated begin/chunks and early commit fail rather than resetting/replaying data.
Request metadata exposes `response_bytes/response_written`. Commit uses the same
deadline-bound token; incomplete buffers expire with their request.
NFC-F remains bounded to255 bytes. Tokens are workspace/session-owned and single-use;
reply, supersession, expiry, deactivation, close or revocation removes their timer
and retained payload. Elapsed guards also apply while the timer queue is blocked.
`hce_unhandled` invokes ISO-DEP's public notifyUnhandled; NFC-F has no equivalent
public method. APDU expiry notifies Android unhandled, while NFC-F expiry invents
no response packet. No owner returns an ISO-DEP6F00 error or no NFC-F response.

`hce_shutdown` requests cleanup while preserving info/events. `device_info`
separates `sdk_cleanup_returned`, `channel_active`, `lease_released` and
`cleanup_error`. An actual SDK channel retains its lease after local cleanup until
its deactivation or service destruction. `device_close` invalidates immediately.
Late replies cannot cross a command/owner boundary. An uncertain cleanup result
quarantines the lease rather than reporting successful release.

### HCE verification scope

The owned Android16 emulator has no NFC adapter. Its actual feature/adapter
queries, unsupported result, malformed-input rejection and real first-use
Ask/Allow/Deny flow were verified through the VM. No adapter support or successful
radio/registration callback was synthesized.

The separate SDK transport fixture constructs an unregistered Session and command
bytes, binds the actual production service components and drives their real
framework Messenger dispatch. A debug-only, non-exported peer runs in its own
Android process so replies cross actual Binder serialization. This independently
verifies every65544-byte extended APDU/261-byte payment APDU/255-byte NFC-F
command, exact command-page bounds/EOF and every65538-byte staged extended
response byte, foreign-workspace denial, malformed replies, duplicate/
superseded/deactivated tokens, deadline cancellation, expiry with the actual timer
queue blocked, notifyUnhandled and cleanup waiting for SDK deactivation. It does
not set the production adapter's supported flag or claim successful routing.

Actual Activity backgrounding closes a constructed live fixture. Changing NFC to
Deny on the real UI thread cancels a VM observed waiting in fixture I/O. A separate
constructed live handle/component fixture is killed by actual process death;
startup restores all three default-disabled component states and the old handle
is stale. Original conversations/permissions are restored and only uniquely
owned workspaces are removed.

An initial same-process peer caused Android's framework to enqueue an already-used
Message while forwarding a reply; the fixture now uses a separate process, as
NfcService does. Another initial NFC-F stale-token test supplied an invalid packet
length and was corrected to use a valid response. Neither failed exploratory run
is counted as RF or registration evidence. The final report explicitly records
`constructed_sdk_fixture=true`, `routing_registration_verified=false`,
`radio_exchange_verified=false` and `physical_devices_verified=false`.

Still open: successful actual AID/system-code/NFCID2 registration and foreground
selection on a supported device, independent reader APDU/NFC-F exchanges, real
link loss/selection conflicts, payment/default-wallet policy and locked-device
behavior, service-cache timing and radio-off recovery, persisted dynamic-route
cleanup across process death, older/vendor devices, background emulation and
public polling/observe-mode extensions. Constructed Binder traffic closes none of
these radio/policy requirements. The complete hardware inventory and separate
strict UWB interval/HID virtual-cable-unplug failures remain open.

References: [Android HCE overview](https://developer.android.com/develop/connectivity/nfc/hce),
[HostApduService](https://developer.android.com/reference/android/nfc/cardemulation/HostApduService),
[HostNfcFService](https://developer.android.com/reference/android/nfc/cardemulation/HostNfcFService),
[NfcFCardEmulation](https://developer.android.com/reference/android/nfc/cardemulation/NfcFCardEmulation).

### HCE batch artifacts

Debug `build/android-hce/collie.apk`: **7,148,760 bytes**
(7.149MB/6.818MiB), SHA-256
`11e2b756958f328527900dd45f6ad56e05372e47ac25bb2db687267a85db885e`.
Non-debug `build/android-hce-release/collie.apk`: **6,964,361 bytes**
(6.964MB/6.642MiB), SHA-256
`1ae4bcb487c0dc5151616b114922197085e9315a5b616df95b96cf1779ae9648`.
Both builds and package checks passed. Optional HCE/HCE-F features, protected
default-disabled services, required ISO-DEP unlock metadata and absent static
NFC-F identities are checked in the compiled APK. HardwareHceChecks, its peer
service and every other debug fixture are absent from non-debug. Native engine/
generated Flexscript bytes match between outputs.

`hce-android-report.json` records62 passing assertions on the exact installed
debug digest, with APK guards before/after, original-state restoration and the
constructed/radio scope flags above. Shared32KiB codec/registry,9 core groups,
15 native lazy-permission groups covering18 first-use capabilities and4 complete
API-reference checks also passed. The full reference is66,493 bytes and the
index10,591; every byte is verified through bounded VM pages with all
capabilities denied, including the reference now extending beyond one64KiB frame.
No permission count/UI schema changed. Compiler/application CI is recorded in
the PR separately from all hardware/radio gates.

On that same final debug digest,55 Camera2/video checks,4 real system take-photo
checks,33 NFC/NDEF/OMAPI checks,10 Android lazy-permission groups and8 VPN
scenarios passed. This covers the added Activity pause/recovery hooks against
actual camera/microphone and shared system-consent behavior. Every report guards
the installed APK and restores original conversation/permission choices. NFC and
OMAPI radio/applet flags remain unverified as in their original suites.

Initial HCE compiler/application CI
[40044700977](https://github.com/J45k4/flexscript/actions/runs/40044700977) passed
for `7b4a8d2fbdb54dca49397677c08ff29d523dd696`. A verification follow-up strengthens
the two older Android permission/VPN scripts: they previously recorded only the
local APK digest, and now verify installed bytes before/after, like HCE/camera/NFC.
Both scripts rejected an actually mismatched older camera APK before creating
any workspace, then passed10 permission groups and8 VPN scenarios with the
unchanged final HCE APK above. `artifact-guards-report.json` records those4
positive/negative guard checks. This changes no APK bytes or hardware scope;
the strict RF/physical/UWB/HID gates remain open.
