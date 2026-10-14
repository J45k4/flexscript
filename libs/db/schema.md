# Readable FlexDB schemas

Declare schemas inside an ordinary `.flex` module:

```text
import "libs/db/flexdb.flex";
extend "libs/db/schema.flex";

database App {
    table Person {
        id:      rowid;
        name:    text;
        age:     i64;
        team_id: i64?;
    }
    table Team {
        id:   rowid;
        name: text;
    }
}
```

The syntax hook turns these declarations into normal Flexscript functions
before parsing. No schema DSL code remains at runtime, and no compiler rebuild
is needed. Declare the extension once; it handles schemas in all loaded
application modules, including imports. Generated helpers are appended after
ordinary declarations, preserving normal global/function ordering. Disk
source files are not modified.

## Types

| Type | Meaning |
| --- | --- |
| `rowid` | Automatic positive row ID; virtual, not a stored column |
| `i64` | Signed 64-bit integer |
| `f64` | IEEE binary64 bit word, compatible with `lib/f64.flex` |
| `text` | Zero-terminated text |
| `blob` | Arbitrary bytes |
| `type?` | Nullable stored field |

Fields may be separated by semicolons, commas or whitespace/newlines. `//`
comments are supported. Field order determines stored column order, excluding
`rowid`. At most one non-null `rowid` field may be declared, in any position.
Every table needs a stored column. The automatic storage ID still exists if
no `rowid` field is declared.

Identifiers are case-sensitive, at most 63 bytes, using letters, digits and
underscores, with a letter/underscore first. Table identifiers become exact
on-disk names and global helper prefixes, so use distinct table type names
across the application. Duplicate fields/generated names are compile errors.
Limits are 32 tables and 256 declared fields per expansion, plus the storage
limit of 64 stored columns per table.

## Opening and reconciling

```text
let db = App_open("people.db");
if !db { return 1; }
let people = Person_table(db);
```

The declaration is the desired schema. `App_open(path)` calls `open_flexdb`
and `App_init(db)`, bringing declared tables into that shape automatically.
There are no numbered versions, migration scripts, or migration history to
maintain. Missing tables are created; existing rows are matched by column name
and rebuilt in the declared order. Row IDs, deleted IDs and the next ID survive.

All declared tables reconcile in one transaction. A missing default, failed
conversion or unapproved field removal rolls back the whole update. Matching
schemas write nothing and do not evaluate defaults or conversions. Additional
undeclared tables are retained, since deleting data requires explicit intent.
Renaming a table is not inferred: a new name creates a new table and retains
the old one.

`App_init(db)` reconciles an already-open database and requires no active
transaction. It returns one on success or zero on error. Use
`flexdb_error(0)` after `App_open` fails. Close with `close_flexdb(db)`.

Each table gets `Person_schema(db)`, `Person_create(db)`, `Person_table(db)`,
`Person_matches(table)` and `Person_sync(db)`. Create/sync require an active
transaction, allowing explicit transactional composition. Normally use the
database-level open/init helpers.

## Declaring how existing data should fit

Safe changes happen automatically: reorder columns, loosen nullability, add
nullable fields, or add a required field with an explicit backfill default.
Required additions to an empty table need no default, and its stored types
can change without converters. Deleted rows do not count as live data. Tightening nullability
is safe when all existing values are non-null; otherwise supply a default.
Existing non-null values are never replaced merely because a default changes.

```text
database App {
    table Person {
        id: rowid;
        name: text from full_name;
        age: i64 using age_from_text;
        active: i64 = 1;
        nickname: text?;
        drop obsolete_note;
    }
}
```

These rules belong to the current schema, not a sequence of imperative steps:

| Rule | Behavior |
| --- | --- |
| `field: TYPE = expression;` | Backfill a newly added field; also replace old nulls when becoming required |
| `field: TYPE from old_name;` | Preserve an old field under its new name |
| `field: TYPE using converter;` | Explicitly convert values if the stored type differs |
| `drop old_name;` | Explicitly allow removal of that old column's data |

Rules may be combined in that order: `field: TYPE from old using convert = default;`.
Defaults require a semicolon/comma. Integer/text/f64 defaults are normal
Flexscript expressions returning a raw word/string/f64 bit word. A blob default
is a typed value handle, e.g. `flexdb_blob(db, "bytes", 5)`. `= null` is available
for nullable fields. Expressions may refer to `db`; they are evaluated once
per mismatching table. These are reconciliation defaults; `Person_values`
still takes every stored field explicitly for new inserts.

Rename rules prefer the current name after reconciliation; they can remain in
the schema and work for databases that still have the older name. If both old
and new names exist, reconciliation fails rather than guessing which data to
keep. An old column cannot feed two new columns. Removing a declaration alone
fails while the old column exists; adding `drop old_name;` explicitly permits
its removal. An already absent dropped column is harmless. Table removal rules
are not implemented; undeclared tables remain accessible by the low-level API.

A converter is ordinary code taking `(db, old_value)` and returning a typed
FlexDB value handle, or zero to fail. It runs on each live value (including
nulls) only when the stored column type differs; it is skipped once the types
match. Its result is checked against the declared type/nullability before any
replacement is published. For example:

```text
fn age_from_text(db, old_value) {
    if flexdb_kind(old_value) == 0 { return flexdb_null(db); }
    // Use the application's checked parser here; return 0 for bad input.
    let text = flexdb_word(old_value);
    if fd_same(text, "42") { return flexdb_int(db, 42); }
    return 0;
}
```

Converters/default expressions should only compute and allocate values: they
must not mutate database rows or perform external I/O. Such external effects
cannot be rolled back. No implicit text/number conversion or guessed rename
is performed. Old binaries do not automatically understand newly reconciled
schemas; deploy applications against the same desired declaration.

Matching schemas do not load checkpoint rows. Reconciliation loads and
rebuilds affected tables in memory and appends their
replacement to the same file. All replacements together must fit the 16 MiB
transaction limit; an oversized update fails without publishing a partial
schema. Existing captured rows/results retain their old layout until released;
use new getters only with rows fetched after reconciliation.

## Building rows

```text
flexdb_begin(db);
let values = Person_values(db, "Puppy", 28, flexdb_int(db, 1));
let id = flexdb_insert(people, values);
flexdb_commit(db);
```

`Person_values(arena, fields...)` builds the typed value list in stored field
order. The virtual ID takes no argument. Non-null integers/reals/text take
raw words/string pointers; a non-null blob takes pointer and byte count.
Nullable fields take a FlexDB value handle such as `flexdb_null(arena)` or
`flexdb_int(arena, value)`, distinguishing null from zero and empty strings.
The arena may be the database or a query arena. Insert/update retain their
runtime type checks.

## Reading fields and compiling queries

```text
extend "libs/db/compile.flex" with "adult";
extend "libs/db/compile.flex" with "by_id";

fn adult(person, minimum) {
    return Person_age(person) >= minimum;
}

fn by_id(person, id) {
    return Person_id(person) == id;
}
```

Put all `extend` declarations in the module header with imports. Syntax hooks
run before predicate compilation, regardless of declaration order. The query
extension generates `adult_query(q, people, minimum)` and
`adult_count(people, minimum)`, using a fused scan. `by_id` uses a primary-key
seek: the compiler proves the generated ID accessor reads the row ID.

Each stored field generates:

| Helper | Result |
| --- | --- |
| `Person_age(row)` | Raw integer, f64 bits, text pointer or blob pointer |
| `Person_age_column()` | Stored column index |
| `Person_age_value(row)` | Typed FlexDB value handle |
| `Person_team_id_is_null(row)` | Null test, for nullable fields |
| `Person_data_bytes(row)` | Byte length, for blob fields |

A declared `rowid` generates its raw getter only. A nullable getter returns
zero for null; test `_is_null` to distinguish null from integer zero.
Accessors require a live row of the corresponding schema. They are ordinary
pure functions, not checked native struct types.

Reconciliation can share unchanged database-owned immutable values between row
versions. Converter results and blob defaults are copied into database ownership
before use, so reused or caller-owned buffers do not become borrowed storage.
Schema replacements retain existing captured rows until database close and remain
transactional. This avoids copying unchanged payloads and building temporary
vectors solely for validation.

The initial DSL covers tables, types, nullability and the implicit primary ID.
Index declarations, foreign keys, uniqueness, automatic table renames/removal
and `person.age` field syntax are not implemented yet.

[The complete example](examples/schema.flex) creates/reopens a database and
prints adults using generated getters and compiled predicates:

```sh
./build/flex libs/db/examples/schema.flex -o build/flexdb-schema
./build/flexdb-schema build/schema.db
```
