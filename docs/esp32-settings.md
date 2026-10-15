# Native persistent settings

`lib/storage/settings.flex` implements an allocation-free key/value store with
atomic snapshot commits over two independent NOR flash banks. It is portable
Flexscript and runs as native code on Linux and original ESP32 Xtensa. The
application supplies memory and drives explicit media operations; the core
never reads or writes hardware itself. The [original-ESP32 flash backend](esp32-flash.md) now binds these operations
to the real controller and passes cached-flash and multi-boot QEMU tests.
Physical cached-flash/reboot verification now passes on the original ESP32
with Puya852016 flash. The optional [radio NVS provider](esp32-nvs.md) adds namespaces, types, handles
and the pinned vendor callbacks. This is not the
ESP-IDF NVS partition format.

## Recovery and storage format

A commit erases the inactive bank, programs a new header and complete snapshot,
reads back and compares every used byte, then programs and verifies a separate
four-byte commit marker. It never erases or programs the current committed
bank. Failed I/O preserves its error and requires reloading the media before
another transaction. A reboot selects the newest valid committed snapshot.
Uncommitted RAM changes are not persistent.

Each bank is4096..65536 bytes in4096-byte increments. The containing media
region is exactly two banks; its adapter must also enforce physical capacity,
sector alignment, firmware/partition exclusion, cache safety and serialization.
The core's offsets are relative to that region. Snapshot commits rewrite a
bank, rather than append individual entries; applications should batch writes
and provision media appropriate to their expected erase cycles. There is no
wear leveling across additional banks, encryption or tamper authentication.

The32-byte little-endian header is:

| Offset | Field |
| --- | --- |
|0 | u32 magic `0x564b5846` (`FXKV`) |
|4 | u32 format version1 |
|8 | u32 generation, modulo2^32 |
|12 | u32 payload length, aligned to4 |
|16 | u32 entry count |
|20 | CRC-32/ISO-HDLC of the payload |
|24 | CRC-32/ISO-HDLC of the preceding24 header bytes |
|28 | u32 commit marker `0x3cc35aa5`, programmed last |

Each record is an8-byte prefix (`u8 key_length`, `u8 type`, `u16 zero`,
`u32 value_length`), followed by key bytes, value bytes and erased-byte padding
to a multiple of4. Keys are unique and sorted lexicographically as unsigned
bytes. Invalid lengths, padding, ordering, duplicate keys, counts, versions,
markers and CRCs invalidate the bank. Unused bytes beyond the payload are
ignored. Equal-generation banks must contain identical snapshots; a generation
separation of exactly2^31 is ambiguous and rejected. The intended sequential
commit protocol keeps the two generations adjacent, including wrap to zero.

Two erased banks return-61; unknown/corrupt media return-74. Mount never formats
or erases. Explicit initial creation is accepted only after both whole banks
have been observed erased. A cut during the first-ever initialization can
leave no valid snapshot and therefore require explicit recovery by the
application; it does not cause automatic destruction of unknown media.

## Memory and values

`kv_size(bank_bytes)` returns the required workspace size, `2*bank_bytes+264`,
or-22 for an unsupported size. The caller owns that workspace throughout its
use. `kv_init(workspace,capacity,bank_bytes)` initializes one global store.
Load both complete media banks into `kv_bank_buffer(0)` and
`kv_bank_buffer(1)`, then call `kv_mount()`. No dynamic allocation is performed
by the store. The two RAM banks hold committed and staged snapshots; the tail
is readback scratch.

On initially erased media, call `kv_create()` and complete an initial
`kv_commit()` to establish a durable empty store. Creation itself only changes
RAM. Do not call `kv_mount()` using stale RAM banks: loading both banks from
media first is mandatory, including after an I/O failure. Mounted RAM no
longer represents the two distinct media banks because it contains staging.

- `kv_set(key,key_size,type,value,value_size)` copies a value into the pending
  snapshot. Keys contain1..63 arbitrary bytes; types are application-defined
  integers1..255; empty values are valid. At most128 entries fit, also bounded
  by the bank's payload capacity. Capacity errors leave pending values intact.
- `kv_get(key,key_size)` returns0 and publishes a borrowed view through
  `kv_value`, `kv_value_size` and `kv_value_type`; missing keys return-2.
- `kv_delete(key,key_size)` removes a pending key or returns-2 if absent.
- `kv_rollback()` discards pending changes and restores the committed snapshot.
- `kv_commit()` returns1 when a commit starts,0 for unchanged settings, or a
  negative error. Setting an unchanged value, or adding then removing a key,
  does not require another erase when the resulting snapshot is unchanged.

Pending values are immediately visible to reads. A commit publishes the entire
pending snapshot atomically. Mutations and commits invalidate borrowed views;
copy a read value before using it as an input to `kv_set`. Set inputs may not
overlap any part of the workspace. Mutations/rollback/another commit return-16
while a commit is active or unresolved after an I/O failure. The caller must
serialize all access; this core provides no locks or interrupt handling.

## Driving a commit

While `kv_busy` is set, call `kv_next_io()`. It returns an operation kind and
publishes `kv_io_offset`, `kv_io_buffer` and `kv_io_size`. Repeated peeks retain
the same operation. Perform that operation synchronously, then call
`kv_io_done(result)` with the exact transferred/erased byte count or a negative
error. Kind1 erases, kind2 programs, kind3 reads. Erases are sector aligned;
program addresses and sizes are4-byte aligned. The media adapter may split
operations internally while preserving their order and ownership.

Reads target a separate256-byte scratch area. `kv_io_done` compares readback
before advancing. Its return value is1 for more work,0 for a completed commit,
or a negative failure. Short I/O and mismatches fail with-5. The original
negative device error is retained in `kv_fault`. After a failure, reload both
banks and mount again to resolve whether the old or new snapshot committed;
a failure after programming the marker can leave the new snapshot durable.

## Verification and remaining integration

Compile and run `scripts/test-esp32-settings.flex` with explicit `--compiler`,
`--ld`, `--rom` and `--qemu` inputs, like the other ESP32 regression runners.
The runner compiles each fixture freshly. Its reference peer uses Python only
as independent test tooling, not as part of firmware.

Native checks cover copied values, binary keys,128-entry limits, capacity,
growth/shrink/deletion, rollback, no-op commits, all I/O failure positions,
readback corruption and generation wrap. Native larger-bank checks cover8,
16,32 and64KiB, including long values and readback spanning many chunks. The
4KiB-bank fixture also runs from cached flash through the original-ESP32 ROM
boot in QEMU. The native independent peer guards the end of its workspace and
input with inaccessible pages and checks a leading workspace canary.

The independent snapshot/NOR model verifies8187 cases:4412 byte-prefix cuts,
160 scattered-byte cuts,256 partially programmed commit markers, generation
ordering and ambiguity,2146 malformed/mutated media cases, and1200 randomized
settings operations. Every cut after an established commit returns either the
old transaction or the complete new transaction. It checks exact operation
ordering, active-bank exclusion and full media bytes against its own model.

Those are software and emulated-CPU results. The flash backend separately
passes57 register/cache and real-controller QEMU checks, including two
independent four-boot paths and interrupted-bank recovery.
It manages volatile write windows and retains ownership when protection
restoration fails, retrying restoration before reload can succeed. The
physical original-ESP32 probe also passes cached byte transfers, erasure of
written data and four boots with600-byte settings. It recovers the
previous transaction after an unfinished bank header and restores flash
protection after every operation. Independent full4MiB readback verifies the
settings and untouched firmware; the original firmware/storage is restored,
checksum-verified and reset afterward. Hardware interruption is between
completed operations, while mid-command power cuts have independent NOR-model
coverage. The optional [Espressif radio NVS provider](esp32-nvs.md) builds on
this backend with separate namespace/type/handle and C ABI verification. The
portable core tests do not touch a physical device. Persistent BLE bonds
also require the separate SMP implementation.

The [boot-counter example](../examples/esp32-settings.flex) shows the firmware
API with explicit storage reservation and creation only on erased media. It
compiles/links as an original-ESP32 XIP image; no automatic flashing is done.
