# RDNA machine code and HIP

Flexscript supports two AMD GPU targets:

| Compiler target | Output | Runtime |
| --- | --- | --- |
| `hip` | HIP C++ source | HIPRTC compiles it when loaded |
| `rdna-gfx1201` | Native AMD HSA ELF code object (`.hsaco`) | HIP loads machine code directly |

Both lower the existing word IR, use `kernel(index,input,output,count)` and
support the GPU intrinsics in `lib/gpu.flex`. Helpers inline into the kernel.
Word arithmetic wraps at 64 bits; comparisons and division are signed.
Ordinary word loads/stores retain unaligned little-endian behavior.
Kernel-reachable allocation, syscalls, FFI, recursion and static data are rejected.

The native pipeline is **Flexscript → word IR → HIP source → HIPRTC/ROCm LLVM
→ gfx1201 machine code**. ROCm performs native instruction selection, register
allocation and binary packaging. This backend does not encode RDNA instruction
bytes itself. Offline code-object compilation requires no GPU context.

## Requirements and commands

The tested machine is an AMD Radeon RX 9070 XT (RDNA4, gfx1201, wave32), Ryzen 9
5900X and ROCm 7.2.4. The implementation currently targets gfx1201; other AMD
architectures have not been validated. It loads `libhiprtc.so` for compilation,
`libamdhip64.so` for execution, and uses headers at `/opt/rocm/include`.
No hipBLAS or rocBLAS is needed for Flexscript inference.

```sh
build/flex --target hip examples/gpu/vector.flex -o build/vector.hip
build/flex --target rdna-gfx1201 examples/gpu/vector.flex -o build/vector.hsaco
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

Device checks passed 10,248 HIP launch/graph/arithmetic comparisons, 27,805 LLM numerical
checks, 1,188,405 prefill/conversion checks and 16 focused greedy-sampler cases.
Real Qwen generation produced “Hello! How can I assist you today? 😊”.
The compiler rebuilds itself byte-for-byte. Native code objects were inspected
as AMD HSA ELF and disassembled to confirm RDNA4 WMMA instructions.
Large-context checks cover retained attention at 4K, 8K, 32K and the final
40,960-token slot, along with tokenizer/report growth and an actual 8,213-token
Qwen prompt. The full 40,960-token model context has not been allocated in this
test; automatic sizing selected the smaller context that fits current VRAM.

GPU execution requires access to `/dev/kfd` and the Radeon render device.
An execution sandbox hiding these devices cannot run these checks.
See [measured performance](llm-benchmark.md#rdna4-and-hip-2026-10-11) for the
workload, rates and comparison limits.

References: [HIPRTC](https://rocm.docs.amd.com/projects/HIP/en/latest/how-to/hip_rtc.html),
[AMD RDNA4 WMMA guide](https://gpuopen.com/learn/wmma-guide-amd-rdna-4-gpus-part-1/).
