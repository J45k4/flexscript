# FlexDB

An experimental embedded relational database written in Flexscript. Open it
with `open_flexdb(path)`. All tables, schemas and committed transactions live
in that one file. There is no server or query-language parser: queries are
ordinary function calls and application loops. The optional schema DSL
reconciles declared schemas automatically on open, without migration files;
lossy changes need explicit rules in the declaration.

Import `libs/db/flexdb.flex` relative to your source. The initial implementation
targets native Linux x86-64 and uses its own file format, not SQLite's format.

## Example

```text
import "libs/db/flexdb.flex";

fn main() {
    let db = open_flexdb("people.db");
    if !db { return 1; }
    let people = flexdb_table(db, "people");
    if !people {
        if !flexdb_begin(db) { close_flexdb(db); return 1; }
        let schema = flexdb_schema(db);
        flexdb_column(db, schema, "name", flexdb_text_type(), 0);
        flexdb_column(db, schema, "age", flexdb_int_type(), 0);
        people = flexdb_create(db, "people", schema);

        let values = flexdb_values(db);
        flexdb_add(db, values, flexdb_text(db, "Puppy"));
        flexdb_add(db, values, flexdb_int(db, 28));
        if !people || !flexdb_insert(people, values) || !flexdb_commit(db) {
            close_flexdb(db); return 1;
        }
    }

    let q = flexdb_query(db);
    let adults = flexdb_where(q, flexdb_scan(q, people),
        flexdb_column_index(people, "age"), flexdb_ge(), flexdb_int(q, 18));
    let i = 0;
    while i < flexdb_count(adults) {
        let row = flexdb_at(adults, i);
        // Read fields or apply any further application-specific predicate here.
        let name = flexdb_word(flexdb_cell(row, 0));
        i = i + 1;
    }
    flexdb_query_close(q);
    close_flexdb(db);
    return 0;
}
```

The complete [people example](examples/people.flex) adds a second table and
joins adults to their teams. Run it twice to exercise both creation and reopen:

```sh
./build/flex libs/db/examples/people.flex -o build/flexdb-people
./build/flexdb-people build/people.db
./build/flexdb-people build/people.db
```

Output on each run:

```text
Puppy -> Compilers
Ada -> Graphics
```

## Tables and values

For human-readable declarations and generated field accessors, use the
optional [schema DSL](schema.md): `database App { table Person { ... } }`.
The function-based schema API below remains available.

`flexdb_schema(db)` creates a schema builder. Add columns using
`flexdb_column(db, schema, name, type, nullable)`, which returns the zero-based
column index, or `-1` on error. Names are case-sensitive byte strings, 1–255
bytes long. Column names within a table and table names within a database must
be unique. `flexdb_create(db, name, schema)` copies the completed schema and
returns a table handle. `flexdb_table(db, name)` looks up an existing table;
`flexdb_column_index(table, name)` returns its column index or `-1`.

| Column type | Value constructor | Representation |
| --- | --- | --- |
| `flexdb_int_type()` | `flexdb_int(arena, number)` | Signed 64-bit integer |
| `flexdb_text_type()` | `flexdb_text(arena, text)` | Copied zero-terminated string; compared as bytes |
| `flexdb_blob_type()` | `flexdb_blob(arena, pointer, bytes)` | Copied arbitrary bytes, including zeros |
| `flexdb_real_type()` | `flexdb_real(arena, bits)` | IEEE binary64 bit word, as in `lib/f64.flex` |
| Any nullable column | `flexdb_null(arena)` | Explicit null value |

The allocation arena may be a database or a query handle. Build a row with
`flexdb_values(arena)` and `flexdb_add(arena, values, value)` in schema order.
Insert and update copy the values into database-owned storage, so query-owned
input values may be freed immediately afterward. Text/blob values are limited
to 1 MiB each; an oversized/negative-length blob constructor returns zero.

`flexdb_insert(table, values)` returns an automatically assigned positive row
ID; zero means failure. IDs are local to each table, increasing, and preserved
on reopen. A rolled-back insert consumes no durable ID. User-defined columns
are not implicitly unique or foreign keys.

`flexdb_get(table, id)` returns a row or zero. `flexdb_update(table, id, values)`
replaces the complete row; `flexdb_delete(table, id)` removes it. Both return
one on success and zero on failure. Read values with `flexdb_cell(row, column)`
and then `flexdb_kind(value)`, `flexdb_word(value)`, or `flexdb_bytes(value)`.
`flexdb_rowid(row)` retrieves the row ID. Invalid row/column lookup returns
zero; zero is a missing handle, whereas a null field has a nonzero value handle.

## Queries in software

Create a temporary arena with `flexdb_query(db)` and release all its results
and values together with `flexdb_query_close(q)`. A connection retains at most
one small closed query arena (64 KiB) for reuse; its old handles remain invalid.
Results hold immutable row
versions; subsequent updates do not change an already materialized result.
The database must remain open while its query results or row handles are used.
Use each result with the query arena that created it. These handles are not
thread-safe.

| Function | Result |
| --- | --- |
| `flexdb_scan(q, table)` | Live rows in ascending row-ID order |
| `flexdb_where(q, rows, column, op, value)` | Typed comparison filter |
| `flexdb_where_null(q, rows, column, is_null)` | Null/non-null filter |
| `flexdb_join(q, left, left_column, right, right_column)` | Inner equality join; left fields followed by right fields |
| `flexdb_project(q, rows, columns)` | Selected fields, in requested order |
| `flexdb_limit(q, rows, offset, count)` | Slice of the result |
| `flexdb_count(rows)` / `flexdb_columns(rows)` | Row count / field count |
| `flexdb_at(rows, index)` | Row handle or zero |

Comparison operators are `flexdb_eq()`, `flexdb_ne()`, `flexdb_lt()`,
`flexdb_le()`, `flexdb_gt()` and `flexdb_ge()`. There are no implicit type
conversions. Nulls never match ordinary comparisons or join keys; use the null
filter instead. Real comparisons follow binary64 semantics, including signed
zero equality and unordered NaNs. Text/blob ordering is lexicographic by byte.

For a projection, build indices with `flexdb_selection(q)` followed by
`flexdb_pick(q, columns, index)`. Joins preserve duplicate matches and emit
left-major, right-minor order. Equality joins build a temporary hash table over
the right input and recheck values, preserving duplicate and null semantics.
Joined rows have no single source row ID and
return zero from `flexdb_rowid`; projection preserves the input row ID.

For arbitrary predicates, iterate a scan and express the condition directly
in Flexscript. The library does not compile a separate query language.

## Compile ordinary predicates

The optional FlexDB compiler extension inspects normal Flexscript functions
and generates their data-access loops. The compiler's existing `extend` hook
loads the extension; the main compiler contains no database-specific rules.

```text
import "libs/db/flexdb.flex";
extend "libs/db/compile.flex" with "adult";
extend "libs/db/compile.flex" with "by_id";

fn adult(row, minimum) {
    let age = flexdb_cell(row, 1);
    return flexdb_kind(age) == flexdb_int_type()
        && flexdb_word(age) >= minimum;
}

fn by_id(row, id) {
    return flexdb_rowid(row) == id;
}

// Inside an application function, with the example's people table:
// let adults = adult_query(q, people, 18);
// let count = adult_count(people, 18);
// let one = by_id_query(q, people, requested_id);
```

There is no expression-string parser. Each predicate takes the row as its
first parameter, then up to 15 normal query parameters. For predicate `name`,
the compiler generates:

| Generated function | Behavior |
| --- | --- |
| `name_query(q, table, parameters...)` | Materialize matching rows only |
| `name_count(table, parameters...)` | Count matches without allocating a result; `-1` on invalid table |
| `name_page(q, table, offset, limit, parameters...)` | Scan in row-ID order, skipping matches until offset, collecting at most limit and stopping early |
| `name_plan()` | `0` for fused scan, `1` for primary-key seek, `2` for adaptive equality |
| `name_plan_name()` | Readable name of the selected access path |

General predicates, including branches and pure helper calls, use a fused
scan: visit live rows once, evaluate the predicate, and collect only matches.
This avoids materializing `flexdb_scan` before filtering. Exact single-field
integer comparisons and proven text equality inline their getter/comparison.
The extension also simplifies proven one-argument field-reader functions used by
ordinary application loops. It follows the complete current helper chain, checks
canonical cell/word readers, retains row-width checks, and leaves unknown/effectful
calls or additional field reads in place. Earlier reader edits prevent this rewrite.
Subsequent predicate extensions still recognize the simplified readers.
`name_page` avoids allocating discarded rows; negative offset/limit fails,
zero limit returns an empty result, and only matching live rows count toward
the offset. It currently scans rather than selecting an equality index.

Count queries do not allocate a query/result arena. For proven integer field
comparisons on checkpoints, the runtime can build a private scalar view instead
of allocating rows and copying unrelated text/blob payloads. It checks directory
and row CRCs, nullability, every encoded field's bounds and the complete row
encoding first. On native x86-64, a schema-specific scanner emitted in Flexscript
performs that complete validation and scalar extraction in one bulk call. It uses
the existing IEEE CRC helper and base x86-64 instructions. The code page changes
RW to RX and is released after filling the view; unavailable executable memory
uses the original Flexscript scan. No expression from database data becomes code.
The view retains 16 bytes per checkpoint row position for one
column per table; requesting another column replaces it. Current RAM rows
always override the view after edits, deletes, inserts or rollback. Compaction,
checkpoint construction, schema replacement and database close release views.
This memory is separate from the automatic-index budget. General predicates
still hydrate checkpoint rows on first use. Adaptive queries keep usage records
and may build an index.

An exact returned row-ID equality to a parameter or literal uses the existing
dense-ID primary-key lookup (with a binary-search fallback). Reversed equality and simple local aliases
are recognized. The extension inspects the `flexdb_rowid` helper's actual IR
before trusting that operation. Other row-ID expressions conservatively stay scans.
The ordinary predicate is still checked on the fetched row.

Predicates and their transitive helpers must not write memory/globals,
allocate, or perform I/O; recursive or unresolved helpers are rejected with
a compile-time diagnostic. Local assignments are allowed. This conservative
contract permits fusion and skipping nonmatching rows without discarding side
effects. Raw memory/field reads remain the author's responsibility, as in
ordinary Flexscript; use the correct table schema and check nullable fields.

The compiler also recognizes exact single-field equality through straight-line
helpers and schema-generated accessors. Integer equality uses `==`; text equality
uses `fd_same`, rather than pointer equality. The runtime selects a scan or a
learned hash index. General predicates and existing explicit query calls remain
available. Arbitrary application loops, range/compound indexes, join reordering,
and vectorization are not implemented.

See [the compiled example](examples/compiled.flex). First create the example
database above, then:

```sh
./build/flex libs/db/examples/compiled.flex -o build/flexdb-compiled
./build/flexdb-compiled build/people.db
```

## Automatic equality indexes

Define the schema and write an ordinary predicate. This first version learns
useful indexes itself:

```text
extend "libs/db/schema.flex";
extend "libs/db/compile.flex" with "by_name";

database App {
    table Person { id: rowid; name: text; age: i64; }
}
fn by_name(person, name) { return fd_same(Person_name(person), name); }
// by_name_count(people, "Puppy") or by_name_query(q, people, "Puppy")
```

`by_name_plan()` returns `2`, meaning an eligible adaptive access path. Initially
it scans and records demand and selectivity. With the default policy it can build
a hash index after at least four prior calls and 32,768 scanned row positions,
for tables with at least 256 row positions, when average matches are below 1/8
of the table. Eligible columns are non-null `i64` and `text`; nullable fields,
other types, compound expressions and ranges scan. Parameters and integer literals
are recognized; literal text pointers conservatively stay scans. Helper readers
are checked against their actual definitions, including earlier extension edits.

Index construction runs synchronously in the querying thread. Each attempt is
limited to 262,144 row positions and approximately 100 ms, checked periodically;
an abandoned build returns scan results and waits before retrying. Observed
repeat matches can select a temporary successor array during construction: it
finds the first unused probing slot with path compression instead of repeatedly
walking duplicate clusters. The resulting buckets are byte-for-byte identical
to ordinary insertion. Scratch is released on success/failure, and its work is
included in the build deadline. Unique builds retain the direct path. This
scratch is outside the retained-index budget and appears in process peak RSS.
The default
budget is 8 MiB of hash buckets and count memos across at most four indexes. Least recently used
indexes are evicted to make room; indexes unused for over 1,024 eligible lookup
calls expire at periodic checks. This budget excludes row caches, metadata and
arena overhead. It is a heuristic, not a measured cost optimizer or a background
worker. A broad query can still use an index learned from earlier selective calls.
Integer count queries with duplicate matches can retain exact counts in a bounded
memo (at most 4,096 entries per index, within the same budget). Entries compare
the full integer key; the first lookup still verifies matching rows. Relevant
committed edits invalidate the memo; active transactions use current rows.
These count memos are not persisted.
RAM integer indexes also retain conservative minimum/maximum keys to reject
out-of-range misses without probing duplicate clusters. Committed edits widen
the bounds; deletions need not tighten them. Reopened buckets have unknown bounds
and use normal verified probing until an index is rebuilt.

Hashes cover the complete text key. Candidate comparisons verify the exact
key using the proven predicate semantics; hashes alone never establish text
equality. Backward-shift deletion preserves probe chains without accumulating
tombstones. Materialized
results retain ascending row-ID order, including duplicate keys. Inside a write
transaction, queries scan the current rows. Successful commits maintain existing
indexes; rollback leaves their buckets unchanged. Capacity exhaustion drops the
cache safely, and schema replacement forgets the affected table's learned state.

Checkpoints persist usage and available buckets in the same database file.
`FLEXCP03` stores buckets with the current full-key hash algorithm. Readers
accept `FLEXCP01` and `FLEXCP02`: old logical rows and usage metadata remain
readable, while obsolete CP02 hash buckets are discarded and can be relearned.
Reopening uses read-only mapped buckets, checking their CRC pages before access;
only matching rows need decoding. Committed edits create a sparse writable copy
of the bucket array: each accessed logical 4 KiB page is checked and copied on
demand. Untouched source pages remain read-only; the budget still charges the
full logical bucket capacity. This reduces the work and physical memory of a
small edit without changing query results or the file's checkpoint bytes.

Validated transaction replay maintains these restored indexes through the same
update/delete/insert path as a live commit, including consecutive insert batches.
It decodes the edited old rows, rather than rebuilding the complete table/index
on the first query. Capacity exhaustion safely drops a derived cache; schema
replacement clears affected indexes. A checksum failure poisons the connection.
Checkpoint writing and whole-index integrity checks copy/check remaining pages
before reading the complete writable array. If a checkpoint plus caches would
exceed the existing 16 MiB limit, caches may be omitted while usage is retained.
A failed database open never checkpoints its partially replayed state.

`flexdb_auto_budget(db, bytes)` sets the bucket/count-memo budget (0 disables learning,
maximum 64 MiB) and forgets current candidates/caches; call it outside a
transaction. `flexdb_index_state(table, column)` returns `0` unknown, `1` learning,
`2` active, or `-1` for an invalid table. `flexdb_index_queries` and
`flexdb_index_hits` expose eligible calls and indexed attempts;
`flexdb_index_bytes(db)` reports the current bucket and count-memo allocation. Changing the
budget is connection-local. No schema migration or logical index log entry is
needed: these indexes are disposable access caches, not uniqueness constraints.

## Transactions and storage

All schema and row mutations require `flexdb_begin(db)`. Apply changes, then
call `flexdb_commit(db)` or `flexdb_rollback(db)`. Each returns one on success
and zero on failure. Nested transactions are rejected. Closing a database
discards an uncommitted transaction; an empty commit appends nothing. Changes
are visible to queries through the same connection before commit.

`begin` records transaction state without allocating a log or table snapshots.
The first mutation prepares both before changing logical data; the held exclusive
lock prevents another connection from changing tables between begin and preparation.
Empty commit/rollback writes no bytes and performs no durable synchronization.
A connection keeps at most one small completed transaction arena (one block of
at most 64 KiB, plus its header) for reuse. Larger scratch arenas are released.
Input values and stored immutable rows retain their existing ownership/lifetimes;
reusing rollback/log memory never reuses those stored rows.

Opening takes a nonblocking exclusive file lock, retained until close. A
second connection, including in the same process, fails instead of waiting.
There is currently no concurrent read-only connection mode. New database files
use mode `0600`; final-path symlinks and non-regular files are rejected.

The file begins with a 32-byte `FLEXDB01` version-one header. Original
transactions use `FLEXTX01`/`FLEXEND1`. After a checkpoint, `FLEXTX02` uses a
48-byte checksummed footer (`FLEXEND2`) that identifies the checkpoint and frame
offsets. No mutable root pointer is overwritten. Transaction headers contain
payload length, increasing sequence number, and independent IEEE CRC32 checksums
for the header and header-plus-payload; all words are little-endian. Operations
create tables, upsert/delete rows, or replace schemas/rows atomically.
Consecutive inserts use schema-typed batches with null bitmaps and implied row
IDs; original upsert records still replay. Commit appends and calls `fsync`;
file creation also syncs the parent directory.

`flexdb_checkpoint(db)` appends the current schema, row directory and live row
data, then fsyncs a checksummed `FLEXCPE1` footer. It requires no transaction and
writes nothing when the existing checkpoint already covers the current commit
and tuning state. Closing an idle connection automatically checkpoints after at
least 64 KiB of log since the previous checkpoint, or when index topology changes.
Usage statistics alone do not trigger automatic checkpoints; use the explicit
checkpoint API to retain learning from a short read-only session. An oversized automatic checkpoint is skipped
without discarding committed data; the explicit API reports the limit. Closing
a connection with an active transaction discards it and skips checkpointing.

For tables with at least 128 rows, checkpoint construction can emit a
schema-specific x86-64 sizing loop and bulk row writer in Flexscript. Remaining
mapped rows are validated and hydrated first; the writer consumes engine-owned
rows, checks destination bounds and retains the exact CP03 encoding and IEEE
checksums. Each temporary code mapping changes from RW to RX and is released
after use. Smaller tables and unavailable executable memory use the ordinary
Flexscript writer. Large disjoint byte copies also have a bounded native entry;
small or overlapping copies retain their existing loop. Arena cleanup combines
exactly adjacent owned blocks into one unmap without releasing intervening maps.

On reopen, the final completed footer locates the latest checkpoint directly.
The file is mapped read-only; schema metadata is verified immediately, while
row-directory pages and individual row checksums are verified on first access.
Only fetched rows are decoded/cached. Transactions after the checkpoint replay
normally. An interrupted checkpoint/tail uses recovery scanning and truncates
only its incomplete final frame. Complete corrupt metadata/transactions fail
open; lazy directory/row corruption fails the read and poisons the connection.
`flexdb_integrity(db)` walks and materializes all current rows to validate the
remaining checkpoint data. A checkpoint is the authoritative committed state:
superseded history before it is not part of current-state integrity checking.
CRC32 detects accidental corruption, not malicious modification.
On native Linux x86-64, a small helper emitted in Flexscript executes the IEEE
CRC32 slicing-by-eight loop with register-held state. It uses the base x86-64
instruction set and no SDK, assembler or C library at runtime. The code page
changes from writable to executable/read-only; if this fails, the ordinary
Flexscript implementation runs. Both paths produce identical existing checksums
and read only the requested byte range.

`flexdb_compact(db)` writes a fresh header and checkpoint to an exclusive
temporary file beside the database, fsyncs it, atomically renames it over the
database, and syncs the parent directory. It holds both inode locks across
publication; new openers verify pathname/inode identity after taking the lock.
A compacted `FLEXDB02` header marks its initial checkpoint as mandatory; an
incomplete base fails rather than recovering to an empty database.
The API requires no transaction, retains stable IDs/tombstones/next ID, and
preserves captured row/results until close. Successful compaction leaves one
data file; a process killed before publication may leave an unused temporary
file. Old checkpoint mappings retain the old inode until the connection closes.

After a commit I/O failure, its outcome is uncertain: close and reopen the
database. The connection rejects further reads/mutations instead of presenting
its in-memory changes as durable. `flexdb_error(db)` returns the most recent
error; use `flexdb_error(0)` after `open_flexdb` fails. Errors are borrowed
strings. Allocation failure/arena overflow terminates the process.

This is an experimental file format and engine, with no compatibility promise
yet. The current bounds are 1,024 tables, 64 columns per table and 16 MiB per
transaction/checkpoint. Legacy files without a checkpoint replay into memory;
checkpoint-backed rows load on demand. The mapped file and cached rows remain
owned by the connection; the row cache currently has no eviction. Row-ID lookup
has a constant-time dense-ID path with a binary-search fallback. The common RAM
lookup checks connection/table status, ID bounds, the stored ID and deletion state
without helper calls; checkpoint rows still decode and validate on first access.
Eligible compiled equalities use adaptive indexes, other filters scan, and
equality joins use a temporary hash table. The first mutation snapshots table
metadata and prepares undo records; begin does not copy whole row indexes.
Superseded database-owned row/value allocations remain until close. The append log
grows with writes until explicit compaction; there is no disk B-tree,
range/compound index, general sorting/aggregate operator, automatic table rename/removal,
unique-column/foreign-key constraint, or multi-threaded access yet. Filesystem/power-loss behavior has
not been validated across devices.

## Checks

```sh
./build/flex scripts/test-flexdb.flex -o build/test-flexdb
TMPDIR="$PWD/build/flexdb/tmp" ./build/test-flexdb ./build/flex
```

Create the `TMPDIR` first if needed. The suite exercises types/nulls, binary
blobs, filters/joins/projection, ID lookup across vector growth, multi-table
transactions, rollback, reopen, process locking, abrupt process exit, commit
failure handling, malformed frames and every byte-truncated prefix of a
transaction. The example is also checked on both initial creation and reopen.
Compiled-predicate checks cover selected plans, helper predicates, result
parity/order, allocation-free counts, literal/parameter seeks, aliases, missing
and deleted IDs, own writes/rollback, and diagnostics for effectful/recursive
predicates and generated-name collisions.

Schema checks cover generated accessors/values and compiler planning, followed
by automatic reconciliation: field reordering, nullability, defaults, explicit
renames/removal/conversion, ambiguous renames, failed conversions and whole-schema
rollback, durable reopen, and every truncated prefix of a replacement transaction.

## Performance comparison

See [the SQLite comparison](performance.md) for measured results and limitations.
The benchmark driver is written in Flexscript; the SQLite baseline uses native
C with prepared statements against the system SQLite library. Neither disables
durable synchronization.

Checkpoint checks cover no-row startup, demand loading, post-checkpoint
transactions, reconciliation, cached immutable queries, every truncated
checkpoint and modern-transaction prefix, eager metadata versus lazy row/page
corruption, current-state integrity, IO failure, and compaction with preserved
IDs, retained results and the replacement inode lock.

Adaptive-index checks cover numeric/text learning and helper recognition,
ordered duplicate matches, own writes, repeated edits, rollback, mapped-cache
maintenance, schema invalidation, checkpoint/compaction reuse, tail invalidation,
scan comparisons after varied updates, collision rechecks, build deadlines,
LRU budgets, expiry and checksum corruption. Earlier extension edits to core
readers/string comparison helpers must conservatively disable the access plan.
