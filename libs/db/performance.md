# FlexDB versus SQLite

## Broader roadmap comparison (2026-10-14)

The latest [roadmap results](benchmark-results.md#bulk-checkpoint-packing-2026-10-14)
contain 355 timing comparisons / 24 scenarios, five measured rounds plus warmup:
**279 FlexDB wins, 57 within 10%, 19 SQLite wins**, using a >10% timing margin.
Schema-specific bulk sizing/packing emitted in Flexscript preserves CP03 bytes
and IEEE checksums. The 100K-row checkpoint/close takes 21.62 ms versus 33.35 ms
in the fresh pre-change storage run; SQLite still takes 9.64 ms in the full run.
First scans and integrity remain losses, and memory/file size need work.
See [current tables](benchmark-checkpoint-pack.md) and the
[previous index-build/scan snapshot](benchmark-index-scan.md).

## Earlier comparison after adaptive indexes (2026-10-14)

Re-ran both benchmark drivers on the current FlexDB source: 100,000 rows,
five alternating measured runs after an excluded warmup, one pinned Ryzen 9
5900X CPU, warm OS cache. SQLite 3.53.4 uses native C `-O3`, prepared statements,
NOMUTEX, WAL and FULL synchronization. FlexDB uses native compiled Flexscript;
both run on the same filesystem. All workload result checks passed.

General workload, using reusable FlexDB inputs and no secondary index on either
engine (milliseconds; lower is better):

| Operation | FlexDB | SQLite WAL |
| --- | ---: | ---: |
| Insert 100,000 rows in one durable transaction | 39.703 | 39.711 |
| 100,000 primary-ID lookups | 10.466 | 32.648 |
| 100 count scans | 111.610 | 209.134 |
| 20 materialized scans | 43.170 | 74.911 |
| 1,000 updates in one durable transaction | 9.317 | 9.035 |
| 100 individual durable updates | 503.750 | 503.777 |
| Close including checkpoint work | 32.552 | 10.638 |
| Reopen plus first lookup | 0.070 | 0.231 |
| First complete count scan after reopen | 37.768 | 3.432 |

Fresh FlexDB input construction raises insertion time to 54.981 ms. The prepared
path avoids those extra application-side allocations. General-workload final
files are 9,295,066 versus 2,514,944 bytes; whole-process peak RSS is 23,036 versus
7,588 KiB. FlexDB retains append history; these files were not compacted.

Secondary equality index workload, unique integer keys:

| Operation | FlexDB | SQLite WAL |
| --- | ---: | ---: |
| 100 equality counts before indexing | 136.453 | 192.159 |
| Automatic learning/build vs explicit durable index creation | 12.748 | 24.870 |
| 100,000 indexed equality counts | 20.486 | 40.193 |
| 1,000 indexed-field updates in one durable transaction | 9.443 | 6.253 |
| Publish checkpoint and close | 35.236 | 11.746 |
| Reopen plus first indexed lookup | 0.139 | 0.282 |

Indexed reads are **1.96× faster** in this run. SQLite is **1.51× faster** for
indexed-field updates and **3.00× faster** for checkpoint/close. Bulk inserts
and individual durable writes in the general workload are effectively tied;
SQLite remains about **11× faster** for the first full scan after reopen.

FlexDB builds on the fifth lookup and allocates 4 MiB of hash buckets. Each
reopen decoded exactly one row. The learning/build phase includes FlexDB's
preliminary scans, but persists its buckets only in the later checkpoint;
SQLite's `CREATE INDEX` is durable before its build timer ends. Those phase
costs therefore differ. Checkpoint/close is measured separately for both, and
should be included when evaluating a complete workload. Setup, compilation,
initial inserts and query preparation are excluded from the equality timings.

The equality workload's final files are 9,054,208 versus 2,322,432 bytes;
whole-process peak RSS is 24,216 versus 8,800 KiB. These are RAM hash caches
versus cached disk B-trees, with different layout and retained history. Results
cover one connection and RAM-fitting warm workloads. They do not establish
SQLite's concurrency, feature coverage or crash-safety maturity for FlexDB.

Raw reports (ignored generated artifacts):
`build/flexdb/bench/100000-current-comparison.json` and
`build/flexdb/bench/100000-auto-current-comparison.json`. The latter driver now
also measures maintained-index writes, checkpoint/close, file size and RSS.

## 2026-10-14: persisted checkpoints and lazy startup

100,000 rows on the same Ryzen 9 5900X. Five alternating measured runs after one excluded warmup, one pinned CPU, warm OS cache. The driver now includes checkpoint/close and first-scan cost, rather than reporting only the faster open. Both engines retain durable synchronization.

| Workload (ms; lower is better) | FlexDB fresh | FlexDB reusable inputs | SQLite DELETE | SQLite WAL |
| --- | ---: | ---: | ---: | ---: |
| Insert 100,000 rows, one durable transaction | 54.813 | 39.032 | 51.206 | 39.945 |
| 100,000 ID lookups, cached | 11.013 | 9.941 | 32.500 | 32.541 |
| 100 count scans, cached | 120.610 | 109.187 | 208.372 | 210.235 |
| 20 materialized scans, cached | 44.594 | 42.468 | 75.035 | 75.309 |
| 1,000 batch updates | 9.283 | 9.354 | 24.275 | 8.964 |
| 100 individual durable updates | 502.044 | 502.352 | 2031.449 | 508.456 |
| Close, including checkpoint work | 34.377 | 32.743 | 0.300 | 10.813 |
| Reopen and first lookup | 0.069 | 0.069 | 0.125 | 0.257 |
| First full count scan after reopen | 37.677 | 37.628 | 3.376 | 3.320 |

Reopen plus one lookup improved from the previous reusable-input median of 31.464 ms to 0.069 ms. The SQLite WAL comparator measured 0.257 ms. This avoids replaying the entire history or materializing every row before the first lookup.

Work is deferred, not removed: the first full FlexDB scan after reopen takes about 37.6 ms versus SQLite WAL's 3.3 ms. Checkpoint creation at close takes about 32.7 ms versus SQLite WAL's 10.8 ms close/checkpoint. The already-loaded scans/lookups remain faster here, while reusable-input inserts and durable writes stay close.

Before compaction the generated FlexDB file is 9,295,050 bytes, retaining its append history and the checkpoint. An illustrative single compaction run reduced a copy to 5,403,357 bytes (about 42% smaller) in about 79 ms, preserving values and IDs. This is not a repeated compaction benchmark. SQLite's final file was 2,514,944 bytes. Whole-process peak RSS was approximately 22.6 MiB for reusable-input FlexDB versus 7.2 MiB for SQLite WAL in this run.

Checkpoints validate metadata at open, directory pages and rows before use. `flexdb_integrity(db)` reads remaining current-state data; superseded historical bytes are outside current-state validation. A truncated optional checkpoint can recover from the previous committed log; an incomplete mandatory base in a compacted file fails without rewriting it. Atomic compaction holds the original and replacement inode locks across rename. The format and OS crash-safety validation remain experimental.

New APIs: `flexdb_checkpoint(db)`, `flexdb_integrity(db)`, `flexdb_compact(db)`. Ordinary `open_flexdb`/schema-generated opens use the checkpoint automatically; idle close auto-checkpoints after 64 KiB of new log. Metadata/row directory mapping is lazy, but decoded rows have no eviction yet. Explicit checkpoints/compaction currently have a 16 MiB snapshot bound; an oversized automatic checkpoint is skipped safely.

Raw report for this run: `build/flexdb/bench/100000-checkpoint.json`. Run the driver below to reproduce; it now records `close_checkpoint_ns` and `first_scan_ns` in every sample.

## 2026-10-13 baseline

Measured locally on 2026-10-13, AMD Ryzen 9 5900X, one pinned CPU. Native Flexscript versus C `-O3` using the installed SQLite library. Warm OS cache; one excluded warmup and alternating execution order. Medians of seven measured runs at 50,000 rows and five at 100,000 rows.

SQLite version: `3.53.4 2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e0945alt1 (64-bit)`.

Both engines retain durable synchronization: FlexDB fsyncs every commit; SQLite uses `synchronous=FULL`. SQLite is measured with DELETE and WAL journals, prepared statements, NOMUTEX, a 64 MiB cache budget, and a read transaction around repeated reads. Setup, statement preparation, compilation, close/checkpoint, and initial schema creation are outside the timed operations. Files are on the same local filesystem.

FlexDB has two input styles: **fresh** constructs typed input values per row; **prepared** reuses a caller-owned input vector/scalar handle (its copied stored rows remain immutable). SQLite reuses prepared statements and input bindings. The prepared path is the closest input preparation comparison. Both styles use the same FlexDB engine.

## 50,000 rows

| Workload (milliseconds; lower is better) | FlexDB fresh | FlexDB prepared | SQLite DELETE | SQLite WAL |
| --- | ---: | ---: | ---: | ---: |
| Insert all rows, one durable transaction | 30.414 | 22.801 | 35.421 | 22.530 |
| 100,000 primary-ID lookups | 9.459 | 6.235 | 29.519 | 29.444 |
| 100 count scans, age >= 50 | 61.323 | 56.586 | 103.778 | 103.447 |
| 20 materialized matching-row scans | 23.337 | 22.035 | 37.283 | 37.482 |
| 1,000 updates, one durable transaction | 5.724 | 5.656 | 24.264 | 8.975 |
| 100 individual durable updates | 506.162 | 501.859 | 2023.672 | 506.167 |
| Reopen and first ID lookup | 16.532 | 16.532 | 0.122 | 0.255 |

| Resource | FlexDB fresh | FlexDB prepared | SQLite DELETE | SQLite WAL |
| --- | ---: | ---: | ---: | ---: |
| Final database file (MiB) | 1.90 | 1.90 | 1.19 | 1.19 |
| Whole-process peak RSS (MiB) | 18.22 | 10.91 | 9.10 | 10.07 |

## 100,000 rows

| Workload (milliseconds; lower is better) | FlexDB fresh | FlexDB prepared | SQLite DELETE | SQLite WAL |
| --- | ---: | ---: | ---: | ---: |
| Insert all rows, one durable transaction | 54.438 | 39.016 | 50.197 | 39.594 |
| 100,000 primary-ID lookups | 10.771 | 8.890 | 32.585 | 32.697 |
| 100 count scans, age >= 50 | 123.077 | 113.606 | 208.614 | 208.753 |
| 20 materialized matching-row scans | 46.037 | 43.377 | 76.069 | 75.311 |
| 1,000 updates, one durable transaction | 9.280 | 9.160 | 24.485 | 8.940 |
| 100 individual durable updates | 502.934 | 502.969 | 2027.984 | 503.747 |
| Reopen and first ID lookup | 31.285 | 31.464 | 0.124 | 0.281 |

| Resource | FlexDB fresh | FlexDB prepared | SQLite DELETE | SQLite WAL |
| --- | ---: | ---: | ---: | ---: |
| Final database file (MiB) | 3.71 | 3.71 | 2.40 | 2.40 |
| Whole-process peak RSS (MiB) | 34.73 | 20.14 | 8.31 | 7.10 |

## What changed

Initial 50,000-row fresh-input FlexDB baseline: 159.5 ms inserts, 31.4 ms lookups, 47.7 ms materialized scans, 12.6 ms batch updates, 604.4 ms individual durable updates, and 124.4 ms reopen. Fresh-input inserts now take about 30 ms; reusable inputs about 23 ms.

Optimizations preserve transaction checks and durability: slicing-by-eight IEEE CRC32; bounded word copies; direct vector word writes; packed row/value allocations; validation, packing and log encoding in one pass; dense-ID lookup and cached table ordinals; row-level undo instead of whole-index copies; schema-typed consecutive insert batches; and reusable bounded replay decoding scratch space. New readers retain support for the original upsert record encoding. Older binaries do not understand the new insert-batch opcode.

The current prepared path matches SQLite WAL bulk inserts and individual durable writes within the observed small differences, while lookups/scans are faster here. At 100,000 rows, batch-update medians differ by about 2.5%. Fresh input construction still leaves bulk inserts about 35–38% behind WAL. Startup remains much slower: FlexDB rebuilds all live rows/indexes from its append log; SQLite loads pages as needed. Closing/checkpoint work is excluded for both engines, and the final SQLite file size is measured after its WAL is checkpointed on close.

This is a small, fixed-query, RAM-fitting benchmark, not overall SQLite feature/performance parity. No secondary age index, join benchmark, concurrent workloads, cold-cache tests, long update history, or database larger than RAM. FlexDB has no page cache/compaction and retains old allocations until close. SQLite cache configuration is a budget, not memory actually used. Peak RSS includes the benchmark process and its input/output allocations, not just the database engine. FlexDB has much less crash-safety validation than SQLite; FULL/fsync settings do not establish equivalent maturity.

## Reproduce

```sh
mkdir -p build/flexdb/tmp
./build/flex scripts/benchmark-flexdb.flex -o build/flexdb/benchmark
TMPDIR="$PWD/build/flexdb/tmp" ./build/flexdb/benchmark ./build/flex 50000 7 build/flexdb/50000.json
TMPDIR="$PWD/build/flexdb/tmp" ./build/flexdb/benchmark ./build/flex 100000 5 build/flexdb/100000.json
```

The JSON includes every sample (including the excluded warmup), medians, CPU ID, SQLite version, and workload description. SQLite development headers/library and a C compiler are needed only for the comparator. The driver creates isolated database files and preserves them for inspection.

Correctness verification: `scripts/test-flexdb.flex` passes all storage, predicate, schema, reconciliation and fast-path suites. Fast paths include comparison against an independent bitwise CRC reference, guarded unaligned copies, repeated undo plus index growth/schema replacement, interleaved batches/updates/deletes, 64-column null masks, legacy records, and interrupted/corrupt transaction recovery.

## Adaptive equality indexes (2026-10-14)

100,000 rows with unique `i64` secondary keys, five alternating runs after an
excluded warmup, one pinned Ryzen 9 5900X CPU, native Flexscript versus C `-O3`
and SQLite 3.53.4. Each query counts matches for a changing key and verifies
its result. SQLite uses prepared statements, NOMUTEX, WAL/FULL synchronization,
a 64 MiB cache budget, and one read transaction for repeated queries.

| Operation | FlexDB (ms) | SQLite (ms) |
| --- | ---: | ---: |
| 100 equality counts without an index | 126.688 | 190.832 |
| Learning/build phase | 12.831 | 11.948 |
| 100,000 indexed equality counts | 19.420 | 39.183 |
| Reopen plus first indexed lookup, warm OS cache | 0.105 | 0.139 |

FlexDB chose and built its index on the fifth query, with 4 MiB of buckets.
Its learning/build time includes the preliminary scans. SQLite explicitly
creates a persistent B-tree index; its build time includes durable `CREATE INDEX`.
FlexDB's indexed counts are **2.02× faster in this workload**. This compares a
RAM hash cache with a disk-page B-tree, not equivalent engine designs or overall
SQLite parity. The per-query scan-to-index improvement is approximately 6,500×
for this large, unique-key table; that number does not apply to broader predicates.

Every measured FlexDB reopen decoded exactly one row for its first lookup;
it reused persisted mapped index pages. Setup, bulk insertion, compilation,
query preparation and FlexDB checkpoint publication are outside these timings.
The query loops include FlexDB's learning/expiry bookkeeping and SQLite's bind,
step and reset calls. This is warm, single-connection, RAM-fitting equality work;
updates, duplicate-heavy keys, cold storage and ranges need separate comparisons.

Reproduce with:

```sh
./build/flex scripts/benchmark-flexdb-auto.flex -o build/flexdb/benchmark-auto
TMPDIR="$PWD/build/flexdb/tmp" ./build/flexdb/benchmark-auto ./build/flex 100000 5 build/flexdb/auto-report.json
```

The driver preserves all samples, medians, SQLite version, affinity and the
isolated work directory in JSON. The initial report is
`build/flexdb/bench/auto-report.json` (ignored generated artifact).
