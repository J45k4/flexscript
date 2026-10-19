# Native IR host comparison — 2026-10-19

The native IR pipeline reduces executable size with effectively unchanged
Qwen GPU OS decode throughput in this comparison. Both hosts use identical
RDNA worker machine code. This measures the new x86-64 host pipeline against
the direct source emitter; it does not compare RDNA against HIP or introduce
a new GPU execution architecture.

RX 9070 XT (gfx1201), Qwen3-1.7B F16, FP32 KV, context 1024, greedy decoding,
profiling off, 32 resident workers of 512 threads. Both chat workers remain
loaded. Each prompt has one warmup and seven measured requests per host,
alternating the host order each round. Every request generates 128 tokens;
all input and output token IDs match across all 32 requests.

Rates measure 127 decode steps from the first to last token, excluding prefill
and the first selected token, including sampling, publication and host polling.
GPU clocks are automatic. The overlapping ranges and mixed paired results do
not establish a speed improvement.

| Prompt tokens | Direct median steps/s (range) | IR median steps/s (range) | Change |
|---:|---:|---:|---:|
| 41 | 158.25 (157.94–158.60) | 158.54 (157.94–158.88) | +0.18% |
| 378 | 154.13 (153.42–154.28) | 154.06 (153.51–154.68) | −0.04% |

IR wins four of seven paired requests on each prompt. Median paired gains are
+0.13% and +0.01%; the table instead compares each host's median throughput.

## Binary sizes

All pairs compile the same current source using the same compiler. Only
`--native-pipeline direct|ir` differs. These are standalone ELF executables;
model weights and GPU objects are separate files.

| Artifact | Direct bytes | IR bytes | Saved bytes | Reduction |
|---|---:|---:|---:|---:|
| Standalone Qwen host | 132,704 | 128,280 | 4,424 | 3.33% |
| Full chat/TUI host | 239,384 | 236,488 | 2,896 | 1.21% |
| Compiler, including both native emitters | 580,664 | 573,912 | 6,752 | 1.16% |
| Resident RDNA worker | 93,552 | 93,552 | 0 | 0% |

Worker SHA-256 in both loaded hosts:
`2bd5f1419df1e0916b46c1f770664d03e337160f9a6956a98eab314b168d7a92`.

## Memory and latency

| Measurement | Direct | IR |
|---|---:|---:|
| Runtime-accounted resident GPU allocation per worker | 3,682,745,976 B | 3,682,745,976 B |
| Median host RSS, short prompt | 440.42 MiB | 441.98 MiB |
| Median host RSS, longer prompt | 467.98 MiB | 469.55 MiB |
| Host peak RSS including model loading | 3,616.25 MiB | 3,617.55 MiB |
| Median first token, short prompt | 59.08 ms | 60.31 ms |
| Median first token, longer prompt | 275.47 ms | 276.24 ms |
| Median request wall time, short prompt | 863.09 ms | 861.80 ms |
| Median request wall time, longer prompt | 1,104.12 ms | 1,104.26 ms |

RSS is read from each running process's `/proc/PID/status`; it includes driver,
anonymous and mapped allocations. Peak RSS includes checkpoint file mappings
during model loading. The IR host uses about 1.56 MiB more steady host RSS in
this run; smaller executable size did not reduce overall inference memory.
GPU allocation accounting excludes driver/module allocations and desktop use.
Startup and single compile times are retained in raw results for diagnostics;
cache/build-order effects make them unsuitable for a startup-speed claim.

## RDNA regression found during the comparison

Shared jump threading could bypass the structured joins that the RDNA emitter
uses to restore execution masks. This produced nonfinite Qwen logits in both
native host pipelines. A small nested divergent loop reproduced wrong values
on physical hardware with the original optimizer and passed after the fix.
RDNA now retains branch joins while still using shared local folding and
reachability; other backends retain jump threading.

`scripts/test-rdna-resident.flex` includes that regression with 2,050 expected
values across `--ir-opt none|basic`, plus partial-block guards. Existing native
attention, element, rotary and RMS checks pass, as do 937,117 LLM GPU checks
and resident protocol tests with one and 32 workers. Full Qwen output also
matches the ordinary decoder in the focused verification run. Shared IR's
8,775 differential checks and native pipeline's 39 checks pass after the fix.

## Reproduce

```sh
python3 scripts/benchmark-native-gpu-os.py --compiler build/flex --rounds 7
```

The benchmark builds both host styles entirely through Flexscript, selects
`--runtime gpu-os --gpu-os-target rdna`, checks the actual worker target and
one resident dispatch per request, and verifies matching tokens and allocation
sizes. Python drives measurement and writes reports. It requires GPU access,
ROCm, the Qwen3-1.7B checkpoint and enough VRAM to retain both workers.

Full token events, artifact hashes, sensors and raw timings are in
`build/gpu-os/native-pipeline/results.json`. A compact snapshot retaining all
timing samples, memory counters and token identity hashes is saved alongside
this document in [benchmark-native-pipeline.json](benchmark-native-pipeline.json).
The compiler used was SHA-256
`d5d6f122b7862a875ef1e2652e5192c86621ed4c023b47812181903ff4bea764`.
