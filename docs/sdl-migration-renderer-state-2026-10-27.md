# Renderer state and batching - 2026-10-27

The retained-state candidate passes the local CPU component, but **scrolling
latency still regresses**. SDL remains the default. All changes are uncommitted
on `codex/sdl-migration`. Earlier candidates and failures remain intact in
[the GPU/packed report](sdl-migration-gpu-2026-10-27.md).
Subsequent visual inspection identified oversized SDL bitmap emoji. The primary
CPU scenes have no emoji, but earlier typing figures are not qualified equal-size
comparisons. [The bitmap-size report](sdl-migration-bitmap-2026-10-27.md) records
the correction and requirement for fresh measurements against that baseline.

## Change and correctness

The native canvas owns its GL context, shader program, VAO, vertex buffer and
texture unit. These bindings are now initialized once instead of repeated for
every batch. The logical viewport uniform is updated only when dimensions
change. Repeating the same physical scissor, logical size, or disabled clipping
no longer splits a pending batch. Texture binding remains explicit on every
draw because texture allocation and uploads can change it. Framebuffer binding
and physical viewport setup remain explicit on target changes. Invalid render
targets are rejected before changing ownership or flushing pending work.

`tests/ui/renderer-state.flex` compares the cached path against a reference that
flushes after every operation. It covers translucent blending, clip changes,
custom logical viewport, differently sized targets, texture allocation/update,
target rejection and deletion. Both IR and direct compiler pipelines produce
byte-identical pixels, with 8 versus 11 fixture draws and no GL errors. The
independent C oracle checks the actual driver program, VAO, vertex buffer,
active texture unit, framebuffer, sampler and logical viewport. This draw-count
reduction describes the fixture, not every Collie frame.

Evidence:

- `build/migration/render-state-correctness-r1/`: initial IR/direct state checks.
- `render-state-window-regression/`: private Weston 1x IR / 2x direct, all 26
  lifecycle/opacity checkpoints, rapid remaps and bounded reopen descriptors.
- `render-state-correctness-final/`: full native Collie/service with real Fcitx
  Pinyin, IR/direct renderer state, matched SDL/native scene correctness, both
  presentation implementations and actual EGL bad-display failure cleanup.
- `render-state-correctness-final/selection-equivalence.json`: all 6,400,000
  selection framebuffer bytes equal the frozen packed candidate. Both SHA-256
  values are `bda803bdf283abaff0ec916c141f898866e5f5b3f94f8ce79a5e3552ee89c835`.

## Matched CPU measurement

`build/migration/render-state-paired-r1/paired-performance/report.json` records
seven alternating pairs of 160 updates for each primary workload. Both modes
use the same newly built executable, content, fonts and inline PNG, with a
1280x800 logical / 1600x1000 physical viewport on the RTX 2070. Native process
maps exclude SDL. GPU query instrumentation is disabled. Active thread CPU
includes update, layout, rendering, presentation submission and arena cleanup;
blocked wall time is excluded. No other build/test workload was launched during
the measurement. Host boundary snapshots are retained, without assigning
individual outliers an unverified cause.

Pooled median / p95 CPU time:

| Workload | SDL (ms) | Native (ms) | Median / p95 speedup |
| --- | ---: | ---: | ---: |
| scroll | 1.4316 / 1.5836 | 1.2413 / 1.3886 | 1.1533 / 1.1404 |
| selection | 1.4063 / 1.5784 | 1.2000 / 1.3529 | 1.1720 / 1.1667 |
| stream | 15.7137 / 25.3590 | 7.4427 / 10.3452 | 2.1113 / 2.4513 |
| navigation | 9.1845 / 11.1545 | 7.2393 / 7.7539 | 1.2687 / 1.4386 |

Geometric-mean speedups are **1.3794 median / 1.4717 p95**, or 27.5% / 32.1%
less CPU time. Whole-run paired bootstrap estimates are 1.3574 median
(95% 1.3331–1.3809) and 1.4961 p95 (1.4369–1.5379). All four point estimates
improve. This candidate passes the local CPU gate. The slower fourth native
streaming run is retained. This is a fresh candidate measurement, not a causal
estimate of the state cache alone or qualification on other hardware.

## Presentation latency remains incomplete

The same session then ran seven pairs of 160 updates for scroll, selection and
typing, with fixed arrivals 23 ms apart. Arrivals are neither dropped nor
retimed; latency includes dispatch waiting. All **8,960 primary** and **6,720
fixed-arrival** updates were presented without discards.

Fixed-arrival input-to-presentation p95:

| Workload | SDL (ms) | Native (ms) | Mean paired p95 difference, native minus SDL (95% interval) |
| --- | ---: | ---: | ---: |
| scroll | 5.551 | 6.474 | +2.409 ms (+0.199 to +6.074 ms) |
| selection | 5.690 | 5.454 | -0.364 ms (-0.686 to -0.075 ms) |
| typing | 8.918 | 8.698 | -0.239 ms (-0.743 to +0.362 ms) |

**Scroll fails; selection improves; typing is inconclusive.** The large sixth
scroll-pair difference (+12.923 ms) remains included. Five other scroll pairs
also regress; no outlier has been removed. Pooled p95 and the mean of paired
per-run p95 differences summarize different quantities and must not be
substituted for each other. The callback-paced CPU run also retains a selection
presentation regression (+0.162 ms, 95% +0.067 to +0.245 ms). The migration does
not pass presentation nonregression.

For fixed-arrival scroll, pooled p95 dispatch waiting is 1.073 / 1.127 ms
(SDL/native), while dispatch-to-presentation is 4.734 / 5.508 ms. This suggests
investigating work after dispatch, but these separate percentiles are not
additive and do not identify a GPU/driver/compositor cause. Headless feedback
still has zero hardware flags, refresh prediction and sequence; no physical
input or scanout result is claimed.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/render-state-ime \
  --collie build/migration/render-state-candidate/collie \
  --paired-benchmark build/migration/render-state-benchmark/ui-benchmark \
  --paired-performance --paired-arrival-ms 23 \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/render-state-paired-r1
```

Next work includes completing GPU/present diagnostics for the latency gap,
first-useful startup/chat-switch presentation, settled idle and memory/texture
soak. Broader script/input acceptance, native GPU CI, hardware cadence and real
desktop acceptance remain required. No acceptance threshold has changed.

`build/migration/render-state-final-evidence.json` records source, executable
and raw-evidence hashes. `render-state-host-cleanup.json` confirms this round's
private runtimes, mounts and matching processes are gone. No desktop session
configuration, system packages, default backend, commit or push was changed.
