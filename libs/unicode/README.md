# Unicode text layout

`import "unicode";` or `import "../libs/unicode.flex";` supplies strict UTF-8
decoding, Unicode 17.0.0 **extended grapheme clusters**, the **bidirectional
algorithm** and default **line-break opportunities** in Flexscript. There
is no external Unicode runtime or runtime data-file dependency.

`unicode_grapheme_scan(text,bytes,out,capacity)` writes 64-bit UTF-8 byte offsets
including the start and end, and returns their count. For empty input the single
offset is 0. Pass `out=0` to count first. Lengths are explicit, so U+0000 works.
Invalid UTF-8, text larger than 1 MiB and short output buffers return 0 with a
static explanation in `unicode_error`. This scan does not allocate.

`unicode_graphemes(text,bytes)` allocates an owned map, released by
`unicode_graphemes_free(map)`. Header words contain the boundary count and input
byte length; offsets begin at byte 32. Navigation helpers
`unicode_grapheme_next(map,offset)` and `unicode_grapheme_previous(map,offset)`
move by user-perceived characters, including combining marks, flags, emoji ZWJ
families, Hangul and Indic conjuncts. `unicode_grapheme_lower` finds a boundary
index. These operations do not reshape text or allocate.

`unicode_utf8_read(text,bytes,offset)` returns `(scalar<<3)|byte_count` or -1 for
an invalid/truncated sequence. It rejects overlong encodings, surrogate scalar
values and values beyond U+10FFFF.

The implementation follows [UAX #29 revision 47](https://www.unicode.org/reports/tr29/tr29-47.html).
The [Unicode License V3](LICENSE.txt) is included with this library.
Property inputs, licenses, URLs and SHA-256 hashes are pinned in
`tests/tooling/unicode/17.0.0/`. The pure Flexscript generator emits 828 packed
immutable property ranges (8,280 data bytes); Hangul syllable properties are
computed directly. No generated C or Python application code is involved.

```sh
build/compiler-next scripts/unicode-properties.flex -o build/unicode-properties
build/unicode-properties tests/tooling/unicode/17.0.0 libs/unicode/properties.flex
nice -n 19 python3 scripts/test-unicode.py --compiler build/compiler-next
```

The tests verify exact regeneration, all 1,114,112 property values against an
independent data parser, and all 766 official grapheme test cases plus six
additional cases under both native compiler pipelines. They also check malformed
UTF-8, capacity bounds, navigation and owned cleanup.

## Paragraph bidirectional layout

`unicode_bidi(text,bytes,mode)` implements P1–I2 of
[UAX #9 revision 51](https://www.unicode.org/reports/tr9/tr9-51.html), including
embeddings, overrides, isolates/FSI, depth overflow, isolating run sequences,
weak/neutral resolution and paired brackets with canonical equivalents.
Modes are `0` LTR, `1` RTL, `2` first-strong/default LTR and `3`
first-strong/default RTL. The input can contain multiple paragraphs: each B
separator terminates its paragraph. A higher-level UI may treat CRLF as one
displayed newline. The returned map owns scalar values and byte offsets; release
it with `unicode_bidi_free(map)`. The source string is no longer borrowed.

`unicode_bidi_level(map,index)` returns a scalar's paragraph embedding level,
or `-1` for an X9-removed control or invalid index.
`unicode_bidi_offset(map,index)` translates a scalar index to a UTF-8 byte
offset, including the end; `unicode_bidi_index(map,byte)` finds the first scalar
starting at/after that byte offset. Invalid lookup bounds return `-1`.
Byte offsets inside a scalar round forward; editing should use grapheme stops.

After shaping and wrapping, call
`unicode_bidi_line(map,first,end,levels,order,capacity)` on a single line, using
scalar indices `[first,end)`. The caller owns `end-first` **bytes** for L1-adjusted
levels and `end-first` **64-bit words** for L2 visual scalar indices. X9 controls
have level 255 and are omitted from the order. The result is the order count,
or `-1` for invalid line/output bounds. Paragraph levels are immutable, so a
different wrap can reuse the same map. Lines may not cross a paragraph boundary.
An empty line returns 0 and allows null output pointers.

Do not reverse a string and shape it as a new string. Shape logical same-level,
same-script/font runs in the resolved direction, then position those runs in
visual order. HarfBuzz performs combining-mark positioning and mirrored glyph
selection (L3/L4). `unicode_bidi_mirror(cp)` supplies the Unicode scalar mirror
mapping for renderers that need it; do not also apply it before HarfBuzz shaping.
`unicode_bidi_class(cp)` and `unicode_bidi_bracket(cp)` expose the pinned
properties. A bracket result is `(paired_scalar<<2)|kind`, where opening is 1,
closing is 2 and a non-bracket is 0.

The result header is 64 bytes followed by 32 bytes per scalar. Header words are
scalar count, UTF-8 byte length, allocation length and first paragraph base.
Records contain scalar0, byte offset8, original class16, working class17,
explicit level18, resolved level19, paragraph base20, FSI direction/known21/22,
and matching isolate/PDI index24. Class numbers are documented in `bidi.flex`;
callers should prefer the lookup functions over internal record offsets.
Input is limited to 1 MiB / 262,144 scalars. Temporary resolution storage is
`4096+64*scalars` bytes and is freed before returning; there are no persistent
global maps/caches. The implementation does not call a Unicode runtime.
The generated bidi data is 763 class ranges, 128 brackets and 428 mirror
mappings: **11,443 packed data bytes**.

```sh
build/compiler-next scripts/unicode-bidi-properties.flex -o build/unicode-bidi-properties
build/unicode-bidi-properties tests/tooling/unicode/17.0.0 libs/unicode/bidi-properties.flex
nice -n 19 python3 scripts/test-unicode-bidi.py --compiler build/compiler-next
nice -n 19 python3 scripts/test-ui-bidi.py --compiler build/compiler-next
```

Both compiler pipelines pass all 770,241 BidiTest direction variants and 91,707
BidiCharacterTest cases (**861,948 total**). Independent property parsing checks
every Unicode codepoint's class, bracket and scalar mirror. Additional tests
cover paragraphs, wrapped-line resets/reuse, trailing isolates, embedded NUL,
invalid UTF-8, empty/auto-RTL text and output capacity. Retained native layout is
checked against official expected levels/order for 336 paragraphs, including
styled and wrapped variants, plus separator cases (1,020 layouts per pipeline).

## Default Unicode line-break opportunities

`unicode_linebreaks(text,bytes)` implements the default LB1–LB31 rules of
[UAX #14 revision 55](https://www.unicode.org/reports/tr14/tr14-55.html), including
mandatory/CRLF breaks, nonbreaking spaces and word joiners, combining sequences,
contextual quotes, numeric punctuation, Hangul, Brahmic orthographic syllables,
regional indicators and emoji modifiers. LB1 uses the recommended default
resolution: AI/SG/XX and non-mark SA become AL, SA Mn/Mc become CM, and CJ becomes
NS. Locale dictionaries and automatic hyphenation are not included.

`unicode_line_break(map,byte)` returns **0** for a prohibited position (including
interior UTF-8 bytes), **1** for a soft opportunity, **2** for a mandatory break,
or **-1** for an invalid offset. End-of-text is mandatory, including empty text.
Release the owned result with `unicode_linebreaks_free(map)`; it does not borrow
the input. The 32-byte header contains input byte length, allocation length and
opportunity count. The byte-addressable masks start at offset 32. Input limits
are 1 MiB / 262,144 scalars. Temporary storage is `32+32*scalars` bytes and is
freed before returning. `unicode_line_property(cp)` exposes packed raw class
and supporting East Asian Width, general category and emoji flags, documented
in `linebreak.flex` / `line-properties.flex`.

The pure Flexscript generator emits 2,497 immutable ranges (**24,970 data bytes**)
and computes Hangul H2/H3 directly. It reads the canonical derived table with
reserved-codepoint defaults. An independent test parser uses the contributory
LineBreak.txt instead, and checks every Unicode codepoint's packed properties.
Both compiler pipelines pass all **19,338** official LineBreakTest cases plus
four additional cases and checks of mandatory/soft kinds, UTF-8 and bounds.

```sh
build/compiler-next scripts/unicode-line-properties.flex -o build/unicode-line-properties
build/unicode-line-properties tests/tooling/unicode/17.0.0 libs/unicode/line-properties.flex
nice -n 19 python3 scripts/test-unicode-linebreak.py --compiler build/compiler-next
```

These are opportunities, not positioned lines. A layout engine must select them
according to actual shaped widths and handle whitespace/discretionary glyphs.
The default algorithm can allow breaks inside some extended grapheme clusters
(for example SPACE + combining mark); the retained UI should apply the grapheme
tailoring described in UAX #14 section 8.2 example 6, preserving mandatory breaks.
The native retained desktop wrapper now uses this map across rich/font runs.
It filters soft opportunities at extended grapheme boundaries and uses emergency
grapheme breaks for an overwide unbreakable span. Actual shaped slices determine
fit; selected soft hyphens display a hyphen, while copy retains U+00AD. Hanging
trailing spaces keep source ranges with collapsed display geometry. SDL retains
its compatibility wrapper. See [desktop text behavior](../../docs/ui.md).
Word/sentence segmentation remains separate.
