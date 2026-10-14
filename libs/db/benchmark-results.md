# FlexDB roadmap versus SQLite: measured results

Measured 2026-10-14 on an AMD Ryzen 9 5900X, one pinned CPU. **24 scenario
configurations, 355 timed comparisons, five measured runs per engine plus an
excluded warmup**. Every case's operation count and result checksum matched
between engines in every round. These are representative variants related to
**49 of the 75 roadmap targets**, including resource measurements; no target's
entire variation matrix is claimed complete.

The baseline engines ran serially, with alternating order. Its three execution batches
finished before the next began. Native Flexscript is compared with C `-O3`,
SQLite 3.53.4, NOMUTEX, WAL/FULL and a 64 MiB default SQLite cache. Dataset sizes
are 1K/10K/100K rows, text lengths 8/32/256 bytes, duplicate counts 1/10/100/1,000,
and null fractions 0/10/50/90%. I/O counters confirm these are warm OS-cache
workloads: measured physical read-byte counters were zero. This is not a
physical-cold, concurrent or larger-than-memory comparison.

## Bulk checkpoint packing (2026-10-14)

Checkpoint construction now uses schema-specific sizing and row-packing loops
emitted in Flexscript for tables of at least 128 rows. The writer consumes owned
RAM rows after remaining mapped rows are validated/hydrated, checks each buffer
bound, emits the exact existing CP03 image and calls the same IEEE CRC helper.
Temporary code changes from RW to RX and is released after each call. Small
tables and unavailable native code retain the ordinary Flexscript path.
Large disjoint copies have a bounded REP MOVSB entry; arena cleanup combines
exactly adjacent owned blocks, preserving intervening mappings and row lifetimes.

The full run has **279 FlexDB timing wins, 57 within 10%, and 19 SQLite
wins** across the same 355 comparisons and 24 scenarios, five measured rounds
plus excluded warmup. All 2,130 cross-engine raw case pairs, timing/resource
median and range aggregates, and preserved worker hashes were checked. These are
>10% classifications of sample medians, not statistical significance or full
75-target coverage. Resources are separate, and older snapshots remain below.

| Scenario / case | Previous full FlexDB ms | Current full FlexDB ms | Current SQLite ms |
| --- | ---: | ---: | ---: |
| lifecycle_100k / checkpoint_close | 31.639925 | 21.623147 | 9.641123 |
| read_100k / final_close | 33.853219 | 21.305732 | 11.842441 |
| text256_10k / final_close | 11.911962 | 10.071731 | 0.897856 |
| lifecycle_100k / compaction | 33.434603 | 25.197188 | 50.332295 |
| recovery_10k / final_close | 11.658669 | 10.506038 | 10.187603 |
| lifecycle_100k / session_total | 225.982524 | 204.786659 | 252.093102 |
| lifecycle_100k / first_full_scan | 13.847702 | 17.078950 | 3.545041 |
| lifecycle_100k / integrity | 37.851311 | 38.518794 | 20.045711 |

A fresh pre-change storage run measured 33.35 ms
for 100K-row checkpoint/close; the full current run measures
21.62 ms (about 35% less time).
SQLite still takes 9.64 ms. A separate diagnostic
fixture puts capacity sizing near 0.3 ms, row packing near 4.2 ms, index emission
near 3 ms, and checkpoint writes/fsync near 11 ms; these diagnostic figures are
not substituted for full matched benchmark rows. Stored footprint and I/O now
limit further checkpoint gains. Lifecycle final file sizes are 12,187,001 bytes
for FlexDB versus 6,017,024 for SQLite; peak RSS is 49,536 versus 20,080 KiB.

First-scan latency remains variable and lost again in this run, and integrity is
still slower. The broad win/loss count also moves with unrelated timing variation;
it does not mean every changed classification was caused by the writer.
Memory use and file size have not been solved by this optimization.

Checks pass: 1,005 core checks plus 77 harness checks, including complete native
versus fallback checkpoint-image parity, exact sizing, 1..64 mixed columns,
nullable high-bit fields, tombstones, extreme scalar values and binary payloads,
every short buffer ending at a guard page, oversized field/total payload rejection,
reopen/compaction, native/fallback large-copy bounds and adjacent-arena release
without unmapping another owner's gap. Existing torn-prefix and corruption checks
also pass. No stored-format or API ownership/lifetime change was introduced.

See [full current timing/resource tables](benchmark-checkpoint-pack.md). Next
work remains denser storage/index representation, first-read and integrity costs,
retained memory, and the remaining schema/adaptive/roadmap variants. The full
all-metric objective is unfinished.

## Index construction and native validation scan (2026-10-14)

Duplicate-heavy builds can now use a temporary successor array with path
compression to find the next empty probing slot directly. It preserves the exact
bucket image/order of ordinary insertion and the CP03 format. Construction is
still bounded by the existing row/time limits; scratch is released on success
or abandonment. Observed duplicate matches select the strategy, while unique
builds retain their direct path. Peak scratch memory remains a separate cost.

First integer count scans over checkpoints now can use a schema-specific x86-64
scanner emitted in Flexscript. It preserves the complete directory/row CRC,
null-mask, required-field, length, row-bound and final-encoding checks, including
unrelated fields. RAM rows are skipped and continue to override the view.
The code uses base x86-64 instructions, transitions RW to RX, calls the existing
IEEE CRC helper and is released after filling the view. Failure to obtain
executable memory uses the Flexscript fallback.

The full snapshot contains **275 timing wins, 50 within 10%, 30 SQLite
wins** across the same 355 comparisons / 24 scenarios, five measured rounds
plus warmup. Every checksum/operation count, timing/resource aggregate and both
worker hashes were verified. These counts exclude resource metrics and do not
prove all roadmap targets or every variation. Prior snapshots remain below.

| Scenario / case | FlexDB before ms | FlexDB now ms | SQLite now ms |
| --- | ---: | ---: | ---: |
| duplicates10_10k / learn_integer | 1.346346 | 1.275290 | 8.689133 |
| duplicates100_10k / learn_integer | 3.938996 | 1.230918 | 8.797714 |
| duplicates1000_10k / learn_integer | 29.483225 | 1.109567 | 8.779155 |
| read_10k / learn_integer | 1.055200 | 1.070507 | 11.371074 |
| lifecycle_100k / first_full_scan | 15.482177 | 13.847702 | 3.495114 |
| lifecycle_100k / cached_full_scan | 0.923118 | 1.432052 | 2.265564 |
| lifecycle_100k / checkpoint_close | 30.316931 | 31.639925 | 9.379804 |
| lifecycle_100k / integrity | 37.723423 | 37.851311 | 20.224550 |

The duplicate-build gap is closed in these measured variants. First-scan latency
is still a loss and varies substantially. A focused run of the identical worker
binary had a 7.44 ms median, whereas this full run has 13.85 ms; raw samples range
roughly 6–18 ms. The full snapshot is retained as current evidence rather than
choosing the faster subset. A diagnostic run added CPU time, page-fault and
context-switch counters outside the timed interval: samples took 7.59–18.17 ms
CPU time, had 620 minor faults and zero major faults. Descheduling alone does not
explain the spread. The diagnostics are in `roadmap-scan-diagnostics.json`.

Tests pass: 1,005 core checks plus 76 harness checks, including exact successor
bucket parity across collisions/wrap, deadline fallback, 64 mixed columns,
nullable/required high-bit columns, extreme integers, multi-page directories,
tombstones, known RAM rows, native/Flexscript view parity, corruption with valid
CRCs and a row ending immediately before an inaccessible page. Source data and
stored row ownership/lifetimes remain unchanged.

See [all current tables and resource measurements](benchmark-index-scan.md).
Next work is still checkpoint/close and integrity cost, first-scan variation and
remaining latency, schema/adaptive cases, retained memory and file size. The
all-metric objective remains active.

## Transaction and field-reader optimization (2026-10-14)

Empty transactions now defer log allocation and rollback snapshots until the
first mutation. Small completed transaction arenas are reused with a one-block
64 KiB limit; larger arenas are released. Snapshot preparation still precedes
logical mutation under the existing exclusive lock. Invalid/empty commits append
no bytes, and stored rows/input-value ownership does not change.

The predicate extension also simplifies proven field-reader functions used by
ordinary application code. It checks actual cell/word definitions and follows
known helper chains, preserves the row-width check, and refuses unknown/effectful
calls or extra field reads. The common primary-ID path performs the same
connection, ID and deletion checks directly, retaining lazy decoding and the
binary-search fallback. The SUM benchmark's application loop and SQLite query
are unchanged; no aggregate API or special benchmark-only result shortcut was added.

Re-ran **all 24 scenarios / 355 comparisons**, five measured runs after warmup,
with alternating order and equal operation counts/checksums: **273 FlexDB wins,
53 within 10%, 29 SQLite wins** using the same >10% timing margin.
All raw comparisons, timing/resource aggregates and worker hashes were verified.
Stricter compile-time proof checks added afterward produce the identical
benchmark worker SHA-256, so these timings apply to the emitted current code.

| Scenario / case | Operations | FlexDB before ms | FlexDB now ms | SQLite now ms |
| --- | ---: | ---: | ---: | ---: |
| write_10k / empty_transactions | 200 | 2.243640 | 0.007680 | 0.067432 |
| read_1k / aggregate_sum_loop | 20 | 0.596860 | 0.278636 | 0.459219 |
| read_10k / aggregate_sum_loop | 20 | 6.081958 | 2.873695 | 4.505757 |
| read_100k / aggregate_sum_loop | 20 | 60.887215 | 28.916377 | 45.819763 |
| read_100k / id_sequential | 100,000 | 2.962683 | 1.613041 | 22.870400 |
| read_100k / id_random | 100,000 | 6.801691 | 5.036297 | 33.170599 |
| write_10k / rollback_mixed_1002 | 1,002 | 0.844045 | 0.837757 | 0.846416 |
| write_10k / update_indexed_field | 1,000 | 6.269031 | 6.283600 | 6.309441 |
| recovery_10k / first_equality_after_tail | 1 | 0.001180 | 0.001130 | 0.007110 |
| lifecycle_100k / first_full_scan | 1 | 15.986472 | 15.482177 | 3.369734 |
| lifecycle_100k / checkpoint_close | 100,000 | 31.380884 | 30.316931 | 9.478421 |

At 100K rows the ordinary SUM loop is 1.58× faster than
SQLite in this run. The 200 empty transactions are 8.78× faster.
These are measured variants, not claims about arbitrary aggregate expressions
or all SQLite transaction semantics. The 29 timing losses and resource gaps
remain visible in the [current complete tables](benchmark-current.md).

Tests pass: 1,005 core checks plus 75 harness checks, including repeated pooled
undo/snapshot reuse, invalid commands followed by empty commit, nested begin,
immutable captured rows, active close, durability/replay, prior reader overrides,
effectful readers and retained unproven calls/additional field checks. The original
sources are not edited by the compiler transformations.

Next work remains storage serialization/first validated scans/integrity,
duplicate-heavy index construction, some adaptive/schema cases, retained memory
and file size. The full objective is still active. Earlier snapshots below are
preserved as historical evidence.

## Replay index optimization (2026-10-14)

Transaction replay now maintains restored equality indexes through the same
maintenance path as live commits. A first edit creates a sparse writable bucket
array; each accessed logical 4 KiB page is CRC-checked and copied from the
read-only source before use. Untouched pages remain in the source mapping.
Full checkpoint writes and index integrity checks validate/copy remaining pages.
The index budget still accounts for the full logical capacity.

The first query after replay no longer rebuilds the entire index/table. Complete
frame validation precedes replay, edits invalidate count memos, schema replacements
clear indexes, and capacity exhaustion safely drops only a derived cache.
A maintenance CRC failure remains a poisoned connection, including after fsync.
Failed-open cleanup also suppresses checkpointing of partially replayed state.

Re-ran **all 24 scenarios / 355 comparisons**, five measured runs after warmup,
with alternating order, matched operation counts and result checksums. Independently
verified every timing/resource aggregate and both worker hashes: **258 FlexDB
wins, 57 within 10%, 40 SQLite wins**, with the same >10% margin. Timing-row
counts vary across runs and do not imply wins on resource metrics or complete
coverage of every roadmap target.

All values below are total median milliseconds for the same case/operation count.
The two recovery rows should be considered together, followed by close/session
costs, so deferred work is visible.

| Scenario / case | FlexDB before ms | FlexDB now ms | SQLite now ms |
| --- | ---: | ---: | ---: |
| recovery_10k / process_exit_recovery | 0.103652 | 0.124933 | 0.412837 |
| recovery_10k / first_equality_after_tail | 3.101071 | 0.001180 | 0.007010 |
| recovery_10k / final_close | 9.017808 | 12.869167 | 13.030560 |
| recovery_10k / session_total | 12.403614 | 13.199532 | 13.455758 |
| lifecycle_100k / mapped_first_write | 10.690216 | 10.882352 | 16.483391 |
| lifecycle_100k / mapped_later_write | 6.427686 | 6.897022 | 6.334351 |
| lifecycle_100k / checkpoint_close | 31.392308 | 31.380884 | 9.739472 |
| lifecycle_100k / first_full_scan | 15.125139 | 15.986472 | 3.498361 |
| lifecycle_100k / integrity | 35.659547 | 38.082162 | 19.994583 |

The first post-replay lookup is 5.94× faster than SQLite in this variant.
The sum of the reported recovery and first-query medians is 0.126113 ms versus
0.419847 ms (3.33×); this is a sum of phase medians, not a separately
sampled combined latency. Whole-session costs remain within 10% here. Single-query
microsecond results include timer overhead and are based on five trials; the
raw ranges are retained. A separate focused lifecycle/recovery run reproduced
the first-query improvement (`roadmap-replay.json`).

Current storage gaps remain: full checkpoint/first-scan/integrity work, some
schema rewrites, application SUM loops, memory retention and file size. The
unchanged cases and unfavorable results remain in the
[complete latest timing/resource tables](benchmark-replay.md). Earlier broad
results below are preserved rather than overwritten.

The correctness suite passes 1,005 core checks plus 71 harness checks and the
additional replay fixtures: sparse copies, source/captured-row immutability,
rollback, integer/text duplicates, updates, deletes, typed batches, capacity
exhaustion, compaction/reopen, corrupt touched/untouched pages, post-fsync poisoning,
and valid-CRC semantic failures that must leave the source file unchanged.

## Initial broad optimization pass (2026-10-14)

Re-ran all **24 scenarios and 355 timing comparisons** with the changes below,
five measured runs per engine after an excluded warmup, alternating engine order
on the same pinned CPU. Every raw result checksum and operation count matched;
all median/min/max statistics and both worker hashes were independently verified.
Using the same >10% presentation margin: **262 FlexDB wins, 48 within 10%,
45 SQLite wins**. These counts concern timing rows, not all resource metrics or
all 75 roadmap targets. They are not a statistical significance claim.

| Scenario / case | Operations | FlexDB before ms | FlexDB now ms | SQLite now ms | Current result |
| --- | ---: | ---: | ---: | ---: | --- |
| read_100k / id_random | 100,000 | 6.693 | 6.638 | 34.016 | FlexDB 5.12× |
| read_100k / integer_hit | 10,000 | 2.032 | 1.790 | 4.156 | FlexDB 2.32× |
| text32_utf8_10k / text_hit | 10,000 | 4.129 | 2.137 | 4.216 | FlexDB 1.97× |
| text256_10k / text_hit | 10,000 | 16.548 | 4.720 | 6.188 | FlexDB 1.31× |
| text256_collision_1k / text_hit | 10,000 | 10964.935 | 4.294 | 4.391 | Within 10% |
| duplicates10_10k / integer_hit | 10,000 | 7.916 | 2.234 | 4.839 | FlexDB 2.17× |
| duplicates1000_10k / integer_hit | 10,000 | 575.063 | 1.015 | 167.369 | FlexDB 164.95× |
| duplicates1000_10k / integer_miss | 10,000 | 28.179 | 0.593 | 1.957 | FlexDB 3.30× |
| read_100k / integer_materialized | 100 | 1.162 | 0.052 | 0.108 | FlexDB 2.06× |
| read_100k / offset_page_middle | 10 | 33.855 | 3.601 | 10.319 | FlexDB 2.87× |
| join_unique_1k / self_join | 1 | 27.068 | 0.291 | 0.559 | FlexDB 1.92× |
| join_duplicates10_1k / self_join | 1 | 28.233 | 1.388 | 2.368 | FlexDB 1.71× |
| lifecycle_100k / checkpoint_close | 100,000 | 53.224 | 31.392 | 9.564 | SQLite 3.28× |
| lifecycle_100k / first_full_scan | 1 | 63.670 | 15.125 | 3.397 | SQLite 4.45× |
| lifecycle_100k / cached_full_scan | 1 | 1.447 | 0.946 | 2.229 | FlexDB 2.36× |
| lifecycle_100k / compaction | 100,000 | 55.454 | 33.257 | 48.632 | FlexDB 1.46× |
| schema_10k / schema_add_nullable | 10,000 | 17.086 | 13.331 | 5.163 | SQLite 2.58× |
| schema_10k / schema_convert | 10,000 | 19.182 | 15.432 | 12.186 | SQLite 1.27× |
| churn100_1k / churn_total | 102,000 | 1627.389 | 696.176 | 650.010 | Within 10% |
| recovery_10k / first_equality_after_tail | 1 | 5.249 | 3.101 | 0.007 | SQLite 447.48× |

The changes are complete-key text hashing and bounded wide string comparisons;
conservative integer index bounds for out-of-range misses; bounded exact-key
integer count memos; backward-shift bucket deletion; one reusable small query
arena; proven getter/comparison inlining; generated `predicate_page` scans;
ordered hash joins; preallocated checkpoint construction; direct owned row
decoding; validated scalar views for integer counts; schema replacement that
shares immutable database-owned values; and an IEEE CRC32 loop emitted in
Flexscript as native x86-64 instructions, with the original portable fallback.
The main compiler contains no new database-specific code.

The pagination comparison now calls the generated page function, whereas the
baseline materialized a full filtered relation before limiting it. Both return
the same ordered page. Duplicate-count speedups include a bounded memo of exact
counts: the first lookup, invalidation, maintenance and rebuild are separate
costs, not a claim that every cold duplicate query is equally fast. Numeric
bounds can reject out-of-range keys without probing, while reopened indexes with
unknown bounds retain full verified probing. Cached checkpoint counts now can
use a scalar view rather than hydrated rows. First access still validates the
complete row encoding, directory CRC and row CRC, including unrelated fields.
The native CRC helper preserves the existing IEEE polynomial and file checksums;
its initial emission is included in first-checksum/session costs.

CP03 checkpoints persist buckets using the new hash algorithm. CP01/CP02 logical
data remains readable; CP02 buckets with obsolete hash semantics are discarded.
Schemas still preserve captured immutable rows and explicitly authorize lossy
changes. Converter outputs and blob defaults become owned copies. No fsync,
recovery or corruption validation was removed to obtain these results.

See [every latest timing and resource table](benchmark-optimized.md). Raw samples,
ranges, checksums, preserved workers and binary hashes are in
`build/flexdb/bench/roadmap-optimized-final.json` and its accompanying Markdown.
Earlier intermediate passes are retained as `roadmap-optimized-v1.json` through
`roadmap-optimized-v4.json`. The baseline tables below remain historical evidence.

## Baseline representative results (before optimization)

All times are median **milliseconds for the listed number of operations**, not
per-query times. A winner needs a margin over 10%; that margin is a presentation
rule, not a statistical significance test. Median/min/max and every raw sample
are retained in the JSON reports.

| Scenario / case | Operations | FlexDB ms | SQLite ms | Faster |
| --- | ---: | ---: | ---: | --- |
| read_100k / id_random | 100,000 | 6.693 | 33.520 | FlexDB 5.01× |
| read_100k / integer_hit | 10,000 | 2.032 | 4.195 | FlexDB 2.06× |
| text8_10k / text_hit | 10,000 | 2.502 | 3.831 | FlexDB 1.53× |
| text32_utf8_10k / text_hit | 10,000 | 4.129 | 4.158 | Within 10% |
| text256_10k / text_hit | 10,000 | 16.548 | 6.067 | SQLite 2.73× |
| text256_collision_1k / text_hit | 10,000 | 10964.935 | 4.354 | SQLite 2518.50× |
| duplicates10_10k / integer_hit | 10,000 | 7.916 | 4.923 | SQLite 1.61× |
| duplicates1000_10k / integer_hit | 10,000 | 575.063 | 173.548 | SQLite 3.31× |
| read_100k / integer_materialized | 100 | 1.162 | 0.103 | SQLite 11.30× |
| read_100k / offset_page_middle | 10 | 33.855 | 10.338 | SQLite 3.27× |
| join_unique_1k / self_join | 1 | 27.068 | 0.561 | SQLite 48.22× |
| lifecycle_100k / checkpoint_close | 100,000 | 53.224 | 9.529 | SQLite 5.59× |
| lifecycle_100k / first_full_scan | 1 | 63.670 | 3.431 | SQLite 18.56× |
| schema_10k / schema_noop | 1,000 | 0.197 | 2.756 | FlexDB 14.03× |
| schema_10k / schema_add_nullable | 10,000 | 17.086 | 5.122 | SQLite 3.34× |
| mixed50read_10k / mixed_writes_50 | 1,000 | 2509.773 | 2595.797 | Within 10% |
| churn100_1k / churn_total | 102,000 | 1627.389 | 644.363 | SQLite 2.53× |
| recovery_10k / process_exit_recovery | 1 | 0.093 | 0.421 | FlexDB 4.53× |
| recovery_10k / first_equality_after_tail | 1 | 5.249 | 0.007 | SQLite 759.52× |

The earlier unique-key read advantage holds, but it does not generalize to all
queries. Long text keys and many duplicate matches favor SQLite. The deliberately
adverse equal-length text keys sharing their first 64 bytes expose a severe
weakness: FlexDB hashes only that prefix plus length, so these keys share a hash
and trigger full candidate rechecks. The 1K-row collision experiment takes about
11 seconds for 10K lookups versus SQLite's 4.4 ms. This is a measured weakness,
not a claim about normal short-text workloads.

Materialized equality results also cost much more for small outputs: each
FlexDB query creates and frees an independent arena, while SQLite consumes rows
through a reused prepared statement. Both consume ID, key, text length and the
nullable field, in ascending row-ID order. Their output/lifetime APIs differ.
Pagination currently materializes the full FlexDB relation before slicing;
SQLite can apply its LIMIT/OFFSET during query execution. Joins use FlexDB's
nested-loop relation API versus SQLite's selected join plan. Aggregates here are
an application sum loop versus SQLite SUM; they are not optimized FlexDB operators.

Checkpoint and first-scan costs remain significant. Reopening after a committed
tail is initially quick, but the first equality lookup rebuilds the invalidated
FlexDB index; SQLite retains its persistent index. Checkpoint/close must therefore
be included with build/rebuild cost when comparing completed workloads.

Unchanged-schema metadata checks are cheap in FlexDB. SQLite's baseline enumerates
PRAGMA table_info with a prepared statement; it is not a second implementation of
FlexDB's schema-policy engine. Actual schema changes compare equivalent final
columns, values and IDs: FlexDB's reconciliation helpers rewrite current rows;
SQLite uses ALTER TABLE for additions and explicit transactionally rebuilt tables
for reorder/convert. Converter input is nonnegative integers, not arbitrary text.
Schema mismatch/rejection and converter failures remain correctness-only checks.

Mixed runs use 1,000 operations with 5/20/50% individually durable updates and
prebuilt integer indexes; these runs are close and largely synchronization-bound.
Churn performs 100 cycles over 1K live rows, each with 1K indexed updates, ten
removals/reinsertions and one durable commit, with compaction every 25 cycles.
FlexDB retains old arena allocations despite compaction; this is visible in the
RSS progression below.

## Baseline memory growth during churn

| Completed cycles | FlexDB current RSS KiB | SQLite current RSS KiB |
| ---: | ---: | ---: |
| 25 | 9,264 | 4,084 |
| 50 | 16,444 | 4,220 |
| 75 | 23,624 | 4,220 |
| 100 | 30,804 | 4,220 |

## Coverage against all 75 targets

Partial means the listed representative variants ran; unlisted variants and
metrics still need work. Timed process recovery is an exit with a committed
checkpoint/tail and an uncommitted transaction, without calling the library's
close API. It does not test interruption during writes or power loss. Current
memory and I/O measurements cover the complete worker, including setup and
maintenance; disk figures are after close/compaction and exclude unobserved
temporary-file peaks.

| Target | Comparison now available | Remaining scope / limitation |
| --- | --- | --- |
| Q01 (Point reads) | Partial: id_sequential, id_random, id_hot32, id_missing … | Primary-ID lookup: sequential, random, hot keys; existing, missing and deleted IDs; full variants and requested metrics remain |
| Q02 (Equality reads) | Partial: integer_hit, integer_miss | Integer secondary key: unique keys, hits and misses; scan, learning and active index phases; full variants and requested metrics remain |
| Q03 (Equality reads) | Partial: text_hit, text_miss | Text secondary key: 8/32/256-byte keys, long shared prefixes, ASCII and UTF-8; full variants and requested metrics remain |
| Q04 (Equality reads) | Partial: integer_hit, integer_miss, integer_materialized, text_hit … | Duplicate keys: 1/10/100/1,000 matches; count and returned rows; full variants and requested metrics remain |
| Q05 (Equality reads) | Partial: null_scan | Nullable integer/text fields; 0/10/50/90% nulls and explicit null predicates; full variants and requested metrics remain |
| Q06 (Scans) | Partial: scan_matches_0, scan_matches_1, scan_matches_10, scan_matches_100 … | Integer predicates selecting 0/0.01/1/10/50/100% of rows; full variants and requested metrics remain |
| Q07 (Scans) | Not timed in this matrix | Text, blob and real-value predicates; narrow and wide rows; full variants and requested metrics remain |
| Q08 (Scans) | Partial: combined_scan | Multiple predicates: conjunction, disjunction, pure helpers and branches; full variants and requested metrics remain |
| Q09 (Result delivery) | Partial: integer_materialized, text_materialized | Count-only, ID-only, selected fields and complete rows for the same predicate; full variants and requested metrics remain |
| Q10 (Pagination) | Partial: offset_page_middle | First/middle/last pages, offset sizes and limit sizes; ID cursor expressed in code; full variants and requested metrics remain |
| Q11 (Relations) | Partial: self_join | Equality joins: one-to-one, one-to-many and many-to-many; matched/unmatched rows; full variants and requested metrics remain |
| Q12 (Range indexes) | Gated | Integer/text range lookups at several selectivities, with and without indexes; missing capability: range indexes |
| Q13 (Compound indexes) | Gated | Two/three fields; equality plus range; correlated and independent fields; missing capability: compound indexes |
| Q14 (Ordering) | Not timed in this matrix | ORDER BY equivalent, ascending/descending, ties and top-K; full variants and requested metrics remain |
| Q15 (Aggregation) | Partial: aggregate_sum_loop | Sum/min/max/average, distinct, grouped aggregates and aggregate joins; full variants and requested metrics remain |
| Q16 (Combined access paths) | Gated | Intersections/unions across indexed predicates, covering projections and indexed joins; missing capability: compiler/runtime access paths |
| Q17 (Text semantics) | Not timed in this matrix | Prefix/substring search and case-folded comparisons expressed in code; declared binary/Unicode behavior; full variants and requested metrics remain |
| W01 (Bulk inserts) | Partial: insert_reused | Sequential inserts; fresh input values versus reusable builders; full variants and requested metrics remain |
| W02 (Transaction batching) | Partial: insert_batch_1, insert_batch_10, insert_batch_100, insert_batch_1000 | Insert batches of 1/10/100/1,000/10,000 rows, within frame limit; full variants and requested metrics remain |
| W03 (Indexed inserts) | Partial: indexed_insert_batch | Insert into a learned-index table; unique and duplicate keys; trigger capacity exhaustion; full variants and requested metrics remain |
| W04 (Updates) | Partial: update_unindexed_field, update_indexed_field, mapped_first_write, mapped_later_write | Random/sequential updates; unchanged indexed field versus changed indexed field; full variants and requested metrics remain |
| W05 (Durable writes) | Partial: insert_batch_1, insert_batch_10, insert_batch_100, insert_batch_1000 | One insert/update/delete per durable transaction; short and long runs; full variants and requested metrics remain |
| W06 (Variable-size updates) | Partial: grow_text_256, shrink_text_5 | Grow/shrink text or blobs, same-size replacement and nullable transitions; full variants and requested metrics remain |
| W07 (Deletes) | Partial: delete_batch, deleted_id_reads | Random, sequential and bulk deletes; 1/50/90% tombstones; full variants and requested metrics remain |
| W08 (Rollback) | Partial: rollback_mixed_1002 | Insert/update/delete rollback; repeated edits to one row; transactions with reads; full variants and requested metrics remain |
| W09 (Empty transactions) | Partial: empty_transactions | Begin/commit, begin/rollback and rejected nested transactions; full variants and requested metrics remain |
| W10 (Churn) | Partial: churn_cycle_25, churn_compact_25, churn_cycle_50, churn_compact_50 … | At least 100 update/delete/reinsert cycles per live row; periodic compaction; full variants and requested metrics remain |
| W11 (Atomicity across tables) | Not timed in this matrix | Transactions changing 2/10/100 tables; rollback and reopen; full variants and requested metrics remain |
| A01 (Index learning) | Partial: learn_integer, learn_text, budget_0, budget_262144 … | Cold connection: queries 1–100; selective, broad and tiny-table workloads; full variants and requested metrics remain |
| A02 (Automatic versus manual) | Partial: learn_integer, learn_text, budget_0, budget_262144 … | FlexDB automatic indexing versus SQLite unindexed and explicitly indexed configurations; full variants and requested metrics remain |
| A03 (Demand changes) | Partial: mixed_writes_5, mixed_writes_20, mixed_writes_50, switch_to_text … | Selective reads become broad; hot key/column changes; write-heavy intervals; full variants and requested metrics remain |
| A04 (Index budgets) | Partial: budget_0, budget_262144, budget_1048576, budget_4194304 … | 0/256 KiB/1/4/8 MiB budgets; more candidate columns than active-index slots; full variants and requested metrics remain |
| A05 (Build limits) | Partial: learn_integer, learn_text, budget_0, budget_262144 … | Table/byte limits and short time budgets; abandoned build followed by scan; full variants and requested metrics remain |
| A06 (Hash collisions) | Partial: text_hit | Equal-length text sharing first 64 bytes; duplicate-heavy and adverse key distributions; full variants and requested metrics remain |
| A07 (Persisted indexes) | Not timed in this matrix | Reopen with learned buckets; first hit, miss and repeated reads; full variants and requested metrics remain; mapped-index first lookup was measured in the earlier equality runner, not this matrix |
| A08 (Mapped-index writes) | Partial: mapped_first_write, mapped_later_write | First write after reopen versus later writes; indexed/nonindexed field changes; full variants and requested metrics remain |
| A09 (Tail invalidation) | Partial: process_exit_recovery, first_equality_after_tail | Reopen checkpoint plus later inserts/updates/deletes, then query affected indexes; full variants and requested metrics remain |
| A10 (Retirement) | Partial: switch_to_text, return_to_integer | Unused indexes, LRU eviction, capacity exhaustion and reappearance of demand; full variants and requested metrics remain |
| A11 (Omitted caches) | Not timed in this matrix | Checkpoint near size limit omits index buckets but retains usage; full variants and requested metrics remain |
| S01 (Startup) | Partial: reopen_first_id | Open an empty database; schema match on existing database; close/reopen repeatedly; full variants and requested metrics remain |
| S02 (Lazy reads) | Partial: reopen_first_id | First lookup after reopen, then random 1/100/1,000/100,000 lookups; full variants and requested metrics remain |
| S03 (First full scan) | Partial: first_full_scan, cached_full_scan | First complete scan after reopen versus subsequent cached scans; full variants and requested metrics remain |
| S04 (Checkpoint publication) | Partial: final_close, checkpoint_close | Narrow/wide tables; zero/one/four active indexes; unchanged and changed state; full variants and requested metrics remain |
| S05 (Lifecycle total) | Partial: session_total | Create → populate → learn/query → mutate → checkpoint → close → reopen → query; full variants and requested metrics remain |
| S06 (Log replay) | Partial: process_exit_recovery | No checkpoint; checkpoint tails of 0/1K/100K transactions; old update history; full variants and requested metrics remain |
| S07 (Compaction) | Partial: compaction, churn_compact_25, churn_compact_50, churn_compact_75 … | Different history/live-data ratios and tombstone fractions; repeat compaction; full variants and requested metrics remain |
| S08 (Integrity) | Partial: integrity | Fully cached and lazy data; indexed/unindexed; increasing database size; full variants and requested metrics remain |
| S09 (Storage footprint) | Partial: compaction | Same logical dataset, after commits/checkpoint/compaction; include every sidecar/temp file; full variants and requested metrics remain |
| S10 (I/O amplification) | Partial: whole-worker /proc/self/io storage-byte counters | Inserts, updates, deletes, learning, checkpoint and compaction; full variants and requested metrics remain |
| S11 (Physical cold reads) | Not timed in this matrix | First lookup and first scan with a documented isolated cold-cache procedure; full variants and requested metrics remain |
| M01 (Memory growth) | Partial: churn_cycle_25, churn_cycle_50, churn_cycle_75, churn_cycle_100 | Open, load 1/10/50/100% of rows, mutate repeatedly, checkpoint, close; full variants and requested metrics remain |
| M02 (Row layout) | Partial: insert_reused | Narrow integers, 64 columns, null-heavy rows, short/long text and blobs; full variants and requested metrics remain |
| M03 (Capacity boundaries) | Not timed in this matrix | Approach transaction/checkpoint 16 MiB bounds; supported large individual values; full variants and requested metrics remain |
| M04 (Scale) | Partial: insert_reused | 1K/10K/100K rows now; 1M/10M and increasing total bytes later; full variants and requested metrics remain |
| M05 (Larger than memory) | Gated | Working set 2×/10× a declared RAM budget; random and sequential access; missing capability: bounded row cache and larger snapshots |
| D01 (Unchanged schema) | Partial: reopen_first_id, matching_schema_1000, schema_noop | Open/init declared schema on a populated lazy database; full variants and requested metrics remain |
| D02 (Add fields) | Partial: schema_add_nullable, schema_add_default, schema_rename_reorder_drop, schema_convert | Nullable addition, required default and tightening nullability with an explicit default; full variants and requested metrics remain |
| D03 (Rename/reorder) | Partial: schema_add_nullable, schema_add_default, schema_rename_reorder_drop, schema_convert | Explicit rename and field reorder; tables with learned indexes; full variants and requested metrics remain |
| D04 (Convert/remove) | Partial: schema_add_nullable, schema_add_default, schema_rename_reorder_drop, schema_convert | Explicit converter/drop; invalid conversion and omitted lossy-change rules; full variants and requested metrics remain |
| D05 (Many-table schema) | Not timed in this matrix | 1/10/100/1,000 small tables; matched and changed declarations; full variants and requested metrics remain |
| D06 (Constraints) | Gated | Unique fields and foreign-key checks; successful/failed writes, cascades and schema changes; missing capability: uniqueness/foreign-key constraints |
| R01 (Process-exit recovery) | Partial: process_exit_recovery | Terminate process before/after durable commit and during checkpoint/compaction; full variants and requested metrics remain |
| R02 (Interrupted files) | Not timed in this matrix | Truncated final transaction/checkpoint, mandatory compacted base and CRC damage; full variants and requested metrics remain |
| R03 (Storage errors) | Not timed in this matrix | Failed writes/fsync, full disk/quota and detached/replaced database path in isolated fixtures; full variants and requested metrics remain |
| R04 (Snapshot/backup workflow) | Gated | Obtain a coherent backup through a defined application protocol; restore and reopen; missing capability: define/test a public backup protocol first |
| C01 (Lock contention) | Not timed in this matrix | Two processes try opening the same file; lock owner exits and another opens; full variants and requested metrics remain |
| C02 (Concurrent readers) | Gated | 1/2/4/8/16 readers, with and without a writer; missing capability: reader concurrency |
| C03 (Concurrent writers) | Gated | Multiple writers; batch sizes and contention levels; missing capability: writer concurrency |
| C04 (Independent files) | Not timed in this matrix | Several processes, each owning a separate database; full variants and requested metrics remain |
| X01 (Mixed workload) | Partial: mixed_writes_5, mixed_writes_20, mixed_writes_50 | Read/write ratios 95/5, 80/20 and 50/50; uniform and hot-key access; full variants and requested metrics remain |
| X02 (Application trace) | Not timed in this matrix | Users/posts/events relations; lookup, append, update, delete and paginated views; full variants and requested metrics remain |
| X03 (Append-heavy logs) | Not timed in this matrix | Timestamped events, burst inserts, retention deletes and recent-event queries; full variants and requested metrics remain |
| X04 (Lookup catalogue) | Not timed in this matrix | Read-mostly text keys, duplicate names, occasional edits and repeated opens; full variants and requested metrics remain |
| X05 (Compilation/setup) | Not timed in this matrix | Small/large schemas and many predicates; extension processing, binary size, SQLite statement preparation; full variants and requested metrics remain |
| X06 (Compression/encryption) | Gated | Off/on with matched algorithms, data and security requirements; missing capability: compression/encryption |

## Reproduce and interpret

```sh
mkdir -p build/flexdb/tmp build/flexdb/bench
./build/flex scripts/benchmark-flexdb-matrix.flex -o build/flexdb/bench/benchmark-matrix
TMPDIR="$PWD/build/flexdb/tmp" ./build/flexdb/bench/benchmark-matrix ./build/flex 5 build/flexdb/bench/roadmap-all.json
```

The default now runs all 24 scenarios serially. For separate batches, the optional
last argument `extra` runs budget/demand/recovery cases, `maintenance` runs
batching/churn, `storage` runs lifecycle/recovery cases and `writes` runs write/mixed-read cases. `smoke` runs one small read scenario. The engine and SQLite
comparator are compiled by the Flexscript driver; SQLite is needed only for its
C comparator. An execution writes JSON plus an accompanying `.json.md` table.
Saved raw results can be summarized without rerunning workloads:

```sh
./build/flexdb/bench/benchmark-matrix --summarize build/flexdb/bench/roadmap-all.json build/flexdb/bench/roadmap-all.json
```

The initial reports are `build/flexdb/bench/roadmap-matrix.json`,
`roadmap-matrix-extra.json` and `roadmap-matrix-maintenance.json`, with matching
Markdown tables. They contain preserved worker directories, actual executable
hashes, all samples including warmup, validated checksums, median/min/max, peak
RSS, final size, storage I/O counters and sampled point-lookup latency. RSS uses
post-exec VmHWM rather than inherited launcher ru_maxrss. The summary sorting
bug found during review was corrected from the unchanged raw samples; all
aggregated times and resources were independently checked against the samples.

Latency rows contain 2,000 timed lookups per trial and a separately measured
empty clock-pair cost. Both workers force kernel clocks. Report raw percentiles
and instrumentation overhead together; do not treat five trial medians as a
pooled p99 or subtract timer overhead as an exact correction.

The SQLite repeated-read families use one read transaction around each phase.
Creation of an explicit SQLite index is durable; FlexDB's learned buckets are
published later at checkpoint. Budget experiments compare a FlexDB bucket budget
with SQLite page-cache settings and a disk index, which constrain different
memory. Mutation phases use fresh FlexDB value vectors and prepared SQLite
bindings. Whole-session timers include key generation, schema/population, query
preparation, latency calibration where present and final close; they exclude
compilation and do not represent an arbitrary production application trace.

## Remaining optimization work after this pass

| Priority | Remaining gap | Next implementation work |
| --- | --- | --- |
| 1 | First validated scans/checkpointing and integrity remain slower | Compile the validated row scan/serialization loops; retain every checksum and bounds check |
| 2 | Broader replay workloads still need coverage | Longer tails, mixed edits and larger datasets; include startup, first query and close together |
| 3 | Column additions rewrite/log every current row | Sparse defaults/schema overlays with a durable file representation and explicit conversion rules |
| 4 | The measured ordinary SUM loop now wins; broader aggregates remain | Add/test specialized reductions, projections and grouping with explicit overflow/null behavior |
| 5 | Empty transaction allocation/snapshot overhead is fixed | Broaden transaction/table-count and failure timing coverage; keep rollback and durability costs visible |
| 6 | Churn RSS and final file sizes still exceed SQLite | Explicit row ownership/reclamation and denser checkpoint/index layouts; old captured row handles cannot silently become invalid |
| 7 | Several adaptive budget/demand variants still lose | Improve duplicate bucket representation, bounded rebuilds and switching policy; time complete sessions |
| 8 | Coverage remains partial and capabilities are gated | Add the missing roadmap features and time cold, concurrent and larger-memory workloads separately |

## Baseline full measured tables

The following tables preserve all 355 scenario/case comparisons. Related target
tags describe measured representatives, not complete target coverage.

### roadmap-matrix.json

| Scenario | Case | Targets | Operations | FlexDB ms | SQLite ms | Faster (>10% margin) |
| --- | --- | --- | ---: | ---: | ---: | --- |
| read_1k | insert_reused | W01,M02,M04 | 1000 | 5.737 | 5.570 | Similar |
| read_1k | id_sequential | Q01 | 100000 | 3.248 | 18.280 | FlexDB |
| read_1k | id_random | Q01 | 100000 | 3.074 | 21.136 | FlexDB |
| read_1k | id_hot32 | Q01 | 100000 | 3.023 | 18.389 | FlexDB |
| read_1k | id_missing | Q01 | 100000 | 8.952 | 13.089 | FlexDB |
| read_1k | scan_matches_0 | Q06 | 20 | 0.266 | 0.376 | FlexDB |
| read_1k | scan_matches_1 | Q06 | 20 | 0.265 | 0.381 | FlexDB |
| read_1k | scan_matches_10 | Q06 | 20 | 0.274 | 0.375 | FlexDB |
| read_1k | scan_matches_100 | Q06 | 20 | 0.268 | 0.384 | FlexDB |
| read_1k | scan_matches_500 | Q06 | 20 | 0.269 | 0.407 | FlexDB |
| read_1k | scan_matches_1000 | Q06 | 20 | 0.270 | 0.431 | FlexDB |
| read_1k | combined_scan | Q08 | 20 | 0.373 | 0.574 | FlexDB |
| read_1k | null_scan | Q05 | 20 | 0.238 | 0.409 | FlexDB |
| read_1k | learn_integer | A01,A02,A05 | 34 | 0.520 | 5.944 | FlexDB |
| read_1k | integer_hit | Q02,Q04 | 10000 | 1.785 | 3.023 | FlexDB |
| read_1k | integer_miss | Q02,Q04 | 10000 | 1.080 | 1.837 | FlexDB |
| read_1k | integer_materialized | Q04,Q09 | 100 | 1.068 | 0.055 | SQLite |
| read_1k | offset_page_middle | Q10 | 10 | 0.438 | 0.113 | SQLite |
| read_1k | aggregate_sum_loop | Q15 | 20 | 0.594 | 0.481 | SQLite |
| read_1k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| read_1k | final_close | S04 | 1000 | 5.787 | 10.224 | FlexDB |
| read_1k | session_total | S05 | 1 | 60.243 | 139.679 | FlexDB |
| read_10k | insert_reused | W01,M02,M04 | 10000 | 10.654 | 9.965 | Similar |
| read_10k | id_sequential | Q01 | 100000 | 3.266 | 18.363 | FlexDB |
| read_10k | id_random | Q01 | 100000 | 3.799 | 24.660 | FlexDB |
| read_10k | id_hot32 | Q01 | 100000 | 3.011 | 19.172 | FlexDB |
| read_10k | id_missing | Q01 | 100000 | 11.952 | 13.874 | FlexDB |
| read_10k | scan_matches_0 | Q06 | 20 | 2.698 | 3.821 | FlexDB |
| read_10k | scan_matches_1 | Q06 | 20 | 2.672 | 3.844 | FlexDB |
| read_10k | scan_matches_100 | Q06 | 20 | 2.662 | 3.822 | FlexDB |
| read_10k | scan_matches_1000 | Q06 | 20 | 2.674 | 3.871 | FlexDB |
| read_10k | scan_matches_5000 | Q06 | 20 | 2.714 | 4.111 | FlexDB |
| read_10k | scan_matches_10000 | Q06 | 20 | 2.723 | 4.389 | FlexDB |
| read_10k | combined_scan | Q08 | 20 | 3.777 | 5.863 | FlexDB |
| read_10k | null_scan | Q05 | 20 | 2.410 | 4.226 | FlexDB |
| read_10k | learn_integer | A01,A02,A05 | 5 | 1.252 | 11.228 | FlexDB |
| read_10k | integer_hit | Q02,Q04 | 10000 | 1.718 | 3.318 | FlexDB |
| read_10k | integer_miss | Q02,Q04 | 10000 | 0.970 | 1.919 | FlexDB |
| read_10k | integer_materialized | Q04,Q09 | 100 | 1.149 | 0.065 | SQLite |
| read_10k | offset_page_middle | Q10 | 10 | 3.812 | 1.046 | SQLite |
| read_10k | aggregate_sum_loop | Q15 | 20 | 6.052 | 4.548 | SQLite |
| read_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| read_10k | final_close | S04 | 10000 | 11.934 | 7.237 | SQLite |
| read_10k | session_total | S05 | 1 | 106.832 | 187.811 | FlexDB |
| read_100k | insert_reused | W01,M02,M04 | 100000 | 51.930 | 63.652 | FlexDB |
| read_100k | id_sequential | Q01 | 100000 | 3.239 | 25.126 | FlexDB |
| read_100k | id_random | Q01 | 100000 | 6.693 | 33.520 | FlexDB |
| read_100k | id_hot32 | Q01 | 100000 | 3.000 | 22.305 | FlexDB |
| read_100k | id_missing | Q01 | 100000 | 14.211 | 17.911 | FlexDB |
| read_100k | scan_matches_0 | Q06 | 20 | 27.112 | 40.305 | FlexDB |
| read_100k | scan_matches_1 | Q06 | 20 | 27.111 | 39.492 | FlexDB |
| read_100k | scan_matches_1000 | Q06 | 20 | 27.199 | 39.604 | FlexDB |
| read_100k | scan_matches_10000 | Q06 | 20 | 27.216 | 40.047 | FlexDB |
| read_100k | scan_matches_50000 | Q06 | 20 | 27.473 | 42.441 | FlexDB |
| read_100k | scan_matches_100000 | Q06 | 20 | 27.748 | 45.522 | FlexDB |
| read_100k | combined_scan | Q08 | 20 | 38.364 | 59.046 | FlexDB |
| read_100k | null_scan | Q05 | 20 | 24.385 | 43.420 | FlexDB |
| read_100k | learn_integer | A01,A02,A05 | 5 | 13.787 | 37.688 | FlexDB |
| read_100k | integer_hit | Q02,Q04 | 10000 | 2.032 | 4.194 | FlexDB |
| read_100k | integer_miss | Q02,Q04 | 10000 | 1.191 | 2.098 | FlexDB |
| read_100k | integer_materialized | Q04,Q09 | 100 | 1.161 | 0.102 | SQLite |
| read_100k | offset_page_middle | Q10 | 10 | 33.854 | 10.338 | SQLite |
| read_100k | aggregate_sum_loop | Q15 | 20 | 60.835 | 45.662 | SQLite |
| read_100k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| read_100k | final_close | S04 | 100000 | 55.669 | 9.754 | SQLite |
| read_100k | session_total | S05 | 1 | 507.493 | 660.920 | FlexDB |
| text8_10k | insert_reused | W01,M02,M04 | 10000 | 9.709 | 9.226 | Similar |
| text8_10k | id_sequential | Q01 | 100000 | 3.245 | 18.383 | FlexDB |
| text8_10k | id_random | Q01 | 100000 | 3.697 | 23.850 | FlexDB |
| text8_10k | id_hot32 | Q01 | 100000 | 3.020 | 19.040 | FlexDB |
| text8_10k | id_missing | Q01 | 100000 | 11.951 | 14.176 | FlexDB |
| text8_10k | scan_matches_0 | Q06 | 20 | 2.685 | 3.724 | FlexDB |
| text8_10k | scan_matches_1 | Q06 | 20 | 2.694 | 3.722 | FlexDB |
| text8_10k | scan_matches_100 | Q06 | 20 | 2.667 | 3.757 | FlexDB |
| text8_10k | scan_matches_1000 | Q06 | 20 | 2.675 | 3.791 | FlexDB |
| text8_10k | scan_matches_5000 | Q06 | 20 | 2.723 | 4.042 | FlexDB |
| text8_10k | scan_matches_10000 | Q06 | 20 | 2.736 | 4.331 | FlexDB |
| text8_10k | combined_scan | Q08 | 20 | 3.829 | 5.780 | FlexDB |
| text8_10k | null_scan | Q05 | 20 | 2.362 | 4.009 | FlexDB |
| text8_10k | learn_text | A01,A02,A05 | 5 | 3.021 | 11.956 | FlexDB |
| text8_10k | text_hit | Q03,Q04 | 10000 | 2.502 | 3.831 | FlexDB |
| text8_10k | text_miss | Q03,Q04 | 10000 | 1.159 | 2.082 | FlexDB |
| text8_10k | text_materialized | Q04,Q09 | 100 | 1.151 | 0.072 | SQLite |
| text8_10k | offset_page_middle | Q10 | 10 | 3.784 | 1.036 | SQLite |
| text8_10k | aggregate_sum_loop | Q15 | 20 | 6.004 | 4.597 | SQLite |
| text8_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| text8_10k | final_close | S04 | 10000 | 10.853 | 7.080 | SQLite |
| text8_10k | session_total | S05 | 1 | 106.193 | 187.303 | FlexDB |
| text32_utf8_10k | insert_reused | W01,M02,M04 | 10000 | 10.804 | 10.146 | Similar |
| text32_utf8_10k | id_sequential | Q01 | 100000 | 3.229 | 18.362 | FlexDB |
| text32_utf8_10k | id_random | Q01 | 100000 | 3.769 | 24.567 | FlexDB |
| text32_utf8_10k | id_hot32 | Q01 | 100000 | 3.020 | 19.075 | FlexDB |
| text32_utf8_10k | id_missing | Q01 | 100000 | 11.927 | 14.241 | FlexDB |
| text32_utf8_10k | scan_matches_0 | Q06 | 20 | 2.694 | 3.818 | FlexDB |
| text32_utf8_10k | scan_matches_1 | Q06 | 20 | 2.685 | 3.863 | FlexDB |
| text32_utf8_10k | scan_matches_100 | Q06 | 20 | 2.673 | 3.860 | FlexDB |
| text32_utf8_10k | scan_matches_1000 | Q06 | 20 | 2.713 | 3.905 | FlexDB |
| text32_utf8_10k | scan_matches_5000 | Q06 | 20 | 2.710 | 4.126 | FlexDB |
| text32_utf8_10k | scan_matches_10000 | Q06 | 20 | 2.730 | 4.412 | FlexDB |
| text32_utf8_10k | combined_scan | Q08 | 20 | 3.780 | 5.693 | FlexDB |
| text32_utf8_10k | null_scan | Q05 | 20 | 2.417 | 4.105 | FlexDB |
| text32_utf8_10k | learn_text | A01,A02,A05 | 5 | 7.455 | 13.136 | FlexDB |
| text32_utf8_10k | text_hit | Q03,Q04 | 10000 | 4.129 | 4.157 | Similar |
| text32_utf8_10k | text_miss | Q03,Q04 | 10000 | 1.295 | 2.119 | FlexDB |
| text32_utf8_10k | text_materialized | Q04,Q09 | 100 | 1.174 | 0.074 | SQLite |
| text32_utf8_10k | offset_page_middle | Q10 | 10 | 3.792 | 1.040 | SQLite |
| text32_utf8_10k | aggregate_sum_loop | Q15 | 20 | 6.019 | 4.731 | SQLite |
| text32_utf8_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| text32_utf8_10k | final_close | S04 | 10000 | 11.906 | 7.608 | SQLite |
| text32_utf8_10k | session_total | S05 | 1 | 114.713 | 192.342 | FlexDB |
| text256_10k | insert_reused | W01,M02,M04 | 10000 | 20.017 | 17.466 | SQLite |
| text256_10k | id_sequential | Q01 | 100000 | 3.271 | 20.404 | FlexDB |
| text256_10k | id_random | Q01 | 100000 | 3.841 | 28.299 | FlexDB |
| text256_10k | id_hot32 | Q01 | 100000 | 3.044 | 20.388 | FlexDB |
| text256_10k | id_missing | Q01 | 100000 | 11.960 | 16.837 | FlexDB |
| text256_10k | scan_matches_0 | Q06 | 20 | 2.710 | 4.890 | FlexDB |
| text256_10k | scan_matches_1 | Q06 | 20 | 2.709 | 4.894 | FlexDB |
| text256_10k | scan_matches_100 | Q06 | 20 | 2.727 | 4.923 | FlexDB |
| text256_10k | scan_matches_1000 | Q06 | 20 | 2.712 | 4.942 | FlexDB |
| text256_10k | scan_matches_5000 | Q06 | 20 | 2.730 | 5.205 | FlexDB |
| text256_10k | scan_matches_10000 | Q06 | 20 | 2.768 | 5.465 | FlexDB |
| text256_10k | combined_scan | Q08 | 20 | 3.976 | 6.991 | FlexDB |
| text256_10k | null_scan | Q05 | 20 | 2.494 | 5.582 | FlexDB |
| text256_10k | learn_text | A01,A02,A05 | 5 | 25.704 | 36.024 | FlexDB |
| text256_10k | text_hit | Q03,Q04 | 10000 | 16.548 | 6.067 | SQLite |
| text256_10k | text_miss | Q03,Q04 | 10000 | 1.989 | 2.387 | FlexDB |
| text256_10k | text_materialized | Q04,Q09 | 100 | 1.238 | 0.118 | SQLite |
| text256_10k | offset_page_middle | Q10 | 10 | 3.781 | 1.413 | SQLite |
| text256_10k | aggregate_sum_loop | Q15 | 20 | 6.103 | 5.933 | Similar |
| text256_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| text256_10k | final_close | S04 | 10000 | 23.361 | 0.894 | SQLite |
| text256_10k | session_total | S05 | 1 | 173.306 | 240.668 | FlexDB |
| text256_collision_1k | insert_reused | W01,M02,M04 | 1000 | 6.764 | 6.468 | Similar |
| text256_collision_1k | id_sequential | Q01 | 100000 | 3.207 | 18.565 | FlexDB |
| text256_collision_1k | id_random | Q01 | 100000 | 3.098 | 22.090 | FlexDB |
| text256_collision_1k | id_hot32 | Q01 | 100000 | 3.034 | 18.296 | FlexDB |
| text256_collision_1k | id_missing | Q01 | 100000 | 8.981 | 13.902 | FlexDB |
| text256_collision_1k | scan_matches_0 | Q06 | 20 | 0.270 | 0.440 | FlexDB |
| text256_collision_1k | scan_matches_1 | Q06 | 20 | 0.267 | 0.435 | FlexDB |
| text256_collision_1k | scan_matches_10 | Q06 | 20 | 0.268 | 0.439 | FlexDB |
| text256_collision_1k | scan_matches_100 | Q06 | 20 | 0.268 | 0.444 | FlexDB |
| text256_collision_1k | scan_matches_500 | Q06 | 20 | 0.274 | 0.466 | FlexDB |
| text256_collision_1k | scan_matches_1000 | Q06 | 20 | 0.274 | 0.493 | FlexDB |
| text256_collision_1k | combined_scan | Q08 | 20 | 0.383 | 0.655 | FlexDB |
| text256_collision_1k | null_scan | Q05 | 20 | 0.239 | 0.489 | FlexDB |
| text256_collision_1k | learn_text | A01,A02,A05 | 34 | 38.523 | 7.744 | SQLite |
| text256_collision_1k | text_hit | Q03,Q04,A06 | 10000 | 10964.934 | 4.353 | SQLite |
| text256_collision_1k | text_miss | Q03,Q04 | 10000 | 1.153 | 2.369 | FlexDB |
| text256_collision_1k | text_materialized | Q04,Q09 | 100 | 110.880 | 0.078 | SQLite |
| text256_collision_1k | offset_page_middle | Q10 | 10 | 0.437 | 0.132 | SQLite |
| text256_collision_1k | aggregate_sum_loop | Q15 | 20 | 0.605 | 0.523 | SQLite |
| text256_collision_1k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| text256_collision_1k | final_close | S04 | 1000 | 10.449 | 6.187 | SQLite |
| text256_collision_1k | session_total | S05 | 1 | 11176.780 | 143.918 | SQLite |
| duplicates10_10k | insert_reused | W01,M02,M04 | 10000 | 10.639 | 9.890 | Similar |
| duplicates10_10k | id_sequential | Q01 | 100000 | 3.172 | 18.541 | FlexDB |
| duplicates10_10k | id_random | Q01 | 100000 | 3.763 | 24.711 | FlexDB |
| duplicates10_10k | id_hot32 | Q01 | 100000 | 3.031 | 18.869 | FlexDB |
| duplicates10_10k | id_missing | Q01 | 100000 | 11.953 | 13.640 | FlexDB |
| duplicates10_10k | scan_matches_0 | Q06 | 20 | 2.723 | 3.876 | FlexDB |
| duplicates10_10k | scan_matches_0 | Q06 | 20 | 2.690 | 3.866 | FlexDB |
| duplicates10_10k | scan_matches_100 | Q06 | 20 | 2.697 | 3.918 | FlexDB |
| duplicates10_10k | scan_matches_1000 | Q06 | 20 | 2.723 | 3.930 | FlexDB |
| duplicates10_10k | scan_matches_5000 | Q06 | 20 | 2.737 | 4.191 | FlexDB |
| duplicates10_10k | scan_matches_10000 | Q06 | 20 | 2.746 | 4.475 | FlexDB |
| duplicates10_10k | combined_scan | Q08 | 20 | 3.863 | 5.880 | FlexDB |
| duplicates10_10k | null_scan | Q05 | 20 | 2.390 | 4.071 | FlexDB |
| duplicates10_10k | learn_integer | A01,A02,A05 | 5 | 1.546 | 11.380 | FlexDB |
| duplicates10_10k | integer_hit | Q02,Q04 | 10000 | 7.915 | 4.923 | SQLite |
| duplicates10_10k | integer_miss | Q02,Q04 | 10000 | 1.311 | 1.904 | FlexDB |
| duplicates10_10k | integer_materialized | Q04,Q09 | 100 | 1.336 | 0.294 | SQLite |
| duplicates10_10k | offset_page_middle | Q10 | 10 | 3.801 | 1.067 | SQLite |
| duplicates10_10k | aggregate_sum_loop | Q15 | 20 | 6.059 | 4.514 | SQLite |
| duplicates10_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| duplicates10_10k | final_close | S04 | 10000 | 11.788 | 7.101 | SQLite |
| duplicates10_10k | session_total | S05 | 1 | 112.819 | 190.237 | FlexDB |
| duplicates100_10k | insert_reused | W01,M02,M04 | 10000 | 10.401 | 9.682 | Similar |
| duplicates100_10k | id_sequential | Q01 | 100000 | 3.200 | 18.373 | FlexDB |
| duplicates100_10k | id_random | Q01 | 100000 | 3.755 | 24.072 | FlexDB |
| duplicates100_10k | id_hot32 | Q01 | 100000 | 3.024 | 18.778 | FlexDB |
| duplicates100_10k | id_missing | Q01 | 100000 | 11.947 | 13.568 | FlexDB |
| duplicates100_10k | scan_matches_0 | Q06 | 20 | 2.727 | 3.826 | FlexDB |
| duplicates100_10k | scan_matches_0 | Q06 | 20 | 2.704 | 3.793 | FlexDB |
| duplicates100_10k | scan_matches_100 | Q06 | 20 | 2.719 | 3.844 | FlexDB |
| duplicates100_10k | scan_matches_1000 | Q06 | 20 | 2.745 | 3.890 | FlexDB |
| duplicates100_10k | scan_matches_5000 | Q06 | 20 | 2.774 | 4.128 | FlexDB |
| duplicates100_10k | scan_matches_10000 | Q06 | 20 | 2.749 | 4.398 | FlexDB |
| duplicates100_10k | combined_scan | Q08 | 20 | 3.920 | 5.757 | FlexDB |
| duplicates100_10k | null_scan | Q05 | 20 | 2.391 | 4.075 | FlexDB |
| duplicates100_10k | learn_integer | A01,A02,A05 | 5 | 3.756 | 11.296 | FlexDB |
| duplicates100_10k | integer_hit | Q02,Q04 | 10000 | 60.838 | 19.402 | SQLite |
| duplicates100_10k | integer_miss | Q02,Q04 | 10000 | 3.748 | 1.956 | SQLite |
| duplicates100_10k | integer_materialized | Q04,Q09 | 100 | 3.220 | 2.290 | SQLite |
| duplicates100_10k | offset_page_middle | Q10 | 10 | 3.773 | 1.032 | SQLite |
| duplicates100_10k | aggregate_sum_loop | Q15 | 20 | 6.065 | 4.519 | SQLite |
| duplicates100_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| duplicates100_10k | final_close | S04 | 10000 | 15.247 | 6.841 | SQLite |
| duplicates100_10k | session_total | S05 | 1 | 175.071 | 205.024 | FlexDB |
| duplicates1000_10k | insert_reused | W01,M02,M04 | 10000 | 10.905 | 9.856 | Similar |
| duplicates1000_10k | id_sequential | Q01 | 100000 | 3.251 | 18.472 | FlexDB |
| duplicates1000_10k | id_random | Q01 | 100000 | 3.751 | 24.642 | FlexDB |
| duplicates1000_10k | id_hot32 | Q01 | 100000 | 3.020 | 18.722 | FlexDB |
| duplicates1000_10k | id_missing | Q01 | 100000 | 11.957 | 14.015 | FlexDB |
| duplicates1000_10k | scan_matches_0 | Q06 | 20 | 2.715 | 4.098 | FlexDB |
| duplicates1000_10k | scan_matches_0 | Q06 | 20 | 2.680 | 4.123 | FlexDB |
| duplicates1000_10k | scan_matches_0 | Q06 | 20 | 2.687 | 4.113 | FlexDB |
| duplicates1000_10k | scan_matches_1000 | Q06 | 20 | 2.711 | 4.038 | FlexDB |
| duplicates1000_10k | scan_matches_5000 | Q06 | 20 | 2.719 | 4.279 | FlexDB |
| duplicates1000_10k | scan_matches_10000 | Q06 | 20 | 2.742 | 4.561 | FlexDB |
| duplicates1000_10k | combined_scan | Q08 | 20 | 3.865 | 6.102 | FlexDB |
| duplicates1000_10k | null_scan | Q05 | 20 | 2.397 | 4.078 | FlexDB |
| duplicates1000_10k | learn_integer | A01,A02,A05 | 5 | 26.165 | 11.549 | SQLite |
| duplicates1000_10k | integer_hit | Q02,Q04 | 10000 | 575.063 | 173.548 | SQLite |
| duplicates1000_10k | integer_miss | Q02,Q04 | 10000 | 28.178 | 1.935 | SQLite |
| duplicates1000_10k | integer_materialized | Q04,Q09 | 100 | 24.536 | 20.000 | SQLite |
| duplicates1000_10k | offset_page_middle | Q10 | 10 | 3.762 | 1.054 | SQLite |
| duplicates1000_10k | aggregate_sum_loop | Q15 | 20 | 6.060 | 4.518 | SQLite |
| duplicates1000_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| duplicates1000_10k | final_close | S04 | 10000 | 15.617 | 10.545 | SQLite |
| duplicates1000_10k | session_total | S05 | 1 | 758.263 | 383.164 | SQLite |
| nulls50_10k | insert_reused | W01,M02,M04 | 10000 | 10.942 | 10.060 | Similar |
| nulls50_10k | id_sequential | Q01 | 100000 | 3.269 | 18.395 | FlexDB |
| nulls50_10k | id_random | Q01 | 100000 | 3.773 | 24.720 | FlexDB |
| nulls50_10k | id_hot32 | Q01 | 100000 | 3.022 | 19.181 | FlexDB |
| nulls50_10k | id_missing | Q01 | 100000 | 11.956 | 14.153 | FlexDB |
| nulls50_10k | scan_matches_0 | Q06 | 20 | 2.701 | 3.787 | FlexDB |
| nulls50_10k | scan_matches_1 | Q06 | 20 | 2.680 | 3.818 | FlexDB |
| nulls50_10k | scan_matches_100 | Q06 | 20 | 2.684 | 3.829 | FlexDB |
| nulls50_10k | scan_matches_1000 | Q06 | 20 | 2.708 | 3.867 | FlexDB |
| nulls50_10k | scan_matches_5000 | Q06 | 20 | 2.718 | 4.092 | FlexDB |
| nulls50_10k | scan_matches_10000 | Q06 | 20 | 2.738 | 4.379 | FlexDB |
| nulls50_10k | combined_scan | Q08 | 20 | 3.562 | 5.270 | FlexDB |
| nulls50_10k | null_scan | Q05 | 20 | 2.517 | 4.369 | FlexDB |
| nulls50_10k | learn_integer | A01,A02,A05 | 5 | 1.256 | 11.486 | FlexDB |
| nulls50_10k | integer_hit | Q02,Q04 | 10000 | 1.718 | 3.285 | FlexDB |
| nulls50_10k | integer_miss | Q02,Q04 | 10000 | 0.972 | 1.966 | FlexDB |
| nulls50_10k | integer_materialized | Q04,Q09 | 100 | 1.150 | 0.065 | SQLite |
| nulls50_10k | offset_page_middle | Q10 | 10 | 3.805 | 1.010 | SQLite |
| nulls50_10k | aggregate_sum_loop | Q15 | 20 | 6.046 | 4.498 | SQLite |
| nulls50_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| nulls50_10k | final_close | S04 | 10000 | 11.405 | 7.239 | SQLite |
| nulls50_10k | session_total | S05 | 1 | 107.123 | 192.875 | FlexDB |
| nulls90_10k | insert_reused | W01,M02,M04 | 10000 | 10.526 | 9.983 | Similar |
| nulls90_10k | id_sequential | Q01 | 100000 | 3.211 | 18.267 | FlexDB |
| nulls90_10k | id_random | Q01 | 100000 | 3.760 | 24.438 | FlexDB |
| nulls90_10k | id_hot32 | Q01 | 100000 | 3.027 | 18.928 | FlexDB |
| nulls90_10k | id_missing | Q01 | 100000 | 11.968 | 13.968 | FlexDB |
| nulls90_10k | scan_matches_0 | Q06 | 20 | 2.698 | 3.777 | FlexDB |
| nulls90_10k | scan_matches_1 | Q06 | 20 | 2.691 | 3.797 | FlexDB |
| nulls90_10k | scan_matches_100 | Q06 | 20 | 2.687 | 3.816 | FlexDB |
| nulls90_10k | scan_matches_1000 | Q06 | 20 | 2.723 | 3.845 | FlexDB |
| nulls90_10k | scan_matches_5000 | Q06 | 20 | 2.718 | 4.112 | FlexDB |
| nulls90_10k | scan_matches_10000 | Q06 | 20 | 2.754 | 4.369 | FlexDB |
| nulls90_10k | combined_scan | Q08 | 20 | 3.304 | 4.831 | FlexDB |
| nulls90_10k | null_scan | Q05 | 20 | 2.555 | 4.529 | FlexDB |
| nulls90_10k | learn_integer | A01,A02,A05 | 5 | 1.255 | 11.255 | FlexDB |
| nulls90_10k | integer_hit | Q02,Q04 | 10000 | 1.707 | 3.297 | FlexDB |
| nulls90_10k | integer_miss | Q02,Q04 | 10000 | 0.968 | 1.930 | FlexDB |
| nulls90_10k | integer_materialized | Q04,Q09 | 100 | 1.156 | 0.066 | SQLite |
| nulls90_10k | offset_page_middle | Q10 | 10 | 3.798 | 1.018 | SQLite |
| nulls90_10k | aggregate_sum_loop | Q15 | 20 | 6.028 | 4.602 | SQLite |
| nulls90_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| nulls90_10k | final_close | S04 | 10000 | 11.227 | 7.225 | SQLite |
| nulls90_10k | session_total | S05 | 1 | 105.990 | 187.271 | FlexDB |
| write_10k | insert_reused | W01,M02,M04 | 10000 | 10.916 | 10.155 | Similar |
| write_10k | learn_integer | A01,A02,A05 | 5 | 1.365 | 7.892 | FlexDB |
| write_10k | update_unindexed_field | W04 | 1000 | 6.155 | 6.263 | Similar |
| write_10k | update_indexed_field | W04 | 1000 | 6.323 | 6.381 | Similar |
| write_10k | rollback_mixed_1002 | W08 | 1002 | 0.827 | 0.838 | Similar |
| write_10k | grow_text_256 | W06 | 1000 | 7.406 | 7.575 | Similar |
| write_10k | shrink_text_5 | W06 | 1000 | 6.268 | 6.965 | FlexDB |
| write_10k | delete_batch | W07 | 1000 | 5.507 | 6.684 | FlexDB |
| write_10k | deleted_id_reads | Q01,W07 | 10000 | 0.278 | 16.922 | FlexDB |
| write_10k | empty_transactions | W09 | 200 | 2.487 | 0.066 | SQLite |
| write_10k | indexed_insert_batch | W03 | 1000 | 5.818 | 5.807 | Similar |
| write_10k | final_close | S04 | 10000 | 11.840 | 7.750 | SQLite |
| write_10k | session_total | S05 | 1 | 82.027 | 119.247 | FlexDB |
| lifecycle_100k | insert_reused | W01,M02,M04 | 100000 | 51.539 | 64.758 | FlexDB |
| lifecycle_100k | learn_integer | A01,A02,A05 | 5 | 12.961 | 36.292 | FlexDB |
| lifecycle_100k | checkpoint_close | S04 | 100000 | 53.224 | 9.528 | SQLite |
| lifecycle_100k | reopen_first_id | S01,S02,D01 | 1 | 0.215 | 0.237 | Similar |
| lifecycle_100k | first_full_scan | S03 | 1 | 63.669 | 3.431 | SQLite |
| lifecycle_100k | cached_full_scan | S03 | 1 | 1.447 | 2.246 | FlexDB |
| lifecycle_100k | matching_schema_1000 | D01 | 1000 | 0.153 | 3.174 | FlexDB |
| lifecycle_100k | mapped_first_write | A08,W04 | 1000 | 15.663 | 16.432 | Similar |
| lifecycle_100k | mapped_later_write | A08,W04 | 1000 | 6.269 | 6.327 | Similar |
| lifecycle_100k | integrity | S08 | 100000 | 15.873 | 20.052 | FlexDB |
| lifecycle_100k | compaction | S07,S09 | 100000 | 55.454 | 51.095 | Similar |
| lifecycle_100k | session_total | S05 | 1 | 307.595 | 253.323 | SQLite |
| join_unique_1k | insert_reused | W01,M02,M04 | 1000 | 5.723 | 5.642 | Similar |
| join_unique_1k | self_join | Q11 | 1 | 27.068 | 0.561 | SQLite |
| join_unique_1k | final_close | S04 | 1000 | 0.024 | 5.359 | FlexDB |
| join_unique_1k | session_total | S05 | 1 | 48.009 | 47.110 | Similar |
| join_duplicates10_1k | insert_reused | W01,M02,M04 | 1000 | 5.708 | 5.641 | Similar |
| join_duplicates10_1k | self_join | Q11 | 1 | 28.233 | 2.305 | SQLite |
| join_duplicates10_1k | final_close | S04 | 1000 | 0.027 | 5.317 | FlexDB |
| join_duplicates10_1k | session_total | S05 | 1 | 49.251 | 48.681 | Similar |
| schema_10k | insert_reused | W01,M02,M04 | 10000 | 10.854 | 9.976 | Similar |
| schema_10k | schema_noop | D01 | 1000 | 0.196 | 2.756 | FlexDB |
| schema_10k | schema_add_nullable | D02,D03,D04 | 10000 | 17.086 | 5.121 | SQLite |
| schema_10k | schema_add_default | D02,D03,D04 | 10000 | 18.904 | 5.104 | SQLite |
| schema_10k | schema_rename_reorder_drop | D02,D03,D04 | 10000 | 17.002 | 12.025 | SQLite |
| schema_10k | schema_convert | D02,D03,D04 | 10000 | 19.182 | 12.163 | SQLite |
| schema_10k | final_close | S04 | 10000 | 12.431 | 8.085 | SQLite |
| schema_10k | session_total | S05 | 1 | 112.370 | 91.194 | SQLite |
| mixed95read_10k | insert_reused | W01,M02,M04 | 10000 | 10.727 | 10.055 | Similar |
| mixed95read_10k | learn_integer | A01,A02,A05 | 5 | 1.450 | 7.795 | FlexDB |
| mixed95read_10k | mixed_writes_5 | X01,A03 | 1000 | 249.736 | 255.432 | Similar |
| mixed95read_10k | final_close | S04 | 10000 | 12.118 | 7.582 | SQLite |
| mixed95read_10k | session_total | S05 | 1 | 290.161 | 317.893 | Similar |
| mixed80read_10k | insert_reused | W01,M02,M04 | 10000 | 10.828 | 10.243 | Similar |
| mixed80read_10k | learn_integer | A01,A02,A05 | 5 | 1.399 | 7.794 | FlexDB |
| mixed80read_10k | mixed_writes_20 | X01,A03 | 1000 | 1003.714 | 1034.197 | Similar |
| mixed80read_10k | final_close | S04 | 10000 | 11.962 | 7.803 | SQLite |
| mixed80read_10k | session_total | S05 | 1 | 1043.955 | 1095.697 | Similar |
| mixed50read_10k | insert_reused | W01,M02,M04 | 10000 | 10.940 | 10.274 | Similar |
| mixed50read_10k | learn_integer | A01,A02,A05 | 5 | 1.461 | 7.790 | FlexDB |
| mixed50read_10k | mixed_writes_50 | X01,A03 | 1000 | 2509.773 | 2595.797 | Similar |
| mixed50read_10k | final_close | S04 | 10000 | 12.139 | 8.862 | SQLite |
| mixed50read_10k | session_total | S05 | 1 | 2550.744 | 2658.107 | Similar |


### roadmap-matrix-extra.json

| Scenario | Case | Targets | Operations | FlexDB ms | SQLite ms | Faster (>10% margin) |
| --- | --- | --- | ---: | ---: | ---: | --- |
| adaptive_10k | insert_reused | W01,M02,M04 | 10000 | 10.732 | 10.037 | Similar |
| adaptive_10k | budget_0 | A01,A02,A04,A05 | 200 | 27.632 | 38.368 | FlexDB |
| adaptive_10k | budget_262144 | A01,A02,A04,A05 | 200 | 27.574 | 8.531 | SQLite |
| adaptive_10k | budget_1048576 | A01,A02,A04,A05 | 200 | 1.276 | 8.337 | FlexDB |
| adaptive_10k | budget_4194304 | A01,A02,A04,A05 | 200 | 1.252 | 8.090 | FlexDB |
| adaptive_10k | budget_8388608 | A01,A02,A04,A05 | 200 | 1.247 | 8.094 | FlexDB |
| adaptive_10k | switch_to_text | A03,A10 | 2000 | 6.468 | 13.800 | FlexDB |
| adaptive_10k | return_to_integer | A03,A10 | 200 | 0.703 | 0.392 | SQLite |
| adaptive_10k | demand_becomes_broad | A03,Q04 | 100 | 48.809 | 14.732 | SQLite |
| adaptive_10k | final_close | S04 | 10000 | 17.149 | 7.851 | SQLite |
| adaptive_10k | session_total | S05 | 1 | 378.949 | 189.122 | SQLite |
| recovery_10k | process_exit_recovery | R01,S06,A09 | 1 | 0.092 | 0.421 | FlexDB |
| recovery_10k | first_equality_after_tail | A09 | 1 | 5.249 | 0.006 | SQLite |
| recovery_10k | final_close | S04 | 10000 | 11.851 | 10.066 | SQLite |
| recovery_10k | session_total | S05 | 1 | 17.359 | 10.477 | SQLite |


### roadmap-matrix-maintenance.json

| Scenario | Case | Targets | Operations | FlexDB ms | SQLite ms | Faster (>10% margin) |
| --- | --- | --- | ---: | ---: | ---: | --- |
| batch_1k | insert_reused | W01,M02,M04 | 1000 | 5.711 | 5.662 | Similar |
| batch_1k | insert_batch_1 | W02,W05 | 1000 | 5032.379 | 5639.060 | FlexDB |
| batch_1k | insert_batch_10 | W02,W05 | 1000 | 501.636 | 511.712 | Similar |
| batch_1k | insert_batch_100 | W02,W05 | 1000 | 50.993 | 52.587 | Similar |
| batch_1k | insert_batch_1000 | W02,W05 | 1000 | 5.650 | 5.585 | Similar |
| batch_1k | final_close | S04 | 1000 | 7.289 | 7.175 | Similar |
| batch_1k | session_total | S05 | 1 | 5617.599 | 6344.729 | FlexDB |
| churn100_1k | insert_reused | W01,M02,M04 | 1000 | 5.717 | 5.631 | Similar |
| churn100_1k | learn_integer | A01,A02,A05 | 34 | 0.614 | 6.125 | FlexDB |
| churn100_1k | churn_cycle_25 | W10,M01 | 25500 | 332.501 | 151.274 | SQLite |
| churn100_1k | churn_compact_25 | W10,S07 | 1000 | 10.935 | 5.480 | SQLite |
| churn100_1k | churn_cycle_50 | W10,M01 | 25500 | 417.780 | 150.792 | SQLite |
| churn100_1k | churn_compact_50 | W10,S07 | 1000 | 10.903 | 5.445 | SQLite |
| churn100_1k | churn_cycle_75 | W10,M01 | 25500 | 416.334 | 150.579 | SQLite |
| churn100_1k | churn_compact_75 | W10,S07 | 1000 | 10.961 | 5.440 | SQLite |
| churn100_1k | churn_cycle_100 | W10,M01 | 25500 | 416.157 | 160.607 | SQLite |
| churn100_1k | churn_compact_100 | W10,S07 | 1000 | 10.979 | 5.418 | SQLite |
| churn100_1k | churn_total | W10 | 102000 | 1627.389 | 644.362 | SQLite |
| churn100_1k | final_close | S04 | 1000 | 3.515 | 6.177 | FlexDB |
| churn100_1k | session_total | S05 | 1 | 1652.550 | 697.507 | SQLite |
