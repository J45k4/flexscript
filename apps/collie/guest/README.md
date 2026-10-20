# Collie VM database API

These functions are supplied to generated Flexscript programs automatically.
Do not import libraries or redefine `db_*` names. The connection is granted by
the harness; programs choose table names, not host database paths. The engine is
the repository's native FlexDB, accessed through a typed value bridge.

The initial database contains no tables. Programs discover existing schemas,
create their own tables, and evolve them using transactions. No planning, notes,
memory or task schema is imposed by the harness. Heap allocations are local to
one program; committed database state persists across programs and resume.

## Values and lists

`db_int(number)`, `db_text(string)`, `db_blob(pointer,bytes)`, `db_real(f64_bits)`
and `db_null()` construct values. Each returns a guest-local handle. Read values
with `db_kind(value)`, `db_word(value)` and `db_bytes(value)`. Kinds are 0 null,
1 signed i64, 2 text, 3 blob, 4 f64 bits and 5 list. `db_word()` returns the
integer, f64 bit word, or guest pointer to text/blob data. Text is NUL-terminated;
blobs preserve arbitrary bytes, including NUL. Text/blob values are at most
32 KiB. Integers retain their full signed 64-bit range.

`db_list()` and `db_values()` create empty lists. `db_add(list,value)` appends;
`db_count(list)` returns its length and `db_at(list,index)` retrieves a value.
All indices start at zero. Handles are not native FlexDB pointers and do not
survive program exit.

## Discovery, transactions and schemas

| Function | Result |
| --- | --- |
| `db_tables()` | List of table-name text values; initially empty |
| `db_columns(table)` | List of `[name, kind, nullable]` lists |
| `db_begin()` | Begin an explicit transaction |
| `db_commit()` | Durably commit pending changes |
| `db_rollback()` | Roll back pending changes |
| `db_schema()` | Empty schema builder list |
| `db_column(schema,name,kind,nullable)` | Append a column; kinds 1..4, nullable 0/1 |
| `db_create(table,schema)` | Create a table inside a transaction |
| `db_add_column(table,name,kind,nullable,default_value)` | Add a column and fill live rows |
| `db_rename_column(table,old,new)` | Rename a column |
| `db_drop_column(table,name)` | Explicitly remove a column and its values |

Schema edits preserve row IDs and deletions. Tables require 1..64 uniquely named
columns. Names are 1..255 bytes. Dropping the last column is rejected. A default
must satisfy the new column's type/nullability for all live rows. Mutations,
including schema changes, require a transaction. Nested transactions are rejected.

## Rows and queries

| Function | Result |
| --- | --- |
| `db_insert(table,values)` | New positive row ID |
| `db_update(table,id,values)` | Replace a complete row |
| `db_delete(table,id)` | Delete the row |
| `db_get(table,id)` | Row, or a null value if absent |
| `db_scan(table,after_id,limit)` | Page of live rows with IDs greater than `after_id` |
| `db_rowid(row)` | Row ID |
| `db_cell(row,column_index)` | Scalar value handle |

Rows are represented as `[id, values_list]`; use the accessors above. Values for
inserts and updates follow schema order. Start a scan at `after_id=0` and continue
from the last returned row's ID. Page sizes are 1..128; request smaller pages when
the encoded result would exceed 64 KiB. Express predicates, searches, joins and
other computation as ordinary Flexscript loops. There is no SQL parser.

Operations fail with handle/integer 0; `db_error()` returns the error text from
the latest database call. A successful empty list or a missing-row null value is
a nonzero handle. `db_kind(row)==0` distinguishes a missing row. Transaction and
mutation functions other than insert return 1 on success. Uncommitted changes
are rolled back when execution ends, including traps and cancellation. A commit
that already completed remains durable even if later execution fails.

## Read-only conversation archive

`db_history(after_id,limit)` returns history rows with cells
`[role, content, source, observation_json]`. Start at ID 0 and page by row IDs.
Each text field is an excerpt of at most 4096 UTF-8 bytes. IDs refer to entries
in a separate, durable archive that model-context compaction does not rewrite.
The archive includes current user requests and generated programs as they are
recorded; an unfinished execution may not yet have an observation.

`db_history_read(id,field,byte_offset,limit)` reads an entire field in chunks.
`field` is `role`, `content`, `source` or `observation`; limits are 1..16384 bytes.
It returns a blob, including an empty blob at end of field. Chunk boundaries are
byte boundaries and may split a UTF-8 character. The archive exposes no mutation
operation and creates no tables in the agent's database. It excludes credentials
and hidden model reasoning.

## Runtime limits

Each call uses a bounded frame (64 KiB maximum), at most 4096 encoded nodes and
16 levels of nesting. A program may make at most 1024 calls and receive at most
1 MiB of database response data. Existing VM memory, fuel, execution time and
combined stdout/stderr traffic limits also apply. Requests use a reserved framed
channel on stderr; responses arrive on a private stdin pipe. Those frames are
consumed by the adapter and do not appear as program output or user prose.

`runtime.flex` is the portable guest API/value codec. `source.flex` embeds it into
the native Collie executable and is regenerated by the repository build driver
or `scripts/embed-collie-guest.flex`. The SDK is mounted read-only by the adapter;
agent-provided imports and compiler extensions remain denied.
