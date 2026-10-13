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

The default `--runtime auto` prefers GPU OS with `rdna-direct`, F16 weights and
a compatible gfx1201 device. It checks cooperative launch, native host atomics,
wave32 and the GPU clock. It builds the worker automatically, falling back to
graph if that build fails. Other backend/weight combinations use graph.
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
python libs/os/gpu/build.py
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

## Layout

- `runtime.flex`: mailbox allocation, schedule upload, resident launch, token
  polling, cancellation and cleanup.
- `resident.hip`: cooperative scheduler, RMS normalization and GPU sampling.
- `build.py`: lowers the existing Flexscript GEMV, attention, rotary and
  elementwise functions to HIP, composes the worker and extracts its ELF object.
- `qwen.flex`: runnable Qwen example with streaming text and optional comparison.
- `tests.flex`: deterministic protocol and token-transition tests.

The prototype uses HIP/LLVM **at build time** for the resident worker. HIP loads
its precompiled AMD code object at runtime. The worker shares existing
Flexscript model functions; adding this runtime does not require a new language
target. Direct RDNA emission for the scheduler and synchronization remains a
future compiler step.

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
checks that the worker has resident occupancy. It caps the grid at one worker
per reported compute unit: the larger occupancy-derived grid stalled grid
synchronization on the tested gfx1201 device. `--workers N` can select a smaller
team.

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

The worker targets gfx1201 and the host adapter targets Linux x86-64. Qwen3
uses F16 weights, FP32 activations/KV, greedy or top-40 temperature sampling and an unfused model
schedule. Prompt prefill continues to use the existing GPU graph. The worker
lives for a generation request and exits afterward, leaving resources available
for the next prefill. The default chat policy is `auto`, preferring GPU OS on
compatible direct RDNA/F16 configurations. It uses graph elsewhere and can be
overridden explicitly. The resident worker uses HIP/LLVM for compilation.

Future work includes direct RDNA scheduler emission, fused resident operations
and longer-lived workers that can
coexist with prefill. Performance needs measurement against the current fused
decoder; removing host launches alone does not establish a speed advantage.

On the RX 9070 XT, the initial Qwen3-1.7B check matched all 32 token IDs of the
existing decoder (31 decode steps in 207,916 microseconds, about 149 steps/s in
this single run). Qwen3-4B also matched its short response through EOS. Streaming
cancellation stopped a separate generation after four published tokens.

A matched chat benchmark on 2026-10-13 used Qwen3-1.7B F16 on the RX 9070 XT,
context 1024, greedy sampling and 128 generated tokens. Both runtimes remained
loaded; five measured requests per configuration alternated after a warmup.
All prompt and generated token IDs matched. Median decode rates, excluding
prefill and the first selected token but including sampling and streaming:

| Prompt tokens | Graph | GPU OS | GPU OS with profiling |
|---:|---:|---:|---:|
| 41 | 135.9 steps/s | 151.1 steps/s | 146.5 steps/s |
| 378 | 120.9 steps/s | 147.9 steps/s | 143.3 steps/s |

GPU OS led graph by 11.2% and 22.3% in these workloads; self profiling reduced
GPU OS throughput by about 3.1%. First-token latency was similar. These results
cover two short-context workloads on this machine, with automatic GPU clocks;
they do not establish results for other models or long contexts.
Reproduce with `python scripts/benchmark-llm-runtimes.py`. Raw samples and the
summary are saved under `build/gpu-os/paired-runtime-benchmark/`.

## Focused tests

```sh
./build/flex libs/os/gpu/tests.flex -o build/gpu-os/tests
./build/gpu-os/tests --workers 1
./build/gpu-os/tests --workers 32
python scripts/test-llm-gpu-os.py --gpu
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
