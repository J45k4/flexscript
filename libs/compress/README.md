# Native Flexscript Zstd

A Zstandard-compatible codec written in Flexscript. The codec calls no C
compression functions and needs no Python, Rust, HIP or LLVM at runtime.
Compile importing applications with the ordinary Flexscript compiler.
The initial allocator/free implementation targets native Linux x86-64.

```text
import "libs/compress/zstd.flex";

let encoder = zstd_encoder_open();
let capacity = zstd_compress_bound(input_bytes);
let compressed = alloc(capacity);
let stored = zstd_compress(encoder, compressed, capacity, input, input_bytes);
// stored >= 0; a negative result means zstd_error(encoder) describes failure.
zstd_encoder_close(encoder);

let decoder = zstd_decoder_open(67108864); // maximum permitted history window
let restored = alloc(input_bytes);
let bytes = zstd_decompress(decoder, restored, input_bytes, compressed, stored);
// bytes == input_bytes on success. Inspect zstd_error(decoder) before closing.
zstd_decoder_close(decoder);
```

Always check allocation and operation results before using their output. Input
and output ranges must not overlap. The caller owns input/output allocations;
closing a context releases its own workspace only. A context may be reused
serially; use separate contexts for simultaneous operations.

## Decoder

The streaming decoder supports raw, RLE and compressed blocks; Huffman literals
with one or four streams; FSE predefined, RLE, new and repeated sequence tables;
repeated offsets; frame content sizes; optional XXH64 checksums; concatenated
and skippable frames. It reads frames produced at all tested C Zstd levels
(1 through 19), subject to the configured window limit. Nonzero dictionary IDs
are rejected; external dictionaries are unsupported. This is not an audited
replacement for the mature upstream decoder.

Streaming buffers are three 64-bit words: `{data_pointer, size, position}`.
The function advances the positions and retains partial input/output state:

```text
let decoder = zstd_decoder_open(67108864);
let result = zstd_decode(decoder, output_buffer, input_buffer);
```

| Result | Meaning |
| --- | --- |
| `0` | One frame completed; bytes of the following frame remain unconsumed |
| `1` | Supply more input or output capacity and call again |
| `-1` | Sticky error; inspect `zstd_error(decoder)` |

A decoder can consume a complete compressed block while retaining decoded bytes.
**Drain it even after source EOF** before treating a nonzero hint as truncation.
A caller must reject EOF without a completed frame and reject no-progress stalls.
`zstd_decoder_reset` clears the error and frame state for a new independent
stream. `zstd_decompress` resets the context and decodes complete buffers directly
into the caller's output, using earlier output as history. It avoids allocating
a streaming ring. It decodes all concatenated frames and rejects truncation,
trailing invalid bytes or insufficient output capacity.

Each decoder owns 442,624 bytes (432.25 KiB) of fixed scratch, plus a 16 KiB
executable mapping when acceleration is enabled. Streaming adds the
frame's advertised history window plus one 128 KiB block of spare capacity.
Blocks decode directly into the free portion of the ring when contiguous space
permits; short blocks and wraps preserve the complete logical history. History is a circular buffer, not a full decoded-file
cache. The configured limit is checked before allocating the ring. Window limits
from 1 KiB to 1 GiB are accepted; FlexDB/PuppyLog cap them at 64 MiB. Buffers and
checksums are bounded by the 128 KiB block limit. A streaming consumer can still
receive bytes before a later checksum error; FlexDB separately validates each
stored extent's CRC before exposing any bytes.

## Encoder

The fast encoder uses a 1,024-entry, eight-byte-key hash with cached four-byte
fingerprints, bounded scalar/SIMD match extension,
repeated offsets and an 8 MiB maximum match window. Adaptive Huffman literals
and adaptive/RLE FSE sequence tables are selected when estimated savings cover
their headers; predefined tables and raw literals remain available. It emits
standard Zstd frames that C Zstd decodes. Compatible entropy tables can be reused
between compressed blocks; raw/RLE whole blocks invalidate candidate table state. Whole-block RLE and raw fallback bound
expansion. Skip distances grow on incompressible data to avoid probing every
byte. There is no dictionary training or optimal parse strategy.

`zstd_compress_bound(n)` returns a safe capacity for up to 2,147,483,647 input
bytes, or `-1` for an unsupported size. `zstd_compress` requires at least that
capacity and returns the encoded length or `-1`. It resets prior errors. Context
creation reserves 2,424,832 bytes (2.31 MiB), reused across frames; callers supply
the complete source and destination. Acceleration adds a 16 KiB executable
mapping. Encoding is currently one-shot, not an
incremental streaming interface. The library offers one fast strategy rather
than pretending to implement C Zstd's numbered quality levels.

## CPU acceleration

On native Linux x86-64, contexts automatically try kernels emitted directly by
Flexscript. A CPUID probe requires BMI2; vector copies use baseline SSE2.
AVX2 table building and copies additionally require AVX/XSAVE/OSXSAVE CPU
support and XCR0-enabled XMM/YMM state. Unsupported AVX2 hosts keep the BMI2
path. Four-stream Huffman decoding keeps reverse bit reservoirs across batches;
Huffman tables use replicated 11-bit lookup with one- or two-symbol entries. No
assembler, C compiler, Python, shared codec, HIP or LLVM is used to create or
run these kernels. The allocator writes code into private RW pages, resolves
relative branches, and changes the complete mapping to RX before calling it.
It never requests simultaneous write/execute permission. If allocation,
protection or CPU detection fails, contexts retain their portable implementation.
Reference lowering and other compiler targets also retain the portable bodies.

The emitted kernels cover sequence decoding, four-stream Huffman decoding, Huffman weight/table decoding, FSE
table construction, matching, sequence bit packing, Huffman encoding and literal
histograms. The surrounding format, entropy-model selection and API code remain
ordinary Flexscript. Decoder kernels validate untrusted bounds. Private encoder
kernels use validated workspace sizes; bit packing checks a conservative output
bound once before entering the kernel, with checked fallback when it does not fit.

`zstd_decoder_acceleration(context, mode)` and
`zstd_encoder_acceleration(context, mode)` query with a negative mode, disable
with zero, and attempt to enable with a positive mode. They return 1 if enabled,
0 if disabled/unavailable. Only change an idle encoder or a decoder at a frame
boundary; changing a decoder during a frame returns -1. Disabling does not change
the frame format. Context construction/code generation is excluded from the
warmed throughput benchmark, so short-lived tiny operations may favor C.

## FlexDB and PuppyLog

The system C Zstd backend remains FlexDB's default. Native complete-buffer
decoding is now faster on the three measured log fixtures; streaming margins
are smaller. See the benchmark for the limits of those measurements. To opt into native
compression **and** decompression on an idle connection:

```text
flexdb_blob_options(db, 4096, 1);
flexdb_blob_native_zstd(db, 1);
```

Selection lasts for the connection only and keeps file-format codec ID `1`.
Existing C-written blobs work in native mode; native-written blobs work in C
mode. Active readers retain their selected implementation. Native writes reject
compression levels other than 1 explicitly. Native mode does not try to load
libzstd; the tests disable that backend while checking reads and writes.

PuppyLog's `flexscript` branch exposes the same path with a leading
`puppylog-flex --native-zstd ...` flag, covering input archives and database
blobs. Higher native encoding levels, encryption, external dictionaries and the
remaining PuppyLog web/API port are outside this codec implementation.

## Validation and measurements

```sh
python3 scripts/test-zstd.py
FLEX_ZSTD_ACCELERATION=0 python3 scripts/test-zstd.py
FLEX_ZSTD_ACCELERATION=baseline python3 scripts/test-zstd.py
python3 scripts/benchmark-zstd.py
```

The compatibility suite uses system libzstd solely as an independent test
oracle. It checks both encoding directions, varying chunk boundaries, checksums,
unknown sizes, concatenated/skippable frames, truncation/mutation cases,
context reuse and mixed native/C FlexDB files. Tests compile small native
Flexscript drivers, check exact-bound byte primitives with guard pages, and
exercise both complete-buffer and streaming decoding. Python is not part of
the library or application runtime. `scripts/test-native-constants.py` also
checks compiler expression results against an independent Python word oracle.
See [benchmark.md](benchmark.md) for reproducible speed, size and memory results.

The decoder and XXH64 implementation adapt Go 1.25.3's BSD-licensed
[`internal/zstd`](https://github.com/golang/go/tree/go1.25.3/src/internal/zstd).
The original copyright notices and [license](licenses/Go-BSD.txt) are retained.
The encoder follows the public
[Zstandard format](https://github.com/facebook/zstd/blob/dev/doc/zstd_compression_format.md).
