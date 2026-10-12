# RDNA machine code and HIP

Flexscript supports three AMD GPU targets:

| Compiler target | Output | Runtime |
| --- | --- | --- |
| `hip` | HIP C++ source | HIPRTC compiles it when loaded |
| `rdna-gfx1201` | Native AMD HSA ELF code object (`.hsaco`) | HIP loads machine code directly |
| `rdna-direct-gfx1201` | Directly encoded RDNA4 instructions in an HSA ELF code object | HIP loads machine code directly |

`hip` and `rdna-gfx1201` lower the existing word IR, use `kernel(index,input,output,count)` and
support the GPU intrinsics in `lib/gpu.flex`. Helpers inline into the kernel.
Word arithmetic wraps at 64 bits; comparisons and division are signed.
Ordinary word loads/stores retain unaligned little-endian behavior.
Kernel-reachable allocation, syscalls, FFI, recursion and static data are rejected.

The general native pipeline is **Flexscript → word IR → HIP source → HIPRTC/ROCm LLVM
→ gfx1201 machine code**. ROCm performs native instruction selection, register
allocation and binary packaging. This backend does not encode RDNA instruction
bytes itself. Offline code-object compilation requires no GPU context.

The direct pipeline is **Flexscript → word IR → RDNA4 instruction encoder →
AMDHSA ELF writer**. It invokes no LLVM, HIPRTC, assembler or linker and reads
no binary template. It emits all 32 Qwen kernel variants, including normalization,
rotary embedding, fused cache/attention, sampling, packing and WMMA prefill.
Unsupported operations are rejected instead of being routed through LLVM.

The encoder inlines helpers, allocates register pairs for word values and
manages EXEC explicitly for branches, divergent returns and loops. It supports
word integer operators, signed division/remainder, packed global memory, LDS,
barriers, launch coordinates/words, shuffle, ballot, FP32 arithmetic and SFU
approximations, F16 conversions and RDNA4 WMMA. Flattened launch indices must
fit uint32; kernels must fit 256 VGPRs and 96 SGPRs. This is a supported subset,
not complete parity with PTX/SASS: atomics, FP64, integer/float conversions,
correctly rounded FP32 divide/sqrt, textures and NVIDIA MMA are not implemented.
F16 encodings switch to e64 for registers outside the gfx12 e32 register class.

Four whole-kernel fast paths in `lib/rdna.flex` provide F16 GEMV, paired gate/up
MLP, packed Q/K/V GEMV and 2048-wide residual RMSNorm. Linear kernels use one
wave per output row, scalar row pointers, eight F16 weights per lane (sixteen
for GEMV widths divisible by 512), and FP32 accumulation. Their blocks must
be one dimensional, 32–1024 threads and a multiple of 32; count is rows × 32.
Widths are positive multiples of 256 and row byte offsets fit uint32.
Residual RMSNorm uses 128 threads per complete 2048-value row and 32 LDS bytes.
The ABI includes eight launch words and hidden HSA v5 block counts and sizes.

`--backend rdna-direct` compiles every inference kernel directly. Compatible
row-major F16 operations use the compact fast paths; BF16, tiled storage and
other widths use ordinary direct word-IR emission. The AMD inference default
is now `rdna-direct`; `--backend rdna` explicitly selects the LLVM route.
HIP still provides memory allocation, loading, launches and graphs in both modes.

## Requirements and commands

The tested machine is an AMD Radeon RX 9070 XT (RDNA4, gfx1201, wave32), Ryzen 9
5900X and ROCm 7.2.4. The implementation currently targets gfx1201; other AMD
architectures have not been validated. Direct mode loads `libamdhip64.so` for
execution. The `hip` and `rdna` LLVM routes additionally need `libhiprtc.so`
and `/opt/rocm/include` headers.
No hipBLAS or rocBLAS is needed for Flexscript inference.

```sh
build/flex --target hip examples/gpu/vector.flex -o build/vector.hip
build/flex --target rdna-gfx1201 examples/gpu/vector.flex -o build/vector.hsaco
build/flex --target rdna-direct-gfx1201 libs/ml/llm/kernels/gemv-direct-rdna.flex -o build/gemv-direct.hsaco
build/flex llm.flex -o build/llm-chat
build/llm-chat --backend rdna-direct --checkpoint build/llm/models/qwen3-1.7b
```

For a single prompt:

```sh
build/flex scripts/llm-infer.flex -o build/llm-infer
build/llm-infer --backend rdna-direct --checkpoint build/llm/models/qwen3-1.7b \
  --context 256 --max-tokens 64 --prompt 'Say hello.'
```

`--backend hip` uses the same kernels through runtime source compilation.
Use `--backend rdna-direct --weights f16` for the native compiler and F16 fast paths.
The checkpoint is the pinned Hugging Face Qwen3-1.7B recipe described in
[inference instructions](llm-inference.md); Flexscript loads its safetensors
directly. `build/llm-chat` finds the local checkpoint automatically.

`--context auto` sizes up to the checkpoint's 40,960-token limit while reserving
GPU headroom and full-prompt working memory. Explicit values such as
`--context 16384` are supported. The latest RX 9070 XT test selected 29,120 tokens
under the current desktop load and processed an 8,213-token prompt, then decoded
“Hello!”. The selected capacity changes with free VRAM. Larger contexts cost
more memory and attention time; the short-context speed measurements do not
predict long-context throughput.

AMD checkpoint uploads use a bounded 64 MiB pinned staging buffer, avoiding
slow transfers directly from a multi-GB file mapping under host-memory pressure.

## Execution and optimization

`lib/hip.flex` handles contexts, allocations, pinned memory, transfers,
three-dimensional launches, streams, events and graph replay. Its Linux x86-64
FFI bridge passes the eleven integer/pointer arguments to `hipModuleLaunchKernel`.
`lib/device.flex` selects the CUDA or HIP adapter without changing the Pup model.

Decode keeps FP16 weights, FP32 activations and FP32 KV caches on the GPU.
Packed projections, fused Q/K/V and MLP operations, streaming weight loads and
native reciprocal/rsqrt/exp2 instructions reduce traffic and arithmetic cost.
AMD row-major matrix-vector kernels load eight adjacent 16-bit weights per
lane and use independent FP32 accumulation chains. Widths divisible by four
but not eight retain the narrower path. Full-wave sums use DPP permutations
and a cross-row permutation; mirrored partial sums preserve a broadcast result
even under cancellation. Shared-only barriers avoid unnecessary global fences.

AMD decode folds Q/K normalization, rotary, cache appends and attention into
one kernel per layer, reducing Qwen3-1.7B from 311 to 199 launches per token.
It retains normalization, rotary and cache outputs for other graph consumers.
Grouped query blocks use their own current K/V row while one designated block
writes the persistent cache, avoiding cross-block races. Each attention block
uses 512 threads and 17,664 shared bytes. Batched prefill keeps its separate
schedule, and NVIDIA retains its existing kernels and schedule.

HIP graphs replay the model schedule. Greedy sampling uses a two-stage GPU
reduction, chooses the lowest token ID on ties and rejects nonfinite logits;
only its eight-byte result reaches the CPU. Temperature sampling uses the
existing CPU top-40 path.

Batched prefill uses the RDNA4 `v_wmma_f32_16x16x16_f16` instruction with FP32
accumulation. Two tiles cover each 24-token prompt tile; split-K reductions,
partial rows and both row-major and tiled weights retain the existing schedule
contract. `gpu_rdna_wmma_f16x8` exposes the native wave32 fragment operation:
four packed FP16 input words, four packed FP32 accumulator words and a shared
offset. It returns the first FP32 pair and stores the remaining three pairs
at that offset, offset + 8 and offset + 16. Each lane needs 24 private shared
bytes. All 32 lanes must participate.

## Verification

```sh
build/flex scripts/test-rdna-direct.flex -o build/test-rdna-direct
build/test-rdna-direct --compiler build/flex
build/flex scripts/test-hip.flex -o build/test-hip
build/test-hip build/flex
build/flex scripts/test-llm-sample.flex -o build/test-llm-sample
build/test-llm-sample build/flex
build/flex scripts/test-llm.flex -o build/test-llm
build/test-llm --backend rdna-direct --compiler build/flex --gpu
build/flex scripts/test-llm-prefill.flex -o build/test-llm-prefill
build/test-llm-prefill --backend rdna-direct --compiler build/flex --gpu
build/flex scripts/test-llm-context.flex -o build/test-llm-context
build/test-llm-context --backend rdna-direct
```

Direct-backend checks pass 16,655 HIP launch/graph/arithmetic/collective
comparisons, 937,117 LLM numerical checks (including real-size BF16/F16 fused
attention), 1,188,405 prefill/conversion checks and 32 greedy-sampler cases
across the LLVM and direct targets.
Real Qwen generation produced “Hello! How can I assist you today? 😊”.
The compiler rebuilds itself byte-for-byte. Native code objects were inspected
as AMD HSA ELF and disassembled to confirm RDNA4 WMMA instructions.
Large-context checks cover retained attention at 4K, 8K, 32K and the final
40,960-token slot, along with tokenizer/report growth and an actual 8,213-token
Qwen prompt. The full 40,960-token model context has not been allocated in this
test; automatic sizing selected the smaller context that fits current VRAM.
The fused and separate attention paths pass 2,048 focused large-cache checks.
The cancellation regression checks that all wave lanes receive the same sum
and that a shared-only barrier publishes results between waves.

Direct-kernel CPU checks cover widths 256, 768, 2048 and 6144 with blocks of 32, 256
and 1024 threads, partial blocks and unequal Q/K/V row counts. Compiler checks
accept ordinary vector kernels and reject native RDNA operations on PTX.
A resident worker generates Ping, a Linux follow-up and BANANA while a test
`libhiprtc.so` aborts immediately if loaded, proving no HIPRTC compilation is needed. The original eight-weight GEMV/MLP instructions and code objects match
independently assembled development references; the wider GEMV stream also
matches its reference instructions. The residual RMSNorm fast path also passes 6,144 CPU comparisons, retained
residual checks and output guards. Production compilation uses only Flexscript.

GPU execution requires access to `/dev/kfd` and the Radeon render device.
An execution sandbox hiding these devices cannot run these checks.
See [measured performance](llm-benchmark.md#rdna4-and-hip-2026-10-11) for the
workload, rates and comparison limits.

References: [HIPRTC](https://rocm.docs.amd.com/projects/HIP/en/latest/how-to/hip_rtc.html),
[AMD RDNA4 WMMA guide](https://gpuopen.com/learn/wmma-guide-amd-rdna-4-gpus-part-1/).
