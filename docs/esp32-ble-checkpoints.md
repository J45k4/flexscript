# BLE checkpoint barriers

`lib/net/smp-durable.flex` prevents pairing effects from escaping before their
retry state is durably acknowledged. It owns no media, authentication key or
rollback anchor. Authenticated framing and exact frozen-payload readback are
implemented in `smp-checkpoint.flex` and `smp-checkpoint-pending.flex` (T471/T474).
The live commit and restart owners now implement that software protocol
(T475/T476). T472 still requires physical media/anchor integration, provisioning
and physical power-cut verification under T463/T139. The original barrier tests
inject successful storage ACKs as boundary events, with no claim of flash durability or restart rollback proof.

Initialize the retry ledger, restore authenticated state (or explicitly provision
an empty store), then initialize the session owner and call
`sd_init(work, capacity, sequence)`
before opening any connections. Supply the verified stored sequence, or zero
for explicit initial provisioning. Workspace is `sd_size(entries)` bytes:
128+112 per configured ledger entry, aligned to8. It must be disjoint from
the owner and both engines. Attachment starts with an uncommitted revision so
restored/interrupted attempts are checkpointed before new protocol effects.

While attached, serialize calls in one host task and use `sd_open`, `sd_pair`,
`sd_request_security`, `sd_input`, `sd_consent`, `sd_packet_sent`,
`sd_event_consumed`, `sd_next_packet`, `sd_next_event`, `sd_phase2`, `sd_failure`,
`sd_close`, `sd_tick` and `sd_inherit`. Their session arguments match the
corresponding `so_*` functions. Resolve private addresses against the immutable
view first, then pass the copied admission key to `sd_open`; calling the raw
owner or `sp_open` while attached bypasses this layer and is unsupported.

Packets, events, affirmative consent and crypto handoffs return -11 until their
identity's mutation revision is committed. Received known SMP input for an
uncommitted live attempt is retained under backpressure. Pairing Failed,
rejected consent and disconnect can still cancel an attempt. New starting PDUs
are copied into the private feature engine, with their queued outputs/events
held behind the barrier. Neither snapshots nor feature completion authenticate
a connection. The existing `sm_packet*` and `sm_event*` globals expose only the
views issued by the gated polling functions.

Attachment captures the owned feature-engine address and link count. A terminal
`sd_fault` revokes views and immediately erases every slot's reserved1024-byte
crypto region, including inactive slots. Binding changes fault against the
captured engine rather than wiping an unrelated replacement. Its memory must
remain reserved until normal gate deinitialization. T485's directed checks
inspect this erasure before invoking any SC poll, which could otherwise mask a
delayed wipe.

`sd_sensitive_register(work, size)` reserves one additional aligned caller-owned
secret area before connections open. Size is8..65536 bytes; it must be disjoint
from every engine, owner and gate span. Registration clears it, excludes it
from all external SD buffers, and adds it to synchronous fault erasure. Release
with `sd_sensitive_release(work)` only after connections close and a pending
checkpoint finishes; release erases the area and removes its registration.
Gate deinitialization refuses an outstanding registration. Keep faulted gate
storage reserved for its terminal lifetime; these APIs do not bypass its error
latch. This mechanism is the OOB ticket-storage prerequisite under T488;
OOB pool/protocol integration remains T487. The directed consumer checks the
full64 KiB extent and its guards on native and both chips without a later poll.

Call `sd_tick(nowMs)` regularly. Failure, timeout, disconnect and history
inheritance create new revisions. Elapsed milliseconds alone do not schedule
new writes. Revisions are tracked per identity:an already committed peer can
progress while another identity's write is pending. ACKs for previously issued
packets remain valid when a later history update needs another checkpoint.

`sd_checkpoint(nowMs)` returns1 after freezing a copied ledger payload,0 when
unchanged, or -16 if a previous payload remains leased to storage. Later
mutations cannot change that frozen payload. `sd_checkpoint_peek()` exposes
`sd_checkpoint_buffer`, `sd_checkpoint_bytes`, `sd_checkpoint_revision` and
`sd_checkpoint_sequence`. The writer must retain the exact tuple and bytes.

After the writer verifies exact media readback/authentication and durably
advances the trusted rollback anchor, call
`sd_done(sequence, revision, 0, nowMs)`. Only that frozen revision becomes
committed; newer mutations still wait for another snapshot. The callback
applies timeouts before releasing anything, so an ACK arriving at the deadline
cannot revive an expired attempt. Wrong/stale tuples return -116 unchanged.
Positive status values are invalid; a byte count is not a success ACK.

Any accepted negative status is a terminal storage failure. The writer must
stop using the leased buffer before calling `sd_done`, including on errors.
The gate then revokes published packet/event views, wipes the relinquished
checkpoint and blocks further operations. Sequence/revision exhaustion and
owner/ledger faults also stop protocol effects. Recover through a verified
storage reload and fresh owner lifetime; never reinterpret an uncertain write
as success. The boot recovery owner below handles authenticated candidate
selection; physical providers and recovery verification remain under T472.

`sd_snapshot(token, out, capacity)` copies272 bytes:the ordinary owner metadata,
then required revision at256 and committed revision at264. This is debug
metadata and does not authorize transport or crypto. `sd_deinit()` requires no
open sessions, pending write or uncommitted state. It wipes its workspace while
retaining nonreused revision/sequence floors for the current host lifetime.
Those RAM floors do not provide a trusted restart rollback anchor.

`tests/esp32/smp-durable-reference.py` takes explicit `--compiler`, `--qemu`,
`--prefix`, `--s3-prefix` and a fresh `--work`. Its independent owner/ledger and
storage-ACK peer covers93 scenarios/2175 observations per native/original/S3
target. Thirty-one isolated barrier, ordering, stale-ACK, timeout, ownership and
view-revocation defects are detected. A separate maximum-capacity consumer
checks all four sessions/32 ledger entries with103 checks per target, using the
existing reserved SDK arena and verifying complete arena reclamation. No memory
profile or emulator implementation is changed. All eight stock-QEMU boots pass;
37 artifacts rebuild exactly from37 captured sources, including all eight
firmware ELF/image pairs. Evidence:
`build/esp32-backend-smp-durable/report.json`.


## Authenticated frames

`lib/net/smp-checkpoint.flex` provides allocation-free AES-CMAC framing. The
storage AES key is sixteen conventional-order bytes; it is not an SMP scalar
in wire order. The caller supplies a sixteen-byte device/store scope and a
positive sequence and revision. The sequence must come from the trusted
storage protocol. Authenticating an arbitrary caller-supplied number does not
establish a rollback floor.

| Offset | Bytes | Field |
| --- | --- | --- |
| 0 | 8 | `FSMPCK01` |
| 8 | 8 | Positive sequence, little endian |
| 16 | 8 | Positive frozen revision, little endian |
| 24 | 8 | Payload length, little endian |
| 32 | 16 | Device/store scope |
| 48 | 104..1344 | Complete `SMPTRY01` checkpoint |
| 48+payload | 16 | Full AES-CMAC of the header and payload |

Payload lengths are 64+40 times the ledger entry count (1..32). Frames occupy
168..1408 bytes. `ck_size(payloadBytes)` returns the frame size and
`ck_seal_work(payloadBytes)` returns the required 264..1504 bytes of scratch.
`ck_seal(key, scope, sequence, revision, payload, bytes, out, capacity, work,
workCapacity)` returns the frame length. `ck_open(key, scope, sequence,
expectedRevision, frame, size, out, capacity, work, workCapacity)` requires112
bytes of scratch and returns the decoded payload length.

Key, scope, input, output and scratch must be mutually disjoint. In particular,
the expected scope cannot point inside the untrusted frame. Parameter failures
return -22 before changing output or scratch. Malformed framing or scope returns
-74; a different sequence or expected revision returns -116. Those header
checks do not invoke AES. Once authentication starts, success, a bad tag and AES
errors all clear the scratch used. Output is published only after complete
authentication and envelope payload-shape validation. A bad tag or inner shape
returns -74; signed provider errors propagate unchanged.

The expected sequence is always exact. `expectedRevision=0` is reserved for
trusted restore, where no prior RAM revision is available; the MAC still
authenticates the encoded positive revision. Commit readback must use the exact
frozen revision. After opening a restored frame, `sr_import` must still validate
the full ledger semantics transactionally. Framing checks only the bounded
length, `SMPTRY01` magic and matching entry count.

Frames provide authentication, not encryption. This payload contains retry
history, not bond IRKs or LTKs. Key provisioning, trusted restart rollback
protection, physical media and bond serialization remain separate requirements.
CMAC follows [RFC4493](https://www.rfc-editor.org/rfc/rfc4493).

## Pending checkpoint readback

`lib/net/smp-checkpoint-pending.flex` binds the envelope to the durable gate:

- `ck_pending_seal(key, scope, out, capacity, work, workCapacity)` seals the
  exact pending sequence, revision and copied payload. It does not start a
  checkpoint; it returns0 when none is pending.
- `ck_pending_verify(key, scope, frame, size, work, workCapacity)` requires
  112+payload bytes of scratch. It privately authenticates and decodes the frame,
  compares every payload byte with the frozen snapshot, clears the private
  staging, and returns0 only for an exact match. A correctly authenticated frame
  with different payload is rejected. Alias checks precede cleanup.

Neither helper calls `sd_done`, even after success or failure. Both exclude gate,
ledger and owner storage from external buffers. Mutations arriving during a
write cannot change the frozen frame. The storage owner must finish and verify
the media transaction, then durably advance the trusted rollback anchor before
issuing the separate exact-tuple success ACK. Readback alone cannot release
protocol effects.

`tests/esp32/smp-checkpoint-reference.py` takes explicit compiler, QEMU, both
cross-toolchain prefixes, both pinned AES provider objects and a fresh work
directory. Its Python cryptography CMAC reference generates1868 vectors and
67386 AES operations per raw target. All32 supported payload sizes run at all16
PS levels for ordinary seal/open, alongside corrupted headers/payloads/tags,
scope/replay checks, aliases, bounds and all88 AES failure positions of a maximum
frame distributed across PS levels. Native OpenSSL and both Xtensa vendor AES
implementations agree. The composed pending-checkpoint consumer adds35 checks
per target, including a valid-MAC wrong payload, revision mismatches, later
mutations and successful verification that leaves pairing blocked.

All eight stock-QEMU boots pass. Thirty-two isolated framing defects and nine
integration defects are detected. The39 captured sources reproduce37 artifacts
exactly, including all eight firmware ELF/image pairs. AES provider objects are
pinned inputs previously built under the crypto checkpoint, not rebuilt here.
Evidence: `build/esp32-backend-smp-checkpoint/report.json`. These tests inject
storage ACKs; they do not establish physical media durability, trusted anchor
advancement, radio pairing or full SMP authentication.


## Settings commit owner

`lib/net/smp-checkpoint-store.flex` (T475) composes the actual two-bank
`lib/storage/settings.flex` I/O protocol with framing and the durable gate. It
must be initialized after verified restore or explicit provisioning, with a
clean mounted settings store. It does not format media, reset an anchor or
implement boot recovery; use the recovery owner below first. Other settings
writers must stay idle for its lifetime.
Serialize calls with the SMP host owner; the gate may keep accepting independent
session mutations while a frozen transaction is pending.

`cs_init(work, capacity, key, scope)` copies the sixteen-byte key and scope into
private storage. Workspace is `cs_size(entries)` =480+80*entries bytes, aligned
to8, disjoint from the engines, gate, settings workspace, key and scope. It is
560..3040 bytes for1..32 ledger entries, separate from the settings two-bank
workspace. The existing SDK arena accommodates the maximum configuration
without changing the native heap or firmware memory profile.

`cs_start(nowMs)` freezes and seals a pending checkpoint, or adopts an already
frozen checkpoint. It returns1 when started,0 when clean, or a negative error.
`cs_next_io()` publishes the following leased requests:

| Kind | Operation | Request fields | Completion |
| --- | --- | --- | --- |
| 1 | NOR erase | Relative offset and byte count | Exact erased byte count |
| 2 | NOR program | Relative offset, readonly buffer and byte count | Exact programmed byte count |
| 3 | NOR read | Relative offset, writable buffer and byte count | Exact read byte count |
| 4 | Trusted anchor load | Readonly sixteen-byte scope | Status0 and loaded sequence |
| 5 | Trusted atomic compare/advance | Scope, expected and desired sequence | Status0 and advanced sequence |

The published fields are `cs_io_token`, `cs_io_kind`, `cs_io_offset`,
`cs_io_buffer`, `cs_io_size`, `cs_io_scope`, `cs_io_expected` and
`cs_io_desired`. Repeated peeks retain the same request and token. Anchor scope
must identify the exact provisioned device/store anchor; a RAM variable or
ordinary flash number cannot fulfill that provider contract.

After the provider finishes and quiesces the operation, call
`cs_io_done(token, result, value, nowMs)`. For media, result is the exact byte
count and value must be0. For anchors, result is0 and value is the loaded or
advanced sequence. Negative provider errors propagate; positive anchor statuses
and invalid callback parameters leave the request pending. Stale tokens return
-116 unchanged. Tokens remain nonreused across normal deinit/reinit in the same
host lifetime. No provider may retain a buffer after its completion callback.

The transaction first loads the trusted sequence and checks it against the gate.
It stores the complete frame as the `smp.retry` blob and drains settings' erase,
program, full header/body readback comparison, commit-marker program and marker
readback. It authenticates the exact frame bytes established by that readback
and compares the frozen payload. Only then does it request an atomic anchor
advance from N to N+1. A separate trusted load must confirm N+1 before it calls
the exact `sd_done` success ACK. A committed older identity can still progress
while a newer mutation waits for its next transaction.

Any accepted media/crypto/anchor failure stops the owner and faults the gate.
An uncertain advance can have taken effect despite a negative result; the owner
does not retry, infer the old value, release pairing or overwrite another bank.
Recovery must reload physical media and the actual trusted anchor in a fresh
verified host lifetime. `cs_deinit()` requires an idle, healthy owner and wipes
the workspace, including its copied key. A faulted owner stays stopped.

`tests/esp32/smp-checkpoint-store-reference.py` runs23 composed scenarios and1005
checks per native/original/S3 target. Its independent NOR peer enforces sector
erase and one-to-zero programming. Cases inject failures after each of seven
small-frame media operations, short completion counts, corrupted readback,
invalid MACs, real vendor AES errors, stale leases, anchor-load/advance/confirm
failures, uncertain advances that actually update the peer counter, deadline
expiry and concurrent dirty revisions. A configuration sized for four sessions/32 ledger entries
uses the maximum frame and eleven media operations; SDK arena reclamation and
workspace guards are checked. Sixteen isolated transaction defects are detected,
including a reproduced10ms-to9ms completion-time rollback. An earlier timestamp
now returns -22 without consuming the I/O lease.
Both stock-QEMU boots pass. The current combined recovery checkpoint captures
58 sources and reproduces128 artifacts, including these firmware ELF/image pairs.
Evidence: `build/esp32-backend-smp-recovery/report.json`. The earlier standalone
checkpoint remains at `build/esp32-backend-smp-checkpoint-store/report.json`.

The anchor and NOR devices here are explicit test peers. This proves the
coordinator's software ordering, not physical media durability or trusted
restart rollback protection. Software boot selection/recovery is implemented
below. Physical power-cut recovery, key/anchor provisioning and actual
device/provider integration remain T472. Radio pairing activation and full
authentication remain gated under T139.


## Boot recovery

`lib/net/smp-checkpoint-recover.flex` (T476) recovers retry state before session,
durable or commit owners attach. Initialize an empty retry ledger with the exact
configured capacity and policy, initialize settings, and read both complete raw
banks into `kv_bank_buffer(0/1)`. Do not call `kv_mount` first:mounting copies the
selected bank over the other RAM image. The ordinary `esp_settings_reload`
already mounts and therefore is not this raw-bank load step. The physical boot
adapter and provisioning policy remain T472.

`cr_init(work, capacity, key, scope)` requires no session/durable/commit owner,
no active feature session, an empty ledger and unmounted, idle settings. It
copies the sixteen-byte key and scope into its workspace. `cr_size(entries)`
is432+80*entries bytes (512..2992), aligned to8 and disjoint from keys, engines
and settings. The initialized ledger capacity, policy, generation floor and
clock are bound for the entire recovery operation.

Call `cr_start(nowMs)`, then drain `cr_next_io()` with the same trusted provider
contract as the commit owner. Kind4 loads the scoped anchor; kind5 atomically
compares and advances it. Requests expose `cr_io_token`, `cr_io_kind`,
`cr_io_scope`, `cr_io_expected` and `cr_io_desired`. Complete a quiesced operation
with `cr_io_done(token, status, trustedValue, nowMs)`. Success status is0, signed
errors propagate, stale tokens return -116 and positive statuses or timestamps
earlier than the last accepted completion return -22 without consuming the
request. Repeated peeks keep the exact token and scope. Tokens remain nonreused
across normal reinitialization within one host lifetime.

Recovery loads the trusted sequence N, then inspects both raw bank images:

- A CRC-invalid bank is ignored as an interrupted/corrupt settings snapshot.
  Every retry blob present in a CRC-valid bank must authenticate and pass full
  ledger semantic validation. A bad MAC or malformed authenticated ledger stops
  recovery, even if another bank contains a usable older frame.
- The highest authenticated sequence must be N or N+1. An available N-1 frame
  cannot replace missing N. A future gap or conflicting frames with the same
  sequence is rejected. Identical duplicate frames are allowed.
- The normal settings mount must select a snapshot containing that exact frame.
  Disagreement between its generation ordering and authenticated sequence
  ordering is rejected before any anchor advance; recovery does not rewrite
  generations or silently choose another snapshot.
- For N+1, recovery performs the scoped compare/advance from N to N+1. For
  either selected sequence, a separate trusted load must confirm it. Only then
  does recovery authenticate the frozen frame again and import the ledger.

`sr_validate(input, size, nowMs)` is the shared, read-only semantic preflight.
It returns a validated record count or a negative error without changing the
ledger, logical clock or lease floor. `sr_import` uses that same preflight before
its atomic publication. Policy, reserved bytes, identities, duplicates, waits,
decay, interrupted-attempt flags and generation floors are checked before an
anchor advance. An interrupted exported attempt becomes a failed retry on
import; it does not become an authenticated connection or a live lease.

A final `cr_io_done` return0 and `cr_state==4` publish `cr_sequence` and
`cr_revision`. The copied key, scope, frames and decoded staging are wiped.
Retain the verified sequence before `cr_deinit()`, initialize the session owner,
attach `sd_init(..., sequence)`, then initialize the live commit owner. The new
gate attachment starts dirty, so restored/interrupted state is checkpointed
before new pairing effects. Recovery does not initialize transport, promote a
bond or declare link authentication.

Any accepted provider, crypto, semantic or binding failure wipes private
workspace and stops recovery with the ledger unchanged. An uncertain advance
may have updated the trusted anchor; reload both actual media and the trusted
anchor in a fresh verified host lifetime. Completely erased media, or no frame
with anchor0, returns -61 and requires explicit provisioning. Missing current
state, conflicts, invalid data and exhausted counters stay closed. No recovery
path formats media, resets a counter or treats a caller-supplied number as a
trusted physical anchor.

`tests/esp32/smp-checkpoint-recover-reference.py` generates817 independent
Python-CMAC/settings cases and runs23668 assertions per native/original/S3
target. It covers all32 ledger capacities, both bank orders, generation wrap
and ambiguity, stale/future/conflicting frames, authenticated malformed policy,
provider errors and352 AES failure positions across maximum-frame recovery.
Those failures include final authentication after the counter already advanced.
The NOR snapshots include343 header/body/commit-marker program prefix cuts and
ten erase prefixes. These are simulated snapshots, not physical power-cut tests.
All twenty stock-QEMU boots and21 targeted recovery defects pass.

The composed consumer `smp-checkpoint-restart-reference.py` adds22 cold-restart
scenarios/552 checks per target. It drives the production commit/settings
engines against the NOR peer, cuts before and after provider completion
callbacks, reloads the actual persisted bytes, recovers against the retained
counter peer and reattaches the durable gate. An interrupted attempt restores a
failed retry; a checkpoint whose commit marker was never written cannot release
pairing output. Both target boots pass.

The combined current-source proof also reruns140 retry scenarios/3886 checks
and23 live-store scenarios/1005 checks per target. In total,29111 checks per
target and all32 stock-QEMU boots pass. Forty-three retry, sixteen store and
twenty-one recovery defects are detected. Fifty-eight captured sources rebuild
128 artifacts exactly, including all32 tested firmware ELF/image pairs. Pinned
AES provider objects are prior crypto-checkpoint inputs, not rebuilt here.
Evidence: `build/esp32-backend-smp-recovery/report.json`.

This proves software framing, ordering and recovery with NOR/anchor boundary
peers. Physical interrupted writes, real trusted-counter integration, secure
key/anchor provisioning and the physical raw-bank boot adapter remain T472.
Full SMP authentication, encryption, bonds and radio pairing remain T139.
