# Resident GPU runtime

This prototype runs Qwen's token loop inside one GPU program. The host
loads weights, prepares the prompt and submits a bounded request. GPU workers
execute the model schedule, update the KV cache, choose the next token and
publish tokens in shared memory until EOS, cancellation or the request limit.
The host polls for output; it launches the resident program once per request.

## Run Qwen

The interactive chat selects a supported runtime automatically:

```sh
./build/flex llm.flex
```

The default `--runtime auto` prefers GPU OS with `rdna`, F16 weights and
a compatible gfx1201 device. It checks cooperative launch, native host atomics,
wave32 and the GPU clock. It builds the shared Flexscript scheduler automatically.
The default worker compiler is HIP on AMD. Native greedy Qwen3-1.7B
decoding now has a small measured lead in the comparison below; use
`--gpu-os-target rdna` to select it. Automatic runtime selection falls back
to graph if that build fails. F16 HIP/RDNA and CUDA configurations may also
use GPU OS when their device
passes the capability checks; other weights use graph. CUDA/PTX support is
implemented but has not been run on NVIDIA hardware here.
In an existing chat, use `/runtime gpu-os` to force it, `/runtime graph` to
return to graph execution, or `/runtime auto` to restore automatic selection.
The title shows `gpu-os` when selected. Streaming, Esc cancellation, model
selection, saved sessions and thinking use the ordinary chat interface.
Greedy selection and temperature sampling both run on the GPU; the latter uses
the same top-40 policy as graph chat, with a persistent random seed.

The monitor and self instrumentation are off by default. Use `/monitor on`
or start with `--monitor on` to enable them. The worker instruments itself and streams per-token
timings into the right-hand panel. At 150 columns and 44 rows, all eight aligned
history tracks fit: matrix operations, attention, grid waits, sampling,
normalization, rotary embeddings, elementwise operations and worker work.
Smaller windows show the tracks that fit. Each horizontal step is a token
interval, with height showing its measured time percentage. `/monitor off`
disables instrumentation on the next reply.
Drag the monitor's vertical divider to change its width. Graphs expand with
the column, up to 64 history samples; chat text rewraps without changing input.

The standalone example remains available:

Run from the Flexscript repository root, with ROCm installed and the Qwen3
checkpoint already downloaded:

```sh
build/flex libs/os/gpu/build.flex
./build/flex libs/os/gpu/qwen.flex -o build/gpu-os/qwen
./build/gpu-os/qwen \
  --checkpoint build/llm/models/qwen3-1.7b \
  --prompt 'What is 2 plus 3? Answer briefly.' \
  --context 256 --max-tokens 32
```

The example automatically builds the worker if its code object is missing.
Use `--rebuild 1` after changing worker sources. Model kernels are compiled with
the existing direct RDNA target; the example uses the original Qwen3 model
schedule and F16 weights. A Qwen3-4B checkpoint can be selected with
`--checkpoint /path/to/qwen3-4b`.

`--verify 1` compares the generated token IDs with the existing decoder on the
same prompt. `--cancel-after 4` exercises the cancellation doorbell. `--report`
selects the JSON output file; the default is `build/gpu-os/report.json`.
Add `--profile 1` to include the last 64 GPU timing records in that report.
Standalone profiling is disabled by default.

## Shared source and backend adapters

The scheduler is now Flexscript: token generation, sampling, cancellation and
profiling share the same source across compiler routes. Host transport and
worker compilation are separate choices:

| Worker compiler | Host transport | Current scope |
|---|---|---|
| `hip` | HIP | Tested greedy/top-40 sampling, cooperative synchronization |
| `rdna` | HIP | Tested gfx1201 greedy decoding; software grid barrier |
| `ptx` | CUDA | Full scheduler emitted; driver JIT; no NVIDIA hardware test yet |
| Direct SASS | CUDA | Adapter boundary prepared; resident synchronization port remains |

`--backend` still selects the ordinary model/prefill kernel target.
`--gpu-os-target auto|hip|rdna|ptx` independently selects the resident
worker compiler. `auto` currently chooses HIP on AMD and PTX on CUDA.
Native RDNA is available explicitly; the current measured lead covers greedy
Qwen3-1.7B on gfx1201.

To run the shared scheduler directly on AMD:

```sh
build/flex llm.flex --runtime gpu-os --gpu-os-target rdna
```

Greedy requests use direct AMD machine code. Temperature requests use a
HIP-compiled worker built from the same Flexscript sources, retaining model,
KV and mailbox allocations; returning to greedy restores the native worker.
Worker events report the actual `worker_target` for each completed request.
The native scheduler currently lacks FP64 sampling operations, so this
fallback is deliberate. The chat builder prepares both artifacts for this
choice. Direct AMD emission itself needs no LLVM, assembler or linker.

For an entirely LLVM-free worker build, without preparing a sampling fallback:

```sh
build/flex libs/os/gpu/build.flex --target rdna --fallback none \
  --output build/gpu-os/direct-only
build/gpu-os/qwen --image build/gpu-os/direct-only/resident.hsaco \
  --verify 1 --context 256 --max-tokens 32
```

An optional `--fallback hip` prepares a sampling worker alongside the native
artifact. `--target hip` remains available explicitly. CUDA output uses
`--target ptx --driver cuda`. Direct SASS resident workers are rejected clearly
until their synchronization primitives are ported; the ordinary SASS model
kernel backend is unchanged.

- `resident.flex`: shared scheduler, RMS normalization, token publication and profiling.
- `sampling.flex`: shared binary64 top-40 selection and RNG.
- `sync.flex`: portable generation barrier for an entirely resident grid;
  HIP substitutes its cooperative-group barrier through a compiler intrinsic.
- `driver.flex`: HIP/CUDA module, mapped-memory, launch and resource adapters.
- `runtime.flex`: backend-independent request allocation, schedule upload,
  polling, cancellation, fallback selection and cleanup.
- `build.flex` and `build-lib.flex`: composes existing Flexscript model functions with the scheduler
  and selects its compiler. Artifact directories are separate by target; a
  source/compiler fingerprint avoids unnecessary rebuilds, with locked builds
  and atomic publication.
- `benchmark.flex`: alternates native and HIP standalone requests, checks token
  identity and saves raw timings; optionally includes an older native artifact.
- `qwen.flex`: runnable Qwen example with streaming and optional comparison.
- `tests.flex`: deterministic protocol, backend-switching and timing-ring tests.

There is no handwritten HIP C++ scheduler. HIP source remains generated output
when using the HIP compiler route. The system/device acquire-release operations
and GPU clock are explicit compiler intrinsics, keeping synchronization and
memory publication semantics out of the model code. CUDA uses nanosecond
`globaltimer` calibration; AMD uses its device-reported wall clock.

The native scheduler passes Qwen3-1.7B token comparisons against the existing
decoder. Compiler load scheduling and an embedded RDNA GEMV primitive roughly
doubled native throughput in the earlier alternating benchmark below. Further
native attention, element, rotary and uniform stage adapters now bring it
slightly ahead of HIP in the latest matched Qwen3-1.7B measurements.

## Request protocol

ABI v1 uses a 192-byte coherent, mapped mailbox with aligned 64-bit fields.
It contains status, cancellation, reason, published token count, request limits
and pointers to the GPU schedule/state/logits. Reserved fields carry temperature
in thousandths, the random seed updated after GPU sampling, and an optional
profile-ring device pointer. An append-only token buffer
follows the header, sized to context capacity, so publication cannot overwrite
unread output. `produced` is released after writing a token; the host acquires
the count before reading tokens. Linux x86-64 host memory ordering and
system-scope GPU atomics provide publication ordering.

Status values: `0` submitted, `1` running, `2` completed, `3` failed.
Reason values: `0` token limit, `1` EOS, `2` cancelled, `3` context limit,
`4` nonfinite logits. `go_wait` joins the request before the mailbox is reused.
`go_close` cancels and joins an active request before freeing its allocations.

Workers use a cooperative grid barrier between dependent schedule operations.
All 512 threads participate in block collectives. The runtime validates the
device's cooperative-launch, native-host-atomic and wave32 capabilities and
checks that the worker has resident occupancy. The default is one worker per
reported compute unit. Pure native RDNA allows an explicit `--workers N` up to
two resident blocks per unit, capped at 112 blocks; HIP and a prepared HIP
sampling fallback retain the one-worker limit. A larger occupancy-derived grid
stalled synchronization on the tested gfx1201 device, so it is not selected
automatically.

Native RDNA uses a bounded 32-bit phase/count word at `work+736`. The last
block publishes the full 64-bit generation at `+968` before flipping the phase
and releasing peers; `+960` stays reserved and zero. The host clears the scratch
region before every launch. Visibility tests cover 1–32 workers, partial worker
groups, low-word and full 64-bit generation wrap. HIP uses its cooperative
barrier and PTX uses the shared software barrier.

## Self instrumentation

The resident worker reads the GPU wall clock around scheduled operations and
external grid barriers. Each block leader accumulates its own work and wait
times. Worker zero publishes a 128-byte record per token into a separate coherent
64-slot ring; sequence numbers let the host reject overwritten or incomplete
records. The host polls records while tokens stream, without launching another
GPU kernel or synchronizing the running request. Profiling adds clock reads,
counter updates and a grid barrier per token, so it has some overhead.

Stage percentages describe worker zero. Worker work shows the mean scheduled
work time across workers as a fraction of the token interval, alongside the
minimum and maximum worker fractions. These timings include synchronization
inside operations: sampling includes its internal grid barriers, and operation
work can include block barriers. External stage grid waits have their own track.
Unclassified scheduler/publication overhead means percentages need not total
100%. The first token uses prefill's existing logits, so its record measures
sampling rather than a full decode step. Prefill is outside this timing ring.

These are measurements of the program's progress, not hardware lane activity
or wave occupancy. No profiler SDK or hardware counter collection is required.

## Current scope

The tested worker targets gfx1201 and the host adapters target Linux x86-64. Qwen3
uses F16 weights, FP32 activations/KV, greedy or top-40 temperature sampling and an unfused model
schedule. Prompt prefill continues to use the existing GPU graph. The worker
lives for a generation request and exits afterward, leaving resources available
for the next prefill. The default chat policy is `auto`, preferring GPU OS on
compatible direct RDNA/F16 configurations. It uses graph elsewhere and can be
overridden explicitly. Worker compilation is selected separately as described above.

Future work includes native scheduler performance tuning, native FP64 sampling,
SASS synchronization, fused resident operations and longer-lived workers that can
coexist with prefill. Further changes need measurement against the current fused decoder; removing
host launches alone does not establish a speed advantage.

## Shared-scheduler benchmark

A matched chat benchmark on 2026-10-13 used Qwen3-1.7B F16 on the RX 9070 XT,
context 1024, greedy sampling and 128 generated tokens. Graph and the shared
Flexscript HIP scheduler remained loaded; three measured requests per
configuration alternated after a warmup. All prompt and generated token IDs
matched. Median decode rates exclude prefill and the first selected token,
but include sampling and streaming:

| Prompt tokens | Graph | Shared Flexscript HIP worker | With profiling |
|---:|---:|---:|---:|
| 41 | 137.6 steps/s | 156.6 steps/s | 151.1 steps/s |
| 378 | 122.1 steps/s | 151.5 steps/s | 146.5 steps/s |

The shared HIP worker led graph by 13.8% and 24.1% in these workloads;
profiling reduced throughput by about 3.3–3.5%. First-token latency was similar.
These results cover two short-context workloads on this machine, with automatic
GPU clocks, and do not establish results for other models or long contexts.
Native RDNA was slower in that initial implementation; the latest comparison
is below.
Reproduce with `python scripts/benchmark-llm-runtimes.py --rounds 3`.
Raw samples and the summary are saved under
`build/gpu-os/flexscript-scheduler-benchmark/`.

## Native compiler tuning benchmark

On 2026-10-13 the standalone host alternated the earlier native worker, the
optimized native worker and shared HIP worker, using Qwen3-1.7B F16, context
1024, greedy sampling, profiling off and 128 generated tokens. Each prompt had
one warmup and three measured requests per worker. Every generated token ID
matched across all 24 requests. Each request reloads the model; decode timing
excludes loading, prefill and the first token but includes sampling/publication
and host polling. This differs from the concurrently loaded chat benchmark
above, so compare rates within each table.

| Prompt tokens | Earlier native | Optimized native | HIP | Native improvement |
|---:|---:|---:|---:|---:|
| 41 | 57.3 steps/s | 112.0 steps/s | 141.6 steps/s | +95.5% |
| 378 | 60.0 steps/s | 112.6 steps/s | 147.8 steps/s | +87.7% |

The compiler batches independent loads, replaces signed power-of-two division
with shifts and uses scalar pointer arithmetic and packed mixed FMAs inside the
resident GEMV adapter. This earlier worker used a software grid barrier and 128
VGPRs. The native build invokes no Python, LLVM, assembler or linker; HIP loads
and submits the resulting AMDHSA object. Native FP64 sampling remains pending.

Reproduce the current native/HIP comparison entirely through Flexscript:

```sh
build/flex libs/os/gpu/qwen.flex -o build/gpu-os/qwen
build/flex libs/os/gpu/benchmark.flex -o build/gpu-os/benchmark
build/gpu-os/benchmark --rounds 3
```

Add `--baseline /path/to/earlier/resident.hsaco` to include an older native
artifact with its `.target` sidecar. This run's raw reports are under
`build/gpu-os/tuning/benchmark-results/results.json`.

An additional matched run later on 2026-10-13 compared that 112-step/s native
artifact with the next compiler/scheduler version and a freshly built HIP
worker. The same two prompts, model, context, token limit and alternating
three-round procedure were used; all 24 requests produced identical token IDs.

| Prompt tokens | Previous native | Current native | HIP | Native improvement |
|---:|---:|---:|---:|---:|
| 41 | 112.1 steps/s | 131.7 steps/s | 142.9 steps/s | +17.5% |
| 378 | 112.7 steps/s | 133.6 steps/s | 148.9 steps/s | +18.5% |

The worker removes per-tile barriers from operations with independent outputs,
hoists matrix descriptors into uniform grid-strided loops, retains RMS inputs,
and batches attention K/V reads. Native synchronization uses hierarchical
arrival counters and explicit cache acquire/release ordering. The compiler
omits proven redundant zero-word writes and handles F16 conversions above v127.
That resident object used 144 VGPRs and 104 SGPRs. Native still needed
about 8.5% and 11.5% higher throughput respectively to reach HIP in these runs;
the automatic resident worker remains HIP. Raw reports are under
`build/gpu-os/tuning/final/results/results.json`.

The next tuning run on 2026-10-13 kept that 144-VGPR object as the baseline
and repeated the same alternating 24-request comparison:

| Prompt tokens | Previous native | Current native | HIP | Native improvement |
|---:|---:|---:|---:|---:|
| 41 | 131.6 steps/s | 134.0 steps/s | 143.0 steps/s | +1.8% |
| 378 | 132.6 steps/s | 134.6 steps/s | 147.8 steps/s | +1.6% |

The compiler gives each inlined function its own sized scratch area, copies
helper arguments directly when source/destination overlap permits it, and
leaves independent LDS reads outstanding. It exits helpers once every active
lane has returned. Attention batches independent shared partials while keeping
the original max/FMA order. A native 128-wide head RMS adapter retains the
portable FP32 accumulation and reduction order. The resident object now uses
124 VGPRs and 104 SGPRs. All generated token IDs match the baseline and HIP.
Raw reports, including every timed sample, are under
`build/gpu-os/tuning/hip-race/args-results/results.json`.

Native still needs about 6.8% and 9.8% higher throughput respectively to reach
HIP in this run, so automatic AMD worker selection remains HIP. Paired matrix
rows, ordinary cached weight loads, four/eight-weight loops and 48/64 resident
workers did not improve full-model throughput and were discarded. A proposed
inactive-else shortcut failed an embedded matrix fixture and was also removed.
The retained compiler passes 13,202 device arithmetic/control/collective checks,
CPU matrix/RMS comparisons including F16 operands above v127, identical
self-builds, the tool-free native/PTX builder checks and real native/HIP-fallback
chat, cancellation and recovery checks. These short-context runs with unlocked
clocks do not establish a win over HIP or third-party runtimes.

## Focused tests

```sh
./build/flex libs/os/gpu/tests.flex -o build/gpu-os/tests
./build/gpu-os/tests --workers 1
./build/gpu-os/tests --workers 32
./build/flex scripts/test-gpu-os-build.flex -o build/gpu-os/test-build
./build/gpu-os/test-build
python scripts/test-llm-gpu-os.py --gpu --native
python scripts/test-llm-monitor.py --gpu
```

Use a worker count at or below the device's reported compute-unit count. The
tests cover GPU-driven token transitions, EOS, cancellation, mailbox reuse,
nonfinite-logit faults, random-state publication, the final context slot and
profile-ring rollover/reset. Profiling checks also compare token transitions
with instrumentation disabled. Monitor checks exercise live timing tracks and
disabling instrumentation for the next reply.
Chat checks cover the `llm.flex` launcher/runtime settings and live GPU
multi-turn recall, streaming, thinking/sampling and cancellation recovery.

## Native RDNA ahead of HIP (2026-10-13)

The latest emitted native worker uses 96 VGPRs and 106 SGPRs. It adds compact
FP32 attention, element and rotary leaves, a uniform stage dispatcher and a
bounded 32-bit phase/count barrier that retains 64-bit generation publication.
The shared unprofiled scheduler also hoists immutable schedule metadata; the
HIP comparison includes that same shared optimization. Weight prefetching and
64-worker experiments gave no repeatable improvement and were discarded.

With both real chat workers loaded, one warmup and seven measured requests per
worker alternated on each prompt. Qwen3-1.7B uses F16 weights, FP32 KV, context
1024, greedy sampling, profiling off and 128 generated tokens. All input and
output token IDs matched the earlier reference. Rates measure client arrival
from first to last token, excluding prefill and the first selected token.

| Prompt tokens | Native RDNA GPU OS | HIP GPU OS | Native lead |
|---:|---:|---:|---:|
| 41 | 156.54 tok/s | 156.19 tok/s | +0.22% |
| 378 | 152.49 tok/s | 151.93 tok/s | +0.37% |

Native led in every measured pair for both prompts. Median paired gains were
0.23% and 0.37%; this is a small lead on this machine with automatic clocks.
The raw token events, timings and worker reports are in
`build/gpu-os/tuning/race2/chat-stage-results/results.json`.

The standalone host, which reloads weights between requests, separately measured
146.67/150.73 steps/s for native versus 143.71/149.40 for HIP over three rounds
per prompt, again with matching tokens. Those rates use a different host timing
path and should be compared within that run. Raw reports are in
`build/gpu-os/tuning/race2/stage-results/results.json`.

Focused checks cover three GQA ratios, position zero and tile boundaries,
mutable positions inside one dispatch, grid-strided tile reuse, all element
operations, CPU rotary values, live caller registers, partial tiles and guards.
The barrier checks include visibility across 1–32 blocks and generation wrap.
Real chat checks cover recall, thinking, cancellation/recovery, HIP temperature
fallback, return to native and stable allocation cleanup. Qwen3-4B was not
rechecked in this run because its checkpoint is absent locally.

```sh
build/flex llm.flex --gpu-os-target rdna
build/flex scripts/test-rdna-resident.flex -o build/llm/test-resident
build/llm/test-resident --compiler build/flex
build/flex scripts/test-rdna-barrier.flex -o build/llm/test-barrier
build/llm/test-barrier --compiler build/flex
```
