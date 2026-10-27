# Bitmap font sizes and a fair SDL baseline - 2026-10-27

Visual inspection of the first full-Collie idle pair found giant SDL emoji,
while native emoji respected the requested text size. The table/header/sidebar
geometry consequently differed. The initial long run was stopped and retained
as unqualified evidence in `build/migration/idle-60s-r1/idle/quality-audit.json`.
The emoji workload remains present.

## Cause and Flexscript correction

For non-scalable faces, SDL_ttf 2.24.0 interprets the opening point-size argument
as a **bitmap strike index**. It clamps the supplied value to the available
strikes and returns metrics/raster data at that strike's size. On the test
machine, Noto Color Emoji has one 109-pixel strike. The application had treated
these metrics and pixels as the requested size, producing oversized emoji.
See the public implementation of
[SDL_ttf size selection](https://github.com/libsdl-org/SDL_ttf/blob/release-2.24.0/SDL_ttf.c#L1765-L1795).

`libs/gui/text/bitmap-size.flex` now probes the requested face through public
FreeType APIs/structures. It chooses the closest bitmap strike and records its
actual raster size. Temporary face, FreeType library and dynamic-library
ownership are released before returning; no second font cache remains live.
The GUI's opaque SDL font handle owns a 40-byte wrapper containing its TTF font
and scaling metadata. Fontconfig face indices are passed to both the probe and
`TTF_OpenFontIndex`, including collection/named-face indices returned by matching.

The SDL path scales width, height and ascent consistently to the requested pixel
size. Bitmap text textures use linear filtering and destination scaling;
scalable fonts keep their existing metrics/raster size. The wrapper and TTF font
are released together. This is all Flexscript implementation. FreeType is
already an SDL_ttf dependency; the probe adds no persistent additional font
engine/cache. No private TTF_Font layout is accessed. Native text sizing is
unchanged.

## Independent verification

`tests/ui/font-sizing.flex` tests scalable text and bitmap emoji at **12, 20, 32,
64 and 109 pixels**, checks public metrics/coverage/empty text, and reads rendered
pixels to reject blank, clipped or strike-sized glyphs. It also tests invalid
paths and repeatedly opens/closes fallback fonts. A test-only C oracle computes
bitmap metrics directly from FreeType, checks native scalable metrics through
FreeType/HarfBuzz, and checks unchanged SDL scalable behavior through public
SDL_ttf calls. Its SDL calls use the already-loaded library only in the SDL case;
the native fixture must not load SDL, even through the oracle.

`scripts/test-font-sizing.py` runs both IR/direct binaries and encodes the raw
captures. The CPU CI workflow runs its SDL dummy-driver correctness variant;
that variant is not a GPU/performance result. CPU checks pass in
`build/migration/font-sizing-cpu-r2/`. The preliminary GPU matrix in
`idle-corrected-short-r1/font-sizing/` passes both pipelines/backends, with
preserved oracle/fixture/orchestration source copies. The subsequent oracle
version avoids linking SDL into native fixture processes. Its current GPU matrix
passes all four pipeline/backend combinations before the corrected long idle
measurement in `idle-corrected-60s-r1/font-sizing/`, including both native
no-SDL-map assertions. Bitmap height/ascent/advance values agree across both
backends at every tested size (for example, 20 requested pixels gives 24/19/25).

Full corrected Collie/Pinyin and all four short idle/caret cases pass in
`idle-corrected-short-r1/`, followed by the four matched rendering/presentation
scenes. Its first-pair captures were inspected: SDL emoji are now normal-sized,
and the table layout closely matches native. Native and SDL glyph pixels need
not be identical because their rasterization/rounding paths differ; requested
sizes and independent metrics are tested explicitly.

## Effect on earlier performance claims

Frozen earlier measurements remain historical results for their exact binaries.
The four primary CPU workload fixtures contain no emoji, so this particular
size mismatch was absent from those scenes. **Earlier Unicode typing numbers
do include emoji and must not be used as qualified equal-size comparisons.**
They are retained, with this quality limitation now identified. The existing
scroll-latency regression is still an open failure. Fresh CPU/latency qualification
against the corrected baseline remains required; this sizing fix does not
qualify the migration or imply a speedup. SDL remains default. Work is local and
uncommitted.
