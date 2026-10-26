# Collie image pipeline benchmark

Measured on 2026-10-26, Linux x86-64, Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz.
Compiler SHA-256: `94fafb1a9c9e2a8a9472bb1297192c8e76ae64186fd1d4981dca80df322bf5c5`.

The complete preview pipeline has a **1.86x geometric mean speedup**
over installed GDK Pixbuf 2.44.8 across 8 matched successful previews.
The large PNG case is effectively a tie; these results do not establish a
universal speedup. PNG decoding and small identity copies still lose cases.

| Input | Flexscript preview ms | GDK preview ms | Preview speedup | Resize speedup | Decode speedup |
| --- | ---: | ---: | ---: | ---: | ---: |
| procedural texture PNG | 123.04 | 123.68 | 1.01x | 2.82x | 0.74x |
| procedural texture JPG | 33.61 | 89.82 | 2.67x | 3.02x | 1.95x |
| procedural texture WEBP | 92.70 | 216.91 | 2.34x | 2.96x | 2.22x |
| procedural desktop RGBA PNG | 33.95 | 54.86 | 1.62x | 2.32x | 0.55x |
| portrait JPEG / EXIF 6 | 78.03 | 134.40 | 1.72x | 2.87x | 1.99x |
| small transparent PNG | 7.29 | 14.17 | 1.94x | 0.56x | 0.74x |
| small JPEG | 2.73 | 9.10 | 3.33x | 0.84x | 3.59x |
| Collie logo PNG | 27.97 | 34.96 | 1.25x | 2.02x | 0.65x |

Ratios greater than 1 favor Flexscript. The resize stage includes image
allocation, output RGBA conversion and release. Small inputs already fit the
preview bounds, so their standalone resize stage measures an owned copy,
while the complete preview skips resizing.

## Method

Run `nice -n 19 python3 scripts/benchmark-image.py`. The script builds both
backends, uses the same process and bytes, pins execution to one CPU, warms
each path, and alternates backend order across five paired samples of five
operations each. Medians include allocation and release. Disk reads and
fixture generation are outside the timed regions. The GDK comparison is an
optimized C adapter, including an in-memory JPEG encoder instead of the old
application's temporary file write/read/delete cycle.

Both complete paths decode, apply EXIF, fit within 1536 pixels and try JPEG
quality 85/70/50 with a 512-KiB limit. The installed GDK encoder emits
grayscale from RGBA input even in a GDK-only process; the reference explicitly
packs RGB before encoding, preserving colors and counting that conversion.
Matching success and JPEG quality are required for inclusion in the aggregate.

The corpus contains one repository Collie logo and deterministic procedural
textures, desktop text/geometry, transparency, a rotated portrait-shaped
texture, small images and incompressible noise. It is not a representative
photography corpus or a comparison against every possible codec backend.

Both output paths retain colors, orientation, bounds and JPEG quality.
Decoded matched previews differ by at most 1.83 RGB RMSE
(on a 0–255 scale). Filters and codec rounding are not byte-identical to GDK.
Independent unit tests compare filter arithmetic with a premultiplied
floating point model within 2.1 LSB, and require byte identity between
our scalar and accelerated paths.

## Budget boundary and limits

The incompressible 2048x1536 case passes at quality 50 in Flexscript but
exceeds the limit in GDK, because their resize filters produce different
high-frequency output. It is retained in the raw report and excluded from
the speed aggregate. A separate 1536x1536 noise image requires no resize;
both implementations reject it after all three quality attempts.

Flexscript owns buffering, EXIF, filtering and preview policy. PNG/JPEG/WebP
still depend on libpng16, libturbojpeg and libwebp, with libwebpdemux for
animated first frames. This benchmark does not claim handwritten Flexscript
codecs outperform those codec libraries.

All raw samples, fixture hashes, output sizes, quality levels and comparison
metrics are in [benchmark-results.json](benchmark-results.json).
