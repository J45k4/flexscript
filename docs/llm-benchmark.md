# Qwen3-1.7B speed baseline, 2026-10-11

Measured on the same NVIDIA GeForce RTX 2070, driver 610.57.04, with an
Intel Core i7-8700K host. GPU workloads ran sequentially; ordinary desktop
applications remained running and clocks were not locked.

| Model execution | Flexscript direct SASS | llama.cpp CUDA | llama.cpp / Flexscript |
| --- | ---: | ---: | ---: |
| Prefill, 23 tokens | 14.94 tokens/s | 1,591.65 tokens/s | 106.53x |
| Decode, 64 steps after 23 tokens | 11.12 tokens/s | 100.92 tokens/s | 9.07x |

These rates divide token counts by the mean elapsed time across three timed
repetitions, after one full warmup. Mean prefill times were 1,539.33 ms and
14.45 ms; mean decode times were 5,754.00 ms and 634.14 ms. Prefill differs
deliberately: Flexscript currently processes one token at a time, while
llama.cpp processes the prompt as a batch.

Both runners used one sequence, a 256-token context capacity, FP32 K/V caches,
identical input token IDs and identical replayed decode token IDs. They timed
model execution and synchronization, excluding loading, compilation,
tokenization, sampling and printing. No tokens were sampled during the timed
decode loop and EOS did not terminate it. Flexscript omitted explicit logits
downloads; llama.cpp may transfer logits internally. This compares actual
runtime execution rather than isolated device kernels.

The checkpoint was the cached Qwen/Qwen3-1.7B revision
`70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`. Flexscript loaded its BF16 weights
directly and used FP32 activations. The official llama.cpp converter produced
an F16 GGUF locally from that same checkpoint, with FP32 normalization vectors.
There was no integer quantization. This is a comparable 16-bit-weight baseline,
not a claim of bit-identical arithmetic across the two implementations.

llama.cpp was the unmodified official CUDA 12.8 release **b11429**, commit
`d81235049384534c167caea52b85a694f6103d14`. Both downloaded archive SHA256s
matched the release API's digests. A small local benchmark harness called those
libraries with all layers on GPU, one host thread, FP32 caches and flash
attention disabled. It supplied the exact token IDs used by the native
Flexscript benchmark. The release's `llama-bench` argument parser rejects
`-ctk f32`, although its library and completion tool support FP32 caches, so
the matched-cache measurement uses the library harness.

For an additional check, the unmodified `llama-bench` executable with default
FP16 caches measured 102.80 decode tokens/s over three repetitions at depth
23. Its serial, batch-size-one prefill measured 104.58 tokens/s. These runs use
the benchmark's random token IDs and are secondary to the matched-token result.

Real greedy chat generation with the same 23-token prompt and FP32 caches
produced identical answer text in both runners. The exact prompt IDs were
checked, including the trailing double newline. llama.cpp's completion timing
was 99.89 tokens/s across 59 subsequent model evaluations; the native
Flexscript chat report measured approximately 10.99 tokens/s across the same
59 evaluations, including its sampling and output overhead.

## Local artifacts and reproduction

The native benchmark is `scripts/bench-llm.flex`; build and invocation are
documented in [LLM inference](llm-inference.md#speed-measurements). The measured
run used `build/llm/final-chat.json` as its token fixture.

Local artifacts under `build/llm/` contain:

- `speed-comparison.json`: combined rates, samples and comparison metadata.
- `flex-benchmark.json` and `llama-matched-benchmark.json`: raw matched samples.
- `llama-matched-bench.cpp` and `llama-matched-tokens.h`: reference harness and
  exact embedded token IDs.
- `llama-benchmark-commands.json`: commands for the stock benchmark runs.
- `llama-completion-command.json`, `.log` and `.txt`: real-prompt command,
  timing and output; the latter two files use the prefix `llama-completion`.
- `gguf-conversion.log` and `qwen3-1.7b-f16.gguf`: local official conversion.

The downloaded binaries and matching source are under `build/llamacpp/`.
They and the reports are local build artifacts, not distributed with the
source tree. The harness can be compiled against those official libraries:

```sh
c++ -O2 -std=c++17 build/llm/llama-matched-bench.cpp \
  -Ibuild/llamacpp/source/ggml-org-llama.cpp-d812350/include \
  -Ibuild/llamacpp/source/ggml-org-llama.cpp-d812350/ggml/include \
  -Lbuild/llamacpp/llama-b11429 -lllama -lggml -lggml-base \
  -o build/llm/llama-matched-bench
LD_LIBRARY_PATH=build/llamacpp/llama-b11429:build/llamacpp/cudart-llama-b11429-bin-ubuntu-cuda-12.8-x64 \
  build/llm/llama-matched-bench build/llm/qwen3-1.7b-f16.gguf \
  build/llamacpp/llama-b11429
```

This baseline identifies a large performance gap, not its full attribution.
Batched matrix multiplication for prefill, faster matrix-vector kernels for
decode, and fewer launches are the main implementation areas to investigate.
Kernel profiling is needed before assigning percentages to those costs.

## Optimized direct SASS, 2026-10-11

The same Pup definition and checkpoint now run with packed GEMV loads,
block-wide RMSNorm, four-warp attention, register-copy propagation, dead-code
removal, dependency scheduling and CUDA graph replay. No model-definition edits,
integer quantization, PTX compilation or cuBLAS execution were introduced.

The matched protocol above, including the exact token fixture, context capacity
and FP32 caches, produced:

| Model execution | Original Flexscript | Optimized Flexscript | Refreshed llama.cpp |
| --- | ---: | ---: | ---: |
| Prefill, 23 tokens | 14.94 tokens/s | 96.50 tokens/s | 1,549.38 tokens/s |
| Decode, 64 steps after 23 tokens | 11.12 tokens/s | 79.67 tokens/s | 100.45 tokens/s |

Optimized native decode samples were 799, 800 and 811 ms. The refreshed
llama.cpp samples were 635.939, 632.747 and 642.790 ms. Native decode improved
7.16x; llama.cpp remains 1.26x faster. Prefill remains serial in Flexscript and
batched in llama.cpp. The performance target has not yet been reached.

Validation on the RTX 2070 passed 21,591 LLM planning/numerical checks, 425 SASS
checks, 11,441 GPU feature checks and 184,337 floating-point checks. The compiler
rebuilt itself byte-for-byte. The full 60-token greedy answer and input IDs
matched the original run exactly. An independent CPU oracle checked all 151,936
logits at four retained-cache predictions: maximum error was below 0.000073,
and all greedy choices and top-five lists matched. Reduction order changes mean
the optimized implementation does not promise bitwise-identical logits.

Additional local artifacts are `speed-comparison-optimized.json`,
`benchmark-load-issue.json`, `llama-matched-optimized-comparison.json`,
`optimized-chat.json`, `optimized-cache.json`, `optimized-reference.json` and
`profile-optimized.json`, all under `build/llm/`. The standalone native profiler
can be reproduced with:

```sh
build/flex-llm scripts/profile-llm.flex -o build/profile-llm
build/profile-llm --checkpoint "$QWEN_CHECKPOINT" \
  --compiler build/flex-llm --tokens build/llm/chat.json \
  --iterations 3 --report build/llm/profile.json
```

It inserts CUDA events around individual kernel launches rather than timing
graph replay. Its measurements include that instrumentation and should guide
optimization, not replace the resident-model benchmark. Matrix-vector kernels
remain the largest measured cost.

## Fused lowering and register allocation, 2026-10-11

Further native compiler and library changes narrow the decode gap with the
same checkpoint, unchanged Pup definition and matched protocol above:

| Model execution | Previous Flexscript | Current Flexscript | Refreshed llama.cpp |
| --- | ---: | ---: | ---: |
| Prefill, 23 tokens | 96.50 tokens/s | 121.48 tokens/s | 1,575.31 tokens/s |
| Decode, 64 steps after 23 tokens | 79.67 tokens/s | 97.07 tokens/s | 101.16 tokens/s |

Native decode samples were 659, 660 and 659 ms; llama.cpp samples were
632.576238, 632.388386 and 633.023938 ms. Native decode improved another 21.84%
and is now 4.05% below llama.cpp's throughput. The speed target has not yet been
reached. Prefill remains sequential in Flexscript and batched in llama.cpp, so
its larger gap remains. Resident-model timing excludes sampling and logits
download; the CLI still performs those operations on the CPU.

The compiler now propagates zero values, folds small constant offsets into
global loads, compacts register pairs and separates address-read completion
from load-result completion. Dependency scheduling retains the two-cycle
scoreboard activation interval. One-dimensional launches take a shorter index
path while multidimensional launches retain their full semantics. Streamed
weight loads bypass L1 so reused activation vectors can stay cached.

Library lowering adds packed normalization, normalization/rotary fusion,
paired MLP projections with SiLU/multiplication, and residual/normalization
fusion. All original intermediate outputs remain available to other consumers.
The schedule drops from 563 to 367 kernels per token. Packed matrix-vector
kernels use 256-thread blocks; fused head normalization/rotary uses 32 threads
per block. These choices require no Pup or checkpoint edits and retain BF16
weights with FP32 activations and caches. No integer quantization, PTX
compilation or external ML runtime was added to inference.

Final validation passed 510 SASS checks across 53 cubins and 111 device runs,
11,982 GPU feature checks across 46 programs/device runs, 184,337 floating-point
checks and 50,591 LLM planning/numerical checks. Native SASS instructions also
passed independent disassembly, and the compiler rebuilt itself byte-for-byte.
All 60 greedy answer tokens and the prompt IDs matched both previous native
runs. An independent CPU oracle checked 151,936 logits at each of four
retained-cache predictions: every argmax and top-five list matched, with
maximum absolute error below 0.000073.

Local reports under `build/llm/` are `speed-comparison-gap.json`,
`benchmark-gap-final.json`, `llama-matched-gap-final.json`, `gap-chat.json`,
`gap-cache.json`, `gap-reference.json` and `profile-gap-final.json`. The native
benchmark's `--fusion` option permits comparisons of individual schedule
rewrites without changing the model. Wider matrix-vector rows, independent
accumulation chains and read-only weight caching did not improve the final
implementation and were discarded.

References: [official release](https://github.com/ggml-org/llama.cpp/releases/tag/b11429),
[benchmark implementation at the measured commit](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/tools/llama-bench/llama-bench.cpp),
[official converter at the measured commit](https://github.com/ggml-org/llama.cpp/blob/d81235049384534c167caea52b85a694f6103d14/convert_hf_to_gguf.py).

## Native decode ahead of llama.cpp, 2026-10-11

The final implementation beats the same official llama.cpp b11429 build on
resident-model Qwen3-1.7B decode in three balanced comparison pairs:

| Measurement | Flexscript direct SASS | llama.cpp F16 GGUF |
| --- | ---: | ---: |
| Decode, pooled nine timed samples | 98.44 tokens/s | 90.82 tokens/s |
| Mean elapsed time for 64 decode steps | 650.111 ms | 704.686 ms |
| Prefill, pooled nine timed samples | 118.97 tokens/s | 1427.89 tokens/s |

The measured decode throughput advantage is **8.39%**. Each process has one
warmup and three timed repetitions; the middle pair reverses runner order.
Every pair favors Flexscript:

| Pair | Flexscript decode tokens/s | llama.cpp decode tokens/s | Advantage |
| --- | ---: | ---: | ---: |
| 1 | 96.82 | 91.20 | 6.16% |
| 2 | 99.48 | 88.21 | 12.78% |
| 3 | 99.07 | 93.19 | 6.31% |

Both runners use the exact same 23 input IDs and 64 replayed decode IDs, a
256-token context, FP32 KV caches, and synchronous per-token model execution.
llama.cpp keeps flash attention disabled as in the preceding matched baseline.
The native model still uses the original BF16 checkpoint and FP32 arithmetic;
llama.cpp uses its official F16 conversion and default internal math policy.
This is a comparable 16-bit workload, not bit-identical arithmetic. No integer
quantization or change to the Pup definition was introduced.

Desktop applications remained active and clocks were not locked. One-second
GPU clock/utilization/power/memory samples were recorded for the entire paired
comparison. This is a result for this RTX 2070 and this short-context decode
protocol, not a claim about every model, device or context. Older absolute
throughput numbers came from different desktop conditions. Prefill remains
sequential in Flexscript and batched in llama.cpp, and still trails substantially.
Both timings exclude caller-side sampling, tokenization, loading and
compilation. Native timing also excludes logits downloads; any internal
llama.cpp output transfer remains included in its decode/synchronize calls.
The native chat CLI still performs CPU sampling and has lower end-to-end throughput.

The main changes are sixteen warps per attention head, native FP32 maximum and
warp-sum instructions, adjacent Q/K/V projection fusion, by-value launch words,
cheaper BF16 expansion and bounded matrix-loop counters, and native compiler
removal of unreachable helper epilogues and empty branches. The schedule now
has 311 launches per token, compared with 367 before this change and 563 in the
initial implementation. Q/K/V fusion retains every original projection output.
Attention uses 512-thread blocks and 16640 shared bytes; packed projections use
256-thread blocks. The native tracked device buffers total 3,506,130,448 bytes
at context 256, excluding driver/module/graph allocations.

The SM75 scheduling changes retain conservative predicate and unknown-operation
delays while using tested six-cycle integer/move, four-cycle FMA and five-cycle
other FP32 delays. The FMA latency agrees with the
[NVIDIA Turing tuning guide](https://docs.nvidia.com/cuda/turing-tuning-guide/#instruction-scheduling).
The CUDA stack register remains reserved and initialized. Kernel launch words
have native constant-bank and PTX lowerings; repeated and zero-argument helper
calls are explicitly tested.

Validation passed **253,503 checks**: 519 SASS checks across 54 cubins and 113
physical-device runs, 13,553 GPU feature checks across 52 programs/device runs,
184,342 floating-point checks, and 55,089 LLM planning/numerical checks. The LLM
suite covers unequal Q/K/V heights, partial blocks, all retained outputs and
cache positions crossing 16- and 32-row boundaries on native SASS and PTX. The
compiler rebuilds itself byte-for-byte. All 60 greedy answer IDs and prompt IDs
match the original run. An independent CPU oracle checks every one of 151,936
logits at four retained-cache predictions: all argmax/top-five lists agree and
maximum absolute error is below 0.000073.

Local evidence: `build/llm/speed-comparison-faster-paired.json`,
`paired-{0,1,2}-{flexscript,llama.cpp}.json`, `paired-gpu.csv`,
`faster-chat-final.json`, `faster-cache-final.json`,
`faster-reference-final.json`, `profile-faster-final.json` and
`{sass,gpu,float}-faster-final-tests.json`. The local comparison runner is
`build/llm/paired-faster.py`; inference itself remains native Flexscript and
direct SASS. Default `build/flex-llm`, `build/llm-infer`, `build/bench-llm`,
`build/profile-llm` and `build/test-llm` binaries are updated to this version.

## Batched prefill ahead of llama.cpp, 2026-10-11

The final native tensor-core path beats the same official llama.cpp b11429
build (commit `d81235049384534c167caea52b85a694f6103d14`) on the matched
23-token Qwen3-1.7B prompt. These are pooled results from nine timed samples
per configuration on the RTX 2070 and Core i7-8700K, with driver 610.57.04:

| Configuration | Prefill ms | Prefill tokens/s | 64 decode steps ms | Decode tokens/s |
| --- | ---: | ---: | ---: | ---: |
| Flexscript, default `--weights f16` | 23.046 | 998.01 | 618.322 | 103.51 |
| Flexscript, `--weights f16-tiled` | 14.437 | 1593.12 | 676.999 | 94.53 |
| llama.cpp, F16 GGUF | 15.130 | 1520.20 | 653.263 | 97.97 |

Tiled storage delivers **4.80% higher prefill throughput** than llama.cpp.
Default row-major storage delivers **5.65% higher decode throughput**.
These wins require different configurations: tiled decode is 3.51% below
llama.cpp, and default row-major prefill remains slower. Tiled storage remains
an explicit option; the default favors decode. This comparison supersedes the
older measurements above for the current implementation and desktop conditions.

Three groups rotate runner order so each configuration occupies each position
once. Each process performs one warmup and three timed samples. Tiled prefill
wins in every group:

| Group | Flexscript tiled prefill ms | llama.cpp prefill ms | Throughput advantage |
| --- | ---: | ---: | ---: |
| 1 | 14.848 | 15.445 | 4.02% |
| 2 | 14.225 | 14.959 | 5.16% |
| 3 | 14.239 | 14.985 | 5.24% |

Both runners receive the same 23 prompt IDs and 64 replayed decode IDs, use a
256-token context and FP32 KV caches, and synchronize model execution.
llama.cpp flash attention remains disabled. Native prefill uses FP16 products
and FP32 accumulation; native decode uses FP32 arithmetic with FP16 stored
weights. This compares 16-bit workloads with different internal math policies.
No integer quantization was added. Desktop applications stayed active and
clocks were not locked; one-second GPU telemetry covers the comparison.
This measures this short prompt on this GPU, rather than long-context scaling.

Timings exclude checkpoint loading, kernel compilation, tokenization, sampling,
printing and graph preparation. Native timings also exclude logits downloads;
llama.cpp's internal output transfer remains inside its execution/synchronize
calls. Chat CLI latency includes additional work outside this benchmark.

The implementation batches prompt projections into native SM75 tensor-core
matrix products, tiles projection weights and staged activations, selects K
partitions by matrix shape, and replays a CUDA graph. Scratch-buffer reuse,
fused normalization/staging and reduction/MLP epilogues reduce memory traffic
and launches. The compiler emits FP16 conversions and HMMA instructions,
allocates aligned register quartets and forwards redundant shared-memory
round trips. Production kernels compile directly to SASS; no PTX compilation
or external ML runtime is involved. The Pup definition and `readme.md` are
unchanged.

Validation passed **2,630,337 checks**: 519 SASS checks across 54 cubins and
113 physical-device runs, 13,577 GPU feature checks, 184,342 floating-point
checks, 55,089 LLM checks and 2,376,810 batch/conversion/fusion checks.
Coverage includes all 65,536 half encodings, native and PTX reference paths,
partial tiles, multiple blocks, split reductions and causal attention.
The compiler rebuilds itself byte-for-byte. All 60 greedy chat tokens match
the original run. An independent CPU oracle checks all 151,936 logits at each
of four retained-cache predictions in both weight layouts: every argmax and
top-five list agrees. Maximum absolute error is 0.007731. The verifier explicitly
uses a 0.02 limit for FP16 prompt products, retaining 0.002 for serial FP32
math; the earlier FP32 error bound does not apply to this batched path.

Reproduce the native tiled configuration from the repository root after
building the tools described in [inference instructions](llm-inference.md):

```sh
build/bench-llm --compiler build/flex-llm --checkpoint "$QWEN_CHECKPOINT" \
  --weights f16-tiled --tokens build/llm/final-chat.json \
  --decode 64 --context 256 --repeats 3 \
  --report build/llm/benchmark-tiled.json
```

Use `--weights f16` for the default row-major comparison. Local evidence is
`build/llm/speed-comparison-prefill-final-paired.json`, the nine
`paired-prefill-final-{0,1,2}-{row-major,tiled,llama.cpp}.json` reports,
`paired-prefill-final-gpu.csv`, `batch-tiled-chat.json`,
`batch-{f16,tiled}-cache-reference.json`, `{sass,gpu,float}-prefill-tests.json`
and `test-llm-prefill-final.log`. The comparison orchestrator is
`build/llm/paired-prefill-final.py`; inference itself remains native Flexscript.

## RDNA4 and HIP, 2026-10-11

The AMD backend runs Qwen3-1.7B on an RX 9070 XT (gfx1201, 16 GiB), Ryzen 9
5900X and ROCm 7.2.4. Native `.hsaco` modules use HIP graphs for decode and
RDNA4 WMMA for batched prefill. FP16 weights and FP32 KV caches stay resident.
The model definition and pinned checkpoint revision are unchanged; there is
no integer quantization. See [implementation and setup](rdna.md).

The official llama.cpp source at commit
`5c8854fd88319125125dc4b836c98b1b215b0f23` was built separately with HIP
(gfx1201) and Vulkan. Its official converter produced an F16 GGUF from the
same safetensors checkpoint. These matched library-harness measurements use
the same 15 input token IDs, 64 replayed decode IDs, 256-token context, FP32
K/V caches, one host thread and synchronous model execution. llama.cpp flash
attention is disabled in this matched-cache comparison. Each runner has one
warmup and three timed samples:

| Runner | 15-token prefill ms | Prefill tokens/s | Decode tokens/s |
| --- | ---: | ---: | ---: |
| Flexscript RDNA, FP16 weights | 13.060 | 1,148.52 | 127.11 |
| llama.cpp HIP, F16 GGUF | 15.776 | 950.81 | 95.09 |
| llama.cpp Vulkan, F16 GGUF | 33.778 | 444.07 | 82.65 |

These rates divide counts by mean elapsed time. Native decode samples are
504.668, 502.073 and 503.802 ms. Timings exclude loading, compilation,
tokenization, caller-side sampling and printing. Flexscript also excludes
logits downloads; any internal llama.cpp output transfer remains inside its
execution calls. Both llama.cpp backends selected first greedy token 9707,
matching Flexscript. This does not establish bit-identical logits.

Stock `llama-bench` was also run with flash attention enabled and its default
FP16 caches, which improves llama.cpp's decode result:

| Stock configuration | Prefill tokens/s | Decode tokens/s |
| --- | ---: | ---: |
| llama.cpp HIP | 1,002.00 | 103.57 |
| llama.cpp Vulkan | 551.78 | 127.72 |

Stock rates are the benchmark's reported mean throughput over three samples.
Those runs use random token IDs, prompt length 15 and decode length 64 after
depth 15, so they are a second comparison with different settings. Native
decode is approximately level with the faster Vulkan result, whose sample
standard deviation is 4.90 tokens/s. The measured short-prompt prefill is
faster than both stock runs. These results do not establish long-context,
large-batch or quantized-model performance. Desktop workloads remained active;
GPU jobs ran sequentially and clocks were not locked.

Greedy application sampling now runs on the GPU and downloads eight bytes per
token. The real CLI prompt “Say hello.” produced “Hello! How can I assist you
today? 😊”: 14 ms prefill and 87 ms for 11 subsequent decode calls, about
125 tokens/s including sampling and text output. The native chat
UI also generated real replies with the default RDNA backend and after a
reload to HIP source. Nonzero-temperature chat still uses CPU top-40 sampling.

Local evidence is `build/llm/rdna-speed-comparison.json`,
`rdna-final-benchmark.json`, `llama-matched-{hip,vulkan}-final.json`,
`llama-{hip,vulkan}-stock.json` and `rdna-gpu-sample-chat.json`.
The matched harness sources and token header are under `build/llm/`;
llama.cpp builds, the converter and project-local HIP BLAS dependencies are
under `build/llamacpp/`. Flexscript inference itself requires no BLAS library.

```sh
build/llm-infer --backend rdna --checkpoint "$QWEN_CHECKPOINT" \
  --context 256 --max-tokens 8 --prompt 'Say hello.' \
  --report build/llm/rdna-tokens.json
build/bench-llm --backend rdna --compiler build/flex \
  --checkpoint "$QWEN_CHECKPOINT" --tokens build/llm/rdna-tokens.json \
  --decode 64 --context 256 --repeats 3 \
  --report build/llm/rdna-benchmark.json
# Stock llama.cpp, after building the chosen GPU backend:
llama-bench -m build/llm/qwen3-1.7b-f16.gguf \
  -p 15 -n 64 -d 15 -r 3 -t 1 -fa on -o json
```

## Wider AMD kernels and fused attention, 2026-10-11

The AMD implementation now loads eight adjacent weights per lane, uses
independent accumulation chains, emits explicit global-memory accesses,
reduces wave sums with native DPP/permutation instructions and uses shared-only
barriers where global ordering is unnecessary. Q/K normalization, rotary,
cache append and attention fuse into one kernel per layer. The decode schedule
falls from **311 to 199 launches** without changing the model or quantizing it.
Original intermediate tensors and KV cache rows remain available.

The faster reference configurations below use the same official llama.cpp
commit and F16 GGUF as the preceding AMD measurements, now with **FP16 KV
caches and flash attention enabled**. Flexscript retains FP32 KV caches.
All runners receive the same 15 prompt IDs and a 64-token decode replay that
cycles the 12 IDs in the real “Say hello.” reply, including EOS. The benchmark
replays EOS as an ordinary input and does not stop early. Context capacity is
256, with one host thread and synchronous model execution.

| Runner | Prefill tokens/s | Decode tokens/s | Timed samples |
| --- | ---: | ---: | ---: |
| Previous Flexscript, `a2322d0` | 1,146.86 | 127.31 | 9 |
| Current Flexscript, default row-major F16 | 1,148.27 | 135.05 | 9 |
| llama.cpp Vulkan, F16 KV, flash attention | 567.69 | 140.05 | 9 |
| llama.cpp HIP, F16 KV, flash attention | 1,000.42 | 103.53 | 3 |

Rates divide token counts by the mean elapsed time across every timed sample.
The original baseline comes from three earlier rotated comparison groups.
The final Flexscript/Vulkan comparison uses three alternating groups, each
with one warmup and three timed samples per process. Flexscript's group decode
rates are 137.78, 130.08 and 137.58 tokens/s; Vulkan's are 139.68, 140.09 and
140.38. One 552.486 ms Flexscript sample is included. Ordinary desktop workloads
remained active and clocks were not locked; GPU jobs ran sequentially.

Pooled decode is **6.08% above the previous Flexscript baseline**, and normal
groups run around 138 tokens/s. The strongest measured Vulkan configuration
remains **3.70% faster in throughput**. Flexscript's short-prompt prefill is
faster than both reference backends. These results do not establish a lead
over vLLM, SGLang, ATOM or MLC, nor predict long-context, batching or quantized
performance. Timings exclude loading, compilation, tokenization, sampling,
printing and caller-side logits downloads; llama.cpp's internal output transfer
remains inside its execution calls. The HIP harness uses ordinary file loading
instead of mmap to avoid a local host-memory-pressure loading stall.

Final validation passes 84,637 LLM checks, 1,188,405 prefill/conversion checks,
10,760 HIP ABI/arithmetic/collective checks, 2,048 long-cache attention checks
and 265 capacity checks. A cancellation regression verifies the reduction
broadcasts an identical finite result to every lane; shared barriers are checked
between waves. The compiler rebuilds itself byte-for-byte, and all 28 LLM
kernels also compile to PTX and direct SASS. Physical execution was on AMD.

Real greedy generation preserves all 12 reply tokens. All 151,936 logits at
each of 12 predictions are finite, every top-five list matches the original,
and maximum absolute difference is 0.017417, below the existing 0.02 FP16-prompt
tolerance. These are comparisons with the original GPU execution, rather than
an independent full-model CPU oracle. Reduction order changes, so logits are
not bit-identical. Automatic context sizing and a real 8,213-token prompt are
also checked through the rebuilt chat worker.

Local evidence under `build/llm/` includes `opt-broadcast-speed-comparison.json`,
`opt-broadcast-paired-{0,1,2}-{optimized,llama-vulkan}.json`,
`opt-speed-comparison.json` (original baseline), `opt-hip-fast.json`,
`opt-quality-comparison.json`, `opt-final-quality.json` and
`opt-large-context-validation.json`. Use the preceding native benchmark
command with `--max-tokens 12` when generating its token fixture to reproduce
the longer decode cycle.

For isolated kernel experiments after preparing the model's native images:

```sh
build/flex scripts/bench-llm-kernel.flex -o build/bench-llm-kernel
build/bench-llm-kernel --image build/llm/mlp-pair.hsaco \
  --kernel mlp-pair --rows 8192 --width 2048 --block 256
```

This uses synthetic nonzero 16-bit weights and reports per-kernel nanoseconds
from five GPU-event samples, each covering 100 graph-captured calls. Use
`bench-llm` for model throughput; isolated kernel gains alone do not establish
an application speedup.


## Initial hybrid direct RDNA linear emission (2026-10-12)

The experimental `rdna-direct` inference mode now emits F16 GEMV, paired MLP
and packed Q/K/V instructions and AMDHSA code objects directly from Flexscript.
The remaining kernels use ROCm LLVM. GEMV uses sixteen weights per lane for
widths divisible by 512, with an eight-weight fallback; MLP and Q/K/V keep the
eight-weight loop. Wider MLP and 32-weight GEMV experiments did not improve
model throughput and were not adopted.

On the same RX 9070 XT, F16 Qwen3-1.7B, 15 prompt IDs, 64-token replay and
256-token context protocol above, the selected production configuration measured
**145.27 decode tokens/s** and **1,151.58 prefill tokens/s** across five timed
samples after one warmup. Decode samples were 444.242, 439.447, 441.032,
440.162 and 437.853 ms; every timed sample is included. Desktop workloads remained
active and clocks were unlocked. This is a separate run from the preceding
llama.cpp comparison, not a new alternating comparison or evidence of a lead
on every runtime. The 150 tokens/s target has not been reached.

```sh
build/bench-llm --backend rdna-direct --compiler build/flex   --checkpoint build/llm/models/qwen3-1.7b   --tokens build/llm/rdna-gpu-sample-chat.json --decode 64   --context 256 --repeats 5 --report build/llm/direct-final-speed.json
```

The direct kernels pass CPU comparisons at widths 256, 768, 2048 and 6144,
three block sizes, unequal Q/K/V row counts, partial blocks and output guards.
The installed inference CLI retains all 12 greedy reply IDs and all top-five
lists against the original GPU reference; all 1,823,232 logits are finite,
with maximum absolute difference 0.01741612 below the 0.02 tolerance.
The compiler self-build is byte-identical and 84 core checks pass. A fused
attention metadata lifetime bug was also fixed by using an independent mapping
for the buffer that gets unmapped after upload.

Local evidence: `direct-final-speed.json`, `direct-final-quality.json` and
`direct-final-quality-comparison.json` under `build/llm/`.


## Complete direct RDNA emission (2026-10-12)

`rdna-direct` now emits every Qwen kernel directly, including WMMA prefill,
fused attention and greedy sampling. Four compact fast paths cover F16 linear
operations and 2048-wide residual RMSNorm; no kernel falls back to LLVM.
The AMD default selects this mode. HIP still loads and dispatches the code.

The new encoder passes the numerical, launch and cache-boundary checks listed
in [RDNA verification](rdna.md#verification). Actual multi-turn generation also
works with HIPRTC deliberately blocked. A gfx12 F16 e32 register-class bug found
in fused attention was fixed using e64 conversions outside the restricted range;
e64 packed F16 destinations also explicitly clear their preserved upper halves.

On the RX 9070 XT with F16 Qwen3-1.7B, 15 prompt tokens, 64 decode tokens,
256-token capacity, one warmup and five timed samples per runner:

| Compiler route | Decode tokens/s | Prefill tokens/s |
| --- | ---: | ---: |
| Complete direct RDNA | 140.97 | 654.39 |
| Existing ROCm LLVM | 136.44 | 1,110.04 |

Rates divide token counts by mean elapsed time. Direct decode samples were
457.163, 454.442, 453.061, 452.969 and 452.389 ms; LLVM samples were
473.301, 468.303, 468.147, 467.677 and 467.977 ms. Both runners were executed
sequentially with the same compiler, checkpoint, token replay and settings.
Desktop activity and unlocked clocks remain sources of variance. This run
shows about 3.3% faster decode than the LLVM route, with slower native prefill;
it is not a fresh comparison against other runtimes. The 150 tokens/s target
remains unmet. Earlier hybrid measurements above use a separate run.

Evidence: `build/llm/benchmark-direct-all-native-final.json`,
`build/llm/benchmark-llvm-all-native-final.json` and
`build/llm/direct-native-fixed-chat.json`.
