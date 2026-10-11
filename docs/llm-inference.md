# Qwen3 inference through direct SASS or CUDA PTX

`libs/ml/examples/qwen3-inference.pup` runs Qwen3-1.7B with a native Flexscript
host, a native ByteLevel BPE tokenizer, resident 16-bit checkpoint weights, FP32
activations and a retained FP32 KV cache. The inference path needs the NVIDIA
driver / `libcuda.so.1` and GLib's Unicode/regex functions. Select direct SASS
with `--backend sass` (default), or driver-compiled PTX with `--backend cuda`.
Neither mode invokes external ptxas, CUDA C++, cuBLAS, Python, Rust or an
external ML runtime.

The three layers are explicit:

1. The `.pup` file defines embedding, RMSNorm, linear projections, split-half
   rotary positions, grouped attention, SiLU, multiplication and residual adds.
   A static layer loop expands this model into a tensor schedule.
2. `libs/ml/llm/pup.flex` checks shapes and chooses reusable kernel templates.
   Matrix-vector products assign one warp to an output row and use aligned
   packed loads when the inner dimension is divisible by four. RMSNorm uses
   packed loads with one warp per 128-wide head or a 128-thread block for larger
   rows. Attention assigns sixteen warps to each head,
   merges online softmax partials in shared memory and needs no score matrix.
   A schedule pass fuses head normalization with rotary embedding, paired MLP
   projections with SiLU/multiplication, adjacent Q/K/V projections, and residual
   addition with normalization.
   Each fusion preserves intermediate tensor outputs for other graph consumers.
   Weights and per-attention KV allocations stay resident between tokens.
3. The ordinary Flexscript GPU compiler emits SM75 cubins or PTX from the same
   `libs/ml/llm/kernels/*.flex`; `lib/cuda.flex` loads and launches them. In CUDA
   mode the NVIDIA driver compiles PTX into machine code for the device.
   Direct-SASS compiler passes propagate copies and zero values, remove dead instructions, fold
   constant load offsets, eliminate unreachable helper epilogues and empty branches,
   allocate register pairs and schedule dependencies.
   Address-read and result-write scoreboards allow independent memory operations
   to overlap. Descriptors travel as eight by-value launch words. CUDA graphs replay the
   complete schedule for each token. Batched prefill expands the original
   schedule before decode fusion, tiles matrix products across output rows and
   prompt positions, splits K deterministically, and constructs causal KV rows.
   Scratch allocations are reused after their last consumer. A separate CUDA
   graph captures each prepared prompt shape, with pinned token uploads.

These execution choices do not require edits to the `.pup` model definition.
Changing reduction order can produce small floating-point differences; tests
check numerical tolerance and greedy outputs against independent references.

This inference Pup subset has its own library planner. It is not yet merged
with the MNIST Pup frontend, and does not support arbitrary Python, user-defined
Pup functions, nested loops, dynamic batches or the full Puppygrad grammar.
Model operators live in the ML library; the core compiler additions are general
packed-memory, launch-argument and floating-point intrinsics.

## Build and run

### Interactive chat

The root `llm.flex` builds a terminal chat application using the reusable
[native TUI library](tui.md):

```sh
build/flex-llm llm.flex -o build/llm-chat
build/llm-chat --checkpoint "$QWEN_CHECKPOINT" --backend sass
# Or select driver-compiled PTX:
build/llm-chat --checkpoint "$QWEN_CHECKPOINT" --backend cuda
```

It streams replies, warms and retains the model/tokenizer/kernels, supports
multiline editing and prompt history, mouse selection/copy, clipboard paste,
scrolling, cancellation, saved conversations and resume. Conversation history
is included in each request. Oldest user/assistant pairs leave the active
context when needed, while remaining in the saved transcript. Each request
rebuilds prompt KV rows from position zero; prompt graphs and scratch buffers
are released afterward, while model weights and decode graphs stay resident.

The default context and reply length are both `auto`. The worker plans the
actual Pup schedule, queries free GPU memory, and chooses a context that fits
weights, KV cache, rotary tables and worst-case prefill scratch. It leaves
10% of GPU memory, or at least 512 MiB, for driver overhead and other apps.
The current engine ceiling is 4096 tokens, including prompt, reasoning and
answer. Replies continue until EOS or the remaining context is used.
Use `--context auto|32..4096`, `--max-tokens auto|N`, `--weights` and `--device`
(CUDA ordinal) at startup. Explicit contexts are checked against the memory
budget too. Free memory is checked again before each prefill; if other apps
consume the reserved working space, the prompt fails with a recoverable message.
`--no-warmup 1` defers model loading until the first prompt. Without an explicit
checkpoint, it checks `QWEN_CHECKPOINT`, then the existing pinned Puppygrad cache,
then `build/llm/models/qwen3-1.7b`. `/download` downloads the pinned manifest's
assets there using resumable curl transfers; downloads are initiated explicitly.
`/models` reports the currently supported Qwen3-1.7B recipe and asset readiness.
No new model architectures, CPU/HIP backends or model file tools are introduced.

| Commands | Purpose |
| --- | --- |
| `/backend sass|cuda`, `/device N`, `/weights FORMAT` | Reload with selected execution settings |
| `/thinking on|off` | Select Qwen3 thinking prompt format |
| `/temperature 0..2` | Greedy at zero (default); top-40 temperature sampling otherwise |
| `/tokens auto|N` | Use available context or set an output cap |
| `/new`, `/clear` | New conversation, or clear display while retaining history |
| `/sessions`, `/resume latest|ID`, `/history` | Browse/resume saved chats and show storage |
| `/logs`, `/help`, `/quit` | Activity, controls and exit |

Enter submits; Ctrl+J or Alt+Enter inserts a newline. Arrows edit, Up/Down
move between wrapped composer rows and recall prompts at the edges;
Shift+arrows select, and Tab completes slash commands.
Ctrl+A selects the composer, Ctrl+C copies selection or quits, Ctrl+X cuts,
and Ctrl+V pastes. Mouse drag copies on release; right-click in the composer
pastes. Escape requests cancellation at the next token boundary; cancelling
loading stops the worker. PageUp/PageDown and the mouse wheel scroll.

Assistant reasoning appears in a collapsed Thinking block, with the answer
visible below it. Click the `[+] Thinking` / `[-] Thinking` header to expand or
collapse it; Ctrl+T toggles the latest block. This also works while reasoning
is still streaming. Folding only changes the display; full text stays in saved
conversations and model context. `/thinking on|off` controls model generation.

`/models`, `/sessions`, `/history` and `/help` open temporary panels just above
the composer, growing upward as needed. Arrows, PageUp/PageDown and the mouse
wheel scroll long panels. Escape closes a panel; typing closes it and edits
the composer. Panel contents are not added to conversation history.
Typing `/models` or `/model` previews the models panel before submission,
including commands completed with Tab or pasted into the composer.

Busy operations show a spinner, elapsed stage time and an activity bar. Kernel
compilation reports kernels completed; weight uploads report bytes transferred;
weight preparation and rotary tables report completed work. Downloads report
files completed (individual transfers continue animating). Tokenizer loading,
GPU initialization, graph preparation, warmup and prefill animate without an
estimated percentage. Indicators clear when the operation finishes or stops.

Chats autosave as private JSON files under `build/llm/sessions`, using a
temporary file and atomic rename. `--history-dir` selects another directory;
`--resume latest` restores a chat at startup. Cancelled partial replies are
saved. The transcript is limited to 1000 messages; `/new` starts another file.
Worker errors appear in the UI and `/logs`, leaving the terminal usable.
Displayed timing includes tokenization, prompt preparation, sampling and
logit downloads, unlike the resident benchmark below.

`build/llm-chat --demo 1` exercises the UI with a clearly marked synthetic
worker, without GPU access or checkpoint loading. Integration checks are:

```sh
python scripts/test-llm-tui.py
build/flex-llm scripts/test-llm-capacity.flex -o build/test-llm-capacity
build/test-llm-capacity
python scripts/test-llm-tui.py --gpu --checkpoint "$QWEN_CHECKPOINT"
```

The GPU checks exercise both backends, baseline token IDs, multi-turn input,
oversized prompt rejection, cancellation/recovery and prompt-memory cleanup.
The checked-in `libs/ml/llm/tests/chat.json` supplies the token regression
fixture; no local benchmark report is required.

### Single-prompt CLI

From the repository root, with an existing Flexscript compiler:

```sh
build/flex compiler/main.flex -o build/flex-llm
build/flex-llm scripts/llm-infer.flex -o build/llm-infer
```

Use the Hugging Face checkpoint files identified in
`libs/ml/examples/qwen3-1.7b.model.json`. The revision is pinned to
`70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`. Existing Puppygrad downloads can be
used directly; neither a format conversion nor another download is needed.

```sh
QWEN_CHECKPOINT=/path/to/Qwen3-1.7B
build/llm-infer --checkpoint "$QWEN_CHECKPOINT" \
  --prompt 'Explain what a GPU kernel is in two sentences.' \
  --max-tokens 64 --context 256 --report build/llm/chat.json
```

Choose the backend independently from the model and weight layout:

```sh
# Direct SM75 machine code, validated on RTX 2070.
build/llm-infer --backend sass --checkpoint "$QWEN_CHECKPOINT"
# PTX compiled by the NVIDIA driver for the installed GPU.
build/llm-infer --backend cuda --checkpoint "$QWEN_CHECKPOINT"
```

Both modes use CUDA for allocation, transfers, launches and graph replay.
CUDA mode needs no CUDA toolkit or `nvcc`; it emits `.ptx` modules instead of
`.cubin` files and loads them through the same Driver API. The current kernel
instruction set requires compute capability 7.5 or newer. Direct SASS requires
SM75 and reports an error suggesting `--backend cuda` on other architectures.
The CUDA path is intended to support newer NVIDIA GPUs through PTX compilation;
physical validation so far is on RTX 2070, with the same 60 greedy chat IDs as
the original SASS run. Other architectures still need device validation and
performance tuning. Reports record `backend` (`sass` or `cuda`) and `target`
(`sass-sm75` or `ptx`), including plan-only reports.

Backend integration checks cover CUDA inference in both FP16 layouts, default
SASS inference, GPU-free CUDA planning, invalid backend rejection, and CUDA
benchmark/profiler execution. Both CUDA layouts match the independent CPU
oracle's argmax and top-five lists at four retained-cache predictions; maximum
absolute logit error is 0.007731 under the FP16-product 0.02 limit. Local evidence
is in `build/llm/cuda-backend-chat.json`, `backend-logit-validation.json`,
`cuda-backend-plan.json`, `cuda-backend-benchmark.json` and
`cuda-backend-profile.json`.

The default chat wrapper supplies an empty completed thinking block, matching
Qwen3's non-thinking format. `--raw 1` passes the prompt without a chat wrapper.
Generation is greedy and stops on the end-of-message/end-of-text token or the
token limit. `--context` reserves KV slots; prompt length plus maximum generated
length must fit. Prefill defaults to a batched tensor schedule, with FP16 tensor-core products
and FP32 accumulation. Only the final prompt row runs the vocabulary projection.
`--prefill serial` retains the original FP32 matrix-vector prefill path.

`--weights f16` (default) converts BF16 checkpoint data once, in place on the
GPU, to FP16 storage. `--weights bf16` retains the original BF16 storage and
FP32 decode arithmetic. `--weights f16-tiled` additionally packs projection
weights into 16-row by 8-column tiles, improving prefill memory access. Decode
uses matching tiled matrix-vector kernels; embeddings, normalization vectors
and the tied vocabulary matrix remain row-major. Tiling temporarily allocates
one matrix during loading, then releases it; it does not retain another copy of
the model. The tiled layout trades decode speed for prefill latency on the RTX
2070, so it is selectable rather than the default.

FP16 staging changes numerical behavior: values outside the FP16 range can
overflow or underflow, and batch linear inputs are rounded to FP16. It is
validated for the pinned Qwen3-1.7B checkpoint. `--weights bf16 --prefill serial`
retains the original BF16/FP32 numerical path. All modes keep the KV cache in
FP32 and leave the Pup model definition unchanged.

The initial recipe requires Qwen3 text checkpoints with BF16 weights, 128-wide
heads, bias-free full attention, no rotary scaling and `rope_theta=1000000`.
It supports one sequence, context capacities up to 4096, and power-of-two GQA
head ratios. Physical testing used Qwen3-1.7B on an RTX 2070 (SM75). Other
architectures, quantization formats and GPU targets have not been validated.
When the configuration ties output and embedding weights, they share a device
allocation. The pinned checkpoint's two copies were checked byte-for-byte.

Validate the model and inspect the schedule without a GPU or driver:

```sh
build/llm-infer --checkpoint "$QWEN_CHECKPOINT" --plan-only 1 \
  --context 256 --report build/llm/plan.json
```

This reads checkpoint metadata, validates the Pup graph, emits cubins or PTX
and reports planned memory and launch geometry. It does not execute inference.
The JSON schedule is an inspection report; the runner rebuilds its schedule
when executing a model.

## Validation

```sh
build/flex-llm scripts/test-llm.flex -o build/test-llm
build/test-llm --compiler build/flex-llm
build/test-llm --compiler build/flex-llm --gpu

build/flex-llm scripts/test-llm-prefill.flex -o build/test-llm-prefill
build/test-llm-prefill --compiler build/flex-llm

build/flex-llm scripts/test-llm-tokenizer.flex -o build/test-llm-tokenizer
build/test-llm-tokenizer --tokenizer "$QWEN_CHECKPOINT/tokenizer.json"
```

The device-free tests check static layer expansion, seven malformed programs,
and emission of all kernel templates through both SASS and PTX. GPU tests compare
nonuniform GEMV at full model widths, partial final blocks, RMSNorm, nonzero
rotary positions, multiple GQA heads, nine cache lengths and cache writes against
independent references. Fused kernels also check every retained intermediate
output, including exact F32 residual additions. PTX is an optional test oracle;
production generation uses SASS.
Tokenizer goldens cover multilingual text, emoji, NFC normalization, special
tokens, contractions, whitespace, digits and ASCII controls. They were produced
with Hugging Face `tokenizers` 0.23.3 against the pinned tokenizer.

For an independent full-model comparison, the optional Python verifier needs
NumPy. Python is only used for this numerical oracle:

```sh
build/llm-infer --checkpoint "$QWEN_CHECKPOINT" --raw 1 \
  --prompt 'Hello world' --max-tokens 4 --context 32 \
  --logits-prefix build/llm/cache- --report build/llm/cache.json
python scripts/llm-reference.py --checkpoint "$QWEN_CHECKPOINT" \
  --report build/llm/cache.json --logits-prefix build/llm/cache- \
  --output build/llm/cache-reference.json
```

The oracle computes the model independently with NumPy. By default it reads
`weight_storage` and `prefill_mode` from the inference report, reproducing FP16
weight staging and FP16 prompt products when selected, with FP32 accumulation.
`--math fp32` instead uses the original BF16 weights and FP32 products. It
checks every vocabulary logit, greedy selection and records the top five across
prefill and subsequent retained-cache decode steps. It does not claim bitwise
agreement with a framework executing all intermediate operations in BF16.
The verifier retains the 0.002 absolute-logit limit for serial FP32 math. For
FP16 prompt products it uses an explicit 0.02 limit: tiny normalization and
reduction differences can cross an FP16 rounding midpoint and propagate.
Reports state the numerical mode, limit, measured errors and greedy choices.
These bounds are not an equivalence proof for arbitrary prompts or models.
`--logits PATH` saves only the first prediction; `--logits-prefix PREFIX` saves
every generation prediction. Reports record input/output IDs, output text,
resident allocation bytes, kernel launches, prefill and decode wall times.
Decode throughput counts subsequent model executions; the first generated
token comes from prefill. Allocation totals are our resident CUDA buffers, not
sampled process/driver peak VRAM.

On the RTX 2070, the initial implementation passed 6,219 planning/GPU checks and
143 tokenizer checks. Four retained-cache predictions matched all four CPU
argmax and top-five lists; maximum absolute logit error was below 0.000069.
A 60-token answer completed at approximately 11 decode tokens/second. Runtime
speed depends on context, clocks and competing desktop workloads; this is a
correctness-first baseline, with 563 kernel launches per model execution.

## Speed measurements

Use the native benchmark runner to time resident model execution separately
from tokenization, sampling, logits downloads and text output:

```sh
build/flex-llm scripts/bench-llm.flex -o build/bench-llm
build/bench-llm --checkpoint "$QWEN_CHECKPOINT" \
  --tokens build/llm/chat.json --decode 64 --context 256 --repeats 3 \
  --report build/llm/benchmark.json
```

The token fixture is an inference report containing `input_ids` and
`generated_ids`. Every repetition overwrites the cache from position zero,
prefills the input IDs and executes the requested number of decode steps,
cycling through the supplied generated IDs. It does not stop on EOS or sample
new tokens. One full warmup run is excluded. The report records individual
wall times, including host launches and GPU synchronization. Loading and
kernel compilation occur before timing.
Add `--backend cuda` to select driver-compiled PTX; it also works with
`--weights f16-tiled`. Kernel loading and driver JIT occur before timed samples.
The existing llama.cpp comparison measurements use the direct-SASS backend;
they do not establish the performance of the selectable CUDA backend.

The benchmark accepts `--fusion MASK` for lowering comparisons with the same
Pup graph: bit 1 enables normalization/rotary and adjacent Q/K/V projection fusion,
bit 2 paired MLP fusion,
and bit 4 residual/normalization fusion. The default is 7; 0 disables the
schedule rewrites. Reports record the mask and resulting kernel count. The
Qwen3-1.7B recipe now executes 311 kernels per token, down from the original 563.

The [RTX 2070 comparison with llama.cpp](llm-benchmark.md) records the measured
baseline and its precision and scheduling differences.

## Packed memory and SFU intrinsics

The GPU library additionally exposes:

- `gpu_load_u32(pointer)` and `gpu_store_u32(pointer,value)`: four-byte-aligned
  global words. The store writes the low 32 bits and returns the input word.
- `gpu_load_bf16(pointer)`: a two-byte-aligned global BF16 load, expanded exactly
  into the low 32 bits of a word containing an FP32 bit pattern.
- `gpu_f32_exp2_approx`, `gpu_f32_rcp_approx` and `gpu_f32_rsqrt_approx`: native
  approximate SFU operations, with subnormal flushing. They are separate from
  the existing correctly rounded divide/sqrt operations. CPU execution exits
  78 explicitly.
- `gpu_load_u16(pointer)` and `gpu_load_u64(pointer)`: aligned two-byte and
  eight-byte global words, respectively. The U16 load zero-extends its result.
- `gpu_f32_max(a,b)`: native numeric maximum. A lone NaN yields the numeric
  argument; positive zero wins over negative zero. NaN payloads are not portable.
- `gpu_warp_sum_f32(value)`: broadcasts the FP32 XOR-tree sum, with offsets
  16, 8, 4, 2 and 1. All 32 lanes must participate; high input bits are ignored.
- `gpu_launch_word(index)`: reads one of eight by-value kernel arguments, with
  the index wrapping modulo eight. These kernels use `cuda_launch_words` or
  eleven matching raw parameter pointers.
- `gpu_load_stream_u64(pointer)`: an aligned eight-byte word using L2 caching
  while bypassing L1, suitable for weights streamed once per model execution.
  It retains ordinary load semantics and has a CPU reference fallback.

Both PTX and SM75 backends lower these intrinsics. Existing unaligned `load64`
and `store64` semantics are unchanged. Warp reductions require full participating
warps. Matrix-vector launches use 32 threads per row, grouped into 256-thread
blocks for packed GEMV and paired MLP projections. Fused head normalization and
rotary use one 32-thread block per head. Larger RMSNorm and residual/normalization
launches use 128 threads per row and 32 shared bytes per block. Attention uses
512 threads per head and 16640 shared bytes per block.

Architecture references: [official Qwen3 model](https://huggingface.co/Qwen/Qwen3-1.7B),
[Transformers Qwen3 implementation](https://github.com/huggingface/transformers/blob/main/src/transformers/models/qwen3/modeling_qwen3.py),
[Turing instruction encodings](https://github.com/daadaada/turingas/blob/master/turingas/grammar.py),
[GLib regex API](https://docs.gtk.org/glib/struct.Regex.html).

## Batched prefill constraints and profiling

The current batch planner prepares one sequence starting at KV position zero
and one fixed prompt length per model instance. Replays of that shape overwrite
those cache positions. Subsequent decode uses the same cache allocations and
continues at the prompt length. A different prompt length needs a new model
instance. Prompt graph preparation and upload occur before benchmark timing.

The default chooses K partitions from matrix height and prompt length, aiming
for at least 512 warp tiles while keeping inner chunks divisible by eight.
Matrix inner widths must be divisible by eight times the selected partition
count. The benchmark's `--prefill-split auto` or `--prefill-split 0..5` changes
this lowering choice without changing the Pup model. Serial prefill remains available for unsupported batch shapes.
Tensor-core warp tiles cover 16 output rows and 24 prompt positions. Tiled
activation staging pads the prompt to a multiple of 24, initializes padding to
zero, and guards all logical outputs. FP32 partial sums are reduced in a fixed
order without atomics. The final vocabulary GEMV consumes the last FP32 row. Tiled lowering also
fuses normalization with FP16 staging and reduction with adjacent SiLU/product
operations, retaining all original FP32 outputs. Product epilogues can stage the
next matrix input directly. Padding is initialized even in these fused paths.

The batch suite checks every FP16/BF16 conversion encoding, FP32 rounding
boundaries, partial matrix tiles, K partition counts, full model inner widths,
causal attention and tiled decode projections on both native SASS and PTX.
The same PTX kernels are selectable for inference with `--backend cuda`;
the CPU oracle remains an independent validation tool.

Profile either schedule with `scripts/profile-llm.flex --mode prefill` or
`--mode decode`, adding `--weights f16-tiled` for tiled storage or
`--backend cuda` for driver-compiled PTX. Per-stage CUDA
events add instrumentation overhead; use the resident benchmark for speed
comparisons. Its samples now include microsecond wall times alongside integer
millisecond fields.
