# Inline and external blobs

FlexDB stores small blobs inline and larger blobs in immutable extents inside
**the same database file**. The application still declares a `blob` field and
passes `flexdb_blob(arena, bytes, length)` to ordinary insert/update calls.
Placement occurs when the database takes ownership of a row. Blob values accept
0 through 67,108,863 bytes (64 MiB minus one); text retains its 1 MiB limit.

The default external threshold is **4,096 bytes**, inclusive. Zero-length blobs
stay inline. External payloads are compressed with **Zstd level 1** by default;
compression is used only when it saves at least 32 bytes. Otherwise the exact raw
bytes are stored. Existing compressed inputs are ordinary opaque bytes: their
logical contents are never interpreted or decompressed before compression.

The default compression backend calls system `libzstd.so.1` through FFI.
New default-backend writes fall back to raw storage when it is absent; reading
an existing Zstd blob through that backend requires the library. An experimental
[native Flexscript Zstd codec](../compress/README.md) is also available:
`flexdb_blob_native_zstd(db, 1)` selects it for reads and writes on an idle
connection. This connection-local policy is not persisted and leaves codec ID
`1` unchanged. Native encoding currently requires level 1; native decoding
accepts C-written frames from other levels. Existing readers retain their
backend. Native mode requires no libzstd, but currently runs slower and produces
larger output; C remains the default. There is no compression of ordinary rows,
text fields or small inline blobs in this implementation.

## Settings and inspection

```text
flexdb_blob_options(db, 4096, 1); // idle database; threshold and Zstd level
```

Thresholds 0 through 1 MiB and levels 1 through 19 are accepted. Settings persist
in the next checkpoint and affect new values; existing extents keep their codec.
A threshold of zero externalizes every nonempty blob. Changes are rejected during
a transaction. Explicit settings changes also make an idle close publish them.

| Function | Meaning |
| --- | --- |
| `flexdb_bytes(value)` | Logical uncompressed byte length |
| `flexdb_blob_external(value)` | Whether this is an external value |
| `flexdb_blob_id(value)` | Stable external ID; zero for inline values |
| `flexdb_blob_stored_bytes(value)` | Payload bytes excluding extent/reference overhead |
| `flexdb_blob_native_zstd(db, enabled)` | Select native (1) or C (0) codec for this idle connection |
| `flexdb_blob_codec(value)` | 0 raw/inline, 1 Zstd |

`flexdb_word` remains the raw scalar/text word accessor. **Use the blob APIs for
payload bytes**: the internal word of an external blob is a descriptor pointer.
Generated schema blob getters use `flexdb_blob_data`; `Table_field_value(row)`
returns the lazy value handle and `Table_field_bytes(row)` its logical size.

## Reading without retaining the payload

`flexdb_blob_read(value, offset, output, count)` copies a logical byte range,
returns `count`, or returns -1 on invalid bounds/I/O/decode/corruption. A zero-byte
read at the logical end is valid. Raw blobs support direct range copies.
Compressed range reads decode the frame from the beginning using a 64 KiB output
scratch buffer. For sequential archive processing, use an incremental reader:

```text
let value = Segment_payload_value(row);
let reader = flexdb_blob_reader_sequential(value);
// Check reader != 0 before use.
let buffer = alloc(65536);
let count = flexdb_blob_reader_read(reader, buffer, 65536);
while count > 0 {
    // Consume exactly count bytes; process split records across calls.
    count = flexdb_blob_reader_read(reader, buffer, 65536);
}
// count == -1 means failure, 0 means EOF.
flexdb_blob_reader_close(reader);
syscall(11, buffer, 65536, 0, 0, 0, 0);
```

The incremental reader keeps one decoder and writes into caller-provided
buffers. It does not restart decoding on each read and retains no complete
uncompressed copy. Both read APIs validate stored CRCs, frame completion and exact
decoded length. Zstd's decoder window is capped at 64 MiB; its workspace is in
addition to caller/output buffers. Close readers before their database and keep
an inline value's owning arena alive while its reader is open. A reader over a
pending value remains valid across commit/rollback and pins its staging buffer
until closed.

`flexdb_blob_reader_sequential(value)` reads fresh committed extents with a fixed
64 KiB `pread` input buffer. Its upfront stored CRC validation uses that buffer
before exposing any output. It never creates a resident payload mapping. A
private close-on-exec descriptor keeps the original file and offset readable if
compaction replaces the database while the reader is active. Close releases that
descriptor, decoder and input buffer.

For already mapped/captured extents it preserves the existing source mapping,
drops consumed read-only pages between calls, and releases the remainder on
close. This supports captured deleted values whose original inode has been
unlinked. Staged anonymous payloads remain pinned and readable across commit or
rollback. Peak memory still includes the caller's output buffer, metadata, any
explicitly materialized values and the decoder's window. Use 64–256 KiB output
buffers for ordinary archive scans.

The original `flexdb_blob_reader(value)` retains pages for callers that prefer
repeated access. Both readers have the same read/close API, validation and value
lifetime rules. This policy changes memory residency, not the file format.

`flexdb_blob_release_pages(value)` returns 1 on success or a harmless no-op,
and 0 for a non-blob, unavailable database or failed memory advice. On Linux it
uses `MADV_DONTNEED` on this blob's read-only file mapping. Its address, captured
values, active readers and old inodes retained across compaction remain valid;
accessing it later faults the same bytes back in. Inline values, anonymous
transaction staging and explicit `flexdb_blob_data` copies are preserved. It
does not create a mapping just to discard its pages. The OS file cache can stay
warm while the connection's page-table entries are dropped. The engine does not
automatically apply this hint to the original reader: scanners can opt in after each blob,
while callers that repeatedly access a blob can retain its resident pages.

`flexdb_blob_data(value)` explicitly materializes the whole logical value and
returns its pointer, or zero on failure. That pointer remains valid until database
close, including across edits/rollback/compaction. The retained copy is a deliberate
cost of this convenience API. Inline values retain their arena lifetime.

## Space, ownership and transactions

A row stores a 48-byte external reference: logical length, ID, extent offset,
stored length, codec and CRC. Each extent adds 112 bytes of header/footer to its
stored payload, without per-extent disk page padding. Checkpoints store references
and do not duplicate payloads. Updating metadata while retaining the existing
blob value also retains its ID and extent. Pass the existing `_value` handle in
replacement values; constructing a fresh blob creates a new immutable object.
There is no content-addressed deduplication of independently constructed blobs.

Rows copy/own their input values. For large inserts use a short-lived query arena
for input construction, then release it after the insert. The engine stages the
compressed/raw external payload until commit; active transaction payloads must
still fit available memory. After a durable commit it releases anonymous staging
buffers unless an active reader pins them. Committed payloads are file-backed; checkpoint loading retains the existing
read-only file mapping. Row lookup does not validate or decompress external
payloads, and blob readers create their own extent mappings on demand. Metadata
and captured versions retain their existing connection lifetime.

All extents for a transaction precede its checked commit record, and one fsync
covers both. An incomplete transaction's orphan extents are truncated together;
complete corrupt frames fail recovery without rewriting committed data. Rollback
writes no extents. External data corruption discovered lazily poisons the
connection, as row corruption does. Integrity checks use the sequential reader
to stream-validate live blobs without retaining decoded copies or mapping fresh
payload extents.

External frames can exceed the existing 16 MiB transaction/checkpoint limit:
that limit still applies to metadata and inline values. Tests include an 18 MiB
incompressible blob with a small checkpoint. This does not remove the other
current table, metadata, row-cache or concurrency limits.

`flexdb_compact` writes each live external ID once to a replacement file and
rewrites reference offsets without changing IDs. It preserves stored compressed
bytes and excludes deleted/unreferenced extents. Captured deleted/old values
remain readable. **There is no in-place free-extent reuse yet**: reclamation uses
compaction. Compaction temporarily needs old plus new file space, and old
mappings/captured versions can keep the previous inode allocated until close.

Files with external storage use `FLEXBL01` extent frames, `FLEXTX03/FLEXEND3`
transactions and `FLEXCP04` checkpoints. Compacted external archives use a
`FLEXDB03` mandatory-base header. Previous formats remain readable; old readers
reject these new formats. Blob schemas with external capability use the checked
Flexscript checkpoint/scalar-scan fallback; non-blob native fast paths remain.

## Reproduce the measurements

```sh
./build/flex scripts/benchmark-flexdb-blobs.flex -o build/benchmark-blobs
./build/benchmark-blobs
```

See [measured compression and storage results](benchmark-blobs.md). The data is
synthetic and does not establish a production log compression ratio or a SQLite
performance win. Higher Zstd levels are not guaranteed to produce smaller output
for a particular input; compare sizes and commit costs for the intended workload.
