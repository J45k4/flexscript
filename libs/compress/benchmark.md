# Native Zstd versus C Zstd

Measured 2026-10-19 on AMD Ryzen 9 5900X, Linux x86-64, system C Zstd 1.5.7, one thread pinned to CPU 3. The native codec is Flexscript, including its runtime-emitted SSE2/BMI2 and CPU/OS-gated AVX2 kernels. No C codec, assembler, C++ optimizer or LLVM implements the native path.

Native complete-buffer decoding wins on all three measured log fixtures: **9.8% synthetic, 5.4% varied and 2.9% stress**. Synthetic and varied streaming also win; stress streaming is effectively tied (native 0.3% behind). These small margins are fixture-specific. The complete PuppyLog scan below still favors C, which remains FlexDB’s default. Native encoding continues to win on all five fixtures in this run.

| Corpus | Input MB | C output bytes | Native output bytes | C encode MB/s | Native encode MB/s | C complete decode MB/s | Native complete decode MB/s | Decode speedup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| synthetic text logs | 7.26 | 628,772 | 574,732 | 1141 | 1303 | 3101 | 3404 | 1.098x |
| random bytes | 8.39 | 8,388,810 | 8,388,810 | 8510 | 15598 | 49150 | 51905 | 1.056x |
| repetitive bytes | 8.39 | 1,036 | 1,036 | 15452 | 25467 | 47552 | 53788 | 1.131x |
| PuppyLog varied prefix | 8.39 | 1,331,603 | 1,401,648 | 904 | 921 | 2584 | 2723 | 1.054x |
| PuppyLog stress prefix | 8.39 | 422,536 | 437,357 | 2265 | 2428 | 6884 | 7085 | 1.029x |

Throughput uses decoded input bytes and decimal MB. Each cell is the median of five samples of 60 operations inside one process. Both backends receive equal warmup and committed buffers and reuse their contexts. C uses `ZSTD_compressCCtx` level 1 and `ZSTD_decompressDCtx`. Startup, context construction/code generation, file I/O and full byte verification are outside the timer. Both decoders read **identical C-compressed bytes**. Both streaming outputs and complete native output are checked byte for byte outside timing; C independently checks native-encoded output. No fixture-dependent caching is used. All samples, input/source hashes and compiler/binary hashes are in [benchmark-results.json](benchmark-results.json).

The synthetic native output is 8.6% smaller than C’s; varied/stress outputs are 5.3%/3.5% larger. The PuppyLog inputs are the first 8 MiB of existing synthetic archives, including binary records, properties and timestamps. They are not customer logs or measurements of the complete production dataset.

## Streaming decode and resident memory

Both stream drivers use 64 KiB output chunks. Peak RSS uses 64 KiB input/output buffers, three decodes in each of three fresh processes; the table takes the maximum self-reported `/proc/self/status` `VmHWM`. File cache is excluded, while C’s loaded shared library is included.

| Corpus | C stream MB/s | Native stream MB/s | Stream speedup | C peak MiB | Native peak MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| synthetic text logs | 2864 | 3026 | 1.057x | 3.12 | 2.60 |
| random bytes | 30020 | 28725 | 0.957x | 2.91 | 2.66 |
| repetitive bytes | 28861 | 30038 | 1.041x | 2.91 | 2.49 |
| PuppyLog varied prefix | 2449 | 2539 | 1.037x | 3.14 | 2.60 |
| PuppyLog stress prefix | 6203 | 6183 | 0.997x | 3.11 | 2.59 |

Native still loses random-byte streaming here. Tiny raw/repetitive times and margins around one percent are sensitive to cache, clocks and background work. Decoder fixed scratch is 442,624 bytes plus a 16 KiB RX reservation (11,160 emitted code bytes). Streaming adds the advertised logical history window plus a 128 KiB spare block; complete-buffer decoding allocates no ring. Encoder workspace is 2,424,832 bytes plus the 16 KiB code reservation. These measured fixed-window memory advantages are not a claim about every workload.

## Decoder changes

Four-stream Huffman decoding keeps four reverse-bit reservoirs across batches and completes exact tails inside the native routine. Native Huffman weight decoding and table building replace repeated host loops; tables use replicated 11-bit lookahead and AVX2 builds eight dual-symbol entries together where supported. FSE setup parses only the actual alphabet, spreads byte-sized temporary symbols in groups, and uses precomputed state transforms. Packed sequence entries carry baseline, extra bits, state width and next-state base.

The sequence loop uses a 56–63-bit reservoir cursor, avoids unchanged repeat-offset writes, retains the extra-bit count, and checks a whole sequence’s 64-byte copy margin before changing state. Checked code handles the buffer edge. AVX2 copies have separate normal and long-match variants; BMI2/SSE2 and portable fallbacks remain. Streaming decodes directly into a circular history buffer when space permits and borrows complete input spans only with bounded readable padding. The physical ring’s spare block prevents speculative output stores from corrupting live logical history, including after short blocks and wraps.

All machine code is emitted by Flexscript at context creation. Pages start RW and become RX after bounded short/near branch fixups. Unsupported CPU/OS features or protection/allocation failures retain the portable implementation. The format, API, checksums and entropy-model selection remain ordinary Flexscript. Encoder optimizations from the previous report are retained: fingerprinted hashing, bounded SIMD matching, cached entropy costs, table reuse and native entropy packing.

| Log corpus | Previous native complete MB/s | Current native complete MB/s | Previous native stream MB/s | Current native stream MB/s |
| --- | ---: | ---: | ---: | ---: |
| synthetic text logs | 2592 | 3404 | 2045 | 3026 |
| PuppyLog varied prefix | 1978 | 2723 | 1752 | 2539 |
| PuppyLog stress prefix | 4392 | 7085 | 3602 | 6183 |

These historical results are not interleaved: the previous report used five samples of 15 operations without CPU pinning. The [pre-decoder report](benchmark-before-decoder-optimization.json), [pre-native-kernel report](benchmark-before-native-kernels.json) and [initial report](benchmark-initial.json) preserve their original methods and samples.

## Complete PuppyLog scan

An existing 180-segment FlexDB archive was queried for an absent message. Both paths scanned 5,000,000 rows and decoded 1,363,298,960 bytes, with zero matches. After one warmup per backend, three paired runs alternated order on CPU 3. This includes parsing, CRC checks, reads and decoder creation for each reader.

| Backend | Median query seconds | Peak RSS KiB |
| --- | ---: | ---: |
| C | 1.544 | 3892 |
| native | 1.610 | 3424 |

Native is still **4.3% slower end to end**, despite winning the warmed complete-buffer codec fixtures. Its peak RSS is about 12% lower. This distinction matters: codec throughput does not guarantee a faster query. The rebuilt PuppyLog executable is 495,096 bytes; both backends pass its 10-test application suite. [Scan results and fixture/binary hashes](benchmark-puppylog-5m.json) preserve this comparison.

## Validation and reproduction

```sh
python3 scripts/test-zstd.py
FLEX_ZSTD_ACCELERATION=baseline python3 scripts/test-zstd.py
FLEX_ZSTD_ACCELERATION=0 python3 scripts/test-zstd.py
FLEX_ZSTD_CPU=3 FLEX_ZSTD_SAMPLES=5 FLEX_ZSTD_ROUNDS=60 python3 scripts/benchmark-zstd.py
```

The compatibility suite passes **668 scenarios** in automatic, baseline SSE2/BMI2 and portable modes: both decoding APIs, C levels 1–19, checksums, unknown sizes, concatenated/skippable frames, truncation/mutations, mixed block/table states, context reuse and FlexDB interchange. New streaming cases force small flushes, near-window matches and repeated physical-ring wraps with tiny buffers. Guard-page byte tests, branch-fixup validation and native-call ABI/order tests run as well. The standalone example runs under hardware/reference lowering; its hardware ELF has no interpreter or dynamic dependencies. This is not a security audit.

`FLEX_COMPILER` selects a compiler (default `build/flex`). Benchmark defaults are five samples of 15 operations; `FLEX_ZSTD_SAMPLES` and `FLEX_ZSTD_ROUNDS` override these. `FLEX_ZSTD_CPU` optionally pins the benchmark and its memory drivers to an available logical CPU; omit it for no pinning. This report used CPU 3 and 60 operations. Generated fixtures and drivers are under ignored `build/compress`; PuppyLog prefixes require the sibling checkout.

The comparison executable is 271,672 bytes including its C FFI harness and verification. The dependency-free [standalone example](tests/standalone.flex) compiles to 220,148 bytes including startup and both codecs. Python and the C oracle belong only to development tests/benchmarks, not the native library or application runtime.
