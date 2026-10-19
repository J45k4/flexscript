# Secure Connections passkey entry

`lib/net/smp-sc-passkey.flex` extends the serialized SC owner with passkey
input/display, all20 authentication rounds and negotiated keypress
notifications on original ESP32 and ESP32-S3. Follow the
[SC attachment and generation rules](esp32-ble-sc.md) before using these APIs.
The feature exchange must select SC Passkey Entry (method1). Each public UI
call requires the connection, fixed SC generation and exact live retry lease.

## UI flow

After the public-key exchange and the responder's public-key acknowledgment,
the owner enters state12. `sc_passkey_prompt(token, generation, lease, out40,
capacity, nowMs)` copies five words when a prompt is available:
connection, SC generation, lease, action and value. Action1 requests input;
its value field is zero. Action2 displays the freshly generated passkey.
Render display values with six digits, including leading zeroes.

For input, call `sc_passkey_enter(token, generation, lease, value, nowMs)` with
an integer0..999999. With negotiated keypress support, first report entry
activity through `sc_keypress` and acknowledge each queued notification,
including Entry Completed. The entry API returns `-11` while a packet is
outstanding or the required completion notification has not been generated.
A transient nonce failure permits retry with the same passkey; a changed
value is rejected once the attempt has captured it.

For display, call `sc_passkey_generate(token, generation, lease, nowMs)` once,
copy and display the prompt, then call `sc_passkey_start(token, generation,
lease, nowMs)`. Generation requests32 fresh entropy bytes and considers ten
independent20-bit candidates. It accepts the first candidate below1000000;
an all-rejected draw returns `-11` without publishing a passkey. This avoids
modulo bias and has no fixed-passkey fallback. Starting before generation or
regenerating an already captured passkey returns `-116`.

`sc_passkey_cancel(token, generation, lease, nowMs)` revokes outstanding output
and erases the attempt. It queues Pairing Failed with Passkey Entry Failed
reason1 behind the durable checkpoint gate. Cancellation remains possible
while a checkpoint is pending; affirmative input/display start remains gated.

These calls do not add asynchronous callbacks or borrowed secret views.
The ordinary `sc_snapshot` and Numeric Comparison prompt never expose the
passkey. Only the explicit display prompt copies it. Keep that copy within
the trusted UI and discard it when pairing ends.

## Keypress events

When both exchanged AuthReq fields enable keypress support, the input side
reports actual UI events with `sc_keypress(token, generation, lease, kind,
nowMs)`. Kinds0..4 mean started, digit entered, digit erased, cleared and
completed. Start before editing; count up to six digits, permit erasure and
clear, and complete after one to six entered digits. Short entries are
equivalent to leading-zero padding. The library validates local event order
and queues each event with its own nonreused TX generation. Acknowledging it
restores the waiting UI state. It never starts commitment rounds by itself.

Received negotiated events produce copied metadata through
`sc_keypress_peer(token, generation, lease, out24, capacity, nowMs)`:
event serial, last kind and current digit count. Peer metadata tolerates missed
start/edit events and never authorizes authentication. Valid incoming events
refresh the30-second SMP deadline. Reserved types fail with reason10;
unnegotiated notifications are ignored. Local notification APIs return `-95`
when the selected method/action or negotiated support does not permit them.

## Authentication and cleanup

Both roles commit to each passkey bit, least significant first, using
`f4(ownX, peerX, freshNonce, 0x80 | bit)`. Each round sends initiator commitment,
responder commitment, initiator nonce and responder nonce in order. Both
verify the peer commitment before advancing. A bad round aborts immediately,
so no later bit is disclosed. Nonces are newly drawn each round. After round20,
f5 uses those final nonces, and both f6 DH checks bind the128-bit padded passkey,
the exchanged IO data and actual connection addresses. These rules follow the
[Core Security Manager Passkey Entry protocol](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host/security-manager-specification.html).

The responder advances only after its nonce packet is acknowledged. Transient crypto
errors cannot consume retained input or publish a partial commitment. Entropy
and crypto boundaries revalidate the exact session lifetime before committing
effects. All passkey/nonces/intermediate storage is erased on failure,
timeout, disconnect and durable-owner fault; successful crypto completion
retains only the private candidate LTK and nonsecret session metadata.

Crypto completion still leaves verified link security zero and does not mark
the retry lease successful. Controller encryption, key-size handling, bonds
and saved-key reconnection remain T484. OOB and legacy authentication remain
T483. Production entropy quality and physical protected-storage/radio evidence
remain required before activating full pairing.

## Verification

`tests/esp32/smp-passkey-vectors.py` generates independent OpenSSL P-256/CMAC
wire peers and includes the preceding192 JW/NC regressions. Its228 passkey
scenarios cover both roles, input/display, notification negotiation, passkeys
0/1/123456/999999, a bad commitment in each of20 rounds, fresh nonce retries,
all AES failure positions in commitment preparation, peer verification and
final derivation, cancellation, stale input, biased-draw rejection, notification
types and deadlines, and cancellation from entropy callbacks.

`tests/esp32/smp-sc-reference.py --vectors-script smp-passkey-vectors.py`
captures the complete source closure and runs native and real Xtensa crypto
on stock QEMU. All420 scenarios/67654 checks pass per native/original/S3 target
in138 positive firmware boots. `smp-sc-controls.py --passkey` detects36
protocol/cleanup defects, including17 specific passkey defects. Current hashes
and exact firmware rebuild evidence are recorded in
`build/esp32-backend-smp-passkey/report.json`. These software checks do not
claim physical pairing, physical entropy or persistent bonds.
