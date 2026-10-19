# Secure Connections OOB integration work

T487 remains open. An unfinished prototype in `lib/net/smp-sc-oob.flex`
implements ticket ownership, the attestation callback boundary and directional
phase-two exchange. The following records its intended complete contract.
Pool lifetime integration, fresh evidence challenge binding (T491), an actual
trusted transport and physical pairing remain unverified or unfinished.
Registered-secret-storage support is implemented under T488. Further firmware
feature expansion is deferred while compiler/backend work is the focus.

The Core OOB protocol must use the same local public key in the transferred
commitment and the in-band exchange. A separate pool is required because the
feature engine clears its reserved crypto region when starting an attempt.
See the [Core OOB and f6 rules](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host/security-manager-specification.html).

## Pool and ticket layout

Plan allocation-free storage of `1024 + 256 * tickets`, tickets1..4. Register
the complete span with `sd_sensitive_register` before opening any session;
also reject overlaps with both crypto provider contexts. The pool must remain
reserved until explicit, quiescent release. All faults must erase the pool
immediately, including faults during entropy or attestation callbacks.

Each256-byte ticket contains: id0, state8, expires16, bound connection24,
role32, incoming witness40, outgoing witness48, connection-floor cutoff56,
local wire address64 (7), canonical peer identity72 (7), private scalar80 (32),
public X/Y112 (64), local r176 (16), local commitment192 (16), peer r208 (16),
peer commitment224 (16), reserved240 (16). Ticket IDs and accepted witness IDs
are increasing and never reused during the host lifetime. Wiping a ticket
retains those global floors. States:1 key prepared,2 random/commitment ready,
3 bound before feature exchange,4 consumed/nonsecret lifetime metadata only.

After the tickets, reserve896 shared bytes: descriptor128, backup128,
copied record32, copied evidence96, crypto staging512. Descriptor words are
ticket id, operation(1 receive/2 sent), local-address pointer, peer-identity
pointer, record pointer, evidence pointer, evidence size, now and expiry.
The target binding temporarily fills user argument at offset72 and restores
it before return. Copied local address and peer identity occupy80 and88;
remaining bytes are zero. Compare the descriptor against its private backup
and staged record/evidence against the quiescent originals after the callback.

## Pre-connection APIs

Plan `sc_oob_init(work, capacity, tickets)`, `sc_oob_new(local, peerIdentity,
expires, now)`, `sc_oob_generate(id, now)`, `sc_oob_export(id, out32, capacity,
now)`, `sc_oob_receive(id, record32, evidence, size, now)`, `sc_oob_sent(id,
evidence, size, now)`, `sc_oob_bind(id, token, now)`, `sc_oob_drop(id, now)`
and `sc_oob_deinit()`. Exported32 bytes are local r followed by its f4
commitment. A copy alone does not attest delivery. Incoming and successful
outgoing delivery must pass an explicitly configured trusted-channel callback.
It returns a fresh, positive witness ID or a signed error. A boolean supplied
by a caller is not a substitute for that callback. Physical OOB adapters and
their evidence/provisioning remain separate integration requirements.

Create/generate tickets and finish the actual evidence checks before opening
the target connection. Capture `sm_token_floor` after each preparatory action;
binding requires a strictly newer connection token, the exact local address,
and the canonical peer identity supplied by the session owner. This prevents
acquiring OOB data after in-band discovery of that connection. The local OOB
feature flag must exactly match possession of an attested incoming record.
A peer claiming local OOB receipt requires an attested outgoing delivery.
At least one direction is required. A bound OOB attempt must not silently
downgrade to another association model.

The host serializes these APIs through the SC owner. A missing attestor fails
closed. Xtensa uses a configured private-call0 one-argument callback with a
64-bit user argument; callback reentry must return busy. Validate immutable
descriptors, copied evidence, lifetime and exact bindings after return.
Evidence is at most96 bytes; the adapter must independently verify its origin,
secret-channel properties, peer identity, record, ticket, expiry and freshness.
The library only enforces this explicit boundary; it cannot prove NFC or other
physical trust by examining a positive callback result.

## Phase-two integration

For method3, `sc_begin` consumes the bound ticket into the existing session
region instead of generating a different key pair. Retain nonsecret ticket
lifetime metadata; erase its key/r/commitment bytes immediately after handoff.
SC-private960..975 holds local r,976..991 peer r,992..1007 peer commitment,
1008 flags,1016 expiry; header560 can hold the ticket id. Set local r to zero
when the peer OOB flag is zero; peer r is zero when no incoming record exists.

Validate the peer curve/debug/reflection policy and ECDH as before. If an
incoming record exists, verify `f4(peerX, peerX, peerR, 0)` against its attested
commitment before revealing a fresh nonce. There are no in-band commitment
PDUs in OOB mode. A queues Na after the public-key exchange and waits for Nb
(new state18). B acknowledges its public key, waits for Na (state19), derives
keys/checks and queues Nb. A derives after Nb and queues Ea. Thereafter use
the existing Ea/Eb verification and private-candidate completion path.

For local f6, r is the peer's OOB r; for expected peer f6, r is the local OOB r.
Both f5 calls use actual role-ordered wire addresses and nonce values. Never
promote verified security or finish the retry lease until future controller
encryption/bond integration is proven.

SC facade calls must reconcile ticket expiry, timeout, peer failure,
disconnect and phase-one errors before returning effects. Pending ticket
expiry must abort its bound attempt with OOB Not Available, revoke old TX
views/tags and charge an active retry lease once. Idle unadmitted connection
expiry can fail locally without a peer packet or retry penalty. Both consumed
and unconsumed tickets must be erased on end of lifetime. Check expiry before
packet acknowledgments too, so a late Eb acknowledgment cannot publish a key
candidate. `sc_fault` and post-crypto revalidation must erase captured pool
storage even if a callback ended or replaced the binding.

## Required verification

Use independent OpenSSL P-256/CMAC peers for both roles and all three OOB
directions, asymmetric local/peer r values and flags, before-connection export/
receive/sent proofs, stale ticket/witness IDs, peer/address binding, monotonic
time and expiry, modified records/commitments, point/debug/reflection policy,
provider and callback errors/mutation/reentry, exact TX generations, gate
backpressure, all lifetime cleanup and pool capacity. Preserve the existing
420 JW/NC/passkey regressions. Run native and both Xtensa consumers with the
existing stock emulator and record physical trust/radio limitations explicitly.
