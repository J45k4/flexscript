# Draw and present GPU timing - 2026-10-27

Status: independent GPU correctness passes in **IR/direct on SDL/native**.
The corrected 28-interval idle measurement finished before compilation/testing
started. The seven-pair diagnostic profile and live presentation checks have
completed. No performance acceptance verdict is claimed from instrumented data.

The earlier timer ends before presentation and may omit SDL's present-time
drawing/blit. `tests/ui/gpu-present.flex` composes two existing bounded timer
contexts: one around update/draw, another around the successful present API.
Both record 64-bit GL_TIMESTAMP pairs. An explicit `glFlush` submits the marker
issued after presentation; there is no `glFinish` or blocking result fetch.
This deliberately changes submission behavior, so CPU/latency values collected
in this mode are diagnostic and cannot qualify their release gates.

Four markers describe draw start/end and present start/end. They preserve the
boundary gap between the two intervals rather than pretending the phases are
adjacent. Overall client timeline time equals draw interval + boundary gap +
present interval. These GPU timeline intervals may include CPU feeding/idle
gaps, scheduling and driver work; they are not exclusive shader/GPU occupancy.
They do not cover compositor work or physical scanout. Their absolute clock is
not the host/compositor presentation clock, so those absolute values must not
be subtracted from each other.

The wrapper rejects out-of-order/repeated phase calls and bounds all allocations
to the configured capacity (at most 10,000 samples). Result availability is
checked before retrieval. If one pair completes first, its result is retained
until the other is available; each pair is read exactly once. A failed present
must not be recorded as a completed interval. A lost window/context rejects the
final marker, and context destruction releases its driver query objects.

`tests/ui/gpu-present-driver.flex` checks the following against
the existing independent C query oracle:

- exact high-word timestamps for all four markers, monotonic phase ordering
  and exact interval sums;
- invalid indices/capacities, duplicate phase calls, unissued results and
  one-shot delivery;
- byte-identical rendered pixels;
- independent query existence before/after owned deletion;
- loss of context between pre-present and post-present markers.

It uses the existing private `--gpu-timing-fixture` orchestration, which
recognizes and validates the extra phase records. All four pipeline/backend
combinations pass in `build/migration/gpu-present-profile-r1/gpu-timing-{0,1}/`.
All three samples per fixture agree exactly with both independent timestamp
pairs, preserve pixels, and release the twelve owned query objects.

The actual Collie UI benchmark now has an opt-in `gpu_present_timing` request.
`scripts/benchmark-ui.py` and `scripts/test-presentation-pair.py` accept
`--gpu-present-timing`, which implies diagnostic `--gpu-timing`. They require
four result reads per update, validate every phase and interval sum, and report
draw/present/client/gap intervals separately. CPU qualification remains disabled
for GPU-instrumented runs. The private session wrapper now exposes
`--paired-gpu-present`; that option was added after the idle process finished and
its original source files were frozen. All five short matched GPU scenes pass,
as do the four uninstrumented short scenes for the new executable.

The saved raw protocol traces from the earlier presentation fixtures were also
audited independently. Each of SDL's 24 presented feedback records belongs to a
distinct commit carrying a non-null buffer; the native fixture has 23 such
records and one discarded outcome. Empty-commit timing therefore does not
explain those fixture results. `scripts/wayland_commit_check.py` rejects an
empty-commit negative control, and both live presentation scripts now apply it.
Six CPU controls cover empty commits, duplicate frame counts, other surfaces,
proxy/buffer reuse, attach-before-feedback ordering and discarded/cancelled
outcomes. They pass locally and are wired into the CPU CI workflow.
This verifies association/order, not the pixels inside a buffer or scanout.
The new live checks pass after the diagnostic profile: SDL has 24 presented
non-null-buffer commits, while native has 23 presented commits and one discarded
outcome. Actual EGL bad-display failure cleanup also passes. The private
compositor then stops normally.

## Completed matched diagnostic profile

`build/migration/gpu-present-profile-r1/gpu-performance/report.json` contains
seven alternating pairs of 160 updates in each of five workloads, with fixed
23 ms arrivals, matched content/fonts/inline PNG and a 1280x800 logical /
1600x1000 physical viewport on the RTX 2070. The corrected bitmap-size baseline
is used. All **11,200 updates** were presented, with no discards and **44,800
query result reads**. Every draw/present/gap/client interval identity is checked.
The report's `cpu_gate_pass` is **unavailable**, as required for query/flush
instrumentation. No concurrent build/test workload was launched during profiling.

GPU timeline median / p95 in milliseconds:

| Workload | SDL draw | Native draw | SDL present call | Native present call | SDL complete client | Native complete client |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| scroll | 0.096 / 0.918 | 0.123 / 1.085 | 0.305 / 0.978 | 0.306 / 0.993 | 0.401 / 1.899 | 0.430 / 2.078 |
| selection | 0.092 / 0.823 | 0.121 / 0.957 | 0.305 / 0.987 | 0.306 / 0.997 | 0.398 / 1.810 | 0.427 / 1.957 |
| stream | 11.753 / 20.279 | 1.088 / 1.406 | 0.060 / 0.306 | 0.306 / 0.987 | 11.802 / 20.315 | 1.433 / 2.374 |
| navigation | 3.458 / 8.470 | 2.722 / 3.316 | 0.305 / 0.950 | 0.307 / 0.993 | 3.746 / 8.580 | 2.934 / 4.093 |
| typing | 1.410 / 2.614 | 1.088 / 2.559 | 0.306 / 1.607 | 0.306 / 1.548 | 1.752 / 4.136 | 1.458 / 3.876 |

Component percentiles are not additive; each complete-client sample is computed
from its own four timestamps. These are timeline intervals, not exclusive GPU
occupancy or compositor/scanout time. The scroll/selection present-call medians
are similar on both modes. Their complete-client p95 differences alone do not
identify the cause of the earlier uninstrumented presentation regression.

Instrumented fixed-arrival input-to-presentation p95:

| Workload | SDL (ms) | Native (ms) | Mean paired p95 difference, native minus SDL (95% interval, ms) |
| --- | ---: | ---: | ---: |
| scroll | 6.275 | 6.186 | -0.169 (-0.538 to +0.113) |
| selection | 6.169 | 6.046 | +0.031 (-0.261 to +0.422) |
| stream | 155.965 | 12.288 | -70.398 (-124.010 to -42.479) |
| navigation | 15.396 | 10.965 | -4.737 (-5.490 to -4.023) |
| typing | 11.560 | 10.635 | -1.519 (-4.337 to +0.456) |

**These are not latency qualification results.** Query drains and final flushes
change scheduling/submission. Streaming retains every scheduled arrival, so a
slower backend accumulates dispatch delay rather than dropping/retiming updates.
The slower fourth SDL streaming run and later typing spikes remain included.
Boundary host snapshots do not prove the cause of individual spikes. Headless
feedback continues to have zero hardware flags/refresh/sequence.

The smaller/inconclusive scroll difference under this diagnostic motivates a
controlled uninstrumented submission experiment, for example an explicit final
native GL flush with all query code off. It is a hypothesis, not proof that a
flush fixes the issue: query placement, host variation and queueing also changed.
The subsequent [query-free native control](sdl-migration-submission-2026-10-27.md)
rejects that post-swap/post-Wayland-flush placement: selection and typing regress,
and scroll is inconclusive. The exact earlier renderer is restored. Do not
substitute the diagnostic run for the failed uninstrumented candidate.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/render-state-ime \
  --gpu-timing-fixture build/migration/gpu-present-ir \
  --gpu-timing-fixture build/migration/gpu-present-direct \
  --presentation-fixture build/migration/render-state-presentation \
  --sdl-presentation-fixture build/migration/render-state-sdl-direct \
  --paired-benchmark build/migration/gpu-present-benchmark/ui-benchmark \
  --paired-gpu-present --package-root build/migration/ime-lab/root \
  --scale 1250 --out build/migration/gpu-present-profile-r1
```

Remaining validation:

1. Use the resulting intervals to investigate the measured scrolling regression.
   Run CPU/latency qualification separately with all query instrumentation off.
2. Complete first-useful startup/navigation, kernel wake tracing, active memory/
   lifetime soak, hardware cadence and real desktop acceptance.

SDL remains default. The full SDL migration is incomplete and uncommitted.
Source/build/raw-evidence hashes are recorded in
`build/migration/idle-gpu-present-final-evidence.json`. The scoped host process,
mount and private-runtime audit is `idle-gpu-present-host-cleanup.json`; all seven
completed/stopped sessions from the idle/GPU round are gone.
