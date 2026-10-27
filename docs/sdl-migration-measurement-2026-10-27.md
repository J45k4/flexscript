# Same-pass measurement reuse - 2026-10-27

Status: retained. Component correctness, the native control and the fresh SDL
CPU component pass. Presentation latency and full migration acceptance remain
unproven. SDL remains the default.

## Scope and correctness

Phase counters from the clear-compatible baseline show layout work averaging
about 3.75 ms per native streaming update and 2.03 ms per navigation update.
Weighted placement can remeasure subtrees already measured at the same width
during that arrange pass. This candidate reuses those results within one pass.
It changes shared Flexscript layout code on both backends; any benefit must not
be attributed solely to replacing SDL.

A fixed 2,048-entry table retains a width and pass number per node, **32 KiB**
total. Each arrange starts a new pass, so no result survives an application
update, edit, image binding or scale change into another draw. Reflowing a
descendant at a different width invalidates its ancestors: their prior desired
sizes may depend on the descendant's earlier measurements. Rollover clears the
table, and UI close frees it. This adds no timer, wakeup or unbounded cache.

`measure-cpu-r4/` passes IR/direct on the SDL dummy backend.
`measure-correctness-r1/measure-reuse/` passes IR/direct × SDL/native on the GPU,
**80 draw comparisons** total. Each compares every retained node's geometry,
desired/content/scroll dimensions and every framebuffer byte against forced
full traversal. All tested draws eliminate repeated measurements. Cases include
nested weighted and intrinsic containers, odd/even widths, padding/font/content/
visibility changes, local editing, scrolling/follow, unresolved/resolved/rebound
images, renderer reset, pass rollover and close/reopen ownership. The image
dimension replacement is actually loaded and asserted. Existing weighted-row
rounding/texture stability checks pass too.

`measure-negative-r1/` removes only ancestor invalidation from a flattened test
source. It is rejected by a deliberate descendant-at-another-width reflow test,
showing that the comparator catches this stale-measurement failure mode.

The initial comparison fixture stalled due to a missing test-loop increment.
Only those two confirmed private fixtures were force-stopped after SIGTERM did
not terminate their non-polling loops. The source/diagnosis is preserved in
`measure-fixture-debug-r1/`; it supplies no correctness/performance result.
A temporary flattening helper also crashed because its export map had not been
initialized. The core confirms a null-pointer load; initializing that helper's
map fixes it. The extracted core was removed. Neither failure was in Collie or
the application implementation. Failed attempts remain separate from passes.

## Controlled experiment and decision criterion

Both A/B variants use the new compiled production Collie UI and identical
measurement-counter/reporting code. Their flattened sources differ in exactly
one global default: layout reuse off versus on. Both allocate the bounded table.
Both request GL 3.3 and use the same EGL buffers, fonts, content, GPU and viewport.
Query instrumentation is disabled; fixed 23 ms arrivals include dispatch waiting.
Seven alternating pairs of 160 updates cover scroll, selection, stream,
navigation and Unicode typing. The first long selection captures must be byte
identical. Per-run measurement counts must fall on every paired workload.

The comparison records whole-run paired CPU median/p95 speedup uncertainty in
addition to presentation p95 differences, without removing outliers. A
demonstrated CPU improvement in streaming or navigation, without a confident
CPU or latency regression elsewhere, justifies proceeding to the full SDL
qualification. If that is not established, preserve the evidence and reconsider
the implementation. Operation-count reduction alone does not prove a speedup.
No numerical release gate in `SLD_migration.md` is changed by this experiment.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/clear-ime \
  --collie build/migration/measure-candidate/collie \
  --paired-benchmark build/migration/measure-benchmark/ui-benchmark \
  --native-submit-control build/migration/measure-control-off/ui-benchmark \
  --native-control-scenes scroll selection stream navigation typing \
  --native-control-contexts 3.3 3.3 --native-measure-reuse-control \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/measure-control-r1
```

This is a native-only control, not SDL qualification or physical input/scanout
evidence. Full Collie/Pinyin and matched UI correctness run before measurement.
No other builds or test workloads run during measured updates.

## Completed native control

`measure-control-r1/native-submission-control/report.json` completed **70 child
runs / 11,200 updates**, all presented without discards. Actual GL versions and
paired EGL buffer settings agree. Every paired scene reduces actual measurement
counts; scroll/selection use 130 instead of 301 measurements per update,
streaming 139 instead of 326, navigation 93 instead of 207. Long selection
captures agree byte for byte.

Whole-run paired geometric-mean CPU speedups (reuse off / on), with 95% intervals:

| Workload | Median CPU speedup | p95 CPU speedup |
| --- | ---: | ---: |
| scroll | 1.294× (1.265–1.324) | 1.375× (1.238–1.555) |
| selection | 1.285× (1.275–1.293) | 1.340× (1.265–1.423) |
| stream | 1.042× (1.024–1.063) | 1.083× (1.011–1.205) |
| navigation | 1.011× (1.002–1.018) | 0.950× (0.832–1.020) |
| typing | 1.050× (1.029–1.063) | 1.073× (1.058–1.087) |

Streaming establishes the predeclared CPU benefit. No other CPU/presentation
case establishes a confident regression, so the criterion for proceeding is met.
This does not establish non-regression for every case: navigation p95 remains
uncertain and its pooled CPU p95 increases.

Mean paired presentation-p95 differences (on minus off), milliseconds:

| Workload | Difference, 95% interval |
| --- | ---: |
| scroll | -0.582 (-0.895 to -0.332) |
| selection | -0.215 (-0.505 to +0.071) |
| stream | -0.703 (-1.996 to +0.268) |
| navigation | +2.256 (-0.172 to +6.754) |
| typing | +0.115 (-0.359 to +0.583) |

Scrolling improves in all seven pairs. The other intervals overlap zero. The
seventh navigation pair retains p95 **24.925 ms on / 9.434 ms off**, with no
outlier removal or claimed interruption/driver attribution. Its uncertainty must
carry forward into qualification, rather than treating the trial as universally
faster. The complete private compositor shut down normally.

The full SDL run uses `measure-benchmark/ui-benchmark` for both SDL and native, with
seven pairs for all four primary CPU cases and separate fixed-arrival scroll,
selection and Unicode typing. Thus both backends receive the shared layout
optimization; this native-only control is not substituted for those SDL gates.

## Completed SDL comparison

`measure-qualification-r1/` passes complete native Collie/service Pinyin and
candidate-popup checks, matched four-scene correctness and the additional
Unicode typing check. Seven alternating pairs of 160 updates per case complete
**8,960 primary CPU updates** plus **6,720 fixed-arrival updates**, without
discards. Queries are disabled. Builds and unrelated tests do not overlap the
measurements. Compositor shutdown completes normally. The command is the clear
qualification command with the package/benchmark/output paths replaced by
`measure-candidate/`, `measure-benchmark/` and `measure-qualification-r1/`.

CPU milliseconds, median / p95:

| Workload | SDL | Native |
| --- | ---: | ---: |
| scroll | 1.156 / 1.270 | 0.961 / 1.068 |
| selection | 1.116 / 1.541 | 0.920 / 1.055 |
| stream | 15.311 / 24.588 | 6.960 / 8.746 |
| navigation | 9.283 / 11.328 | 7.178 / 7.753 |

All four improve. Pooled geometric-mean speedups are **1.427× median** and
**1.634× p95**, about **29.9% / 38.8% less CPU** respectively. Whole-run paired
95% lower bounds are **1.371× / 1.520×**, above the unchanged 1.25× requirement.
The CPU component gate passes. These are current native-versus-SDL measurements;
the separate on/off control establishes the effect of shared measurement reuse.

Fixed 23 ms arrival-to-presentation p95, milliseconds:

| Workload | SDL | Native | Mean paired native minus SDL p95, 95% interval |
| --- | ---: | ---: | ---: |
| scroll | 5.137 | 5.882 | +0.571 (-0.050 to +0.935) |
| selection | 5.189 | 5.286 | +0.220 (-0.089 to +0.674) |
| typing | 8.815 | 8.968 | +0.079 (-0.431 to +0.666) |

These intervals permit regression; non-regression and the improvement target
are not established. Scroll regresses in six pairs, with the seventh retained
as measured; no run is removed to strengthen either conclusion.

Callback-paced presentation still shows confident small scrolling and selection
regressions: **+0.155 ms** (95% +0.054 to +0.237) and **+0.153 ms** (+0.069 to
+0.235), both positive in all seven pairs. Native streaming and navigation improve
under that pacing, but those wins do not waive interactive latency requirements.

Native streaming CPU p95 **8.746 ms** still exceeds half a nominal 60 Hz interval;
its p99 is 9.260 ms. Navigation CPU p95/p99 is 7.753/8.490 ms. Actual hardware
cadence, missed-scanout rate and scanout latency remain unverified: these headless
records have zero hardware flags and refresh prediction. Startup/first-use,
active lifetime/memory, full feature/input coverage and GPU CI remain open too.

The measured shared state/patch phase still averages about 2.33 ms for streaming
and 2.51 ms for navigation (monotonic wall-clock phases, not exclusive CPU
attribution). Inspection shows packet ownership transfer and per-node model
compaction repeatedly serialize then parse JSON. This is a concrete candidate
for the next isolated profile/optimization; no improvement from changing it has
been implemented or claimed here.

Current source, binary, frozen-control and raw-result hashes are recorded in
`build/migration/measure-final-evidence.json`; the scoped cleanup audit is
`measure-host-cleanup.json`. Work is local and uncommitted.
