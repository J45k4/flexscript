# SDL migration GPU diagnostics - 2026-10-27

This is diagnostic evidence, **not complete performance acceptance**. SDL remains
the default. The packed-vertex candidate passes the local CPU component, but
scroll/selection latency still fails nonregression. Earlier timing results remain in
[the paired report](sdl-migration-paired-2026-10-27.md).
The subsequent retained-state candidate has its own correctness and measurements
in [the renderer-state report](sdl-migration-renderer-state-2026-10-27.md).
Later visual inspection found an SDL bitmap emoji sizing mismatch; historical
typing measurements are therefore not qualified equal-size comparisons. See
[the bitmap-size correction](sdl-migration-bitmap-2026-10-27.md). Original raw
measurements are retained, and fresh baseline qualification remains necessary.

## GPU timestamp method and limits

`tests/ui/gpu-timing.flex` adds optional benchmark instrumentation. It allocates
two OpenGL timestamp query objects per measured update, bounded by the configured
sample count. It drains deferred renderer commands before recording each marker:
native `gr_flush`, or public `SDL_RenderFlush` on the accelerated OpenGL SDL
renderer. A result is read only after `GL_QUERY_RESULT_AVAILABLE` says it is
available; there is no `glFinish`, blocking result wait or framebuffer readback
per measured update. Collection happens after the measured workload. Query
objects are explicitly released while the context is alive; destroying a context
also releases its GL objects. Owned CPU storage can then be freed without calling
the destroyed context. A stale window handle does not permit GL calls.

The reported interval is **GPU timeline time around update/draw**, ending before
the present API. It can include idle gaps while the CPU supplies commands. It
does not isolate shader occupancy, include SDL's possible present-time work,
cover the compositor, or measure scanout. Its absolute clock is not the host or
presentation clock. Do not subtract timestamps between those domains. In
particular, a large streaming interval is not proof of equally large exclusive
GPU execution. Complete client GPU execution/present instrumentation remains a
release gate.

The forced batch drains and extra queries can change CPU work and scheduling.
The reporter checks that both children requested the same diagnostic mode and
sets `cpu_gate_pass` to unavailable when it is enabled. Use the regular
uninstrumented path for CPU/latency qualification. Normal application rendering
loads no timer code; the helper is imported by the test benchmark only.

The method follows the public
[OpenGL timestamp query](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glQueryCounter.xhtml),
[result availability](https://registry.khronos.org/OpenGL-Refpages/gl4/html/glGetQueryObject.xhtml)
and [SDL render flush](https://wiki.libsdl.org/SDL2/SDL_RenderFlush) contracts.

## Independent checks and retained failure

`tests/tooling/gpu-timing.c` is a test-only independent oracle linked to the
system GL implementation. IR and direct fixtures both pass on SDL/native in
`build/migration/gpu-timing-correctness-r2/`:

- exact 64-bit start/end timestamps agree with the C API, including high words;
- unissued/invalid indices, repeated starts/ends/results and capacity bounds are
  rejected without reading an unissued result;
- timer queries preserve the rendered RGBA framebuffer exactly;
- explicit query deletion is checked independently with `glIsQuery`;
- destroying the window invalidates the timer context and frees its CPU storage
  without using the destroyed GL context.

`gpu-timing-correctness-r1/` retains the initial failed pixel comparison.
`gpu-timing-pixel-debug/` identifies a real first-map scale transition: the native
window's initial buffer is 640x480, then changes to 400x300 after fractional output
preference delivery. The query values had already matched the oracle; the two
captures were of different-sized framebuffers. The fixture now presents and
dispatches the mapping/scale transition before comparing stable pixels. This
does **not** qualify first-useful-frame timing or remove that startup case from
the migration requirements.

## Draw-interval profile before the opaque-region change

`build/migration/gpu-timing-profile-r1/` preserves the same actual compiled UI,
fonts, inline image, RTX 2070 client GPU and matched 1280x800 logical / 1600x1000
physical viewport as the earlier comparison. It uses seven alternating pairs
of 160 updates in five workloads, with scheduled arrivals 23 ms apart. All
**11,200** measured updates were presented; **22,400** 64-bit query results were
collected after availability. GPU instrumentation was enabled on both modes.

Pooled GPU draw-timeline intervals, median/p95 in milliseconds:

| Workload | SDL | Native |
| --- | ---: | ---: |
| scroll | 0.095 / 0.099 | 0.125 / 0.287 |
| selection | 0.094 / 0.096 | 0.126 / 0.270 |
| stream | 12.379 / 22.560 | 1.543 / 2.289 |
| navigation | 2.993 / 10.627 | 3.064 / 5.396 |
| typing | 1.792 / 2.915 | 1.353 / 2.203 |

The short scroll/selection draw interval is not sufficient to explain the entire
earlier p95 latency gap. Frame-gate waits, present return and compositor timing
remain distinct in raw data. Host interruptions/frequency were not traced in
this profile and no outlier was removed or assigned an unverified cause. This
diagnostic has no CPU/latency release verdict.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n 19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/observer-arrival-ime \
  --paired-benchmark build/migration/gpu-benchmark-before/ui-benchmark \
  --paired-gpu --package-root build/migration/ime-lab/root \
  --scale 1250 --out build/migration/gpu-timing-profile-r1
```

## Opaque native window region

The actual SDL protocol trace publishes a full opaque region, while the prior
native path published none. The native renderer now tracks whether its current
window backbuffer is known opaque after an unclipped, fully opaque clear.
Premultiplied translucent drawing over that destination preserves opacity.
Transparent clears or clipped holes invalidate it; clearing a separate layer
does not. Swap, resize and surface replacement reset the proof for a new buffer.
Partial frames therefore cannot inherit an earlier buffer's opaque hint.

`wt_opaque` publishes or clears the hint using surface-local logical dimensions.
It caches dimensions/state and creates a short-lived `wl_region` only when
coverage changes. The compositor copies the region before its temporary protocol
object is destroyed; no persistent region or per-frame creation is needed for
steady opaque UI frames. Scaling preserves logical bounds.

This follows [Wayland's opaque region contract](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_surface-request-set_opaque_region),
which permits compositing optimizations. This is a candidate explanation/change,
not a measured claim that the hint removes the latency gap. Transparent and
partial content must never be falsely marked opaque to obtain a performance win.

`build/migration/opaque-window-regression-r1/` passes the private Weston 1x IR /
2x direct lifecycle suite. The independent compositor observer checks the actual
committed opaque region, its full coverage and exact logical extents through
resize, fullscreen, maximize, minimize/restore and remap. Existing framebuffer,
retained texture/text and twelve-reopen FD checks also pass. Pure toplevel state
tests pass in both pipelines. No default backend change, commit or push was made.

The first opaque-only comparison in `build/migration/opaque-paired-r1/` passes
the aggregate CPU component (1.3495 median / 1.4477 p95 speedup, paired lower
bounds 1.3114 / 1.3537), but its scheduled-arrival latency remains inconclusive.
Mean paired p95 differences, native minus SDL, are +0.350 ms scroll, +0.007 ms
selection and -1.260 ms typing; all intervals cross zero, with especially broad
typing uncertainty. This run precedes the stricter opacity proof above and the
post-swap flush; it is not final-source qualification or a demonstrated hint win.
Raw host run-context snapshots are retained, without per-frame causal claims.

`opaque-window-regression-r3/` passes **26 checkpoints** at both 1x IR and 2x
direct, including six additional opacity probes: transparent clear, partial
opaque clear, opaque clear plus translucent drawing, a clipped transparent hole,
transparent layer rendering over an opaque destination, and a partial new frame.
Independent committed region states and framebuffer alpha agree. Every created
temporary region has a matching destructor. R2 preserves an intermediate test
failure: its checker incorrectly expected zero size constraints on the added
fixed-window steps; the recorded empty opaque region was already correct.

The renderer also explicitly flushes the Wayland connection after successful EGL
swap, instead of deferring queued output to a later event wait. Fatal connection
failure releases frame/measurement ownership and reports an error. SDL does the
same explicit flush in its public
[Wayland EGL backend](https://github.com/libsdl-org/SDL/blob/main/src/video/wayland/SDL_waylandopengles.c).
The final candidate is measured separately in `opaque-flush-paired-r1/` with GPU
query instrumentation **disabled**. CPU frequency/governor, selected CPU
interrupt/softirq/time counters, CPU pressure and child CPU/fault/context-switch
counts are recorded at run boundaries only. They cannot identify the cause of
an individual outlier; no sampling worker runs beside the timed workload.

The completed `opaque-flush-paired-r1/` has 8,960 primary CPU updates and 6,720
additional scheduled-arrival updates; all received presentation outcomes. Its
four-case pooled CPU speedups are 1.2778 median / 1.3545 p95 (21.74% / 26.17% less
time), but the paired median lower confidence bound is **1.2109**, below 1.25.
The CPU gate is therefore **false**. The paired p95 interval is 1.2781–1.3683.
All individual point estimates improve, which does not override the median
confidence miss. Prior passing CPU results are not substituted for this result.

Scheduled-arrival p95s, SDL/native in milliseconds, are 7.620/8.517 scroll,
5.559/5.634 selection and 9.050/8.722 typing. Mean paired p95 differences are
+1.536 ms (95% -2.260 to +5.448), -0.227 ms (-0.907 to +0.210), and -0.082 ms
(-0.539 to +0.438), respectively. These broad intervals do not establish a
latency win. All outliers and host run-context snapshots remain in the data.

## Packed vertex candidate

The native renderer used six bytewise 32-bit helper calls for every vertex.
`gr_vertex` now writes the same six little-endian 32-bit fields with three packed
64-bit stores on the supported Linux x86-64 target. The low member is masked so
negative/high-word inputs cannot overwrite its neighbor; the high member keeps
the same low-32-bit truncation. Vertex stride, GPU attributes and all draw content
remain identical.

`scripts/test-native-vertices.py` compares the actual writer with Python's
independent standard `struct` ABI, with guards around each vertex. **4,120**
vertices across IR/direct compilation pass signed, high-word, color, UV, mode,
random-input and write-bound checks without opening a display. The check is
included in CPU CI. `packed-window-regression/` passes the complete 26-step 1x IR /
2x direct window/opacity suite. Byte equivalence and correctness do not constitute
a speed claim; this candidate needs its own matched measurements.
`packed-correctness-r1/` also passes real full Collie Pinyin, the independent GPU
oracle and SDL/native raw presentation checks. The selected Markdown/table
framebuffer is **byte-identical across all 6,400,000 bytes** to the frozen
pre-packing renderer (`selection-equivalence.json` records both hashes).

## Packed candidate measurements

`build/migration/packed-paired-r1/` uses the current packed writer, known-opacity
proof and post-swap flush, with GPU query instrumentation disabled. Seven
alternating pairs of 160 updates give 1,120 samples per backend/workload. All
8,960 primary CPU updates and all 6,720 additional scheduled-arrival updates
received compositor presentation outcomes, without discards. The same explicit
SDL scaling hint, viewport, physical resolution, fonts and actual client GPU are
used on both backends; host run-context snapshots are retained.

CPU work median/p95, milliseconds:

| Workload | SDL | Native | Median / p95 speedup |
| --- | ---: | ---: | ---: |
| scroll | 1.433 / 1.579 | 1.306 / 1.545 | 1.097 / 1.022 |
| selection | 1.423 / 2.148 | 1.299 / 2.003 | 1.096 / 1.072 |
| stream | 15.789 / 25.080 | 7.450 / 9.252 | 2.119 / 2.711 |
| navigation | 9.522 / 11.394 | 7.420 / 8.897 | 1.283 / 1.281 |

The local CPU component passes: pooled geometric-mean speedups are **1.3447
median / 1.3965 p95**, or 25.63% / 28.39% less time. All four individual point
estimates improve. Run-level paired median speedup is 1.3366, 95% interval
**1.3293–1.3443**; paired p95 is 1.3895, interval **1.3131–1.4562**. Both lower
bounds clear 1.25. These describe this recorded configuration, not performance
on every driver or a causal estimate for the packed writes alone.

Fixed 23-ms scheduled-arrival p95, including dispatch waiting:

| Workload | SDL | Native | Mean paired p95 difference, native minus SDL (95% interval) |
| --- | ---: | ---: | ---: |
| scroll | 5.525 ms | 6.208 ms | +0.631 ms (+0.377 to +0.812 ms) |
| selection | 5.520 ms | 5.672 ms | +0.282 ms (+0.027 to +0.604 ms) |
| typing | 10.857 ms | 10.160 ms | -1.460 ms (-4.087 to +0.101 ms) |

**Latency nonregression fails for scroll and selection.** Their paired intervals
are above zero. Typing is inconclusive. No gate was relaxed and no outlier was
removed. CPU success does not qualify this migration or permit a default switch.
The compositor's hardware flags/refresh/sequence remain zero, so these are
scheduled replay/headless compositor results, not physical input or scanout.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n 19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/packed-ime --collie build/migration/packed-candidate/collie \
  --paired-benchmark build/migration/packed-benchmark/ui-benchmark \
  --paired-performance --paired-arrival-ms 23 \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/packed-paired-r1
```

Full GPU execution/present timing, the remaining latency gap, first-useful
startup/chat-switch presentation (including the first-map scale transition),
60-second settled idle, matched PSS/RSS/texture lifetime, broader input/script
acceptance, native GPU CI and real desktop acceptance remain open. Work remains
uncommitted on `codex/sdl-migration`.
