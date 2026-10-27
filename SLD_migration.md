# SDL migration plan

Status: Linux x86-64 / Wayland implementation delivered, with native Wayland as
Collie's default in a Wayland session and explicit SDL compatibility retained.
See [correctness acceptance](docs/sdl-migration-correctness-2026-10-27.md) for the
current scope, evidence and platform limits. All changes are local on
`codex/sdl-migration`; this document does not imply a merge or release.

Acceptance update, 2026-10-27: the user stated, "i think speed seems fine lets now
finish the correctness and then i think this goal is done". Performance is
accepted by the user. The original numerical latency targets below were not all
met; their reports and misses remain preserved. They are no longer completion
blockers. Correctness and explicit limits remain required. The sections and
unchecked boxes below preserve the original broader roadmap; the current
acceptance matrix is in the linked correctness report.

The requested filename is `SLD_migration.md`; the dependency being replaced is
SDL2, including SDL2_ttf. Initial target: Collie on Linux x86-64 / Wayland.
Planning baseline: master `b7aad8c`, containing the merged Collie integration.

## Objective and original performance requirement

Replace SDL's window/input/rendering layer with a Flexscript-owned backend while
retaining Collie's existing application logic and portable UI definitions.

Original requirement, superseded only for performance acceptance by the user
on 2026-10-27: the backend must outperform SDL before becoming Collie's default.
Removing a dependency alone is not completion. Performance gains must
come with equivalent functionality, readable text, correct input and bounded
resource use. Do not trade quality, resolution, content or correctness for speed.

All numerical gates below are proposed acceptance targets, not measured results.
Freeze them with the benchmark fixtures before optimization. Missed gates must remain reported. The user's
subsequent acceptance is recorded above; no measured miss is relabeled as a pass.

## Outline

1. Capture a reproducible SDL baseline and define backend-independent tests.
2. Separate window/input and drawing APIs from SDL-specific implementation.
3. Bring up a minimal native Wayland window in Flexscript.
4. Implement the 2D renderer through EGL/OpenGL.
5. Replace SDL_ttf with direct font discovery, shaping and rasterization adapters.
6. Complete clipboard, IME, cursor, scaling and window lifecycle behavior.
7. Run Collie end to end and optimize measured bottlenecks.
8. Switch the default only after correctness and performance gates pass.

## Current implementation

The application is a retained UI implemented in Flexscript, rather than a set of
SDL-provided widgets:

```text
Collie state and compiled views
  -> keyed widget updates
  -> retained UI records, layout, Markdown, tables and selection
  -> gui_* drawing/window/input calls
  -> SDL2 renderer and SDL2_ttf
  -> display server / compositor
```

- `apps/collie/ui/`: portable view definitions and event/state reducers.
- `libs/ui/desktop/`: retained widgets, layout, painting, input and text caches.
- `libs/gui/window.flex`: SDL window/event handling and display dimensions.
- `libs/gui/canvas.flex`: SDL renderer creation, drawing and presentation.
- `libs/gui/draw.flex`: Fontconfig lookup, SDL_ttf text and image texture uploads.
- `libs/gui/gl.flex`: existing window-backed OpenGL API through SDL.
- `apps/collie/desktop/main.flex`: event loop and several direct SDL cursor,
  capture and test-event calls that also need migration.

Text is currently rasterized into temporary SDL surfaces/textures and copied into
cached widget textures. Dirty frames clear and repaint the window; unchanged text
and image textures can be reused. The event loop waits up to 16 ms between passes.
The SDL renderer is selected automatically; the current code does not guarantee
that a particular GPU backend is selected.

Image decoding, EXIF orientation and preview resizing already live in
`libs/image`; their codec dependencies and CPU performance are separate from this
migration. Do not count an independent image-library optimization as an SDL
replacement performance gain.

## Proposed architecture

```text
Collie / portable UI
  -> retained desktop layout, editing and scene state
  -> backend-neutral GUI API
       -> Wayland window/input backend, written in Flexscript
       -> Flexscript 2D renderer using EGL/OpenGL
       -> Flexscript text layout/cache with direct font-library adapters
```

Keep the existing `gui_*` and `ui_desktop_*` application-facing behavior where
practical. Window events and rendering resources must have explicit ownership,
stable handles and cleanup rules. Platform surface sizes and physical framebuffer
sizes must remain distinct.

Suggested module boundaries, to confirm during API extraction:

| Boundary | Responsibility |
| --- | --- |
| `libs/gui/backends/wayland/` | Connection, protocols, windows, events, clipboard, IME and scaling. |
| `libs/gui/renderer/` | EGL context, draw commands, textures, clipping, layers, batching and presentation. |
| `libs/gui/text/` | Font lookup, shaping, rasterization, glyph atlas and cluster-to-text mappings. |
| SDL compatibility backend | Existing behavior for comparison and temporary fallback. |

The implementation and build tooling remain Flexscript. Initial external
dependencies are explicit: libwayland-client, libwayland-cursor for cursor-theme
fallback when compositor cursor shapes are unavailable, xkbcommon, EGL/OpenGL and the system
graphics driver, Fontconfig, FreeType and HarfBuzz. Existing image codecs remain.
No Python generator or new C application shim is required. Generate the required
Wayland protocol bindings with Flexscript tooling, or maintain reviewed
Flexscript bindings with protocol-version checks.

Removing SDL does not mean implementing every display, font and graphics-driver
facility from scratch. Native X11, Windows/macOS, direct DRM/KMS output and new
image codecs are outside the first delivery. Keep the SDL backend selectable
during development; final native-Wayland operation must not load SDL or SDL_ttf.

## Phase 1: baseline and measurement harness

- [ ] Record the exact SDL application/compiler revisions, build flags, SDL/TTF
  versions, selected renderer, video backend, GPU, driver, compositor, fonts,
  display scale, resolution and refresh rate.
- [ ] Preserve a baseline executable and deterministic fixtures in ignored build
  output. Store reproducible commands, fixture hashes and raw measurements in a
  tracked report, excluding credentials and personal conversation data.
- [ ] Instrument state update, layout, shaping/rasterization, texture upload,
  draw submission, presentation and input handling separately.
- [ ] Extend the current selection-performance test to support both backends.
- [ ] Make event injection, screenshots and test assertions backend-independent.
  Keep real display-server input tests alongside synthetic reducer tests.
- [ ] Establish the following workload suite before tuning.

| Workload | Fixed content and actions |
| --- | --- |
| Long transcript scrolling | Deterministic long chat with prose, code, tables and inline images; replay wheel and scrollbar dragging. |
| Text selection | Start inside text and in its surrounding padding; drag across wrapped text, code and tables, then copy. |
| Streaming output | Feed the same text/Markdown chunks at fixed times; measure update-to-presentation and upload work. |
| Sidebar and navigation | Search, resize sidebar, switch chats/projects/settings with identical preloaded fixtures. |
| Editing and fonts | Type, move caret, select and paste Unicode; exercise Latin, CJK, combining marks, emoji and font fallback. |
| Resize and scale | Same window sizes at 1x, 1.25x, 1.5x and 2x, including movement between differently scaled outputs. |
| Idle and startup | First useful frame; 60-second settled idle with caret disabled, plus a separate focused-editor idle case. |

Exit: the SDL baseline, measurement boundaries and fixtures are reproducible.

## Phase 2: extract backend boundaries

- [ ] Route window lifecycle, cursor, clipboard, capture and all events through
  backend-neutral functions, including direct calls in Collie's main loop.
- [ ] Define physical keys, modifiers, UTF-8 commits and text composition without
  exposing SDL event structures. Existing numeric key mappings need an explicit
  compatibility translation, rather than silently changing shortcuts.
- [ ] Define drawing commands for fills, rounded rectangles, clip stacks, texture
  upload/copy, alpha, cached layers and capture/readback.
- [ ] Separate text metrics/shaping from platform surfaces and renderer textures.
- [ ] Preserve current SDL output and run existing tests after extraction.

Exit: Collie and retained UI code no longer call SDL-specific functions directly;
the compatibility backend still passes the baseline behavior tests.

## Phase 3: minimal Wayland window

- [ ] Implement registry discovery, surface and xdg-shell lifecycle, configure/ack,
  close, title, app ID and resizing with bounded protocol-version negotiation.
- [ ] Bring up pointer/keyboard events and xkbcommon keymap/modifier handling.
- [ ] Implement buffer ownership and compositor release handling. A shared-memory
  test surface is acceptable for bring-up; it is not the final fast renderer.
- [ ] Integrate Wayland events, service-pipe readability, frame callbacks and
  timers into one nonblocking event loop. Avoid replacing SDL's polling with
  another permanent 16-ms wakeup loop.
- [ ] Test in an isolated compositor/display, preserving the user's live session.

Exit: an SDL-free Flexscript example opens, draws, receives input, resizes and
closes without protocol errors or leaked descriptors/buffers.

## Phase 4: native 2D renderer

- [ ] Create a Wayland EGL window surface and a documented OpenGL context profile.
  Existing `lib/graphics.flex` is headless EGL/OpenGL groundwork, not a complete
  window backend; adapt its useful pieces without assuming interchangeability.
- [ ] Implement textured/solid quads, rounded-corner coverage, clipping, opacity,
  render-target layers and consistent premultiplied/straight-alpha boundaries.
- [ ] Batch compatible draws and reuse command/storage buffers. Avoid per-widget
  GL state queries, per-frame object creation and GPU readbacks in normal drawing.
- [ ] Upload images once and update only changed regions of dynamic textures.
- [ ] Reuse cached layers; add explicit damage tracking where it reduces work.
  Respect EGL buffer preservation/age rules: a newly acquired backbuffer cannot
  be assumed to retain the previous frame's pixels.
- [ ] Handle resize, scale changes, resource invalidation, capture and cleanup.
  Record GPU timings without forcing a blocking completion every frame.

Exit: the renderer passes blend, clipping, texture, layer and resize tests, and
renders Collie geometry/images through the existing GUI API.

## Phase 5: replace SDL_ttf and improve text work

- [ ] Retain Fontconfig discovery and fallback; bind FreeType and HarfBuzz directly.
- [ ] Shape runs and retain glyph positions, advances and text-cluster mappings.
  Use those same mappings for caret/selection/hit testing and copy boundaries.
- [ ] Cache glyphs by face, size, style, variation/render settings and scale in
  bounded texture atlases. Upload new glyphs rather than rebuilding textures for
  every word or streaming token.
- [ ] Cache shaping and layout with explicit invalidation for content, font,
  available width and display scale. Bound memory and define eviction behavior.
- [ ] Preserve hinted small text, font fallback, baseline alignment, CJK and color
  emoji behavior at supported sizes/scales. Compare actual pixel captures.
- [ ] Treat Unicode segmentation, bidirectional ordering and line breaking as
  explicit layout responsibilities; HarfBuzz shaping alone does not implement a
  complete text editor. Document any remaining limitations instead of claiming
  full Unicode support from successful Latin-only tests.

Exit: SDL_ttf is absent from the native path; editing geometry agrees with the
rendered text and the typography/input acceptance fixtures pass.

## Phase 6: desktop behavior and Collie integration

- [ ] Clipboard source/offer transfers with asynchronous file-descriptor I/O,
  bounded payloads, cancellation and ownership changes.
- [ ] Keyboard repeat, compose/dead keys and IME preedit/commit with caret geometry.
  Test Finnish layouts and an actual CJK input method.
- [ ] Cursor themes and scale, resize cursors, focus loss, scrolling and drag
  lifetimes. Preserve drags initiated inside the window when the pointer leaves
  its bounds, using Wayland's appropriate protocol semantics.
- [ ] Fractional scaling, output changes, maximize/fullscreen, minimize/restore
  and compositor disconnect. Handle missing optional protocols explicitly.
- [ ] Preserve permissions dialogs, accounts, attachments, image previews,
  thinking summaries, Markdown links/tables and keyboard shortcuts.
- [ ] Add the backend to the native builder and CI without restoring Python app
  or build dependencies. Keep service/network/VM work outside the UI thread.

Exit: the complete application passes the migrated desktop integration suite,
including nested-compositor tests and a recorded real-desktop acceptance run.

## Performance release gates

Performance must beat the production SDL renderer, not merely a forced software
SDL path. Compare native Wayland against SDL's native Wayland backend first;
report XWayland separately. Record the actual rendering backend and GPU for both.

Let T be one display refresh interval: 16.67 ms at 60 Hz, 8.33 ms at 120 Hz.
Application CPU frame work includes update/layout/text/upload/draw submission and
excludes blocking vsync wait, which is reported separately. End-to-end latency
includes scheduling and presentation rather than stopping at draw submission.

| Metric | Required gate before default switch |
| --- | --- |
| UI CPU work | At least 20% lower median **and** p95 CPU work per update/frame, aggregated by geometric mean over the four primary workloads: scrolling, selection, streaming and navigation. At least three must improve individually, including scrolling and selection. |
| Per-workload regressions | No repeatable slowdown above 5% in any required workload's median or p95. Publish individual results; an aggregate win cannot hide a failed workload. |
| Input to presentation | p95 must not regress beyond measurement uncertainty in selection, scrolling and typing. Target at least 10% improvement where measurable above the display-refresh floor. Report that floor explicitly; if latency is tied, the mandatory CPU-work improvement still applies. |
| Smooth frames | Under sustained scroll/selection on the target machine, p95 application CPU frame work <= T/2 and p99 <= 3T/4. Fewer than 1% missed presentation intervals in the scripted steady-state run, with compositor/system interruptions recorded. |
| Idle | No redraws, uploads or GPU submissions for an unchanged/unfocused window. Settled idle CPU and wakeups must be no worse than SDL. Focused caret blinking is measured separately and limited to required updates. |
| Startup/navigation | p95 first useful frame and chat-switch presentation must not regress above 5%; report cold and warm cases separately. |
| Memory/lifetime | No leaks or unbounded cache growth. Report CPU RSS/PSS, texture/atlas bytes and peak usage. No unexplained repeatable increase above 5% at matched warmed workloads; any deliberate tradeoff needs an explicit decision before acceptance. |
| Visual/input quality | Same content, effective resolution, font sizes and required features. No blurry scaling, broken glyphs, missing effects, incorrect selection or reduced input support to meet timing gates. |

These are hard delivery gates on a named target machine/configuration. Intel/AMD
and NVIDIA driver coverage should be reported separately; one GPU's result does
not establish performance on all hardware. An unsupported configuration must be
identified rather than silently measured on a different device or software path.

### Benchmark procedure and evidence

1. Run both backends with identical deterministic application/model fixtures,
   fonts, data, viewport, scale, refresh rate and compositor settings. Keep network
   and model-generation delays out of backend rendering comparisons.
2. Separate cold-cache startup from warmed steady state. Warm each backend equally.
3. Use at least seven paired runs per workload, alternating/randomizing backend
   order. Do not run the baseline and candidate simultaneously. Run long enough
   for useful tail statistics: at least 1,000 interactive samples where applicable.
4. Record raw samples and median/p95/p99, plus paired ratios and uncertainty. Keep
   outliers in the data and explain interruptions; repeat noisy runs rather than
   declaring a win from a single timing spike. Count genuinely completed updates
   and presented frames, not iterations of an empty loop.
5. Measure CPU work, GPU execution, presentation cadence, input latency, allocations,
   uploads and memory separately. Timestamp asynchronous presentation using a
   consistent clock. Event-dispatch-to-presentation is not physical
   button-to-photon latency; identify the boundary and any missing instrumentation.
6. Verify screenshots, selection/copy results and completed interactions for both
   backends. A fast run with dropped events or incorrect output is a failed run.
7. Publish a report with commands, source/build hashes, environment, fixture hashes,
   raw samples, individual wins/losses, aggregate calculation and remaining gaps.
   Offscreen tests establish correctness and CPU behavior; actual Wayland
   presentation tests are required to claim desktop smoothness or latency gains.

## Phase 7: optimize from the results

Investigate measured costs in this order, adjusting priority when traces justify it:

1. Avoid unnecessary layout/shaping on selection, hover and scrolling.
2. Eliminate transient per-run text surfaces/textures with glyph-atlas reuse.
3. Reduce texture uploads, copies and draw/state changes.
4. Reduce redundant repainting with correct cached layers and damage tracking.
5. Improve frame scheduling and input/service wakeups without busy polling.
6. Add SIMD or GPU kernels only where profiling demonstrates a remaining bottleneck.

Protect correctness with the same fixtures after each optimization. A renderer
microbenchmark win does not substitute for the full Collie performance gates.

## Phase 8: rollout and definition of done

- [ ] Functional, typography, input and lifecycle tests pass on the native path.
- [ ] All mandatory performance gates pass with a published reproducible report.
- [ ] Actual nested and real Wayland runs are recorded; headless evidence is labeled.
- [ ] Process maps prove the native Collie path loads neither SDL2 nor SDL2_ttf.
  Inspect dynamic loading as well as static dependency listings; dlopen libraries
  are not reliably discovered by `ldd` alone.
- [ ] Default selection, supported platforms, dependencies and error/fallback
  behavior are documented. Keep an explicit comparison/fallback option initially;
  distinguish fallback runs from native-backend measurements.
- [ ] Repeated create/resize/scale/close tests leave no resources or stale handles.
- [ ] CI includes both the native backend and retained SDL compatibility coverage.
- [ ] Review the measured result, then make native Wayland Collie's default in a
  separate scoped change. Subsequent SDL backend removal must account for other
  GUI/OpenGL consumers and X11 users rather than deleting their only backend.

Do not mark this migration complete while it merely renders a window, passes
software-only tests, matches SDL speed, or achieves gains by reducing quality.

## First implementation task

Create a separate implementation branch/worktree. Deliver Phase 1's baseline and
Phase 2's backend boundary first, followed by the minimal SDL-free Wayland example.
Each milestone should include its tests, evidence and remaining gaps. This plan
does not itself authorize publishing or merging future implementation changes.

## Technical references

- [Current GUI API](docs/gui.md)
- [Wayland protocol and operation](https://wayland.freedesktop.org/docs/html/ch04.html)
- [SDL renderer selection](https://wiki.libsdl.org/SDL2/SDL_CreateRenderer)
- [SDL text surfaces](https://wiki.libsdl.org/SDL2_ttf/TTF_RenderUTF8_Blended)
- [FreeType documentation](https://freetype.org/freetype2/docs/index.html)
- [HarfBuzz shaping](https://harfbuzz.github.io/shaping-and-shape-plans.html)
- [xkbcommon documentation](https://xkbcommon.org/doc/current/index.html)
