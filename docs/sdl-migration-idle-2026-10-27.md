# Full Collie idle and memory checks - 2026-10-27

This work adds opt-in diagnostics and private full-application measurements.
It does not qualify the complete migration or change SDL as the default. The
existing scroll-latency failure and other release gates remain open.

## Boundaries and setup

`apps/collie/desktop/probe.flex` implements a replay-only `native_probe` request.
The normal application loop consumes it once after event handling and drawing,
before its existing wait. It requires metrics to have been enabled with
`--dump-loop`. It writes cumulative process/thread CPU clocks, monotonic time,
all render/upload counters, focus, caret eligibility, logical/physical viewport,
GPU identity and loop/wait counts. The native path also records logical texture
storage/count, glyph-atlas pages/bytes, shape-cache/transient bytes and submitted
draw batches. No periodic timer, file polling or sampler thread is added to
ordinary app execution.

`scripts/test-collie-idle.py` runs the same full Collie package in SDL/native
modes with separate deterministic data directories, no account credentials and
no model/network workload. The conversation contains Markdown, a table, a link,
inline code and Unicode. Inline images and active navigation/streaming are not
covered by this idle workload. The client GPU, effective viewport, focused
widget and backend/process maps must match the intended case.

Each process warms for five seconds. Snapshots delimit either an unchanged,
visible **unfocused** window or a **focused composer with blinking caret**.
There are no input mutations during the measured interval. The focus change is
performed by a separate small floating window on the private headless Sway
compositor, not a synthetic GUI focus event. Sway's tree/workspace state and the
app's focus/caret state are checked independently. A persistent virtual keyboard
keeps the headless seat's real keyboard enter/leave delivery available without
typing. No user desktop window, package or desktop configuration is changed.

The external script records endpoint process CPU ticks and per-thread context
switch counters for Collie and its service descendants. It samples RSS/PSS every
five seconds and retains individual process high-water RSS values. PID/start
times, the process set and thread set must remain stable. Sampled peaks are not
continuous peaks. PSS includes shared-page accounting and can be influenced by
other processes; no exclusive GPU residency is measured. Logical native texture
bytes are storage accounting, not a driver allocation/residency measurement.

The process CPU clocks include the first snapshot's diagnostic overhead. Context
switches and event-loop iterations are **wake proxies**, not a kernel wake trace.
The service's existing 50 ms idle polling remains part of the process-group
comparison. Idle render counters and native draw batches must remain unchanged;
caret presents must match the expected two updates per second within endpoint
tolerance. Native cache sizes must remain bounded and unchanged in these cases.

First-pair screenshots are captured after measurement and normal run expiry, so
capture/readback work is excluded from the measured window. Fixtures, snapshots,
memory samples, maps, logs, final state and executable/source hashes are retained.
Final reports preserve every run and compute paired uncertainty without removing
outliers. A short functional run does not qualify a 60-second/performance gate.

## Short functional checks and retained setup failures

`build/migration/idle-short-r1/` and `idle-short-r2/` preserve failed setup checks.
The headless SDL client did not receive usable keyboard focus after the earlier
input fixture's temporary devices disconnected. The first attempt therefore had
inconsistent focus/caret eligibility, and the second explicitly rejected missing
initial keyboard focus. This is not treated as proof of an SDL rendering defect.
The compositor logs record virtual keyboard addition/removal.

`idle-short-r3/` keeps a real virtual keyboard connected for each case and passes
all four three-second checks:

| Case | Backend | UI process CPU | Loop iterations | Presents |
| --- | --- | ---: | ---: | ---: |
| unfocused | SDL | 10.178 ms | 186 | 0 |
| unfocused | native | 0.138 ms | 1 | 0 |
| caret | SDL | 18.085 ms | 185 | 6 |
| caret | native | 6.506 ms | 13 | 6 |

Both unfocused cases have zero draw/copy/create/upload/raster/present counter
increments. Native idle draw batches do not advance. Both caret cases have six
presents and no texture allocation, upload or text rasterization. Native cache
sizes are unchanged. These are correctness observations, not final speed or
memory acceptance. Subsequent diagnostics also assert the accelerated OpenGL SDL
renderer and identical hardware GPU strings.

## Retained visual-equivalence failure

The initial `idle-60s-r1/` run was **stopped after the first unfocused pair**.
Both intervals rendered nothing, but visual inspection of the retained captures
showed giant SDL bitmap emoji versus correctly sized native emoji. Header,
sidebar and table geometry therefore differed. Its partial CPU/memory numbers
are not a qualified matched comparison. `idle/quality-audit.json` records the
failure, and the interrupted run's artifacts remain intact. No conclusion about
relative memory use is drawn from it.

SDL_ttf's bitmap strike-index semantics required a compatibility-path fix;
[the bitmap-size report](sdl-migration-bitmap-2026-10-27.md) records that change,
independent metric/pixel checks, and the corrected screenshots. Emoji remain in
the workload. They were not removed to make the comparison pass.

`idle-corrected-short-r1/` passes all four three-second full-Collie cases and the
matched four-scene rendering/presentation smoke checks after the correction.
Both unfocused cases render/upload/present nothing. Each caret case presents six
times, with no texture allocation/upload/rasterization. The SDL screenshot now
has normal-sized emoji and the same table layout as native, subject to ordinary
font rasterization/rounding differences.

## Corrected seven-pair 60-second measurement

The longer run uses **seven alternating pairs per case**, with the two backends
run serially. At each backend launch, the private keyboard is held for that case
only. The run includes 28 measured intervals of 60 seconds; startup/warmup and
shutdown are outside each interval. No concurrent build or test workload is
launched during measurement.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/render-state-ime \
  --collie build/migration/idle-corrected-candidate/collie \
  --font-sizing-fixture build/migration/font-sizing-ir-final \
  --font-sizing-fixture build/migration/font-sizing-direct-final \
  --idle-focus build/migration/idle-focus --idle-seconds 60 --idle-runs 7 \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/idle-corrected-60s-r1
```

All **28 intervals** and final report checks completed successfully in
`build/migration/idle-corrected-60s-r1/idle/report.json`. The private compositor
then stopped normally. The exact app/orchestration sources recorded at startup
were verified against their hashes and copied to `idle/source-snapshot/` before
later test-orchestration changes. Kernel wake tracing, active-workload
memory/texture soak, GPU residency and real desktop/hardware coverage remain
unproven. SDL remains default and the branch remains uncommitted.

### Unfocused result

All **seven unfocused pairs** have completed. The independent interim summary is
`idle/unfocused-interim-summary.json`; final paired statistics are in the main
report. Both backends have zero draw/copy/create/upload/raster/
present increments in every unfocused interval. Native draw batches and cache
storage remain unchanged.

| Metric, median across seven runs | SDL | Native |
| --- | ---: | ---: |
| UI process CPU per 60 wall seconds | 167.178 ms | 0.156 ms |
| Event-loop iterations per interval | 3,708 | 1 |
| App/service CPU per interval, coarse process ticks | 170 ms | 10 ms |
| App/service voluntary context switches per interval | 5,033 | 1,196 |
| Warm app/service RSS | 148,440 KiB | 150,716 KiB |
| Warm app/service PSS | 79,231 KiB | 69,209 KiB |

These are subset medians. Native RSS
is about 1.5% higher in this particular idle subset; PSS is lower. Shared-page
accounting and individual runs, including the first SDL process's larger memory
footprint, remain in the raw data. This does not qualify active-workload memory,
allocation peaks or lifetime soak. Context switches/iterations remain wake
proxies, and the service's polling remains included.

### Focused caret result and paired uncertainty

Every caret interval produced **exactly 120 presentations**, or two per second.
There were no texture creations, uploads or text rasterizations during the
measured caret intervals. Native cache storage stayed unchanged. Total measured
caret presentations across both backends were **1,680**.

| Metric, median across seven runs | SDL | Native |
| --- | ---: | ---: |
| UI process CPU per 60 wall seconds | 331.140 ms | 119.489 ms |
| Event-loop iterations per interval | 3,700 | 241 |
| App/service CPU per interval, coarse process ticks | 340 ms | 130 ms |
| App/service voluntary context switches per second | 88.504 | 23.900 |
| Warm app/service RSS | 149,472 KiB | 150,476 KiB |
| Warm app/service PSS | 81,661 KiB | 70,517 KiB |

The final report resamples entire paired runs 10,000 times with a fixed seed.
Mean paired differences below are native minus SDL, normalized per wall second:

| Case | UI process CPU difference (95% interval) | App/service voluntary context-switch difference (95% interval) |
| --- | ---: | ---: |
| unfocused | -2.851 ms/s (-3.056 to -2.695) | -63.897/s (-65.068 to -62.726) |
| caret | -3.615 ms/s (-4.085 to -3.327) | -64.859/s (-65.618 to -64.242) |

Native warm RSS medians are 1.5% higher unfocused and 0.7% higher with the caret.
No individual paired warm RSS ratio exceeds a 2.6% native increase. PSS is lower
in every paired warm observation, but the initial SDL process's much larger
footprint remains included rather than discarded. Sampled peaks, per-process
high-water values and every raw endpoint remain available. These idle cases
show no unbounded texture/cache growth; they are not active-workload/lifetime
soak or proof of exclusive GPU memory use.

The measured local idle/caret CPU and render components pass. The full idle
acceptance flag remains false because kernel wakeups were not directly traced.
The complete migration remains unqualified due to its other open gates,
including scrolling latency, first-useful startup/navigation and active memory.
The final source/build/raw-evidence index is
`build/migration/idle-gpu-present-final-evidence.json`, with scoped cleanup in
`idle-gpu-present-host-cleanup.json`. No owned process, mount or private runtime
from this round remained in the audit. No default switch, commit or push was made.
