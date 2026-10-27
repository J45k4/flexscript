# SDL migration implementation evidence

Worktree: `build/sdl-migration`, branch `codex/sdl-migration`, based on merged
master `b7aad8c670fa80e5fa6493b84066c7af8dd384f9`. Implementation is uncommitted.
Current status: the Linux/Wayland implementation and functional acceptance are
complete for the scope in [the correctness report](sdl-migration-correctness-2026-10-27.md).
The user accepted speed on 2026-10-27. Earlier milestones and performance misses
below remain historical evidence; see the final acceptance section at the end.

## Verified on 2026-10-26

- Backend-neutral pointer capture, cursors, diagnostics and normalized replay
  events replace direct SDL calls in Collie and the retained UI.
- The preserved accelerated SDL benchmark renders actual compiled Collie views
  in a private NVIDIA/Wayland compositor: seven runs, 160 samples per run in
  each of scroll, selection, streaming and navigation. Preliminary raw output:
  `build/migration/sdl-baseline/`. This fixture still needs inline image cards,
  proper startup timing, presentation feedback, idle/memory and uncertainty.
- Native Wayland xdg-shell lifecycle, nonblocking prepare/read/cancel handling,
  configure/ack, bounded shared-memory buffer reuse and frame scheduling work
  in isolation. `build/wayland-window-ir 100` passed 100 frame callbacks using
  one buffer. A frame callback is not presentation feedback.
- Both compiler native pipelines support six-word C ABI callbacks, retaining
  callback-only function targets. The callback suite passes 12,012 calls plus
  rejection cases; the existing native pipeline suite passes 39 checks.
- The Flexscript EGL/OpenGL 3.3 renderer passes pixel assertions for rectangles,
  clipping, alpha, uploaded RGBA images and render-target orientation, reporting
  zero GL errors. No new C rendering/window shim is used.
- Direct Fontconfig/FreeType/HarfBuzz adapters match an independent C test
  oracle in 20 comparisons across native IR and direct compilation: metrics,
  glyph IDs, UTF-8 clusters, positions and raster checksums, including Finnish,
  CJK, combining marks, RTL runs and fixed-strike color emoji. Public C structure
  offsets are independently checked before testing the adapter.
- Bounded glyph atlases use R8 coverage and premultiplied color pages. The GPU
  text fixture verifies coverage against FreeType bytes, equality of direct vs
  cached-layer text within one 8-bit level, and no upload/rasterization on a hit.
  Result: 75 hits, 74 misses, two pages, 286,089 glyph upload bytes, zero GL errors.
- The experimental `FLEX_GUI_BACKEND=wayland` path renders the actual compiled
  Collie views, Markdown, tables, icons, CJK and selection via the public GUI API.
  A 24-sample selection smoke run and its visual capture passed. Input in this
  smoke test is normalized replay, not compositor-delivered pointer input.
- All four 24-sample native smoke workloads now pass (scroll, selection, stream,
  navigation), with screenshots and process-map assertions excluding both SDL2
  and SDL2_ttf. The private compositor's test seat delivers a real keymap and
  keyboard focus. These are not physical key/pointer delivery tests.
- The full native Collie/service fixture preserves a Unicode draft while opening
  settings/account, returning to chat and toggling the sidebar through normalized
  replay. Artifacts: `build/migration/wayland-ui-tests/`.
- The keyboard adapter handles seat capabilities, keymaps, serialized XKB masks,
  physical GUI key translation, key repeat and dead-key compose. Independent
  native IR/direct tests pass Finnish å/ä/ö, Shift, AltGr and acute composition.
  Pointer motion/button/axis decoding is implemented but still needs real
  drag/focus-loss/hotplug lifecycle coverage.
- A test-only Weston module now delivers key press/release, UTF-8 text, pointer
  motion, left-button press/release and a wheel step over the actual Wayland
  connection. `tests/ui/wayland-input.flex` passes all seven assertions with no
  SDL loaded. This is compositor-delivered input, not physical-device timing.
  The module uses Weston's public server API, runs only in a dedicated private
  compositor, and is never linked into or required by the application.
- Cache stress: 64 large CJK glyphs force 13 page evictions while staying within
  four atlas pages. Previously evicted glyphs rasterize again. 1,200 varying runs
  stay within the 2 MiB retained shape budget and repeated runs reuse a shape.
- Compiler self-host stages 2 and 3 are byte-identical (SHA-256
  `0c045c32d20e120c59e358d8abcd573868f46427342a28b7b67e8c7be7362832`).
  The SDL compatibility path passes 144 headless GUI checks, unavailable-display
  handling, and all 14 desktop layout groups. CI now includes native callback,
  stack-argument, font and XKB oracle checks; remote CI has not been run.
- Native clipboard now uses `wl_data_device` sources/offers with bounded,
  nonblocking transfers, request cancellation, five-second deadlines and strict
  UTF-8/1 MiB validation. Its descriptors join the Wayland poll set, so waiting
  for a slow clipboard owner does not block input or require a clipboard timer.
- Independent `wl-copy` / `wl-paste` interoperability passes both directions at
  100,000 and 1,048,576 bytes. Incoming data reaches an actual retained UI input;
  process maps exclude SDL. A test owner stays alive until the independent
  consumer acknowledges completion, including compositor clipboard-manager reads.
- Editor paste completion preserves the insertion point and rejects stale
  completions after focus, typing, selection or request changes. Closing the UI
  cancels the transfer and releases the snapshot/result. Cut retains the text
  when copying fails. SDL also uses the normalized asynchronous completion API.
- Kernel pipe tests cover the 1 MiB boundary, overflow, invalid UTF-8, embedded
  NUL, repeated reads without descriptor growth, cancellation and closed-peer
  EPIPE without changing the caller's signal mask. No global SIGPIPE handler is
  installed. Expired reads and writes close their descriptors and retained
  buffers/sources. These and editor race checks were added to CPU CI.
- The full SDL retained-UI suite passes 92 checks and 73 raster checks, plus table,
  Markdown cache, scrolling, selection, resize/DPI and example verification.
  Portable UI tests pass five groups; the shared Collie reducer passes 20 groups.
- That broader suite caught callback definitions being rejected while ordinary
  view transforms captured a semantic source snapshot. Snapshot recording now
  preserves callback-address metadata and its capability effect; transform
  execution still rejects native callback pointers. Regression coverage now
  passes 18,012 native callback calls, semantic snapshot checks and rejection of
  execution in transforms. The native pipeline suite still passes all 39 checks.
  New self-host stages 4/5 match SHA-256
  `99c701435e49c1335b56e262be691595b485428795c9df80bd23dfbacf00964c`.
  `build/compiler-next` now points to that verified compiler.
- Native cursors now prefer the compositor's cursor-shape protocol and otherwise
  use `libwayland-cursor` themes, including horizontal resize. The fallback honors
  `XCURSOR_THEME` and `XCURSOR_SIZE`, keeps at most four integer-density themes,
  and uses the latest pointer-enter serial. Repeated unchanged requests do not
  submit updates. Cursor-shape requests and the theme fallback pass the private
  protocol fixture; the server reports zero invalid focus serials. Actual themed
  cursors also pass on a real 2x output. The fallback now animates theme images
  with bounded cursor-surface callbacks; the compositor owns the shape path.
- Logical window size and physical framebuffer size are now independent.
  Fractional-scale + viewporter preferred scales drive physical buffer sizes;
  entered outputs and preferred integer scale supply the fallback. A single
  output's density is available before first map. Resize/density changes update
  EGL, clipping, fonts and cached layers, preserving the logical UI and drafts.
- A private compositor-side fixture sends 1x -> 1.25x -> 1.5x -> 2x -> 1x.
  Actual native captures pass clipping/pixel checks with zero GL errors at
  1600x1000, 2000x1250, 2400x1500, 3200x2000 and back to 1600x1000, while logical
  editor bounds and text survive. Custom canvas coordinates survive the same
  sequence. These injected preferences prove protocol/rendering behavior;
  physical mixed-monitor movement has not been accepted.
- A real Weston integer-2x output passes all four native Collie workloads and
  the complete service/UI fixture at 1600x1000 logical / 3200x2000 physical.
  Startup checks confirm 2x density before the first buffer is presented.
  Artifacts: `build/migration/wayland-hidpi-tests/`. This remains correctness
  evidence, not performance or physical-display latency acceptance.
- The Flexscript protocol generator is now independently checked against
  `wayland-scanner` for all 22 interfaces, including signatures, typed/nullable
  arguments and versioned additions. Canonical upstream wayland-protocols 1.49
  XML, licenses and hashes are pinned under `tests/tooling/wayland-protocols` so
  older CI distributions can run the same oracle. Public cursor/protocol ABI
  offsets, mixed-output scale decisions and invalid/oversized rejection pass
  CPU tests and are included in CI.
- Native text-input-v3 version 1 now carries atomic preedit, commit and
  surrounding-delete transactions. Outgoing state includes a UTF-8-safe bounded
  surrounding window and the actual logical caret rectangle after layout/pan.
  Missing text-input support retains XKB compose/dead-key input. The backend also
  accepts a valid `no_keymap` keyboard event before a virtual keyboard supplies
  its map, clearing prior XKB/compose/repeat state instead of closing the window.
- Preedit is underlined with its selected range/caret and remains separate from
  the saved draft. Focus epochs reject queued edits after editor replacement,
  focus changes or external value changes. Model echoes preserve the insertion
  point. Escape cancels composition before Collie's back/page shortcut. Enter
  does not submit while composition is active.
- The normalized token queue bounds retained composition to 128 transactions
  and 4000 UTF-8 bytes per string, releases borrowed data on the next poll, and
  frees pending payloads on close. CPU tests pass under both compiler pipelines:
  long preedit, Chinese commits, selection/deletion order, UTF-8 boundaries,
  serial mismatch/wrap, focus/model races and cleanup. Independent SDL-header
  events verify normal/extended composition and character-to-byte conversion.
  Like existing event fixtures, this bypasses SDL2-compat's text injection bug;
  it is decoder/ABI coverage, not actual SDL IME delivery acceptance.
- Real Fcitx 5.1.23 Pinyin composition passes on a private NVIDIA headless Sway
  1.12/wlroots 0.20.2 compositor, including a candidate popup capture inspected
  below the caret, incremental `n` -> `ni hao`, and committed `你好`. Both native
  compiler pipelines pass. The complete Collie/service app preserves that
  Chinese composer draft and shuts down cleanly at 125% and 200% scale. No SDL
  is present in process maps; native GL reports zero errors. These are actual
  input-method/protocol tests driven by a virtual keyboard, not physical-device
  timing or physical-monitor acceptance.
  Artifacts: `build/migration/ime-collie-tests-125/` and
  `build/migration/ime-headless-2x/results/` (also repeated from the final build at
  `build/migration/ime-headless-125-final/results/`). The reproducible wrapper
  creates a separate D-Bus/runtime/config session and stops it automatically.
- After the IME changes, the native input fixture still passes all seven
  compositor-delivered key/pointer assertions; independent clipboard peers
  still pass both directions at 100,000 and 1,048,576 bytes. All four native
  2x UI smoke workloads and the full Collie/service fixture pass. The SDL path
  retains 144 GUI checks, unavailable-display handling, 92 retained-UI checks,
  73 text raster checks and all 14 Collie desktop layout groups.
- Unicode 17 extended grapheme segmentation is implemented in Flexscript, with
  strict length-delimited UTF-8 and no external Unicode runtime. The Flexscript
  generator emits 828 immutable packed ranges (8,280 data bytes). Both compiler
  pipelines pass all 766 official grapheme conformance cases plus six edge cases,
  and every property value across all 1,114,112 code points matches an independent
  parser of the pinned, licensed UCD inputs. Generator output is byte-identical.
- Font fallback and emergency word wrapping now keep graphemes intact, so a
  family emoji is not split into separate fonts at each ZWJ. Logical arrow and
  delete operations consume entire graphemes, including accents, flags, family
  emoji and Indic conjuncts. Editor hit testing filters interior boundaries.
  Selection replacement/copy/cut expand partial grapheme ranges. Tests include
  a joiner insertion that leaves the logical insertion point inside the newly
  joined cluster; subsequent user deletion still removes that whole cluster.
  Internal hit testing caches endpoint validity and checks the nearest two
  valid stops instead of repeatedly searching the full boundary map.
- Native caret and selection x coordinates use the exact cached HarfBuzz run
  used by rendering, rather than reshaping each prefix. Font GDEF ligature
  carets are adjusted for the shaped advance; missing carets use the cluster's
  advance divided across graphemes. Cache keys include explicit direction.
  Twenty IR/direct cases match independent HarfBuzz metrics, including kerning,
  combining marks, RTL, CJK, color emoji and deliberately uneven GDEF carets in
  LTR and RTL test fonts. These SFNT mutations are test-only, never app assets.
- Native retained-editor checks at 125% and 2x verify whole-grapheme arrows and
  deletion, one-glyph family emoji fallback, unsplit emergency wrapping, tabs,
  decreasing RTL caret positions, logical-end caret placement and selection.
  After warming, 1,000 pointer hits produce zero new layout builds, prefix font
  measurements or shape-cache misses. Captures report zero GL errors and no SDL.
  `build/migration/grapheme-native-125/results/text-editing-capture.png` was
  inspected for the mixed-font/RTL selection result.
- The rebuilt full Collie/Pinyin fixture and all four native smoke workloads
  pass at 2x. The compact 800x500 logical layout uses its actual header settings
  control; Ctrl+B opens/focuses conversation search and return preserves the
  Unicode composer draft. Replay data is isolated per run, preserving inputs
  without restoring prior navigation. SDL retains its compatibility prefix
  measurements, while passing all 144 GUI, 92 retained-UI, 73 raster and 14
  desktop layout checks after the grapheme changes. The complete wide 125%
  suite also passes, including the direct compiler's native text fixture.
  Artifacts: `build/migration/grapheme-native-2x-verified/`,
  `build/migration/grapheme-native-125-verified/` and
  `build/migration/grapheme-final-125/` and `build/migration/grapheme-final-2x/`.
  The final 2x run includes the endpoint-cache and insertion/deletion edge fixes.
  Remote CI is not yet run.

### Paragraph bidi and visual editing (2026-10-26)

- `libs/unicode/bidi.flex` implements Unicode 17 UAX #9 P1–I2 and separate
  per-wrapped-line L1/L2, including explicit overrides/embeddings, depth overflow,
  FSI/isolates, isolating run sequences and paired brackets. Paragraph maps keep
  logical byte offsets and can be reused for different wraps. All storage is
  bounded and explicitly released. The pure Flexscript generator pins and hashes
  its inputs and emits 11,443 packed bytes of class/bracket/mirror data; no new
  application Unicode runtime dependency is introduced.
- Both native compiler pipelines pass the **entire** official Unicode 17 bidi
  corpus: 770,241 BidiTest direction variants plus 91,707 BidiCharacterTest cases
  (**861,948** total). Every codepoint's class, paired bracket and scalar mirror
  match an independent parser. Additional checks cover paragraph boundaries,
  wrapped whitespace/isolates, immutable paragraph reuse, UTF-8/scalar lookup,
  empty/auto-RTL input, embedded NUL, malformed UTF-8 and output bounds.
  Evidence: `build/migration/unicode-bidi-tests/report.json` and
  `build/migration/unicode-bidi-test.log`.
- Native retained text resolves bidi across rich/style/font runs and separately
  within table cells, before wrapping. L1 can split trailing whitespace from an
  existing run; L2 changes visual x positions while piece storage and copy order
  remain logical. Measurement, glyph drawing and caret maps share the same
  explicit direction and shape-cache entry. Script itemization uses the existing
  HarfBuzz Script adapter, with strong-script changes at grapheme boundaries and
  Common/Inherited context; complete Script_Extensions resolution is not claimed.
  CRLF remains one displayed newline even when paragraph levels split its runs.
- Independent retained-layout checks use official expected paragraph levels and
  a separate test-side L1/L2 calculation: 336 paragraphs in plain, styled and
  wrapped variants plus separator cases, **1,020 layouts per compiler pipeline**.
  They check levels, visual character order, logical source spans, adjacent visual
  piece bounds and agreement with the draw-path widths. Two additional table
  layouts check independent cell bases, RTL links, logical copy order and clips.
  Evidence: `build/migration/ui-bidi-tests/`.
- Native horizontal arrows follow visual grapheme positions, selection collapse
  chooses the visual edge, and pointer/arrow caret affinity distinguishes the two
  visual positions at a logical bidi boundary. Actual private GPU editor tests
  check 26 pointer stops, visual arrow traversal in both directions, whole RTL
  selection collapse and unchanged logical content. After warming, 1,000 pointer
  hits still produce zero layout rebuilds, prefix measurements or shape misses.
  The mixed Arabic/Hebrew/Latin/number capture at
  `build/migration/bidi-editor-125-verified/results/text-editing-capture.png` was
  visually inspected, including joined Arabic and mirrored brackets.
- The rebuilt full Collie/service app passes real Pinyin preedit/Chinese commit
  at 125% and 2x. The 2x run also passes all four native workload smokes and the
  compact full-app navigation/settings fixture. The direct compiler's editor
  fixture passes at 2x. Process maps contain no SDL and GL reports zero errors.
  These private headless GPU runs prove functional behavior, not physical monitor
  smoothness or the paired performance target. Artifacts:
  `build/migration/bidi-editor-125-verified/` and
  `build/migration/bidi-editor-2x/`. The final newline-caret fix is included in
  `build/migration/bidi-final-125/` and `build/migration/bidi-final-2x/`; both pass
  all functional checks. The 2x final capture was also visually inspected.
- One earlier private-session attempt (`bidi-editor-125/`) failed before the new
  editor ran: the unchanged IME fixture received plain `nihao ` and no preedit.
  The original protocol/Fcitx/report logs remain saved. The driver now waits for
  the private Fcitx service to acknowledge active Pinyin on the focused context,
  rather than relying on a fixed delay. Both subsequent scale runs still assert
  real `你好` preedit/commit and pass; those assertions remain required.
- The final 125% wrapper exited with a cleanup error after all functional checks
  passed: a private document-portal FUSE mount was still shutting down while
  `TemporaryDirectory` traversed it. Its mount/process audit found that shutdown
  had completed; the leftover test directory was then removed. The wrapper now
  waits for private portal mounts, can unmount only its own `/tmp/fs-ime-*/doc`
  portal, and saves `runtime-cleanup.json`. The final 2x wrapper exits cleanly.
  This was test-runtime cleanup, not a suppressed application failure.
- Regression checks pass: 772 grapheme cases, 20 independent font cases, 20
  independent caret cases, 144 GUI checks, 92 retained-UI checks, 73 raster checks,
  Markdown/tables/scrolling/selection/examples, both-pipeline IME editor checks
  and all 14 Collie desktop layout groups. The CPU suites are wired into CI;
  remote CI has not run. SDL remains the default and frozen baseline artifacts
  remain untouched. No paired performance gain is claimed.
  One concurrent regression run recorded a 141.5 us selection drag median. The
  isolated diagnostic after the native sessions stopped was 107.5 us (27 us hit
  median), with zero warm layout builds/font measurements. Both raw results are
  retained; these diagnostics do not substitute for the paired acceptance suite.

### Default Unicode line-break engine (2026-10-26)

`libs/unicode/linebreak.flex` implements the Unicode 17 UAX #14 default LB1–LB31
opportunity algorithm in Flexscript. A byte-addressable owned map distinguishes
prohibited, soft and mandatory boundaries. LB9 combining context, initial/final
quotes and East Asian context, numeric sequences, Hangul, Brahmic syllables,
regional-indicator parity and emoji modifier rules are included. Recommended
default SA/CJ/ambiguous resolution is used; no dictionary/hyphenation service or
new application runtime dependency is added.

Both compiler pipelines pass all **19,338 official cases**, four added cases,
mandatory/soft-kind and malformed-input/access checks. All 1,114,112 packed
property values match an independent parser of the contributory LineBreak.txt,
EastAsianWidth, DerivedGeneralCategory and emoji data. The Flexscript generator
instead uses DerivedLineBreak with canonical reserved-codepoint defaults; all
inputs have pinned URLs/hashes and Unicode licensing. Regeneration is exact.
There are 2,497 packed ranges / 24,970 data bytes, with direct Hangul lookup.
Evidence: `build/migration/unicode-linebreak-tests/` and
`build/migration/unicode-linebreak-test.log`. The CPU suite is wired into CI.

At this checkpoint the engine was not yet used by the retained desktop wrapper. Selecting these
opportunities across rich/font runs using shaped widths, grapheme tailoring,
trailing whitespace and visible discretionary soft hyphens remains work. Existing
native bidi UI verification therefore proves the current space/emergency-grapheme
wrapper, not complete Unicode wrapping. Word/sentence segmentation is separate.
Rebuilding Collie and the native UI benchmark with the unused line-break import
produces byte-identical binaries to the final GPU-tested bidi builds (the compiler
removes unreachable code/data). Evidence: `build/migration/linebreak-app-binaries.json`.

### Native wrapping integration (2026-10-26)

- `libs/ui/desktop/flow.flex` now chooses Unicode line-break opportunities across
  rich/style/font runs, filtered at global extended grapheme boundaries. A style
  or font boundary does not itself create a break. Exponential search and binary
  refinement query the actual shaped slices to choose a line; overwide spans use
  emergency grapheme breaks. Long ordinary words are split before the 32 KiB
  per-run shaping limit. A single over-limit grapheme remains unsupported.
- Measurement probes use a reusable 64 KiB arena; temporary overflow blocks are
  freed after each probe. Only final positioned pieces enter the retained layout.
  Unicode maps and the probe arena are released when layout finishes. Shape and
  glyph-cache bounds remain unchanged. SDL retains its compatibility wrapping
  path and its existing prefix geometry; the frozen SDL artifacts are unchanged.
- Tabs have an explicit one-byte-to-four-space mapping. Selected soft-hyphen
  breaks map the source U+00AD suffix to a displayed hyphen; copy/delete operate
  on the source. Hanging trailing spaces preserve their source spans with empty
  display text and collapsed carets. These mappings survive L1 splitting and L2
  positioning and are shared by drawing, hit testing and selection geometry.
  Fitting a line therefore does not move a word merely to retain blank trailing
  spaces, and an inactive soft hyphen stays invisible.
- RTL horizontal navigation now crosses wrapped lines in paragraph direction,
  preserving upstream/downstream affinity at their shared logical byte offset.
  Entry to an adjacent paragraph uses its logical endpoint even when the base
  direction changes. Merged table layouts retain visual navigation capability.
  CPU checks verify left movement into an RTL table cell stays in that cell.
- **789 wrap layouts per compiler pipeline** pass: 352 official LineBreakTest
  samples in plain/styled variants, focused whitespace/tab/SHY/combining cases,
  CJK/Arabic/Hebrew/emoji, and a 40 KB unbroken word. Actual selected ordinary
  breaks must match canonical opportunities; focused Latin cases exhaustively
  calculate greedy choices using an independent C HarfBuzz width oracle, and
  check each displayed fragment's width. The existing **1,020 bidi layouts per
  pipeline** and mixed-direction table cases still pass.
  Evidence: `build/migration/ui-linebreak-tests/`, `flow-wrap-tests.log` and
  `flow-bidi-test.log` under `build/migration/`.
- `tests/ui/wrap-editor.flex` is a real-font native CPU editor test that opens no
  window. Both pipelines pass source/display caret maps, SHY copy/delete, hidden
  spaces, RTL wrapped-line/paragraph keys, emergency grapheme safety, warm cache
  reuse, line caps and cleanup. Multiline inputs keep scrollable geometry despite
  a viewport line cap; read-only text caps its visible layout. An initial test
  incorrectly expected the input's geometry to be capped; it now checks both
  contracts explicitly. The new CPU suites are wired into CI; remote CI has not
  run.
- Private GPU runs at 125% and 2x pass the editor cases, actual Pinyin/Chinese
  commit in full Collie/service, all four native workload smokes and wide/compact
  app navigation/settings fixtures. The editor verifies 24 exact pointer stops,
  SHY glyph/caret placement, source-preserving deletion/copy, hidden-space carets
  and RTL line transitions. Warm hits still make no layout builds, prefix font
  measurements or shape-cache misses. Process maps contain no SDL and GL reports
  zero errors. The 125% capture was inspected for joined Arabic, mirrored
  brackets, CJK punctuation wrapping, visible `extra-` / `ordinary`, and a
  nonbreaking-space group. Artifacts: `build/migration/flow-editor-125/` and
  `build/migration/flow-editor-2x/`; test runtimes shut down cleanly.
- The final build adds an unfocused-caret fix: focus loss hides the caret and
  excludes its blink phase from `ui_desktop_needs_draw`; focus gain resets the
  blink epoch and dirties one frame so the caret is immediately visible. Both
  CPU IME pipelines pass focus/idle assertions. Native pixel readbacks at 125%
  and 2x prove the caret disappears on blur; advancing its clock across three
  blink intervals does not request another draw. The current-source full suite
  passes in `build/migration/flow-final-125/` and `flow-final-2x/`, including
  real Pinyin/Collie and all four workload smokes. The final 2x wrap capture was
  visually inspected. This is a caret-redraw fix, not a complete idle-CPU/wakeup
  or initial-focus/multiwindow lifecycle acceptance result.
- SDL regression checks retain 92 UI checks, 73 raster checks,
  Markdown/tables/scrolling/selection/examples and both-pipeline IME editor checks.
  Diagnostic selection medians in that regression run were 25 us per hit and
  109.5 us per drag frame; these are not paired acceptance measurements. Actual
  presentation timing, complete lifecycle/complex-script acceptance and the full
  matched performance/memory gates remain unproven. SDL stays the default.
  The final SDL run also passes 144 GUI checks and all 14 Collie desktop groups.
  Its concurrent selection diagnostic was 42/203 us (hit/drag medians); after
  private GPU sessions stopped, the isolated current-source diagnostic was
  27/110.5 us. Raw results remain in `flow-final-desktop.log` and
  `flow-selection-isolated.json`. No regression/gain is inferred from this
  host-sensitive single-run variation; matched acceptance measurements remain
  required.

### Animated cursors and seat recovery

- The native theme fallback advances frames from monotonic elapsed time, skips
  zero-duration frames, updates each frame's size/hotspot, and requests at most
  one cursor-surface callback. The event wait combines cursor/key-repeat/pipe
  deadlines and returns promptly when pending events change them. Static cursors
  and hidden cursors have no animation timer or callback. Theme selection starts
  its clock after theme loading. No application repaint is required.
- Keyboard capability loss previously cleared the `wl_seat` reference while its
  pointer remained live. It now drops keyboard state, repeat and modifiers while
  preserving the seat/pointer/clipboard. Capability restoration creates usable
  input objects again. Pointer leave/device loss releases active drags at (-1,-1)
  with no clipboard-authorizing serial. Seat/global removal releases cursor,
  clipboard (including pending pipes/sources/offers), keyboard and IME resources;
  clipboard manager removal also releases its old data device.
- `scripts/test-native-cursor.py` passes 2,000 independently checked frame and
  deadline cases per IR/direct pipeline, including elapsed time beyond 49 days,
  static/all-zero/zero-delay frames, invalid bounds, timeout/callback exclusion
  and focus cleanup. The public cursor ABI is checked against system headers.
  The CPU fixture is wired into compiler CI; remote CI has not run.
- `scripts/test-wayland-cursor-session.py --regressions` passes on fresh private
  Weston/NVIDIA sessions at actual 1x (IR) and 2x (direct). A generated three-frame
  theme changes dimensions and hotspots. Each lifecycle run records all frames,
  41 completed callbacks, 43 cursor commits, one reused callback metadata record,
  zero application repaints and no loaded SDL. It verifies static-cursor cache
  hits, animation cancellation/restart on pointer leave/reentry, keyboard and
  pointer capability recovery, two active-drag cancellations and seat removal.
  Wire logs independently confirm all three logical hotspots at both densities.
  These are compositor protocol tests, not physical input or latency evidence.
- A third private server passes the existing 1x/1.25x/1.5x/2x/1x framebuffer,
  text/clip/custom-canvas checks with zero GL errors, cursor shapes with zero
  invalid serials, close while an animated callback is pending, all seven normal
  input-delivery checks, and independent `wl-copy`/`wl-paste` interoperability at
  100,000 and 1,048,576 bytes. CPU keyboard, 22-interface metadata, clipboard pipe
  and asynchronous editor-paste regressions pass. Artifacts and cleanup receipts:
  `build/migration/cursor-session-verified/`, `cursor-state-tests/`.
- Both compiler pipelines also pass 100 repeated clipboard seat detachments with
  simultaneous active incoming/outgoing pipes, sources and offers: failed read
  completion, closed descriptors, emptied ownership lists and unchanged FD count.
  The SDL regression retains 92 UI and 73 raster checks, Markdown/tables/scrolling/
  selection and examples. Its 26/110.5 us hit/drag medians are diagnostics only,
  not matched performance evidence. Rebuilt Collie plus the retained editor pass
  real Fcitx Pinyin preedit/Chinese commit, candidate-popup/caret placement and
  Unicode selection/wrapping at private 1.25x with zero GL errors and no SDL maps.
  Artifacts: `build/migration/cursor-candidate/`, `cursor-collie-125/`.
- This closes the animated-theme gap; complete window lifecycle, physical
  mixed-output movement, presentation timing and the matched performance/memory
  acceptance gates remain outstanding. SDL remains the default.

### Native window lifecycle

- Added `toplevel.flex` with owned, bounded title storage, requested/confirmed
  window states, normal/preferred restore sizes and configure transactions. The
  native backend negotiates xdg-shell up to version 6, capped by the server's
  advertised version, so tiled-edge states can constrain a client resize.
  Geometry/state becomes current at `xdg_surface.configure`, and malformed state
  arrays/oversized compositor sizes are rejected. Zero-size state-only configures
  retain current fullscreen/maximized/tiled dimensions rather than replacing them
  with the saved floating size; both pipelines cover that regression.
- `GUI_HIDDEN`, show/hide and client-requested resize now work. Hidden drawing and
  readback use a pbuffer; hidden/unconfigured present neither attaches a buffer
  nor increments presentation counters. Hiding releases the EGL window surface,
  unmaps content and destroys the xdg role. Showing uses an asynchronous sync
  barrier, recreates the role, reapplies title/app ID/constraints/requested modes,
  and awaits fresh configure before attaching content. The same Wayland surface,
  GL context, layer textures, font caches and atlas ownership survive.
- Added backend-neutral maximize, minimize and restore requests, including SDL
  compatibility. Restore means shown, windowed and unmaximized. Fixed floating
  windows retain their requested size; fullscreen/maximized/tiled sizes obey the
  compositor and defer application resize requests to the windowed restore size.
  Fixed-size hints are relaxed for fullscreen and restored afterward. Disconnect
  or compositor close emits one close event and releases held input/transfers.
- xdg-shell provides no unset-minimize operation. Our programmatic restore after
  a minimize request recreates the role; actual focus remains compositor policy.
  Reusing the role failed to get a fresh configure on the tested Weston 15.
  The role lifecycle was checked against [SDL's Wayland implementation](https://raw.githubusercontent.com/libsdl-org/SDL/SDL2/src/video/wayland/SDL_waylandwindow.c).
  Rebinding the EGL surface alone did not resolve that failure; no confirmed
  driver-FIFO root cause is claimed. The EGL configuration now explicitly needs
  both window and pbuffer support, verified here on NVIDIA.
- Both compiler pipelines pass the CPU configure/title/restore/bounds fixture;
  it is wired into compiler CI. SDL passes 147 GUI checks plus unavailable-display
  and five harness checks. The retained UI still passes 92 UI/73 raster checks,
  Markdown/tables/scrolling/selection/examples. Its concurrent 25.5/107.5 us
  hit/drag medians are diagnostics, not paired acceptance measurements.
- `window-release-verified/` records private Weston 15 at 1x IR and 2x direct,
  negotiating xdg-shell v5. Independent compositor state/wire observations and
  framebuffer pixels verify initial hidden drawing, map, ordinary resize,
  fullscreen/restore, maximize/unmaximize, hidden attribute replay,
  minimize/restore, 20 rapid remaps, retained layer/text rendering, fixed-size
  requests and close/disconnect. Twelve repeated hidden create/resize/close
  cycles each leave the process at six descriptors; stale handles are rejected.
  These short runs do not establish long-running memory/ownership acceptance.
- Weston 15's generic xdg size getters return zero. Their observations are kept
  separately from the independent protocol logger's received min/max requests.
  Sway IPC's `geometry` is the original natural size, while its layout rectangles
  can describe a forced outer container; neither alone proves composed content
  size after an external resize. See [Sway's IPC implementation](https://raw.githubusercontent.com/swaywm/sway/1.12/sway/ipc-json.c).
  The Sway fixture instead requests a repaint and checks the actual private
  compositor capture: both corner extents and marker sizes retain the requested
  dimensions at fractional/2x scale. Failed attempts remain in `window-session-r*`
  and `window-sway-125*`; they include the corrected renderer upload-counter/state
  slot collision and observer assumptions, rather than discarded failures.
- `window-release-cursor/` also passes animated cursor/seat recovery, static/leave idle,
  fractional scale transitions, seven normal input checks, pending-callback close
  and independent clipboard copy/paste through 1 MiB after the lifecycle changes.
  All generated evidence stays under ignored `build/migration/`.
- Final current-source Sway runs at 1.25x and 2x negotiate xdg-shell v6. They
  verify tiled edge notifications, preserve tiled dimensions across a client
  resize request, and apply the preferred size when floating again. The fixture
  repaints configure events while awaiting checkpoints so real compositor
  transactions can complete; it does not treat the first state-only configure
  or an IPC observation timeout as completion. Full rebuilt Collie/service,
  actual Fcitx Pinyin/preedit/candidate placement, the retained Unicode editor,
  and all four 24-sample native workload smokes pass with zero GL errors and no
  SDL maps. Wide/compact settings/sidebar/draft fixtures also pass. Artifacts:
  `window-verified-125/`, `window-verified-2x/`, `window-release-candidate/` and
  `window-release-benchmark/`. This is correctness evidence, not paired timing.
  Final native Collie/table/Unicode-editor captures were visually inspected.
  `window-final-evidence.json` records source/binary hashes and a host-visible
  cleanup audit: the five final Weston sessions and both final Sway runtimes
  stopped, with no matching test processes or mounts left. Remote CI and the
  performance release gates remain unproven; SDL remains the default.

## Reproduction

Run from this implementation worktree. Generated binaries/captures remain in
ignored `build/`. Application code, protocol generator and builders are
Flexscript; C/Python here are independent test oracles/orchestration only.

```sh
nice -n 19 python3 scripts/test-native-text.py --compiler build/compiler-next
nice -n 19 python3 scripts/test-native-callback.py --compiler build/compiler-next
nice -n 19 python3 scripts/test-native-keyboard.py --compiler build/compiler-next
nice -n 19 python3 scripts/test-native-cursor.py --compiler build/compiler-next
nice -n 19 build/compiler-next tests/ui/toplevel-state.flex -o build/migration/toplevel-state
build/migration/toplevel-state
nice -n 19 python3 scripts/test-wayland-metadata.py --compiler build/compiler-next
nice -n 19 build/compiler-next tests/ui/display-state.flex -o build/migration/display-state
build/migration/display-state
nice -n 19 build/compiler-next tests/ui/clipboard-pipes.flex -o build/migration/clipboard-pipes
SDL_VIDEODRIVER=dummy build/migration/clipboard-pipes
nice -n 19 build/compiler-next tests/ui/clipboard-editor.flex -o build/migration/clipboard-editor
SDL_VIDEODRIVER=dummy build/migration/clipboard-editor
nice -n 19 build/compiler-next examples/gui/wayland-canvas.flex -o build/wayland-canvas
nice -n 19 build/compiler-next examples/gui/wayland-text.flex -o build/wayland-text
nice -n 19 build/compiler-next scripts/build-ui-benchmark.flex -o build/build-ui-benchmark
nice -n 19 build/build-ui-benchmark --compiler build/compiler-next --out build/migration/native
```

Self-contained cursor/seat protocol and regression sessions (requires the
already extracted Weston 15 tree and private GPU access; installs nothing):

```sh
nice -n 19 python3 scripts/test-wayland-cursor-session.py \
  --compiler build/compiler-next --weston-root build/weston-root \
  --out build/migration/cursor-session-verified --regressions
nice -n 19 python3 scripts/test-wayland-window-session.py \
  --compiler build/compiler-next --weston-root build/weston-root \
  --out build/migration/window-release-verified
```

The private Sway/Fcitx session wrapper accepts `--window-fixture` in addition to
the IME, text, Collie and benchmark fixtures. It runs the fixed-size/composed-pixel
and tiled-restore checks against that session's IPC socket, then stops the private
compositor and removes its runtime. For example:

```sh
nice -n 19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/window-release-ime \
  --text-fixture build/migration/window-release-editor \
  --window-fixture build/migration/window-release-size \
  --collie build/migration/window-release-candidate/collie \
  --benchmark build/migration/window-release-benchmark/ui-benchmark \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/window-verified-125
```

GPU runs require a private compositor, with `DISPLAY` unset. The test compositor
is Weston 15.0.1, headless backend, GL renderer, kiosk shell, 1600x1000, 1x scale.
Client environment:

```sh
env -u DISPLAY XDG_RUNTIME_DIR="$PWD/build/migration/runtime" \
  WAYLAND_DISPLAY=wayland-flex-test nice -n 19 \
  build/wayland-text build/migration/wayland-text.rgba
env -u DISPLAY XDG_RUNTIME_DIR="$PWD/build/migration/runtime" \
  WAYLAND_DISPLAY=wayland-flex-test FLEX_GUI_BACKEND=wayland nice -n 19 \
  build/migration/native/ui-benchmark build/migration/native-smoke.request.json
```

The test-seat compositor uses a separate socket `wayland-flex-input` and Weston's
`--fake-seat` option. Run the integrated smoke suite against that private socket:

```sh
nice -n 19 python3 scripts/test-wayland-ui.py \
  --benchmark build/migration/native-input/ui-benchmark \
  --collie build/native-candidate/collie --runtime build/migration/runtime \
  --display wayland-flex-input --require-seat
```

For protocol input delivery, compile the independent Weston 15 module and start
a **new dedicated private compositor** with the same headless settings plus
`--fake-seat --socket=wayland-flex-delivery
--modules="$PWD/build/migration/weston-input.so"`. The module sends its sequence
once per newly mapped test surface. Do not load it into an ordinary session.

```sh
cc -shared -fPIC -O2 -Wall -Wextra -Werror -Wno-error=attributes \
  -Ibuild/weston-root/usr/include/libweston-15 \
  $(pkg-config --cflags wayland-server pixman-1 xkbcommon) \
  tests/ui/weston-input.c -o build/migration/weston-input.so
nice -n 19 build/compiler-next tests/ui/wayland-input.flex -o build/migration/wayland-input
env -u DISPLAY XDG_RUNTIME_DIR="$PWD/build/migration/runtime" \
  WAYLAND_DISPLAY=wayland-flex-delivery nice -n 19 build/migration/wayland-input
```

The two test-seat/delivery compositors started for this verification were stopped
afterward. Start fresh instances before reproducing their checks.

Clipboard interoperability uses the same input fixture in a separate private
socket (`wayland-flex-clipboard`). Build and run:

```sh
nice -n 19 build/compiler-next tests/ui/wayland-clipboard.flex -o build/migration/wayland-clipboard
nice -n 19 python3 scripts/test-wayland-clipboard.py \
  --binary build/migration/wayland-clipboard --runtime build/migration/runtime \
  --display wayland-flex-clipboard
```

The production editor uses `gui_clipboard_request(window)`, receives
`GUI_CLIPBOARD` with a request token, then takes/releases its owned result.
The old synchronous native helper can read our own selection only; external
selections require the asynchronous API. Multiple simultaneous incoming reads
are intentionally canceled in favor of the newest request. Up to eight outgoing
transfers retain their source bytes while clipboard ownership changes.

Display/cursor fixtures use the same private setup with the test-only
`weston-input.so` and `weston-display.so` modules. The latter advertises the
fractional-scale and cursor-shape protocols and writes a report selected with
`FLEX_WESTON_DISPLAY_REPORT`. Its generated C protocol headers/code are an
independent test producer, never an application dependency. Compile them with
`wayland-scanner server-header` / `private-code` from the canonical XML and link
with `tests/ui/weston-display.c` and Weston 15 public headers. Include the tablet
protocol C metadata for the cursor manager's typed reference.

```sh
nice -n 19 build/compiler-next tests/ui/wayland-scaling.flex -o build/migration/wayland-scaling
nice -n 19 build/compiler-next tests/ui/wayland-cursor.flex -o build/migration/wayland-cursor
nice -n 19 build/compiler-next tests/ui/wayland-canvas-scale.flex -o build/migration/wayland-canvas-scale
nice -n 19 python3 scripts/test-wayland-display.py \
  --scaling build/migration/wayland-scaling --cursor build/migration/wayland-cursor \
  --canvas-scaling build/migration/wayland-canvas-scale \
  --runtime build/migration/runtime --display wayland-flex-fractional \
  --server-report build/migration/display-server.json
```

For actual integer-2x output, Weston headless `--width`/`--height` are logical:
`--width=1600 --height=1000 --scale=2` produces 3200x2000 physical pixels. Do not
double both the requested size and scale. The cursor fixture requires the input
module; the complete Collie smoke suite uses a clean private compositor without
injected input. Run `tests/ui/wayland-canvas-scale.flex` with argument `2000` to
check initial density before the first present. Collie's `--dump-window FILE`
records logical/physical dimensions, density and SDL process-map status for QA.

IME CPU checks and an actual CJK input method run:

```sh
cc -shared -fPIC -O2 -Wall -Wextra -Werror tests/ui/ime-events.c -o build/migration/ime-events.so -ldl
nice -n 19 build/compiler-next tests/ui/ime-editor.flex -o build/migration/ime-editor
env -u DISPLAY -u WAYLAND_DISPLAY SDL_VIDEODRIVER=dummy \
  nice -n 19 build/migration/ime-editor build/migration/ime-events.so
nice -n 19 build/compiler-next tests/ui/wayland-ime.flex -o build/migration/wayland-ime
nice -n 19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/wayland-ime --collie build/native-candidate/collie \
  --package-root build/migration/ime-lab/root --scale 2000 \
  --out build/migration/ime-headless-2x
```

The last command needs render-node access. It forces `WLR_BACKENDS=headless`,
uses a new mode-700 runtime and a separate D-Bus session, and never loads the
user's Sway/Hyprland/Fcitx configuration. It requires Sway, Fcitx/Pinyin, wtype and
`dbus-run-session`; grim supplies an additional compositor/candidate screenshot
when available. Omit `--package-root` if the test dependencies are installed.
For this local run, seven packages were downloaded and extracted only into the
ignored test root: sway, wlroots0.20, libime, opencc, marisa,
fcitx5-chinese-addons and libliftoff. URLs/SHA-256 are recorded in
`build/migration/ime-lab/packages.json`; no system packages were installed.
Use `--native-pipeline direct` when building the second-pipeline fixture.
The low-level `scripts/test-wayland-ime.py` can instead use an already-running
**private** session described by `--session FILE.json`.

An attempted private nested Hyprland 0.56.2 instance aborted during backend
creation: Aquamarine requested wl_compositor version 6 while Weston advertised
5. The command/log and SIGABRT backtrace identify this test-environment failure;
no Collie window ran there. Sway's headless backend supplied the actual IME
acceptance environment. No user desktop session/configuration was changed.

The manually started IME lab and this round's three private Weston display/
cursor/HIDPI servers were stopped after saving evidence. The reproducible IME
wrapper also stopped each of its private sessions. Start a fresh private server
before reproducing the lower-level native display/clipboard tests.

Unicode and shared caret geometry checks:

```sh
nice -n 19 python3 scripts/test-unicode.py --compiler build/compiler-next
nice -n 19 python3 scripts/test-unicode-bidi.py --compiler build/compiler-next
nice -n 19 python3 scripts/test-unicode-linebreak.py --compiler build/compiler-next
nice -n 19 python3 scripts/test-ui-bidi.py --compiler build/compiler-next
nice -n 19 python3 scripts/test-ui-linebreak.py --compiler build/compiler-next
nice -n 19 build/compiler-next tests/ui/wrap-editor.flex -o build/migration/wrap-editor
build/migration/wrap-editor
nice -n 19 python3 scripts/test-native-carets.py --compiler build/compiler-next
nice -n 19 build/compiler-next tests/ui/grapheme-editor.flex -o build/migration/grapheme-editor
env -u DISPLAY -u WAYLAND_DISPLAY SDL_VIDEODRIVER=dummy \
  nice -n 19 build/migration/grapheme-editor
nice -n 19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/wayland-ime --text-fixture build/migration/grapheme-editor \
  --collie build/native-candidate/collie --benchmark build/migration/native-input/ui-benchmark \
  --package-root build/migration/ime-lab/root --scale 2000 \
  --out build/migration/grapheme-native-2x
```

The optional `--text-fixture` and `--benchmark` clients run inside the same private
session and are stopped before it is removed. Noto Core/CJK/Color Emoji fonts are
explicit CPU CI test dependencies. GDEF test fonts are derived only under ignored
build output using an independent SFNT writer; no font assets are added to the
application. The library includes the Unicode license, and the Flexscript
desktop builder copies it to `licenses/Unicode.txt`; that resource-only change
was checked against an unchanged application binary hash. [Unicode library details](../libs/unicode/README.md).

The initial compact 2x smoke replay assumed the wide sidebar's settings key and
failed before reaching settings. It now selects the actual compact header key,
types into the conversation search after Ctrl+B, and verifies return to chat
preserves the draft. Per-run data directories avoid restoring earlier test
navigation. The original failures remain in `grapheme-native-2x*` logs alongside
the passing `*-verified` runs; they were fixture assumptions, not ignored app
failures. Existing frozen SDL binaries/data remain preserved. Any refreshed
paired baseline must retain source/fixture hashes and equivalent visible content;
these correctness timings do not establish a performance result.

The paired performance harness explicitly selects each backend, records source
hashes including untracked modules, retains per-run paired ratios and estimates
run-level bootstrap intervals. It now checks the required count of individually
improved workloads. The native paired performance run is still outstanding.

Hardware: NVIDIA RTX 2070, driver 615.78.08, Intel i7-8700K. GL reports
`NVIDIA GeForce RTX 2070/PCIe/SSE2`. The private compositor uses presentation
clock `CLOCK_MONOTONIC_RAW`. Never open test windows on the user's desktop.

## Native service/GUI waits and editor deadlines

The ordinary native Collie loop now uses `gui_wait_sources` to poll service
stdout/stderr, pending stdin writes and a child pidfd together with Wayland and
clipboard descriptors. Native keyboard repeat, animated cursor and clipboard
transfer deadlines remain in that poll. Writable stdin is watched only while
bytes are queued; stderr drains with a bounded per-turn budget and EOF removes
its watch. A missing pidfd falls back to a bounded one-second child-health
check. Frame-limited diagnostic runs retain their existing pacing, and SDL's
ordinary compatibility loop retains its existing 16-ms wait.

`ui_desktop_wait_ms` supplies dirty/density and 500-ms caret deadlines without
periodically waking unfocused, hidden or disabled editors, or a caret hidden by
IME preedit. The main loop includes replay and optional run-duration deadlines.
`--run-ms` and `--dump-loop` permit testing that ordinary loop without the
`--frames` path. These diagnostics count startup work too; they are not the
60-second settled CPU/wakeup/memory acceptance measurement.

A real Pinyin regression exposed an input-only seat: Sway initially advertised
no keyboard while granting `text-input-v3` focus. Native input now normalizes
that focus while no keyboard exists and initializes a newly created GUI record
from already received focus. Keyboard capability removal falls back to an
entered text-input context. The editor resumes/enables on the resulting focus
event. CPU fixtures cover text-input-only enter/leave and preserve keyboard
focus ownership when a keyboard exists.

Evidence from current sources:

- `tests/ui/wait-sources.flex` passes in native IR and direct pipelines under
  SDL dummy: real nonblocking pipe read/write/backpressure/EOF/invalid readiness,
  caller-owned bytes, validation, maximum 10+16-source poll with allocation
  canaries, UI/caret/IME/visibility deadlines and application scheduling rules.
  Both wait-source pipelines and the existing IME editor regression are wired
  into CPU CI; remote CI has not been run.
- `build/migration/wait-verified-125/` and `wait-verified-2x/` pass private Sway
  sessions with real Fcitx Pinyin, the full Collie/service using its ordinary
  event-driven loop, retained Unicode editing, nine window-size/lifecycle steps,
  four 24-sample renderer correctness workloads and wide/compact navigation.
  Captures and process maps exclude SDL on the native path; editor GL errors are
  zero. The 2x full Collie Chinese draft capture was visually inspected.
- `tests/ui/wayland-wait.flex` and its independent Python producer verify delayed
  FD readability, blocked-writer recovery, real Escape delivery, EOF/hangup and
  invalid-descriptor wakeup on a private compositor. The API does not read the
  byte supplied by the producer. `wait-direct-verified-2x/` passes the direct
  pipeline's native fixture, real Collie Pinyin/replay, and independent service
  termination while the hidden GUI is blocked. Service loss exits with failure
  instead of waiting for the ten-second diagnostic duration. This is a functional
  wakeup check, not latency acceptance.
- Hidden Collie used three iterations/three waits in approximately 1.5 seconds,
  two source wakeups, no zero-time waits and zero presentations at both scales.
  Startup still uploaded 13,787,322 bytes; these totals do not establish zero
  settled GPU work or a comparison with SDL. The real Pinyin run at 1.25x used
  42 iterations over 6.4 seconds. Normal-loop replay retained a Unicode draft
  across settings/account/return with 28 iterations over 2.5 seconds.
- SDL compatibility regressions pass 147 GUI checks, unavailable-display handling,
  92 desktop UI checks, retained selection geometry/visual-cache checks and all
  14 full Collie desktop layout groups (`wait-sdl-layout.log`).
  Initial manual invocations missing required fixture/report arguments failed
  before their checks; the correctly parameterized runs pass.

The failed native sessions `wait-session-r1` through `r4` remain available.
`r1` exposed the input-only focus regression, subsequently fixed. `r2`/`r3`
showed a virtual keyboard appearing only when a key was already held; the
producer now allows capability/keymap delivery before pressing. `r4` confirmed
that wtype's generated F8 map used physical position 1, while this API preserves
physical key codes. The fixture now injects Escape at its matching physical
position. `wait-session-r5` and both complete scale suites pass; no missing key
was waived. One pipe-observation timing is only a functional timeout guard,
not presentation latency evidence.

Reproduce the complete scale suite (use `2000` for the compact case):

```sh
nice -n 19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/wait-ime --text-fixture build/migration/wait-editor \
  --window-fixture build/migration/wait-window \
  --wait-fixture build/migration/wayland-wait \
  --collie build/migration/wait-candidate/collie \
  --benchmark build/migration/wait-benchmark/ui-benchmark \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/wait-verified-125
```

Source/binary hashes and native session diagnostics are recorded in
`build/migration/wait-final-evidence.json`. The host-visible final audit
`wait-host-cleanup.json` checked eight private sessions, including failed attempts:
no test processes, runtime directories or mounts remained. No publication or
system configuration changes were made.

The worker/service process still has its pre-existing idle/active polling.
The GUI change removes the permanent 16-ms native application loop; it does
not claim zero wakeups for the entire process group. Presentation-feedback/frame
pacing integration and paired settled CPU/wakeup/memory measurements remain.

## Native frame pacing and presentation records

The native renderer requests at most one application `wl_surface.frame` callback.
`gui_frame_ready` gates the ordinary Collie loop's draw/present work while input,
service FDs and application deadlines continue to run. Dirty state is retained
while awaiting a frame or a shown/configured surface; it no longer creates a
zero-time wait loop. Hidden ordinary Collie now avoids even its initial paint:
the private 1.5-second diagnostic observed four iterations, zero presentations
and zero texture uploads. This remains a short functional check, not the required
settled idle comparison. Explicit/frame-limited rendering retains its existing
submission behavior; SDL pacing remains unchanged.

Optional `wp_presentation` v1 support records caller tags, arm/submit/receipt
clock samples, actual compositor presentation timestamps, refresh prediction,
sequence, flags and output identity. Native callers query the compositor's POSIX
clock and use it for the entire latency interval. The 256-byte header lazily
allocates a bounded 40-KiB store: 64 pending and 256 completed 128-byte records.
Pending capacity returns failure, completion overflow increments a visible lost
counter, and hide/disable/global removal cancel observations. Cancelled does not
mean discarded or invisible. Seconds/sequence high words are retained; timestamp
range failures return an explicit status. The optional protocol is not required
for ordinary native rendering, and telemetry is disabled by default. SDL feedback
is still unsupported; this is not a matched backend latency result.

A failed EGL swap now clears a newly created frame callback and its associated
measurement. `gui_present` propagates the renderer error; Collie stops its loop,
reports the error and performs its bounded service/resource shutdown. A close
request skips further rendering. This prevents pacing from leaving the application
waiting forever on a frame that was never submitted.

Evidence and reproduction:

- Pinned licensed presentation-time XML is added to the existing 1.49 manifest.
  The Flexscript scanner regenerates all **24** interfaces exactly; independent
  `wayland-scanner` C metadata/public ABI comparisons pass. No scanner/C shim is
  used by the application.
- `tests/ui/presentation-state.flex` passes native IR/direct CPU tests for high
  seconds words, signed-nanosecond limits, invalid timestamps, 64 pending and 256
  completed limits, tag ownership, cancellation, queue wrap/overflow and cleanup.
  Both pipelines are wired into CPU CI. Remote CI remains unrun.
- `presentation-final-125/` and `presentation-final-2x/` verify current-source
  real Pinyin/editor/full Collie, window sizing, FD waits, service loss and all four 24-sample correctness workloads
  on private NVIDIA/Sway. The ordinary app uses frame/FD/deadline scheduling.
- `scripts/test-wayland-presentation.py` compares **24** library records against
  independent raw Wayland events: timestamps, refresh, sequence, flags, output
  identity and request order match. There is one application frame callback
  outstanding at a time. The 25th submission is cancelled on hide; a separately
  armed tag is also cancelled. The direct compiler fixture passes in
  `presentation-final-2x/`; both final scale suites exercise driver failure.
- `presentation-fd-current/` also passes a freshly rebuilt direct-pipeline
  joint-FD fixture against the final callback code, alongside raw presentation
  checks and the driver-failure fixture. This refresh avoids relying only on
  the preserved FD binaries from the preceding wait milestone.
- A separate fixture gives the actual EGL driver a null display parameter and
  restores the valid display before cleanup. It receives `EGL_BAD_DISPLAY`,
  reports failure, counts no presentation, leaves the frame ready, and cancels the
  pending measurement. This tests an API failure, without inducing a GPU fault.
- The benchmark's opt-in `native_feedback` mode waits for frame readiness and
  records one compositor outcome per measured update. `--benchmark-feedback` in
  the private session wrapper enables it for all four correctness workloads.
  All 24 updates per workload received presentation feedback without discards
  in the passing runs. The interval starts before normalized input/update
  dispatch; it is not physical input latency. Swap-return timing remains separate.
  Cold/warm first-useful-presentation instrumentation and SDL feedback remain.

- `presentation-window-regression/` passes the independent Weston lifecycle
  observer at 1x IR and 2x direct: 20 rapid remaps, fixed/resizable/maximize/
  fullscreen/minimize/restore, close/disconnect, retained pixels and 12 reopens
  with a constant FD count of six. This covers the newly added frame callback's
  lifecycle; it is not a long-running resource soak.
- SDL compatibility still passes 147 GUI checks, 92 desktop UI checks, the IME
  editor regression and all 14 full Collie layout groups in
  `presentation-sdl-layout.log`. Native IR/direct wait tests also verify that
  SDL returns its explicit unsupported-feedback result.
- The current 2x full Collie Chinese draft capture was visually inspected.
  Source/binary hashes and final host-visible cleanup audit are recorded in
  `presentation-final-evidence.json` and `presentation-host-cleanup.json` under
  `build/migration/`. Work stays uncommitted on `codex/sdl-migration`.

Both tested Sway sessions advertise `CLOCK_MONOTONIC` (1), and presentation flags
are **zero**. Headless timing is neither a hardware timestamp nor physical scanout
proof. These short correctness samples do not establish cadence, p95 latency,
matched CPU speedup, idle, memory or the 1,000-sample performance gates. Original
`presentation-session-r1/` and `presentation-verified-2x/` artifacts are retained;
the first run covered the initial implementation before the swap-failure test.

```sh
nice -n 19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/presentation-ime \
  --text-fixture build/migration/presentation-editor \
  --window-fixture build/migration/presentation-window \
  --presentation-fixture build/migration/wayland-presentation \
  --wait-fixture build/migration/presentation-fd \
  --collie build/migration/presentation-candidate/collie \
  --benchmark build/migration/presentation-benchmark/ui-benchmark \
  --benchmark-feedback --package-root build/migration/ime-lab/root \
  --scale 1250 --out build/migration/presentation-final-125
```

## SDL presentation observer and matched measurements - 2026-10-27

The optional presentation API now also observes one SDL Wayland canvas window.
`libs/gui/backends/wayland/sdl-observer.flex` obtains the borrowed display/surface
through public `SDL_GetWindowWMInfo`, then creates its own registry, presentation
manager, callbacks and event queue. It neither replaces SDL proxy listeners nor
disconnects/destroys SDL's display/surface. Child proxies inherit the private
queue through short-lived wrappers; SDL keeps ownership of its event dispatch.
The registry/manager are reused over window reopens and released before SDL video
teardown. Ordinary SDL drawing/wait behavior is unchanged when observation is off.
Enabling feedback on X11/dummy or an SDL OpenGL API window returns unsupported;
disabling an uninstrumented SDL window is a successful no-op.

Independent checks in `tests/tooling/sdl-wayland.c` verify the installed public
SysWM structure layout and the runtime display/surface pointers. Both compiler
pipelines pass the observer fixture: 24 raw-protocol-matched timestamps, real
keyboard input before/after observer teardown, SDL-pushed events, rejection of a
second active owner, hide cancellation, six reopens, freed sample storage and a
still-live borrowed connection. Final direct-pipeline evidence is in
`build/migration/observer-final-2x/`; the earlier IR run is preserved in
`build/migration/sdl-observer-session-r1/`. The 2x session also verifies native
presentation failure cleanup, real Collie Pinyin, Unicode editing and window
lifecycle. Local SDL checks pass 147 GUI assertions, 92 UI assertions and 14
Collie layout groups. These counts precede the shared layout fix below.

The benchmark now requests compositor feedback on both accelerated backends,
checks the same logical/physical viewport and actual client GPU, includes an
uploaded inline image, and verifies that every scroll/selection sample changes
the rendered state. CPU sampling includes present submission and arena cleanup;
the individual phases and whole-process/thread CPU are retained separately.
`scripts/test-presentation-pair.py` checks matched short correctness runs;
`scripts/benchmark-ui.py --presentation-feedback` records seven alternating
pairs of 160 measured updates per workload and whole-run paired uncertainty.
Diagnostic trace binaries are explicitly rejected as qualification data.

The installed SDL compatibility runtime needs explicit
`SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0` in the private test environment for the
same DPI-aware logical viewport as native. The initial mismatch was rejected
and preserved; neither system configuration nor the product default was changed.
The corrected pre-layout-fix comparison has 8,960 measured updates, with no lost
or discarded outcomes. Its CPU gate **fails**: scrolling median does not improve,
and the median speedup's paired 95% interval does not establish 20% lower CPU.
Raw results, exact configuration and limitations are in
[the paired report](sdl-migration-paired-2026-10-27.md). The earlier timer run
that excluded present/cleanup is preserved but cannot qualify CPU performance.

Profiling then found repeated text-cache invalidation on both backends:
`sidebar-mode-timeline` was measured at 107 logical pixels, placed at 108, and
rebuilt twice per frame. Weighted-row measurement now uses the same cumulative
remainder allocation as placement. `tests/ui/weighted-layout.flex` checks odd/even
widths, exact pixel stability, zero warm texture/text work and real width-change
invalidation. It passes CPU IR/direct and a private native GPU run. In the matched
24-sample checks, warm scrolling/selection now perform **zero** texture creations,
uploads, font measurements and rasterizations on both backends. Evidence:
`build/migration/observer-cache-trace/summary.json` and
`build/migration/observer-weighted-verified/`. Both comparison modes were rebuilt
with this shared fix; it is not credited solely to replacing SDL.

The post-fix full comparison in `build/migration/observer-paired-full-r3/`
passes the local **CPU component**: all four workload medians/p95s improve;
geometric-mean speedups are 1.3441 median and 1.4409 p95. Run-level paired 95%
lower bounds are 1.3159/1.3729, both above the 1.25 target. All 8,960 updates
received presentation feedback. No gate was relaxed; the failed R2 evidence
remains. Native scroll/selection headless presentation p95s are slightly higher,
so latency is not treated as passed from CPU results or the refresh floor.
All 14 full SDL Collie layout groups also pass after the shared fix.

The additional bounded Unicode typing/model-echo fixture passes every edit and
all 2,240 presentation outcomes in `build/migration/observer-typing-r1/`.
Callback-paced dispatch-origin p95 latency is slightly slower on native for
scroll/selection/typing; paired 95% differences are above zero. This **does not
pass latency nonregression**, even though both are near the headless refresh
floor. The paired report records the misses. An additional fixed-arrival mode
preserves scheduled arrivals, dispatch waits and presentation separately using
`gui_presentation_track_at`; CPU IR/direct state tests verify explicit-origin
ownership and rejection of invalid/future origins. Negative/future timestamps
allocate no pending tag. Fixed-arrival measurements remain separate evidence.
Current shared UI regressions also pass 92 UI and 73 text raster assertions,
Markdown/table/scroll/selection checks, plus all 147 GUI assertions.

The additional 23-ms scheduled-arrival comparison in
`build/migration/observer-arrivals-r1/` retains all 6,720 updates across seven
pairs of scroll/selection/typing. It **does not pass latency nonregression**:
selection's paired p95 difference is +0.503 ms (95% +0.145 to +0.955 ms),
scrolling is narrowly slower, and typing is inconclusive. Origins, dispatch
waiting and compositor time are separate; no event is retimed/dropped. This
three-case diagnostic neither replaces the primary CPU aggregate nor proves
physical input/hardware cadence. Current native raw-presentation, actual EGL
failure and direct SDL observer ownership/input checks pass in the same session.
`build/migration/observer-arrivals-final-2x/` additionally passes current-source
full Collie Pinyin, direct Unicode editing and nine window steps, weighted-layout
pixel/cache checks, both presentation observers and matched four-case correctness
at 2x. The Chinese draft and selected Markdown/table captures were visually
inspected. Source/binary/artifact hashes and host-visible cleanup are recorded
in `build/migration/observer-final-evidence.json` and
`build/migration/observer-host-cleanup.json`. No default switch, commit or push
has been made.

## GPU draw diagnostics and known opaque content - 2026-10-27

[The GPU diagnostic report](sdl-migration-gpu-2026-10-27.md) records 11,200
measured updates and 22,400 deferred 64-bit OpenGL query results across five
workloads. IR/direct fixtures agree with an independent C GL oracle, preserve
pixels and verify query/context ownership. This interval ends before present,
may contain CPU feeding gaps and excludes compositor execution. Its forced batch
drains make its CPU/latency values diagnostic; the reporter leaves the CPU gate
unavailable. Complete GPU execution/present acceptance remains open.

The native renderer now advertises opaque surface coverage only after proving
the current backbuffer opaque with a full unclipped clear. Transparent/clipped
clears remove the hint; transparent layers preserve an opaque window destination;
new swap/resize/surface buffers must establish their own opacity. An independent
Weston observer verifies exact committed regions and pixel alpha through six
opacity probes and the existing window lifecycle: 26 checkpoints at 1x IR and
2x direct, balanced temporary region creation/destruction, 20 rapid remaps and
twelve reopens. Evidence: `build/migration/opaque-window-regression-r3/`.

The first opaque-only candidate retains passing aggregate CPU numbers but noisy,
inconclusive arrival latency in `opaque-paired-r1/`. The final renderer also
flushes the Wayland connection immediately after successful EGL swap and cleans
up frame/measurement ownership on fatal connection failure. Final-source matched
measurements are separate in `opaque-flush-paired-r1/`; the prior candidate's
numbers are not substituted for them. Both runs include read-only host run-context
snapshots, without per-frame interruption/frequency attribution.

`opaque-flush-paired-r1/` subsequently misses the median CPU confidence gate:
pooled speedups are 1.2778 median / 1.3545 p95, but the paired median lower bound
is 1.2109. All point estimates improve, which does not establish the required
20% median gain. Scheduled-arrival latency remains inconclusive. These misses
are preserved; earlier passing runs are not substituted for this candidate.

The next native change packs the six 32-bit GL vertex fields into three paired
64-bit writes, replacing repeated bytewise helper calls. Both compiler pipelines
match an independent `struct` byte-layout oracle for 4,120 signed/high-word/random
vertices and retain write guards. The check is wired into CPU CI. Current-source
window/opacity checks pass at 1x IR / 2x direct in `packed-window-regression/`;
full Collie Pinyin, GPU query ownership and presentation checks pass in
`packed-correctness-r1/`. Its 6.4 MB selection framebuffer is byte-identical to
the frozen pre-packing renderer. Its own matched measurements are separate in
`packed-paired-r1/`; correctness is not a speed verdict.

The completed packed run passes the local CPU component: geometric-mean speedups
1.3447 median / 1.3965 p95, with paired lower bounds 1.3293 / 1.3131. All four
point estimates improve. All 8,960 primary and 6,720 scheduled-arrival updates
were presented. **Latency still fails** for scroll/selection: paired p95
differences are +0.631 ms (95% +0.377 to +0.812) and +0.282 ms (+0.027 to +0.604).
Typing is inconclusive. GPU query instrumentation is off in these measurements;
earlier failed/inconclusive runs remain intact. The GPU report records methods,
individual results, uncertainty, retained failures and commands.
Current source/build/raw-evidence hashes are in
`build/migration/gpu-opaque-final-evidence.json`; the host-visible process,
mount and private-runtime audit is in `gpu-opaque-host-cleanup.json`. All private
servers/runtimes from this round are gone. No default change, commit or push has
been made.

The timer fixture exposed an initial native 2x-to-1.25x buffer transition after
first mapping on Sway. Stable-pixel timer checks now warm through it, while the
startup/first-useful-frame requirement remains unqualified. Original failure and
diagnostic artifacts are retained. SDL remains the default; all work is local
and uncommitted.

## Retained renderer state and batching - 2026-10-27

The native renderer now retains its owned program/VAO/VBO/texture-unit bindings,
updates the logical viewport uniform only when needed, and avoids flushing on
unchanged physical clip/size state. Uploads still bind textures explicitly;
target switches still bind framebuffer/physical viewport. Invalid targets are
rejected before mutating ownership. IR/direct pixel and independent driver-state
checks pass (8 fixture draws versus 11 forced flushes), along with the full
Collie/Pinyin, window/opacity and presentation suites. The selected conversation
capture remains byte-identical to the prior packed renderer.

The fresh `render-state-paired-r1/` measurement passes the local CPU gate:
1.3794 median / 1.4717 p95 speedups, paired lower bounds 1.3331 / 1.4369, and
all four workloads improve. All 15,680 measured updates were presented.
**The latency gate still fails**: fixed-arrival scroll regresses (+2.409 ms mean
paired p95, 95% +0.199 to +6.074), selection improves, typing is inconclusive.
The callback-paced selection regression is retained too. The large scroll
outlier remains in the calculation. See
[the renderer-state report](sdl-migration-renderer-state-2026-10-27.md) for full
methods, pixels, per-workload results, limitations and commands. SDL remains
the default; the work is isolated and uncommitted.

## Full Collie settled idle instrumentation - 2026-10-27

Opt-in replay snapshots now delimit settled full-application intervals without
counting startup rendering as idle. They record CPU clocks, render/upload counters,
real focus/caret state, loop activity and native texture/atlas/shape storage.
Independent private-compositor orchestration records the app/service process
tree's RSS/PSS and thread context switches. A separate floating window takes
real focus, while a persistent virtual keyboard keeps the headless seat usable.
Both backends render unchanged text/table/Unicode fixture content at matched
effective resolution. SDL must use the accelerated OpenGL renderer.

The four three-second functional cases pass in `idle-short-r3/`: unfocused cases
draw/upload/present nothing; focused cases present six caret updates with no
texture allocation/upload/rasterization. Initial missing-keyboard/focus fixture
failures remain in `idle-short-r1/` and `idle-short-r2/`. The first long run was
stopped after inspecting its first pair: SDL bitmap emoji were oversized and
changed layout relative to native. Its partial results remain unqualified in
`idle-60s-r1/`; the fixture was not simplified to omit emoji.

The SDL path now chooses a bitmap strike and scales metrics/drawing to the
requested pixels, through a Flexscript-owned font wrapper and temporary public
FreeType probe. Scalable-font metrics and native text sizing stay unchanged.
Independent C metrics and pixel-size checks pass in both compiler pipelines;
the CPU variant is wired into CI. Corrected full Collie/Pinyin, short idle/caret,
matched rendering/presentation checks and inspected captures pass in
`idle-corrected-short-r1/`. See
[the bitmap-size report](sdl-migration-bitmap-2026-10-27.md). Earlier emoji typing
measurements are now identified as unqualified equal-size comparisons; primary
CPU fixtures contain no emoji, but fresh measurements against the corrected
baseline remain necessary.

The corrected seven-pair 60-second run finished all **28 intervals** under
`idle-corrected-60s-r1/`, with normal private-compositor shutdown. The unfocused
pairs pass zero render/upload/present and unchanged native draw-batch/cache
checks. Median UI CPU per 60 seconds is 167.178 ms SDL / 0.156 ms native, with
3,708 / 1 event-loop iterations. Every caret interval presents exactly 120 times,
without allocation/upload/rasterization; median UI CPU is 331.140 / 119.489 ms,
with 3,700 / 241 loop iterations. Paired uncertainty favors native CPU/context
switches in both cases. Warm RSS medians are 1.5% / 0.7% higher native for the two
cases, with no individual paired increase above 2.6%; PSS is lower. All raw runs,
sampled peaks and frozen original app/orchestration source files are retained.
Context switches/loop counts are wake proxies, so kernel
wake tracing and active memory/lifetime soak remain open. See
[the idle report](sdl-migration-idle-2026-10-27.md) for the method and limits.

## Draw/present GPU diagnostic preparation - 2026-10-27

While the corrected idle measurement runs serially, separate test-only sources
now prepare four GPU markers spanning update/draw and the successful present
API. The helper retains partial availability results, validates phase order and
uses an explicit final `glFlush` without blocking result reads or `glFinish`.
The benchmark/reporters expose separate draw/present/client/gap intervals and
continue to disable CPU/latency qualification under query instrumentation.
The independent-query/pixel/ownership fixture now passes IR/direct on both
backends, after the idle process ended. Five short GPU phase scenes and the four
normal scenes pass. The seven-pair diagnostic profile finished all 11,200 updates
with 44,800 timestamp reads, without concurrent builds/tests. The present-call
timeline medians for scroll/selection are about 0.306 ms on both backends;
complete-client p95 remains slightly higher native. Query/flush instrumentation
keeps CPU/latency qualification unavailable, and its different scheduling does
not erase the earlier uninstrumented failure. A controlled query-free submission
experiment remains appropriate. Saved SDL/native protocol traces also associate every
presented fixture record with a distinct non-null-buffer commit; an empty-commit
negative control fails as intended, and this check is wired into both live
presentation scripts, which now pass live too, alongside real EGL failure cleanup.
The private compositor stopped normally. Exact idle sources were frozen before orchestration edits.
See [the GPU-present checks](sdl-migration-gpu-present-2026-10-27.md).

## Query-free submission control - 2026-10-27

The extra post-swap/post-Wayland-flush GL submission hypothesis was tested as a
single renderer delta. Full Collie/Pinyin, IR/direct renderer pixels/state,
Weston lifecycle/opacity and presentation/failure checks pass, with byte-identical
selection captures. A new native A/B tool then ran seven alternating pairs of
160 updates for scroll, selection and Unicode typing, with query instrumentation
off, fixed 23 ms arrivals, matched resolution/fonts/GPU and boundary host context.
All 6,720 updates were presented and the long selection pair is byte-identical.

The control **rejects the change**: scroll p95 difference is inconclusive
(-0.132 ms, 95% -0.344 to +0.023), while selection regresses +0.759 ms
(+0.559 to +1.004) and typing +0.555 ms (+0.344 to +0.826). Both regressions occur
in every pair. The exact pre-experiment renderer was restored after verifying
the isolated delta and snapshot hash. Experimental source/binaries and all raw
results remain preserved; the controlled comparison tool stays available.
No default switch or SDL qualification claim was made from the rejected variant.
See [the submission control](sdl-migration-submission-2026-10-27.md).

## EGL context control and clear compatibility - 2026-10-27

An independent EGL inspector/oracle now records the actual current buffer and
context settings, verifies ownership and unchanged pixels, and runs on both
backends/compiler pipelines. Native uses RGBA8/depth0/GL3.3, while the SDL
OpenGL baseline uses RGB8/alpha0/depth24/GL4.6 on this driver. These measured
differences do not establish a performance cause.

A preferred-4.6 candidate passed correctness and actual unsupported-version
fallback/error checks. The controlled native comparison enforces actual context
versions and matching buffer settings; its flattened sources differ in exactly
the request version. All 6,720 query-free updates present without discards and
selection pixels agree exactly. Paired scroll/selection/typing p95 intervals all
overlap zero; no benefit was established. The preference and its constructor were
removed, restoring the exact prior renderer before the subsequent clear fix.
Experimental sources, binaries and raw results remain preserved. See
[the context control](sdl-migration-context-2026-10-27.md).

The public native clear calls previously honored clipping, unlike SDL's
whole-target clear. A new fixture passes SDL but fails native before the fix.
Public `gui_clear`/`gui_texture_clear` now clear the full target, temporarily
disabling scissor while preserving it for subsequent draws. Raw renderer clipped
clears retain their behavior. Six pixel cases pass IR/direct × both backends
with exact capture equality, including empty clips, custom logical viewports,
queued draws and transparent layers. Native state/batching, raw clipped-opacity,
window lifecycle, EGL metadata and presentation/failure checks also pass.

The rebuilt complete Collie/service passes real Pinyin and candidate-popup tests;
matched four-scene correctness passes. A fresh seven-pair query-free primary CPU
and fixed-arrival latency comparison completed in `clear-qualification-r1/`
against the corrected bitmap-text baseline: 15,680 measured updates, zero
discards. The current CPU component passes, all four workloads improving, with
1.343× median / 1.350× p95 pooled geometric-mean speedups and whole-run lower
95% bounds 1.261× / 1.340×. Arrival latency remains inconclusive; a large SDL
scroll-pair asymmetry is retained without exclusion or causal attribution.
Callback-paced scrolling still regresses +0.602 ms (95% +0.107 to +1.189).
Streaming/navigation CPU p95 also exceeds half a nominal 60 Hz interval; actual
hardware cadence is unverified. The clear fix is retained for correctness, with
all performance/default gates unchanged. See
[the clear compatibility report](sdl-migration-clear-2026-10-27.md).

## Same-pass measurement candidate - 2026-10-27

The next candidate removes repeated subtree measurement at identical widths
within an arrange pass. A bounded 32 KiB table is invalidated by each new pass;
descendant reflow invalidates previously measured ancestors. No geometry result
is retained across application updates/draws. The change applies to both backends.
IR/direct dummy checks and 80 private GPU comparisons against forced full
traversal pass, including exact geometry/pixels, edits, images, reflow, rollover
and close/reopen cleanup. Removing ancestor invalidation in a negative control
is correctly rejected. Full native Collie/Pinyin and matched UI scenes pass.

The native-only performance control compares otherwise identical sources
with reuse off/on across all five workloads, enforcing actual GL3.3, matching EGL
buffers and fewer measurement operations. Initial scrolling counts fall from
301 to 130 per update. All 11,200 controlled updates present without discards;
selection pixels are byte-identical. Paired CPU median gains are about 23% for
scroll, 22% for selection, 4% for stream, 1% for navigation and 5% for typing.
Stream establishes the required benefit for proceeding, and scroll presentation
p95 improves in every pair (-0.582 ms, 95% -0.895 to -0.332). Navigation p95
remains uncertain, including a retained 24.925 ms candidate spike. No confident
CPU/presentation regression is established elsewhere in this control. The full
SDL comparison completed separately in `measure-qualification-r1/`: all 15,680
updates present without discards. The new candidate passes its own CPU component,
with 1.427× median / 1.634× p95 pooled geometric-mean speedups (about 30% / 39%
less CPU), all four cases improving, and paired 95% lower bounds 1.371× / 1.520×.
The fixed-arrival interactive intervals still permit regression. Callback-paced
scroll/selection regress +0.155/+0.153 ms, positive in every pair, with 95%
intervals +0.054..+0.237 / +0.069..+0.235. Native streaming CPU p95 remains
8.746 ms, above half a nominal 60 Hz interval. The optimization is retained;
the migration/default gates remain open. Shared state/patch phases still take
about 2.33/2.51 ms for stream/navigation, and repeated JSON serialization/parsing
in ownership transfer/compaction is a next profiling target. See
[the measurement experiment](sdl-migration-measurement-2026-10-27.md).

## Direct ownership-copy candidate - 2026-10-27

The next candidate replaces repeated JSON serialization/parsing during packet
ownership transfer, model/image compaction and returned events with direct
Flexscript copies into the destination arena. The new `j_copy` owns nodes,
vectors, pairs, keys and text, keeps field order/exact metadata, validates limits
and does not modify parser state. Compaction still releases the prior model
arena every update; no deferred collection or larger retention budget is added.

IR/direct JSON tests pass independent Python value checks, source mutation/free,
signed extremes, exact metadata, maximum collections/depth, growth and seven
negative cases. Borrowed-text and borrowed-key negative controls are rejected.
IR/direct × SDL/native model tests pass 60 retained-state/geometry/pixel
comparisons, 1,600 compaction updates and caller-arena release checks, with stable
1 MiB fixture arenas. Full native Collie/Pinyin and matched UI scenes pass too.
The otherwise identical native round-trip/direct-copy control completes in
`direct-copy-control-r1/`: all 11,200 updates presented, no discards, unchanged
layout measurement counts and identical selection pixels. Paired median CPU
speedups are 1.350× stream, 1.497× navigation and 1.548× typing; their 95% lower
bounds exceed one. Mean paired presentation-p95 differences improve -1.408,
-3.084 and -3.036 ms with negative 95% intervals. No confident regression is
established in the other cases. This justifies fresh full SDL qualification in
`direct-copy-qualification-r1/`. That comparison completes 15,680 measured updates
without discards, with full native Collie/Pinyin and matched UI correctness
passing first. The new CPU component passes: 1.448× median / 1.608× p95 pooled
geometric-mean speedups (about 31% / 38% less CPU), all four cases improving and
paired 95% lower bounds 1.407× / 1.543×. The direct copy is retained.

Latency remains failed: fixed-arrival typing regresses in all seven pairs,
+1.243 ms (95% +0.775 to +1.926), about 14.2% pooled p95 slower native. Fixed
scroll/selection remain uncertain, and callback-paced selection regresses
+0.314 ms (+0.069 to +0.559). Native stream CPU p95/p99 is 8.395/10.968 ms, so
the nominal 60 Hz half-interval target remains narrowly missed too. A next input
lead is unconditional editor-event emission for empty IME acknowledgements;
tracing is needed before assigning cause or changing semantics. Unchanged
surrounding/rectangle state is already coalesced, and IME must remain enabled.
See [the ownership-copy experiment](sdl-migration-copy-2026-10-27.md).

## Current acceptance, 2026-10-27

The user accepted speed and requested correctness completion. The final
correctness report supersedes the earlier default-switch gates in this journal:
[correctness acceptance](sdl-migration-correctness-2026-10-27.md). The historical
measurements above remain unchanged, including latency misses and their evidence
limits. Native Wayland is now Collie's automatic choice in Wayland sessions;
explicit SDL selection and X11 compatibility remain available. The generic GUI
library's default is unchanged for other applications.

An empty IME transaction previously cancelled unrelated pending paste and
invalidated editor state. The editor now ignores an empty transaction when it
has no active preedit, while retaining protocol serial handling, explicit
cancellation, preedit clearing, commit/delete and invalid-payload handling.
The reproducer failed before the change and passes in IR/direct builds. Both
pipelines are added to the existing CI job; remote CI has not run.

Fresh final checks cover real Fcitx Pinyin in full Collie, automatic/explicit
backend selection, 93 shared desktop UI checks in each pipeline, Markdown tables,
scrollbars, 80 resource-teardown cycles, lifecycle transitions, cursor/input
recovery and independent clipboard peers. See the report for exact artifacts,
reproduction and limits. All work remains isolated and uncommitted.

## Platform coverage and follow-up

The delivered scope is Linux x86-64 Collie with one native Wayland application
window, EGL window and pbuffer surfaces, OpenGL 3.3, direct font adapters and
native clipboard/input. Private GPU compositors on this NVIDIA host provide the
functional evidence. This is not physical-device, physical mixed-monitor or
hardware scanout proof. Wider GPU/driver/input-method coverage, full
Script_Extensions tailoring, a long-duration ownership soak and GPU CI remain
follow-up qualification. Relative pointer mode and the generic externally owned
GL-context API stay on SDL, as do X11 clients. These limitations are explicit;
there is no silent fallback when native initialization fails.

Maximum atlas allocation is four 1024-square RGBA pages (16 MiB); R8 pages use
one quarter that space. Metadata has 1024 bounded entries. Shaping retains at
most 2 MiB plus one bounded transient oversized run and a fixed 256-entry table.
No performance improvement is claimed from the smoke timings.
