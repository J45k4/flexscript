# Whole-target clear compatibility - 2026-10-27

Status: correctness and the refreshed CPU component pass; latency remains
unqualified. SDL remains the default.

## Problem and change

The native public `gui_clear` and `gui_texture_clear` previously forwarded to
the raw clipped renderer clear. SDL_RenderClear clears the entire current target
regardless of viewport/clip. Calling clear while a clip was active could leave
stale pixels outside the clip on native Wayland, including in cached layers.

The public native calls now use `gr_clear_all`. The shared clear implementation
flushes pending draws, temporarily disables scissoring for a whole-target clear,
and restores scissoring before the next draw. The cached physical rectangle
remains valid. This also works with an empty clip, custom logical canvas size,
opaque window clears and transparent layer clears. Opacity is proven only for
whole opaque window clears; clearing a layer does not change the window's
opacity proof. The raw `gr_clear` keeps its clipped behavior for internal users
and explicit transparent/partial-frame opacity tests.

All shipped changes are Flexscript. The Python harness only orchestrates tests
and compares independently derived expected pixels and captures.

## Regression and correctness evidence

The public-API fixture tests six cases:

1. Queued clipped drawing, opaque whole-window clear, then clipped drawing.
2. Whole-window clear with an empty clip, preserving that empty clip afterwards.
3. Transparent layer clear with a nonempty clip and following clipped drawing.
4. Opaque layer clear with an empty clip and following suppressed drawing.
5. Transparent layer clear with an empty clip.
6. Returning to the window preserves its pixels after layer operations.

Every pixel, including alpha, is checked against a geometric expected result.
Layer targets are 32×24 with a 16×12 logical viewport; the window also uses a
custom logical viewport. Captures must agree byte for byte across both backends
and both compiler pipelines. Pending draws test clear ordering; drawing after
clear tests restored clip state rather than merely inspecting a cache field.

Before the fix, `clear-before-r1/` passes all SDL cases and fails the first native
case (`window-clipped`). That failing executable, capture and logs are retained.
An exploratory dummy/software run failed readback with SDL's “Tried to read
outside of surface bounds”; it is not counted as a GPU result or a passed test.
The fixture uses the matched hardware-rendered private session.

After the fix, `clear-correctness-r1/` passes:

- All six cases on IR/direct × SDL/native, with exact byte equality.
- Independent 22-attribute EGL metadata/configuration and ownership checks on
  both backends/pipelines; native again creates the accepted 3.3 context.
- Independent native GL bindings/state and identical cached/reference pixels,
  still 8 cached batches versus 11 explicitly flushed reference batches.
- Native real Pinyin, raw presentation/commit association, and actual bad-display
  swap failure cleanup without counting a failed presentation.

`clear-window-r1/` separately passes private Weston 1x IR / 2x direct, including
all 26 lifecycle/opacity checkpoints, repeated remaps, bounded descriptors and
framebuffer pixels. This protects the retained raw clipped-clear behavior.

The rebuilt complete package is `build/migration/clear-candidate/`; the compiled
Collie UI benchmark is `clear-benchmark/`. Final clear/EGL and measurement sources
are frozen in `clear-source-snapshot/` with a SHA-256 manifest. The final fixture
passes again before the full application/measurement run in
`clear-qualification-r1/`.

## Refreshed performance measurement

The complete native Collie/service passes real Pinyin composition/commit and
candidate-popup checks. The matched four-scene SDL/native correctness checks
also pass. The same rebuilt benchmark executable then runs both backends with
GPU query instrumentation disabled. Seven alternating 160-update pairs cover
all four primary CPU cases, followed by scroll/selection/Unicode typing with
fixed 23 ms arrivals, including dispatch waiting. No other build or test workload
runs during measurement. Raw outliers remain; uncertainty resamples whole runs.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/clear-ime \
  --collie build/migration/clear-candidate/collie \
  --canvas-clear-fixture build/migration/clear-ir \
  --canvas-clear-fixture build/migration/clear-direct \
  --paired-benchmark build/migration/clear-benchmark/ui-benchmark \
  --paired-performance --paired-arrival-ms 23 \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/clear-qualification-r1
```

This run supersedes neither physical input/scanout acceptance nor the remaining
startup, lifetime/resource, kernel wake and full-feature gates. A CPU pass alone
cannot change the default. See `SLD_migration.md` for the unchanged requirements.

The primary CPU run has completed all 56 child runs / **8,960 updates**. Its
component gate passes. All four workloads improve median and p95 CPU time:

| Workload | SDL median / p95 ms | Native median / p95 ms |
| --- | ---: | ---: |
| scroll | 1.489 / 2.385 | 1.302 / 1.979 |
| selection | 1.509 / 2.403 | 1.311 / 2.071 |
| stream | 17.511 / 30.816 | 9.106 / 14.168 |
| navigation | 9.624 / 12.973 | 7.484 / 11.864 |

The geometric mean of pooled SDL/native CPU ratios is **1.343× median** and
**1.350× p95**, equivalent to about 25.6% and 25.9% less CPU respectively.
Whole-run paired uncertainty gives lower 95% speedup bounds **1.261× median**
and **1.340× p95**, above the unchanged 1.25× minimum. These figures are the
current backend comparison, not an attribution of a speedup to the clear fix.

The separate arrival run completed all 42 child runs / **6,720 updates**. Together
the two measured suites contain **15,680 presentations and zero discards**.
Queries are disabled in both suites. Full application correctness and all
private-session shutdowns complete successfully.

Fixed-arrival input-to-presentation p95, milliseconds:

| Workload | SDL | Native | Mean paired native minus SDL p95, 95% interval |
| --- | ---: | ---: | ---: |
| scroll | 5.946 | 5.792 | -2.614 (-7.842 to +0.297) |
| selection | 6.549 | 6.541 | -0.080 (-1.194 to +0.792) |
| typing | 10.869 | 11.084 | -0.351 (-2.469 to +1.589) |

All intervals overlap zero and permit regression; neither the non-regression
requirement nor the improvement target is established. In particular the sixth
scroll pair contains SDL p95 **21.254 ms** versus native **3.320 ms**, a large
asymmetry retained in full. It strongly affects the mean paired difference and
has not been attributed to a particular host interruption or driver cause.
Pooled p95 alone must not be used to call this case passed.

The separately retained callback-paced primary run still shows a confident
scrolling regression: mean paired native-minus-SDL p95 **+0.602 ms**, 95%
**+0.107 to +1.189 ms**. Its pooled p95 values are 17.062 ms SDL / 17.778 ms native.
The two pacing methods measure different arrival boundaries; the fixed-arrival
result does not erase the callback-paced failure.

Even the passing aggregate CPU component is not a full frame-budget result:
native streaming/navigation CPU p95 is 14.168/11.864 ms, above half a nominal
60 Hz interval. Actual hardware cadence is not measured here: compositor
feedback has zero hardware flags and refresh prediction. The migration remains
incomplete, with no change to release thresholds or the default backend.

All hashes and the scoped host-cleanup audit are retained under
`build/migration/context-clear-final-evidence.json` and
`context-clear-host-cleanup.json`. Work remains local and uncommitted.
