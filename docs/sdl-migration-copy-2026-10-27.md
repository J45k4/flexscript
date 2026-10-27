# Direct JSON ownership copies - 2026-10-27

Status: retained. Correctness, native control and the fresh SDL CPU component
pass. Interactive presentation latency still fails acceptance. SDL remains
default; no prior package's result is substituted for this candidate's checks.

## Problem and implementation

The last qualified package's shared state/patch phase averages about 2.33 ms per
native streaming update and 2.51 ms per navigation update. Those are wall-clock
phase measurements, not exclusive CPU attribution. Source inspection finds
repeated `j_parse(j_dump(value))` copies for incoming packets, every retained
widget descriptor, image bindings and returned editor events.

`j_copy` now copies valid JSON nodes directly into the current Flexscript host
arena. Nodes, array/object vectors, pairs, keys and text all belong to the
destination. It keeps field order, canonical null/boolean values, signed integer
values and exact numeric metadata; the latter is validated before copying.
Reader limits remain: depth 64, arrays 65,536 entries, objects 4,096 fields.
Vectors keep power-of-two capacities so subsequent ordinary growth is valid.
Copying does not modify parser globals. It adds no runtime library or cache.

The retained UI uses the direct path for packet ownership transfer, model/image
compaction and returned events. The diagnostic `ud_direct_copy` switch retains
the round-trip path for identical-source tests. Compaction still frees the old
arena on every update; no deferred collection or larger retention budget is
introduced. Both SDL and native receive the shared implementation.

Exact fractional/exponent/large-number nodes are supported by the new generic
copy API and preserve their original text. The UI differential trace uses the
node types accepted by its previous strict round-trip reader; preserving full
numeric metadata is tested independently, not misreported as an old-reader pass.

## Correctness evidence

`direct-copy-json-r4/` passes both IR and direct pipelines. A Python JSON/Decimal
oracle checks output values independently. The Flexscript fixture checks every
owned pointer before scrubbing and freeing the original arena, then verifies the
copy again. It also checks parser-state independence, collection growth, signed
integer extremes, canonical primitives, Unicode/control text, exact metadata,
maximum collections and maximum valid depth. Seven negative cases reject excess
depth/cycles, unknown kinds, invalid numeric text, excess array/object sizes and
duplicate fields.

`direct-copy-negative-r1/` deliberately borrows text or field-key pointers instead
of copying them. Both variants are rejected by the ownership verifier before
source release. Failed fixture compilations (missing test import and an
unsupported spelling of the minimum integer literal) are not passing evidence;
the final fixture uses the equivalent in-range integer expression.

`direct-copy-ui-cpu-r1/` passes IR/direct on SDL dummy. The private GPU matrix
`direct-copy-correctness-r1/model-copy/` passes IR/direct × SDL/native: **60 state,
geometry and framebuffer comparisons** against round-trip copying, plus **1,600
compaction updates** across those four variants. Every incoming packet's caller
arena is released. All retained JSON/key pointers must belong to the UI pool;
returned editor events survive later model compaction. Cases cover Unicode
editing/echo, style/text/visibility patches, keyed moves, scrolling, resize,
controlled drafts, image bindings, removal/reinsertion and close cleanup.
Both paths retain a stable 1 MiB model arena in this fixture; this is not a full
application memory-soak result. Caret animation is hidden for deterministic pixel
comparison; real Pinyin/candidate-popup coverage is tested separately.

The current ownership path also passes the existing weighted-row and same-pass
measurement tests on the CPU. Those prior caches/layout algorithms are unchanged.
The generic JSON and model tests are wired into the CPU workflow; remote CI has
not been run. All new shipped implementation/build code remains Flexscript;
Python supplies independent test orchestration and value checks.

## Native control and decision criterion

The two flattened benchmarks differ in exactly one global default:
`ud_direct_copy=0` versus `ud_direct_copy=1`. Both retain layout reuse, the same
renderer/context/buffers/fonts/content and all reporting code. Seven alternating
pairs of 160 updates cover all five workloads, with fixed 23 ms arrivals and
query instrumentation off. Every pair must perform the same number of layout
measurements and the first long selection capture must be byte-identical.

A demonstrated streaming or navigation CPU median/p95 benefit, without a
confident CPU or latency regression elsewhere, justifies proceeding to fresh SDL
qualification. A counter reduction or small fixture pass is not a release gate.
Outliers remain and paired uncertainty resamples whole runs. No concurrent build
or test workload is permitted during measured updates.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/clear-ime \
  --collie build/migration/direct-copy-candidate/collie \
  --paired-benchmark build/migration/direct-copy-benchmark/ui-benchmark \
  --native-submit-control build/migration/direct-copy-control-off/ui-benchmark \
  --native-control-scenes scroll selection stream navigation typing \
  --native-control-contexts 3.3 3.3 --native-direct-copy-control \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/direct-copy-control-r1
```

This is native-only evidence. Full Collie/Pinyin and matched-scene correctness
precede timing. Hardware scanout, startup, memory/lifetime, full-feature/input and
GPU CI gates still apply before changing the default.

## Completed native control

`direct-copy-control-r1/native-submission-control/report.json` completes all
**70 runs / 11,200 presented updates**, without discards. Both actual contexts are
GL3.3 and paired EGL settings agree. Every pair performs the same number of
layout measurements; the long selection capture matches across all 6,400,000
bytes (SHA-256 `ddc86757f667660f8f71ddfb31a815eeb8dee89fa996e6a67a36d6d5fc87ca7d`).

Whole-run paired geometric-mean CPU speedups (round trip / direct), 95% interval:

| Workload | Median | p95 |
| --- | ---: | ---: |
| scroll | 1.044× (1.032–1.054) | 1.108× (0.976–1.229) |
| selection | 1.040× (0.955–1.100) | 1.141× (1.071–1.227) |
| stream | 1.350× (1.314–1.382) | 1.160× (1.030–1.295) |
| navigation | 1.497× (1.445–1.553) | 1.413× (1.282–1.555) |
| typing | 1.548× (1.528–1.569) | 1.703× (1.531–1.913) |

Streaming and navigation demonstrate the predeclared CPU benefit. No other
CPU/presentation case establishes a confident regression, satisfying the
criterion for proceeding. This does not establish universal non-regression:
scroll CPU p95 and selection median remain uncertain.

Mean paired direct-minus-round-trip presentation p95, milliseconds:

| Workload | Difference, 95% interval |
| --- | ---: |
| scroll | -0.063 (-0.248 to +0.116) |
| selection | -0.237 (-1.131 to +0.444) |
| stream | -1.408 (-2.624 to -0.223) |
| navigation | -3.084 (-4.756 to -1.730) |
| typing | -3.036 (-3.708 to -2.341) |

Navigation and typing improve in every pair. Streaming includes two worse pairs;
all outliers remain. These comparisons isolate the selected ownership-copy path
on native; they are not gains over SDL. Both backends receive the implementation
in the fresh qualification. The full native Collie/service/Pinyin and matched
four-scene checks pass before timing, and the private compositor stops normally.

## Completed SDL comparison

`direct-copy-qualification-r1/` passes full native Collie/Pinyin/candidate-popup,
matched four-scene rendering and the additional Unicode typing check. It then
completes **8,960 primary CPU updates** and **6,720 fixed-arrival updates**, with
no discards, queries, concurrent builds or other test workloads. Shutdown is
normal. The command is the prior full SDL qualification command using
`direct-copy-candidate/`, `direct-copy-benchmark/` and
`direct-copy-qualification-r1/` paths.

CPU median / p95, milliseconds:

| Workload | SDL | Native |
| --- | ---: | ---: |
| scroll | 1.219 / 1.942 | 1.039 / 1.595 |
| selection | 1.185 / 1.845 | 1.020 / 1.546 |
| stream | 14.099 / 23.714 | 5.560 / 8.395 |
| navigation | 6.801 / 9.836 | 5.345 / 6.031 |

All four improve. Pooled geometric-mean SDL/native ratios are **1.448× median**
and **1.608× p95**, about **31.0% / 37.8% less CPU**. Paired whole-run 95% lower
bounds are **1.407× / 1.543×**, above the unchanged 1.25× minimum. The current CPU
component passes. The shared patch phase averages roughly 0.49 ms stream and
0.69 ms navigation on native; the separate native control establishes the
copy-path gain, while these figures compare equally updated backends.

Fixed 23 ms arrival-to-presentation p95, milliseconds:

| Workload | SDL | Native | Mean paired native minus SDL p95, 95% interval |
| --- | ---: | ---: | ---: |
| scroll | 3.417 | 3.599 | +0.108 (-0.123 to +0.468) |
| selection | 3.482 | 3.993 | +0.470 (-0.058 to +1.047) |
| typing | 8.469 | 9.671 | +1.243 (+0.775 to +1.926) |

Typing regresses in every pair; pooled p95 is about 14.2% higher native. This
fails the interactive non-regression requirement and the general repeatable
slowdown guard. Scroll/selection intervals still permit regression. Improving
native typing relative to the round-trip implementation does not establish
parity with the equally improved SDL baseline.

Callback-paced selection also regresses **+0.314 ms** (95% +0.069 to +0.559).
Scrolling is uncertain (+0.102 ms, -0.446 to +0.557); navigation has a small
positive difference (+0.031 ms, +0.007 to +0.055). Streaming improves -9.795 ms
(-11.488 to -8.777), which does not waive interactive requirements. No outlier
is removed or attributed to an unmeasured interruption.

Native stream CPU p95 **8.395 ms** still exceeds half a nominal 60 Hz interval;
p99 is 10.968 ms. Navigation p95/p99 is 6.031/6.807 ms. Actual hardware cadence,
scanout and missed-interval acceptance remain unverified on this headless
compositor, whose hardware flags/refresh prediction are zero. Startup, active
memory/lifetime, complete feature/input and GPU CI requirements also remain.

Input inspection provides a next diagnostic lead, not a causal result: native
surrounding-text/rectangle setters already suppress unchanged state, but
`wm_done` queues an editor transaction for empty acknowledgements as well as
actual edits. The typing fixture records two polled events per update on native.
Protocol tracing should distinguish harmless acknowledgements from real
composition/commit/delete events before changing this path. IME functionality
must remain enabled and real Pinyin/serial/focus/ownership checks must still pass.

Source/build/raw-result hashes are in
`build/migration/direct-copy-final-evidence.json`, with a scoped host audit in
`direct-copy-host-cleanup.json`. Work remains local and uncommitted.
