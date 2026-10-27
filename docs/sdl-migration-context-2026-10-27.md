# EGL configuration and context control - 2026-10-27

Status: **4.6 preference rejected for lack of demonstrated benefit**. The
production renderer again requests OpenGL 3.3 core. The EGL metadata inspector
and independent oracle remain available. SDL remains the default backend.

## Actual configurations

The test-only Flexscript inspector reads the current EGL display, draw surface,
context and configuration ID. It checks 22 numeric attributes against a separate
C oracle that enumerates configurations independently, and verifies unchanged
current ownership and rendered pixels. Strings are copied before temporary
library handles or contexts are released. Metadata is sampled outside measured
UI work. Native process maps must exclude SDL.

On the private NVIDIA RTX 2070 / 615.78.08 session at logical 1280×800,
physical 1600×1000:

| Property | SDL OpenGL renderer | Native baseline |
| --- | --- | --- |
| EGL configuration ID | 22 | 4 |
| RGB bits | 8/8/8 | 8/8/8 |
| Alpha / depth / stencil bits | 0 / 24 / 0 | 8 / 0 / 0 |
| Buffer bits | 24 | 32 |
| Sample buffers / samples | 0 / 0 | 0 / 0 |
| Actual GL version | 4.6.0 NVIDIA | 3.3.0 NVIDIA |
| GLSL version | 4.60 NVIDIA | 3.30 NVIDIA via Cg compiler |

Both use EGL 1.5 NVIDIA, the OpenGL client API, a backbuffer and destroyed swap
behavior, with allowed swap intervals 0 through 1. Prior protocol evidence also
records XRGB and ARGB buffer formats respectively. These are measured setup
differences; they do not establish the cause of a latency difference.

`egl-config-r1/egl-config/` contains the original IR/direct × SDL/native
metadata and independent-oracle checks. The restored 3.3 path passes again in
`clear-correctness-r1/egl-config/` after the subsequent whole-target clear fix.

## Experimental preference and correctness

The candidate first requests 4.6 core, retaining the same 3.3 shader sources,
EGL buffers and draw code. It retries 3.3 only for EGL_BAD_MATCH or
EGL_BAD_ATTRIBUTE; allocation/display errors do not trigger a version retry.
An actual unsupported 99.0 request falls back to a valid 3.3 context. An invalid
display fails with EGL_BAD_DISPLAY without a lower-version retry. Tests restore
the original context/surface, release only their own temporary resources, and
verify byte-identical pixels and retained GL bindings afterwards.

`context46-correctness-r1/` passes full native Collie/service with real Pinyin,
IR/direct EGL oracle and renderer-state checks, matched UI scenes, presentation
commit association, and real EGL swap-failure cleanup. `context46-window-r1/`
passes private Weston 1x IR / 2x direct lifecycle, opacity, remap and FD checks.
The short native selection capture is identical to the original 3.3 baseline
across all 6,400,000 bytes.

## Query-free native control

The two flattened benchmark sources differ in exactly one context request:
`gr_context(g,config,3,3)` versus `gr_context(g,config,4,6)`. The control is
`context46-control33/ui-benchmark`, the candidate
`context46-benchmark/ui-benchmark`. This avoids attributing new metadata/report
code to the context-version change. Per-run actual GL versions are enforced;
paired EGL color/alpha/depth/stencil/sample/swap settings must agree.

Seven alternating pairs of 160 updates for each of scroll, selection and Unicode
typing use the same GPU, viewport, fonts/content, CPU affinity and fixed 23 ms
arrivals. Both variants disable GPU queries. No builds or other test workloads
run during measurement. Every arrival, dispatch and presentation is retained;
uncertainty resamples whole paired runs and removes no outliers.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/context46-ime \
  --paired-benchmark build/migration/context46-benchmark/ui-benchmark \
  --native-submit-control build/migration/context46-control33/ui-benchmark \
  --native-control-contexts 3.3 4.6 \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/context46-control-r1
```

`context46-control-r1/native-submission-control/report.json` contains all
42 runs: **6,720 presented updates**, no discards. The long selection captures
are byte-identical (SHA-256
`ddc86757f667660f8f71ddfb31a815eeb8dee89fa996e6a67a36d6d5fc87ca7d`).

Input-to-presentation p95, milliseconds:

| Workload | Native 3.3 | Native 4.6 | Mean paired 4.6 minus 3.3 p95, 95% interval |
| --- | ---: | ---: | ---: |
| scroll | 6.166 | 6.254 | +0.315 (-0.075 to +0.916) |
| selection | 5.357 | 5.361 | +0.149 (-0.006 to +0.414) |
| typing | 8.990 | 8.613 | -0.297 (-0.934 to +0.341) |

All three intervals overlap zero. A higher context version has not demonstrated
a scrolling benefit, so the preference/fallback production change is removed.
The exact pre-experiment renderer snapshot was restored before the separate
clear-semantics change. The context-specific fallback fixture and policy fields
were removed from current tests alongside the constructor; general metadata
checks remain independent of that rejected implementation.

Experimental renderer/fixture/orchestration sources are frozen in
`context46-experiment-source/`, including their manifest. The candidate package,
both benchmark sources/binaries and all raw correctness/control evidence remain.
This native-only comparison is not an SDL CPU or latency qualification and does
not resolve the migration's outstanding presentation gate.
