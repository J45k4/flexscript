# FlexDB benchmark targets

Benchmark roadmap against SQLite, updated 2026-10-14. Measure equivalent results
and durability, including the costs of learning, index maintenance, persistence
and reopening. Current results and their full methodology are in
[libs/db/performance.md](libs/db/performance.md).

**P0**: next work, especially current weaknesses and complete workload costs.
**P1**: broader coverage and scaling. **P2**: capabilities to benchmark after
implementation. **Measured** means the named variant has timing data, not that
the entire target matrix is covered. **Partial** means some variants are timed.
**Untimed** means supported functionality needs a benchmark. **Checks only**
means correctness checks exist, but performance has not been measured.
**Gated** means a missing capability or limit prevents the intended experiment.

## External blob measurements (2026-10-17)

[Compression/storage results](libs/db/benchmark-blobs.md) measure 4 KiB automatic
placement, Zstd levels, raw fallback, incremental/range reads, metadata updates
and compaction. Tests include an 18 MiB raw external payload outside the metadata
transaction/checkpoint limit. These diagnostics are separate from the historical
SQLite matrix; they do not complete its workload variants or resource targets.

## Executed SQLite comparison (2026-10-14)

The roadmap now has **355 timed comparisons across 24 scenario configurations**,
with five measured runs plus warmup per engine and validated operation counts and
checksums. Representative variants related to **49 of these 75 targets** have
measurements, including resource usage; complete variation coverage is still
pending. Every target's measured or missing coverage is listed in the
[comparison results](libs/db/benchmark-results.md#coverage-against-all-75-targets).

The latest bulk-checkpoint snapshot has **279 timing rows favoring FlexDB,
57 within 10%, and 19 favoring SQLite**, using a >10% margin. Checkpoint/close
has improved (100K rows: 21.62 ms versus 33.35 ms in a fresh pre-change run), but
SQLite still takes 9.64 ms. First validated scans remain a loss with substantial
variation; memory use and file size remain gaps. Complete 75-target coverage and
resource metrics are separate. See the
[latest analysis](libs/db/benchmark-results.md#bulk-checkpoint-packing-2026-10-14)
and [current timing/resource tables](libs/db/benchmark-checkpoint-pack.md).

The [matrix runner](scripts/benchmark-flexdb-matrix.flex) executes concrete
variants and saves JSON/raw samples plus Markdown. Gated capabilities, physical
cold-cache tests, large-memory workloads, broad recovery fault injection and
several remaining supported variants have no timing comparison yet.

## Workload target table

For elapsed time and resource use, the initial goal is SQLite parity on matched
workloads; retain existing read advantages. For throughput, aim to meet or exceed
SQLite. Report regressions and unsupported cases independently. Correct results
and the promised durability are required regardless of performance.

| ID | Priority | Area | Benchmark and variations | Metrics / specific goal | Current coverage |
| --- | --- | --- | --- | --- | --- |
| Q01 | P0 | Point reads | Primary-ID lookup: sequential, random, hot keys; existing, missing and deleted IDs | ns/query, queries/s, p50/p95/p99; preserve current advantage | Partial comparison: sequential/random/hot/missing/deleted IDs; sampled latency |
| Q02 | P0 | Equality reads | Integer secondary key: unique keys, hits and misses; scan, learning and active index phases | Phase times and latency distribution; include learning in total cost | Partial comparison: unique integer hits/misses at 1K/10K/100K rows |
| Q03 | P0 | Equality reads | Text secondary key: 8/32/256-byte keys, long shared prefixes, ASCII and UTF-8 | Queries/s, hash/comparison cost and bytes examined | Partial comparison: 8/32/256-byte text, UTF-8 and adverse shared prefixes |
| Q04 | P0 | Equality reads | Duplicate keys: 1/10/100/1,000 matches; count and returned rows | Time versus result cardinality; preserve ascending row-ID order | Partial comparison: 1/10/100/1,000 matches; counts and ordered row results |
| Q05 | P1 | Equality reads | Nullable integer/text fields; 0/10/50/90% nulls and explicit null predicates | Exact null semantics and fallback cost | Partial comparison: null predicates at 0/10/50/90% nulls |
| Q06 | P0 | Scans | Integer predicates selecting 0/0.01/1/10/50/100% of rows | Rows/s, ns/row, branch and output costs | Partial comparison: six match-count variants at 1K/10K/100K rows |
| Q07 | P1 | Scans | Text, blob and real-value predicates; narrow and wide rows | Throughput versus payload size; consume equivalent fields | Checks only |
| Q08 | P1 | Scans | Multiple predicates: conjunction, disjunction, pure helpers and branches | Fused scan versus equivalent SQLite query and explicit FlexDB filter pipeline | Partial comparison: guarded conjunction count |
| Q09 | P0 | Result delivery | Count-only, ID-only, selected fields and complete rows for the same predicate | Allocation count, output bytes and elapsed time; checksum consumed results | Partial comparison: ordered matching rows; native handles versus SQL streaming |
| Q10 | P1 | Pagination | First/middle/last pages, offset sizes and limit sizes; ID cursor expressed in code | End-to-end time and rows examined; expose full-materialization cost | Partial comparison: middle OFFSET page, 25 rows |
| Q11 | P1 | Relations | Equality joins: one-to-one, one-to-many and many-to-many; matched/unmatched rows | Time versus input/output sizes; compare identical ordered results | Partial comparison: 1K-row self-joins, unique and duplicate keys |
| Q12 | P2 | Range indexes | Integer/text range lookups at several selectivities, with and without indexes | Access-plan crossover and output cost | Gated: range indexes |
| Q13 | P2 | Compound indexes | Two/three fields; equality plus range; correlated and independent fields | Queries/s, index bytes and write amplification | Gated: compound indexes |
| Q14 | P2 | Ordering | ORDER BY equivalent, ascending/descending, ties and top-K | Sort memory, total time and stable result semantics | Untimed through application code; general ordering operator absent |
| Q15 | P2 | Aggregation | Sum/min/max/average, distinct, grouped aggregates and aggregate joins | Rows/s, group memory and result parity | Partial comparison: application sum loop versus SQLite SUM |
| Q16 | P2 | Combined access paths | Intersections/unions across indexed predicates, covering projections and indexed joins | Total time, fetched rows and index bytes versus scans and SQLite's selected plan | Gated: compiler/runtime access paths |
| Q17 | P1 | Text semantics | Prefix/substring search and case-folded comparisons expressed in code; declared binary/Unicode behavior | Scan throughput and precisely matched comparison semantics | Untimed; specialized text indexes absent |
| W01 | P0 | Bulk inserts | Sequential inserts; fresh input values versus reusable builders | Rows/s, encode/commit times; close/checkpoint reported separately | Partial comparison: reused inserts in matrix; earlier fresh/reused runner |
| W02 | P0 | Transaction batching | Insert batches of 1/10/100/1,000/10,000 rows, within frame limit | Throughput and p99 commit latency versus batch size | Partial comparison: 1,000 inserts at batch sizes 1/10/100/1,000 |
| W03 | P0 | Indexed inserts | Insert into a learned-index table; unique and duplicate keys; trigger capacity exhaustion | Encode, index-maintenance and commit costs; fallback remains correct | Partial comparison: 1,000 inserts with an active integer index |
| W04 | P0 | Updates | Random/sequential updates; unchanged indexed field versus changed indexed field | Time per row; isolate data encoding, index maintenance and fsync | Partial comparison: changed/unchanged indexed fields; first/later mapped writes |
| W05 | P0 | Durable writes | One insert/update/delete per durable transaction; short and long runs | p50/p95/p99 latency, fsync count and operations/s | Partial comparison: 1,000 individually durable inserts; earlier durable updates |
| W06 | P0 | Variable-size updates | Grow/shrink text or blobs, same-size replacement and nullable transitions | Latency, allocated bytes, retained old rows and log bytes/write | Partial comparison: text growth to 256 bytes and shrink to 5 bytes |
| W07 | P0 | Deletes | Random, sequential and bulk deletes; 1/50/90% tombstones | Delete/commit latency, later scan/index costs and file growth | Partial comparison: 1,000-row delete batch and deleted-ID reads |
| W08 | P0 | Rollback | Insert/update/delete rollback; repeated edits to one row; transactions with reads | Time, allocation retention and unchanged committed result checksum | Partial comparison: 1,002-operation mixed rollback |
| W09 | P1 | Empty transactions | Begin/commit, begin/rollback and rejected nested transactions | Fixed overhead and zero unnecessary disk writes | Partial comparison: empty begin/commit and begin/rollback |
| W10 | P0 | Churn | At least 100 update/delete/reinsert cycles per live row; periodic compaction | Steady throughput, p99, RSS slope and bytes/live row | Partial comparison: 100 update/delete/reinsert cycles; compaction every 25 |
| W11 | P1 | Atomicity across tables | Transactions changing 2/10/100 tables; rollback and reopen | Transaction overhead and consistent committed snapshots | Checks only |
| A01 | P0 | Index learning | Cold connection: queries 1–100; selective, broad and tiny-table workloads | Per-query latency, build point and cumulative break-even versus scanning | Partial comparison: integer/text learning and budget cases |
| A02 | P0 | Automatic versus manual | FlexDB automatic indexing versus SQLite unindexed and explicitly indexed configurations | Whole workload time, including equivalent index publication | Partial comparison: automatic cache versus explicit SQLite index; session totals |
| A03 | P0 | Demand changes | Selective reads become broad; hot key/column changes; write-heavy intervals | Adaptation lag, wasted builds and total time versus fixed plans | Partial comparison: switch to text/back; selective demand becomes broad |
| A04 | P0 | Index budgets | 0/256 KiB/1/4/8 MiB budgets; more candidate columns than active-index slots | Active bucket bytes, process RSS, eviction/rebuild counts and latency | Partial comparison: 0/256 KiB/1/4/8 MiB; different engine memory scopes |
| A05 | P0 | Build limits | Table/byte limits and short time budgets; abandoned build followed by scan | Worst query pause, fallback cost and retained allocations | Partial comparison: normal builds and bucket-budget denial; timeout timing pending |
| A06 | P1 | Hash collisions | Equal-length text sharing first 64 bytes; duplicate-heavy and adverse key distributions | Probe lengths, build time and full predicate rechecks | Partial comparison: 1K equal-length 256-byte keys sharing first 64 bytes |
| A07 | P0 | Persisted indexes | Reopen with learned buckets; first hit, miss and repeated reads | Metadata/page checks, decoded rows and startup latency | Partial: first indexed hit decodes one row |
| A08 | P0 | Mapped-index writes | First write after reopen versus later writes; indexed/nonindexed field changes | Copy-on-write pause, memory spike and commit time | Partial comparison: first/later 1,000-row writes after mapped reopen |
| A09 | P0 | Tail invalidation | Reopen checkpoint plus later inserts/updates/deletes, then query affected indexes | Tail replay, discarded cache cost and relearning time | Partial comparison: committed tail invalidation and first equality rebuild |
| A10 | P1 | Retirement | Unused indexes, LRU eviction, capacity exhaustion and reappearance of demand | Memory reclaimed, cooldown and time until useful again | Partial comparison: column-demand switch and return; other retirement cases pending |
| A11 | P1 | Omitted caches | Checkpoint near size limit omits index buckets but retains usage | Publication time, reopen/rebuild cost and no lost data | Checks only |
| S01 | P0 | Startup | Open an empty database; schema match on existing database; close/reopen repeatedly | Fixed startup latency, descriptors/maps/allocations and RSS | Partial comparison: populated warm reopen |
| S02 | P0 | Lazy reads | First lookup after reopen, then random 1/100/1,000/100,000 lookups | Time versus decoded rows and touched pages | Partial comparison: first lazy ID lookup; broader lazy access sequence pending |
| S03 | P0 | First full scan | First complete scan after reopen versus subsequent cached scans | Deferred decoding cost; close the current SQLite gap | Partial comparison: first versus cached scan on a 100K-row dataset |
| S04 | P0 | Checkpoint publication | Narrow/wide tables; zero/one/four active indexes; unchanged and changed state | Build/CRC/write/fsync time, peak RSS and persisted bytes | Partial comparison: indexed publication/close across dataset variants |
| S05 | P0 | Lifecycle total | Create → populate → learn/query → mutate → checkpoint → close → reopen → query | Total wall time and work per completed application session | Partial comparison: complete measured protocol sessions, including setup/close |
| S06 | P0 | Log replay | No checkpoint; checkpoint tails of 0/1K/100K transactions; old update history | Startup time versus log bytes and operations | Partial comparison: one committed tail after process exit; historical full replay |
| S07 | P0 | Compaction | Different history/live-data ratios and tombstone fractions; repeat compaction | Time, temporary disk/RSS peaks, bytes reclaimed and resulting open speed | Partial comparison: indexed compaction and compaction during 100-cycle churn |
| S08 | P1 | Integrity | Fully cached and lazy data; indexed/unindexed; increasing database size | Bytes/s, time, allocations and unchanged data | Partial comparison: current-state integrity check at 100K rows |
| S09 | P0 | Storage footprint | Same logical dataset, after commits/checkpoint/compaction; include every sidecar/temp file | Total and peak bytes, bytes/live row and bytes/indexed row | Partial comparison: final closed files; temporary/sidecar peak tracking pending |
| S10 | P0 | I/O amplification | Inserts, updates, deletes, learning, checkpoint and compaction | Bytes read/written, page faults and fsyncs per logical operation | Partial comparison: whole-worker physical I/O byte counters; per-operation tracing pending |
| S11 | P0 | Physical cold reads | First lookup and first scan with a documented isolated cold-cache procedure | Storage latency, faults and physical I/O; distinguish warm process from warm OS cache | Untimed |
| M01 | P0 | Memory growth | Open, load 1/10/50/100% of rows, mutate repeatedly, checkpoint, close | Current/peak RSS, row-cache bytes, retained versions and released mappings | Partial comparison: post-exec peak RSS and current RSS during churn |
| M02 | P1 | Row layout | Narrow integers, 64 columns, null-heavy rows, short/long text and blobs | ns/row, allocation count, encode/decode bytes and storage density | Partial comparison: three-column rows, text lengths and null fractions |
| M03 | P0 | Capacity boundaries | Approach transaction/checkpoint 16 MiB bounds; supported large individual values | Throughput near limits; explicit failure or safe optional-cache omission | Checks only |
| M04 | P0 | Scale | 1K/10K/100K rows now; 1M/10M and increasing total bytes later | Scaling curve, startup/RSS, latency and max successful dataset | Partial comparison: 1K/10K/100K representative datasets |
| M05 | P2 | Larger than memory | Working set 2×/10× a declared RAM budget; random and sequential access | Bounded memory, throughput, page-cache behavior and useful failure modes | Gated: bounded row cache and larger snapshots |
| D01 | P0 | Unchanged schema | Open/init declared schema on a populated lazy database | Metadata-only time; zero unnecessary row hydration or writes | Partial comparison: generated match/init versus SQLite metadata enumeration |
| D02 | P1 | Add fields | Nullable addition, required default and tightening nullability with an explicit default | Reconciliation time, row copies, disk/RSS peaks and preserved IDs | Partial comparison: nullable addition and required default at 10K rows |
| D03 | P1 | Rename/reorder | Explicit rename and field reorder; tables with learned indexes | Reconciliation, cache invalidation/relearning and stable IDs | Partial comparison: rename/reorder with explicit drop at 10K rows |
| D04 | P1 | Convert/remove | Explicit converter/drop; invalid conversion and omitted lossy-change rules | Successful cost and fast atomic rejection; retain original data on failure | Partial comparison: successful integer-to-text conversion and explicit drop |
| D05 | P1 | Many-table schema | 1/10/100/1,000 small tables; matched and changed declarations | Schema lookup, init time and metadata size | Untimed; DSL expansion limits need separate accounting |
| D06 | P2 | Constraints | Unique fields and foreign-key checks; successful/failed writes, cascades and schema changes | Throughput and atomic rejection cost with equivalent enforcement | Gated: uniqueness/foreign-key constraints |
| R01 | P0 | Process-exit recovery | Terminate process before/after durable commit and during checkpoint/compaction | Recovery time and preserved acknowledged commits; classify incomplete work | Partial comparison: exit without DB close, committed tail and uncommitted edit |
| R02 | P0 | Interrupted files | Truncated final transaction/checkpoint, mandatory compacted base and CRC damage | Recovery/rejection latency and unchanged valid committed data | Checks only |
| R03 | P1 | Storage errors | Failed writes/fsync, full disk/quota and detached/replaced database path in isolated fixtures | Error latency, resource cleanup and committed-state outcome after reopen | Partial correctness; timed fault injection needed |
| R04 | P1 | Snapshot/backup workflow | Obtain a coherent backup through a defined application protocol; restore and reopen | Pause time, copy bytes and restored committed-state checksum | Gated: define/test a public backup protocol first |
| C01 | P1 | Lock contention | Two processes try opening the same file; lock owner exits and another opens | Rejection and lock-release latency; explicit exclusive-access semantics | Checks only; no concurrent-reader mode |
| C02 | P2 | Concurrent readers | 1/2/4/8/16 readers, with and without a writer | Aggregate throughput, p99, consistency and writer wait | Gated: reader concurrency |
| C03 | P2 | Concurrent writers | Multiple writers; batch sizes and contention levels | Successful commits/s, fairness and retry/wait behavior | Gated: writer concurrency |
| C04 | P1 | Independent files | Several processes, each owning a separate database | Aggregate throughput and contention for CPU/storage bandwidth | Untimed |
| X01 | P0 | Mixed workload | Read/write ratios 95/5, 80/20 and 50/50; uniform and hot-key access | Operations/s, p99 and lifecycle total with adaptive indexes | Partial comparison: 95/5, 80/20 and 50/50; 1,000 mixed operations |
| X02 | P0 | Application trace | Users/posts/events relations; lookup, append, update, delete and paginated views | Useful requests/s, correctness, RSS and cumulative persistence cost | Untimed |
| X03 | P1 | Append-heavy logs | Timestamped events, burst inserts, retention deletes and recent-event queries | Ingest rows/s, query p99 and storage growth/reclamation | Untimed; indexed ranges gated |
| X04 | P1 | Lookup catalogue | Read-mostly text keys, duplicate names, occasional edits and repeated opens | Request latency, adaptation and startup over many sessions | Untimed |
| X05 | P1 | Compilation/setup | Small/large schemas and many predicates; extension processing, binary size, SQLite statement preparation | Compile/setup times reported separately and amortized over short sessions | Untimed |
| X06 | P2 | Compression/encryption | Off/on with matched algorithms, data and security requirements | Throughput, latency, stored size and CPU overhead | Gated: compression/encryption |

## Dataset and execution matrix

Choose combinations appropriate to each workload and record total logical bytes.
The current runners support at most 100K rows; larger scales are targets, not
existing measurements. A dataset crossing a format limit must be reported as
unsupported until that limit is addressed.

| Dimension | Target variants |
| --- | --- |
| Rows | 1K, 10K, 100K; then 1M and 10M where supported |
| Row/value size | Narrow integer rows; 128 B, 1 KiB and 64 KiB payloads; individual values approaching the supported 1 MiB bound |
| Columns/tables | 1/8/32/64 columns; 1/10/100/1,000 tables, with DSL/runtime limits identified |
| Key distribution | Sequential, uniform random, fixed hot set, Zipf-like skew, duplicates, shared-prefix text and misses |
| Selectivity | 0%, 0.01%, 1%, 10%, 50%, 100%; fixed match counts for materialization cases |
| Nulls | 0%, 10%, 50%, 90%; valid schema types and explicit null behavior |
| History | Fresh database, checkpointed state, short/long tail, many updates, sparse/tombstoned table, compacted state |
| Cache | Same-process warm; new process with warm OS cache; controlled cold OS cache; working set larger than declared memory budget when supported |
| Index state | Disabled, learning, active, reopened mapped, invalidated, rebuilding, evicted and omitted from checkpoint |
| Transactions | 1/10/100/1K/10K operations per transaction, respecting current byte bounds |
| SQLite configuration | WAL/FULL primary comparison; DELETE/FULL separately; cache budget and relevant settings recorded per connection |
| Input/output API | Fresh/reused FlexDB inputs; SQLite prepared/bound statements; count/IDs/selected fields/full rows with equal result consumption |
| Runtime environment | Hardware, storage, filesystem, compiler/library versions, CPU affinity, process load and dataset seed recorded |

## Measurement rules

| Rule | Requirement |
| --- | --- |
| Equivalent work | Same seeded logical data, types, predicates, match counts and committed state. Check result counts and checksums outside timed regions, including result order when part of the contract. Validate updated/deleted values as well as reads. |
| Access paths | Record the actual FlexDB plan/index state and SQLite query plan. Measure both scan parity and each engine's best supported plan; label them separately. |
| Durable comparison | Retain FlexDB fsync and SQLite FULL synchronization. Report data encoding, commit, index publication, checkpoint and close separately and in lifecycle totals. A volatile index build and a durable CREATE INDEX are different phases. |
| Setup accounting | Report compilation, schema setup, initial population and statement preparation separately. Include them in startup/session totals where the application pays those costs. |
| Repetition | Alternate engine order, exclude a declared warmup, use at least five measured runs, retain all samples and report median plus range. Tail latency requires enough per-operation samples; five run medians are not p99 measurements. |
| Latency instrumentation | Record measurement overhead; avoid per-query clock calls dominating tiny lookups. Use batched throughput measurements alongside a calibrated latency experiment. |
| Cache definition | Record process and OS-cache state independently. Reopening alone is not a physical cold-storage test. Use isolated cold-cache experiments without disturbing unrelated workloads. |
| Schema comparison | Compare the same final schema, IDs and preserved data, including SQLite application-side reconciliation/transform work. Unchanged-schema opens and changed-schema rewrites are separate cases. Lossy changes require the same explicit rules. |
| Resources | Record current/peak RSS, index/row-cache allocations where available, all database/sidecar/temp bytes, page faults, I/O bytes and synchronization counts. Label unavailable metrics rather than estimating them as observed facts. |
| Long-running work | Measure time series and memory/file growth, not just a final median; include maintenance spikes and adaptation pauses. |
| Fault outcomes | Record acknowledged commits and verify them after recovery. Process termination and truncated-file checks do not establish power-loss safety; stronger claims require a suitable separate test environment. |
| Unsupported cases | Record the exact feature/limit, input size and failure behavior; never turn a missing capability or failed run into a zero-duration result. |
| Regression policy | Flag a median slowdown over 10% against the same-machine prior baseline; repeat only when noise or a failure leaves the result uncertain. Track correctness failures independently of speed. |

## Existing runners and next batch

| Runner / report | Coverage |
| --- | --- |
| [scripts/benchmark-flexdb.flex](scripts/benchmark-flexdb.flex) | Fresh/reused bulk inserts, ID reads, scans, updates, individual durable writes, checkpoint/close, reopen, first scan, final size and peak RSS; SQLite DELETE and WAL |
| [scripts/benchmark-flexdb-auto.flex](scripts/benchmark-flexdb-auto.flex) | Integer equality scans, automatic learning, indexed counts, indexed-field updates, checkpoint/close, mapped reopen, final size and peak RSS; SQLite WAL with explicit index |
| [scripts/test-flexdb.flex](scripts/test-flexdb.flex) | Functional and recovery checks; these are not timing benchmarks |
| [libs/db/performance.md](libs/db/performance.md) | Current measured comparisons and historical baselines |

Start with **S03/S04/S05** (deferred scan and persistence cost), **W04/A08**
(indexed writes and mapped-cache copying), **Q03/Q04/A03** (text, duplicate keys
and changing demand), then **X01/W10/M01/S09/S10** (mixed work, churn and resource
growth). Add latency distributions across this batch. Larger-than-memory and
concurrency comparisons follow the capabilities required by their gated rows.
