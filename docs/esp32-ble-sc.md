# Secure Connections pairing owner

`lib/net/smp-sc.flex` implements the offline Just Works and Numeric Comparison
phase-two exchange in both roles.
[Passkey Entry and keypress APIs](esp32-ble-passkey.md) now extend the same owner. `lib/platform/esp32-smp-sc.flex` connects it
to the existing namespaced Mbed TLS AES and p256-m providers on original ESP32
and ESP32-S3. It uses the feature engine's reserved session storage and adds
no allocations or operating system.

This component ends with a private candidate LTK. Controller encryption,
verified security, retry success, key distribution, persistent bonds and saved
key reconnection remain T484/T139. OOB and legacy exchanges remain T483. Radio activation also requires verified entropy and physical protected
storage/rollback-anchor integration. The test entropy streams and storage ACKs
are explicit boundary peers.

## Attachment and calls

Initialize both crypto providers, including a trusted random callback, then
initialize the feature engine, retry ledger, session owner and durable gate.
Call `sc_init()` before opening connections. It checks provider availability
and disjointness from every owned engine/ledger/gate span. While attached,
serialize host activity through the `sc_*` facade:

- `sc_open`, `sc_pair`, `sc_request_security`, `sc_consent` and `sc_close`
  retain the durable owner's arguments and semantics.
- `sc_input(token, packet, size, nowMs)` handles feature exchange and supported
  crypto PDUs. `-11` retains input for later delivery. Protocol rejection
  normally returns1 and queues Pairing Failed behind the durable barrier;
  provider errors retain their signed value.
- `sc_next_packet`, `sc_packet_sent`, `sc_next_event` and `sc_event_consumed`
  use the existing copied engine packets/events and exact acknowledgments.
- After acknowledging the feature response and consuming its event, call
  `sc_begin(token, featureGeneration, lease, nowMs)`. Consent and storage gates
  must already be satisfied. Legacy association returns `-95`. The unfinished
  [OOB prototype](esp32-ble-oob-design.md) requires a prepared, attested ticket;
  it is not a production pairing path.
- Poll `sc_prompt(token, generation, lease, out32, capacity, nowMs)`. Result1
  copies four words: connection, SC generation, lease and the six-digit value.
  Preserve leading zeroes when displaying it. Zero means no pending prompt.
- Answer with `sc_confirm(token, generation, lease, accepted, nowMs)`.
  Acceptance requires the outstanding response packet to be acknowledged.
  Rejection can revoke that packet. Stale generations or leases return `-116`.
- `sc_tick(nowMs)` enforces the existing30-second attempt deadlines.

The **SC generation** is the feature generation captured at `sc_begin`. It
stays fixed for UI decisions. Every newly queued SC packet receives a separate,
increasing **TX generation**. A packet acknowledgment uses its published TX
tag; it must never substitute the SC generation. An accepted acknowledgment
may immediately queue the next PDU, notably the responder's commitment.

`sc_snapshot(token, out80, capacity, nowMs)` copies ten metadata words:
state, SC generation, lease, prompt flag, numeric value, user acceptance,
planned authentication, verified link security, raw provider error and current
TX generation. It publishes no keys. Verified security remains zero throughout
this component, including after both DH checks pass.

## Protocol and ownership

The owner validates the peer curve point, rejects the Core debug X coordinate
(including either Y sign) and reflected local X, and derives DHKey with a fresh
per-attempt private scalar. Fresh nonce bytes use the guarded entropy callback
without scalar rejection. Both roles follow the
[Core Security Manager exchange](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host/security-manager-specification.html):
the responder commits with f4, the initiator verifies after the nonce exchange,
Numeric Comparison uses g2 and exact user approval, and f5/f6 bind both actual
addresses, IO capabilities and role-ordered nonces before DH-check verification.

All crypto inputs use the existing SMP wire-order convention. The full16-byte
candidate LTK remains private for future CTKD/key-size handling. T484 must apply
the negotiated key-size mask before controller use or persistence. The crypto
completion state10 does not release the retry lease as a successful pairing.

Private scalar, public keys, DHKey, nonces, MacKey and intermediate checks are
erased when no longer needed. Completion retains only the private LTK and
metadata. Failure, timeout and disconnect erase the entire reserved region.
Durable-owner faults synchronously erase that region in every configured slot,
including inactive ones, before returning. Crypto/entropy calls revalidate the
session lifetime before publishing; callback-driven cancellation cannot revive
keys. Busy reentry rejects with `-16`.

## Verification

`tests/esp32/smp-sc-vectors.py` constructs independent peer transcripts with
Python cryptography/OpenSSL P-256 and CMAC. `smp-sc-reference.py` captures the
source closure, runs the native consumer, links the real pinned target crypto
objects and executes bounded firmware batches on stock QEMU for both chips.
It records exact source/tool/provider hashes and ELF/image/UART hashes.
`smp-sc-controls.py` proves the corpus detects isolated protocol and cleanup
defects. Current counts and artifacts are in
`build/esp32-backend-smp-sc/report.json`.

Coverage includes both roles/association methods, independently derived LTKs
and wire packets, numeric rejection and stale decisions, old/future TX tags,
debug/reflected/invalid points, bad commitments and DH checks, terminal cleanup,
two live sessions, every AES derivation failure position, transient curve errors
and cancellation from entropy callbacks. These are software checks; no physical
radio pairing, entropy quality, controller encryption or flash power-cut claim
is made.
