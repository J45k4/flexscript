# RDNA machine code and HIP

Flexscript supports two AMD GPU backends:

| Compiler target | Output | Runtime |
| --- | --- | --- |
| `hip` | HIP C++ source | HIPRTC / ROCm LLVM compiles it when loaded |
| `hip --emit code-object --gpu-arch gfx1201` | Offline AMDHSA ELF code object | HIP loads the compiled code object |
| `rdna-gfx1201` | Directly encoded RDNA4 instructions in an AMDHSA ELF code object | HIP loads machine code directly |

The compiler driver owns offline HIP compilation and code-object extraction:

```sh
build/flex --target hip --emit code-object --gpu-arch gfx1201 kernel.flex -o kernel.hsaco
```

`--target hip` still emits HIP source by default; `--emit source` makes that
choice explicit. Code-object emission requires a base AMD GPU architecture such
as `gfx1201` or `gfx90a`. The driver invokes ROCm's `hipcc` with `-O3` and
`-ffp-contract=off`, then extracts the requested architecture's AMD GPU ELF.
Use `--rocm-root PATH` for an installation outside `/opt/rocm`.

Commands use argument vectors. Work is staged beside the destination, and an
existing output is replaced only after both tools succeed and the output passes
ELF header validation. Symlink destinations and aliases of source/import files
are rejected. Tool errors retain their diagnostics and leave existing output
intact. The direct `rdna-gfx1201` backend remains a separate emission path.

Driver checks run without a GPU, including mocked tool failures and a second
architecture's flag forwarding:

```sh
build/flex scripts/test-gpu-codeobject.flex -o build/test-gpu-codeobject
build/test-gpu-codeobject build/flex
```

At inference level, `--backend rdna` selects the native encoder.
`--backend hip` retains the LLVM-based fallback.

Both backends lower word IR and use `kernel(index,input,output,count)`.
Word arithmetic wraps at 64 bits; comparisons and division are signed.
Ordinary word loads/stores retain unaligned little-endian behavior.
Kernel-reachable allocation, syscalls, FFI, recursion and static data are rejected.

The native pipeline is **Flexscript → word IR → RDNA4 instruction encoder →
AMDHSA ELF writer**. It invokes no LLVM, HIPRTC, assembler or linker and reads
no binary template. It emits all 32 Qwen kernel variants, including normalization,
rotary embedding, fused cache/attention, sampling, packing and WMMA prefill.
Unsupported operations are rejected instead of being routed through LLVM.

The encoder inlines helpers, allocates register pairs for word values and
manages EXEC explicitly for branches, divergent returns and loops. It supports
word integer operators, signed division/remainder, packed global memory, LDS,
barriers, launch coordinates/words, shuffle, ballot, FP32 arithmetic and SFU
approximations, F16 conversions and RDNA4 WMMA. Flattened launch indices must
fit uint32; kernels must fit 256 VGPRs; execution masks use up to 96 SGPRs. This is a supported subset,
not complete parity with PTX/SASS: general atomics, FP64, integer/float conversions,
correctly rounded FP32 divide/sqrt, textures and NVIDIA MMA are not implemented.
F16 encodings switch to e64 for registers outside the gfx12 e32 register class.
The direct encoder also supports system/device acquire-release word loads and
stores, system exchange, system/device fetch-add, cache-ordering fences and the
GPU wall clock. These support the [shared Flexscript GPU OS](../libs/os/gpu/README.md)
scheduler. Child function frames can reuse caller registers dead at a call;
scratch registers live above each function's own frame. The resident worker
uses 96 VGPRs for a 512-thread block. Native leaves reserve s96..s103;
uniform stage bounds use s104..s105, bringing that worker to 106 SGPRs. F16 conversions use the long encoding above v127.
HIP's cooperative grid barrier has a separate intrinsic; the native scheduler
uses a bounded 32-bit phase/count barrier with a fully resident grid, while
preserving the full 64-bit generation publication. Device
relaxed loads and release/acquire fences are also available to shared schedulers.
Independent global and LDS loads stay outstanding until an operand read, register
overwrite or control-flow edge requires completion. Signed division/remainder
by positive powers of two use a sign-correct bias and shift rather than the
generic restoring-division loop.

`gpu_rdna_gemv_stage_f16(index,step)` embeds a compact matrix-vector operation
inside a larger resident program. A full active wave owns one output row;
`step` is a wave-uniform schedule descriptor containing weights, input, output
and width. The width is a positive multiple of 256 and row byte offsets fit
uint32. It uses scalar pointers, packed 128-bit loads, F16/F32 mixed FMAs and
eight or sixteen weights per lane without increasing the resident worker's
scratch register budget. Inactive waves skip scalar loads explicitly. `gpu_rdna_gemv_grid_f16(index,step)` hoists that descriptor once and walks
all assigned output rows using scalar loop state. `gpu_rdna_rms_stage_f16(row,step)`
retains four inputs per thread for a 2048-wide RMSNorm row in a full 512-thread
block. The GPU OS adapter retains ordinary Flexscript for other dimensions.
`gpu_rdna_rms_head_f16(index,step)` normalizes a 128-element FP32 head with F16
weights in one complete wave, retaining the portable FP32 reduction order.
`gpu_rdna_attention_f32(index,step)` computes a complete 512-thread,
128-dimensional attention head tile with sixteen online-softmax partials and
an ordinal LDS merge. `gpu_rdna_element_f32(index,step)` handles FP32 adds,
multiplies, SiLU, copies, F16 embedding gathers and KV row appends.
`gpu_rdna_rope_f32(index,step)` computes split-half rotary pairs. Mutable token
and position words use vector loads whose visibility is acquired by the grid
barrier; scalar cached loads are reserved for immutable descriptors.
`gpu_rdna_stage(step)` selects and walks these stages with scalar tile bounds
for a complete active block. Matrix and RMS shape checks retain portable
Flexscript fallbacks for other widths. The unprofiled shared scheduler hoists
its immutable schedule pointer/count and avoids per-stage profiling branches.
These adapters preserve the portable FP32 operation/reduction order.

Independent attention K/V reads are issued before their FP32 consumers without
changing accumulation order. Proven-zero upper words avoid redundant writes;
facts are discarded at control-flow and EXEC boundaries.

Four whole-kernel fast paths in `lib/rdna.flex` provide F16 GEMV, paired gate/up
MLP, packed Q/K/V GEMV and 2048-wide residual RMSNorm. Linear kernels use one
wave per output row, scalar row pointers, eight F16 weights per lane (sixteen
for GEMV widths divisible by 512), and FP32 accumulation. Their blocks must
be one dimensional, 32–1024 threads and a multiple of 32; count is rows × 32.
Widths are positive multiples of 256 and row byte offsets fit uint32.
Residual RMSNorm uses 128 threads per complete 2048-value row and 32 LDS bytes.
The ABI includes eight launch words and hidden HSA v5 block counts and sizes.

`--backend rdna` compiles every inference kernel directly. Compatible
row-major F16 operations use the compact fast paths; BF16, tiled storage and
other widths use ordinary direct word-IR emission. The AMD inference default
is `rdna`; `--backend hip` selects the LLVM route.
HIP still provides memory allocation, loading, launches and graphs in both modes.

## Requirements and commands

The tested machine is an AMD Radeon RX 9070 XT (RDNA4, gfx1201, wave32), Ryzen 9
5900X and ROCm 7.2.4. The implementation currently targets gfx1201; other AMD
architectures have not been validated. Direct mode loads `libamdhip64.so` for
execution. The `hip` route additionally needs `libhiprtc.so`
and `/opt/rocm/include` headers.
No hipBLAS or rocBLAS is needed for Flexscript inference.

```sh
build/flex --target hip examples/gpu/vector.flex -o build/vector.hip
build/flex --target rdna-gfx1201 examples/gpu/vector.flex -o build/vector.hsaco
build/flex --target rdna-gfx1201 libs/ml/llm/kernels/gemv-direct-rdna.flex -o build/gemv-direct.hsaco
build/flex llm.flex -o build/llm-chat
build/llm-chat --backend rdna --checkpoint build/llm/models/qwen3-1.7b
```

For a single prompt:

```sh
build/flex scripts/llm-infer.flex -o build/llm-infer
build/llm-infer --backend rdna --checkpoint build/llm/models/qwen3-1.7b \
  --context 256 --max-tokens 64 --prompt 'Say hello.'
```

`--backend hip` uses the same kernels through runtime source compilation.
Use `--backend rdna --weights f16` for the native compiler and F16 fast paths.
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
build/test-llm --backend rdna --compiler build/flex --gpu
build/flex scripts/test-llm-prefill.flex -o build/test-llm-prefill
build/test-llm-prefill --backend rdna --compiler build/flex --gpu
build/flex scripts/test-llm-context.flex -o build/test-llm-context
build/test-llm-context --backend rdna
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
The resident head RMS fast path also passes 33 CPU reference rows, incomplete
blocks, repeated calls in both branch arms, output guards and 48 live caller
values that push F16 operands above v127. Helper-copy and early-return fixtures
exercise divergent lanes, and shared/global read fixtures check both wait counters.

GPU execution requires access to `/dev/kfd` and the Radeon render device.
An execution sandbox hiding these devices cannot run these checks.
See [measured performance](llm-benchmark.md#rdna4-and-hip-2026-10-11) for the
workload, rates and comparison limits.

References: [HIPRTC](https://rocm.docs.amd.com/projects/HIP/en/latest/how-to/hip_rtc.html),
[AMD RDNA4 WMMA guide](https://gpuopen.com/learn/wmma-guide-amd-rdna-4-gpus-part-1/).
