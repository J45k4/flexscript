# SDL migration paired measurements - 2026-10-27

**Not qualified for a default switch.** After the shared weighted-layout fix, the matched CPU component passes locally. The remaining acceptance gates are open; SDL remains the default.

This is a private headless NVIDIA/Wayland comparison, with compositor feedback on both backends. It establishes neither physical scanout/input latency nor complete migration acceptance.

Later known-opacity, flush, GPU and packed-vertex work is recorded in
[the renderer diagnostic report](sdl-migration-gpu-2026-10-27.md). Its current
packed candidate passes the local CPU component but still fails scroll/selection
latency nonregression. The historical R2/R3 measurements below remain unchanged.

## Configuration and measurement boundary

- CPU: Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz; benchmark process pinned to CPU 3.
- Platform: `Linux-7.2.8-9-omarchy-x86_64-with-glibc2.44`.
- GPU: NVIDIA GeForce RTX 2070/PCIe/SSE2, reported by each client GL renderer; accelerated SDL `opengl` versus native EGL/OpenGL. Driver 615.78.08.
- SDL runtime is sdl2-compat 2.32.74 over SDL3 3.4.18; Wayland client 1.26.0. Installed public SDL ABI was checked independently.
- Same compiled Collie UI executable, fixtures, image asset and fonts; backend selected explicitly per child. No software SDL baseline.
- 1280x800 logical viewport, 1600x1000 framebuffer, 1.25x scale, nominal headless output mode 1600x1000@60 Hz.
- Seven alternating paired runs per workload, 160 measured updates per child after 48 warmups: 1,120 samples per backend/workload, 8,960 measured updates total.
- `SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0` is explicit for both children. With the installed compatibility runtime default, SDL returned 1600x1000 logical coordinates while native returned 1280x800; that mismatched run was rejected. The documented hint restores equivalent DPI-aware layout. No desktop/system configuration was changed.
- CPU work uses thread active time from normalized input/update dispatch through layout/text/upload/drawing, present submission and arena cleanup. Blocked wall time is excluded by `CLOCK_THREAD_CPUTIME_ID`; before-present, present and cleanup CPU are retained separately. Whole-process/thread CPU over the measured interval is also recorded, including driver threads and event servicing.
- Every measured update has a matching compositor presentation outcome; none were discarded or lost. All feedback uses advertised `CLOCK_MONOTONIC` (1). Flags, refresh prediction and sequence are zero: hardware timing and missed-refresh counts are unavailable.
- Both backends used a decoded/uploaded inline image preview. Every scroll sample changes offset, every selection sample changes caret, and rendered selection text is recorded. Actual window resize events update the compiled view viewport. Paired captures were visually inspected for readable text, Markdown/table/selection and the image preview; rounded-corner pixels were also checked. This is not a complete typography/feature equivalence audit.
- No concurrent agent builds/tests ran during timed intervals. Host interruption tracing was not captured, so remaining run-to-run variation has no confirmed attribution; all samples/outliers are retained.

The [SDL scaling hint](https://wiki.libsdl.org/SDL3/SDL_HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY) controls legacy 1:1 output versus normal desktop scaling. This report records the configured comparison, not an unqualified result for every SDL/default-DPI configuration.

## Post-layout-fix active CPU results (R3)

Tracing found that the Timeline tab alternated between 107-pixel measurement and 108-pixel placement on every frame. Weighted-row measurement now uses the same cumulative rounding as placement. Both backends were rebuilt with the fix. The regression checks odd/even remainders, unchanged framebuffer pixels, zero warm texture/text work and invalidation on a real width change. IR/direct CPU and native GPU checks pass; all 14 full Collie desktop layout groups pass against the rebuilt package.

The new full comparison uses the configuration and CPU boundary above: seven alternating pairs, 1,120 samples per backend/workload, all 8,960 measured updates presented. Warm scroll/selection now create/upload no textures and measure/rasterize no text on either backend. This shared improvement is not counted as a native-only gain against a stale SDL baseline.

| Workload | SDL median / p95 | Native median / p95 | SDL/native median / p95 |
| --- | ---: | ---: | ---: |
| scroll | 1.495 / 2.244 | 1.364 / 2.156 | 1.096 / 1.041 |
| selection | 1.498 / 2.376 | 1.378 / 2.175 | 1.087 / 1.093 |
| stream | 15.847 / 25.057 | 7.475 / 9.368 | 2.120 / 2.675 |
| navigation | 9.544 / 11.270 | 7.385 / 7.951 | 1.292 / 1.417 |

Pooled geometric-mean speedups are **1.3441 median** and **1.4409 p95**: 25.60% and 30.60% less CPU time. All four workloads improve individually in both measures. Run-level paired median speedup is 1.3343, bootstrap 95% interval **1.3159–1.3555**; paired p95 is 1.4315, interval **1.3729–1.4879**. Both lower bounds clear 1.25. This passes the CPU component for this private configuration; it does not pass the full migration.

Native scroll/selection CPU p99s are 2.276/2.249 ms, below the nominal 60-Hz CPU budgets. Hardware cadence remains unknown. Headless update-to-presentation p95s are 16.464/16.447 ms on SDL versus 16.701/16.667 ms on native for scroll/selection. Those slightly larger native values must be assessed with paired uncertainty; they are not automatically a latency tie because both are near a refresh floor. Streaming is 28.051 versus 16.687 ms, navigation 16.507 versus 16.694 ms. Physical input, hardware scanout and the other gates remain unqualified.

Raw post-fix data: `build/migration/observer-paired-full-r3/paired-performance/report.json`. Diagnostic-only traces: `build/migration/observer-cache-trace/summary.json`. Matching pixel/cache checks: `build/migration/observer-weighted-verified/`. Earlier runs below remain preserved and describe their actual source/timer boundaries.

## Callback-paced typing and latency uncertainty

The additional typing fixture uses the real compiled composer. It repeats `ä中👋 -> ä中 -> ä -> empty` through normalized UTF-8 commit/backspace events and the model echo, asserting text, focus and caret after **every** update. Each backspace removes one grapheme. This bounded cycle avoids progressively longer drafts. It is an additional latency workload and never replaces a primary workload in the four-case CPU aggregate.

`build/migration/observer-typing-r1/` contains 24-sample matched correctness captures and seven alternating pairs of 160 measured typing updates. All **2,240** updates were presented, with no lost/discarded outcomes. Typing update-to-presentation pooled p95 is **16.424 ms SDL / 16.659 ms native**. CPU medians/p95s are 5.479/9.002 ms SDL and 5.411/8.921 ms native; typing is not included in R3's CPU aggregate.

Paired whole-run p95 presentation differences, native minus SDL:

| Workload / source | Mean difference | Bootstrap 95% interval |
| --- | ---: | ---: |
| scroll / R3 | +0.265 ms | +0.166 to +0.371 ms |
| selection / R3 | +0.229 ms | +0.128 to +0.342 ms |
| typing / typing R1 | +0.215 ms | +0.107 to +0.331 ms |
| stream / R3 | -11.348 ms | -11.806 to -10.872 ms |
| navigation / R3 | +0.133 ms | -0.056 to +0.323 ms |

**The current dispatch-origin latency comparison fails nonregression for scroll, selection and typing.** Their intervals are above zero; the refresh floor does not turn them into passed ties. The additional R3 analysis is in `build/migration/observer-r3-analysis/report.json`; it reproduces the immutable R3 CPU results using the updated reporting logic. The reporter now requires confidence bounds as well as point estimates for its CPU component, and leaves the CPU verdict unavailable when the four primary scenes are incomplete.

These runs dispatch the replay immediately after each backend delivers a frame callback. A separate fixed-arrival mode now schedules replay at identical intervals independent of callback delivery, preserving scheduled origin, dispatch wait and presentation as separate timestamps. `gui_presentation_track_at` records that known origin in the compositor's advertised clock and rejects negative/future arrivals. It does not infer a clock conversion. Scheduled replay explicitly requires the advertised monotonic clock. Fixed-arrival results must be reported separately; they do not erase the dispatch-origin regression or establish physical input latency.

## Fixed scheduled arrivals (additional latency run)

`build/migration/observer-arrivals-r1/arrival-performance/` records an additional seven alternating pairs of 160 updates for **scroll, selection and typing**, with arrivals 23 ms apart. The same interval is used on both backends and is deliberately independent of frame callbacks. Every scheduled origin is retained without dropping or retiming an update. Presentation latency is exactly dispatch waiting plus dispatch-to-presentation; these components are recorded separately. All **6,720** measured updates were presented, without discards or lost records. This three-scene diagnostic does not produce a replacement four-scene CPU aggregate.

| Workload | SDL scheduled-arrival-to-presentation p95 | Native p95 | Paired mean p95 difference, native minus SDL (95% interval) |
| --- | ---: | ---: | ---: |
| scroll | 5.615 ms | 6.587 ms | +0.692 ms (+0.0003 to +1.201 ms) |
| selection | 5.594 ms | 5.953 ms | +0.503 ms (+0.145 to +0.955 ms) |
| typing | 9.859 ms | 9.182 ms | -0.387 ms (-1.325 to +0.700 ms) |

**Latency remains unqualified.** Selection is slower beyond this run's uncertainty; scrolling's interval is narrowly above zero. Typing is inconclusive. The lower virtual-compositor latencies do not contradict the earlier callback-paced floor: arrivals now occur independently of callbacks, and neither run supplies hardware refresh/scanout timestamps. The 23-ms replay is an additional arrival experiment, not a replacement for sustained-refresh or physical-input acceptance. Host interruption/frequency tracing is still absent; no outlier was removed or attributed to an unverified cause.

The same session also passes current-source full Collie Pinyin in the ordinary event loop, native weighted-layout pixel/cache checks, direct-pipeline SDL observer ownership/input checks, native raw presentation matching and actual EGL bad-display failure cleanup. Both presentation observers retain the caller's advertised-clock origin; invalid/future origins allocate no tag in CPU IR/direct tests. All test surfaces are private/headless.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n 19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/observer-arrival-ime \
  --collie build/migration/observer-candidate-arrivals/collie \
  --weighted-fixture build/migration/weighted-layout-direct \
  --sdl-presentation-fixture build/migration/observer-arrival-sdl-direct \
  --presentation-fixture build/migration/observer-arrival-presentation \
  --paired-benchmark build/migration/observer-benchmark-arrivals/ui-benchmark \
  --paired-arrival-ms 23 --package-root build/migration/ime-lab/root \
  --scale 1250 --out build/migration/observer-arrivals-r1
```

## Corrected active CPU results before the layout fix (R2)

Numbers below are pooled medians/p95s across seven runs, in milliseconds. Ratios greater than one favor native.

| Workload | SDL median / p95 | Native median / p95 | SDL/native median / p95 |
| --- | ---: | ---: | ---: |
| scroll | 2.298 / 3.349 | 2.325 / 3.129 | 0.988 / 1.070 |
| selection | 1.933 / 3.031 | 1.852 / 2.986 | 1.044 / 1.015 |
| stream | 16.602 / 25.882 | 8.422 / 14.705 | 1.971 / 1.760 |
| navigation | 10.563 / 12.063 | 7.858 / 9.173 | 1.344 / 1.315 |

Pooled geometric-mean speedups are 1.2859 for median CPU work and 1.2592 for p95 (22.23% and 20.59% lower CPU time). These point estimates do not override a failed individual workload or uncertainty.

Run-level paired median speedup is 1.2783, with a bootstrap 95% interval of 1.2171–1.3357. Its lower bound is below the required 1.25 speedup for 20% less time. The paired p95 estimate is 1.3601, interval 1.2692–1.4536. Bootstrap resamples whole paired runs, not supposedly independent individual frames.

**This pre-fix CPU run fails:** scrolling median does not improve, and the median uncertainty does not establish the mandatory 20% gain. Selection improves modestly; streaming and navigation improve substantially. No gate was relaxed after seeing the data.

## Headless presentation observations before the layout fix (R2)

| Workload | SDL p95 update-to-presentation | Native p95 |
| --- | ---: | ---: |
| scroll | 16.509 ms | 16.619 ms |
| selection | 17.575 ms | 16.615 ms |
| stream | 27.967 ms | 16.693 ms |
| navigation | 16.426 ms | 16.632 ms |

The boundary starts just before normalized replay/update dispatch, not physical input arrival. Both backends use equivalent application frame-callback pacing while observed. These values sit near a virtual 60-Hz scheduling floor for light workloads; zero hardware flags/refresh/sequence prevent a hardware cadence verdict. Typing latency, startup/first useful presentation, physical input, GPU execution and mixed-output behavior remain unqualified. `first_frame_ns` in raw data is the older swap-return diagnostic, not a passed startup gate.

## What this points to next

- The repeated width/cache transition was traced and fixed above. Continue using measured costs and retain the shared fix in both backend fixtures.
- Protect visible text, caret/selection, image, clip and viewport correctness while reducing retained layout/text-cache work. Apply shared UI fixes fairly to both backend fixtures and measure again; do not leave SDL deliberately slower to manufacture a win.
- Keep presentation CPU/submission and cleanup inside the CPU boundary. Add host interruption/frequency evidence for later measurements instead of explaining away noisy runs.
- The remaining plan gates include real typing/input latency, cold/warm startup/chat-switch presentation, settled idle, RSS/PSS/texture lifetime, GPU execution, broader font/input/window acceptance, native GPU CI and real desktop acceptance. SDL stays the default.

## Evidence, failures and reproduction

- Corrected pre-fix raw samples, per-run ratios, 10,000-resample run-level intervals, source/build/font hashes, requests and captures: `build/migration/observer-paired-full-r2/paired-performance/`. Post-fix R3 data is preserved separately.
- `observer-paired-smoke-r1/` preserves the rejected viewport mismatch. `observer-scale-hint0/` preserves matching 24-sample captures; both selection captures were visually inspected.
- `observer-paired-full-r1/` preserves the preliminary run. It ended CPU sampling before present submission/cleanup, so its CPU numbers cannot qualify the plan; it is not silently substituted for the corrected run.
- `observer-final-2x/` verifies both renderers at matched 2x density, the direct-pipeline SDL observer against raw protocol events/C pointer oracle, real keyboard input before/after teardown, six reopens sharing one registry, full native Collie Pinyin, Unicode editing, window lifecycle and native swap-failure cleanup.
- Independent ABI/native metadata checks, CPU wait/queue checks, 147 SDL GUI checks, 92 desktop UI checks and 14 full SDL Collie layout groups pass locally. Remote CI has not run. No test windows were opened on the user desktop.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n 19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/observer-ime \
  --paired-benchmark build/migration/observer-benchmark-fixed/ui-benchmark \
  --paired-performance --package-root build/migration/ime-lab/root \
  --scale 1250 --out build/migration/observer-paired-full-r3
```

The wrapper checks matched correctness first, then runs the two backends serially. Frozen earlier SDL artifacts are preserved; the new comparison uses a freshly built, matched SDL mode. Work remains uncommitted on `codex/sdl-migration`.
