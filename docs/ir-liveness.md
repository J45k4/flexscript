# Local liveness and native call preservation

`compiler/ir-liveness.flex` computes which local values can be read after an
instruction. The native IR backend uses this information by default to save
only live caller-saved cached locals around ordinary calls, syscalls,
allocation, FFI and `machine.call1` lowerings. Arguments already copied onto
the expression/argument stack do not make their original local live after a
call. Callee-saved register preservation remains part of the normal ABI.

For example, after `show(y)` in this function, only `x` needs preservation:

```text
let x = calculate();
let y = x + 1;
show(y);
return x;
```

The analysis works backward over word IR. A local read adds its bit; a local
assignment removes the previous value's bit. Branches combine requirements
from all successors. A predecessor worklist propagates changes until a fixed
point, including loop backedges and nested loops. It makes no assumptions about
callee purity or whether a particular callee happens to leave registers intact.

The shared interface accepts a mapping from local slots to the bits the
consumer wants tracked, up to 64 distinct values. Each tracked local needs its
own bit; zero excludes a slot. It contains no register or
target instruction conventions. The current consumer maps the three volatile
x86 cached locals to bits; other backends can request their own tracking sets.
Other backends do not yet use these results to change register preservation.

Results are queried through `ir_live_after(pc)` and remain valid until the next
analysis. Scratch is reused between functions. Functions larger than 131,072
IR records retain conservative saves, bounding the largest scratch arena to
about 5.2 MiB. Invalid edges, unknown instructions, invalid local references or
allocation failure also retain all requested values. This pass does not change
IR, frame layouts, serialization, call evaluation order or RDNA reconvergence.
The direct source emitter remains a reference path with conservative saves.

## Measurements — 2026-10-19

Both compilers include the same upstream ARM64/RISC-V backend merge. The baseline
is the compiler at checkpoint `a872a81`; the candidate adds shared liveness and
selective preservation. These are native IR comparisons, rather than comparing
the direct source emitter against IR.

| Artifact | Before bytes | After bytes | Saved |
|---|---:|---:|---:|
| PuppyLog with the same embedded assets | 1,189,984 | 1,129,336 | 60,648 (5.10%) |
| Self-hosted compiler, including new analysis | 647,416 | 598,880 | 48,536 (7.50%) |
| Call-heavy benchmark executable | 643 | 619 | 24 (3.73%) |

The synthetic benchmark computes an independently checked checksum over
50 million iterations. Each iteration calculates eight locals, uses them,
then calls a helper; those locals are overwritten before their next read.
It targets redundant preservation, rather than representing application
throughput. Two warmups per binary precede nine alternating measured pairs,
pinned to one permitted CPU with automatic clocks. Timings include process
startup.

| Process wall time | Before | After |
|---|---:|---:|
| Median | 136.44 ms | 129.12 ms |
| Range | 136.20–136.84 ms | 128.76–129.47 ms |

The median speed ratio is 1.057x, with 5.37% less wall time. All nine measured
pairs favor selective preservation. This is not an end-to-end PuppyLog or GPU
throughput measurement. The application size comparison compiles identical
source; the HTTP tests verify the emitted assets against the original files.

Reproduce with compilers saved before and after the change:

```sh
python3 scripts/benchmark-native-liveness.py \
  --before /path/to/baseline-flex --after build/flex \
  --application ../puppylog/flex/main.flex
```

`--application` is optional and measures binary size only. Raw timing samples,
compiler hashes and settings are in
[ir-liveness-results.json](ir-liveness-results.json). The original working
reports are under `build/ir-liveness/`.

## Verification

```sh
FLEX_COMPILER=build/flex python3 scripts/test-ir-liveness.py
```

The suite compares every instruction's live-out mask with an independent
iterative CFG oracle, including random cycles, branch joins, assignment kills,
unreachable components and bit 63. Native cases cover dying values, values
needed only on the next loop iteration, overwrites, pending expression operands,
branches and clobbering callees. It checks full-width output, conservative
fallbacks, and a reduction in the call fixture's executable size. An optional
`FLEX_BASELINE_COMPILER` isolates the same IR emitter before liveness; otherwise
the executable reference uses `--native-pipeline direct`.

The 9,849 liveness checks pass alongside core, VM/JIT, CSE, shared IR, native ABI,
word/condition oracles, lowering, frontend, transformation and Wasm self-hosting
checks. Native Zstd's 668 interoperability cases and PuppyLog's 10 HTTP plus
10 archive checks pass. The new native Qwen host matches the ordinary decoder
for a complete 128-token AMD GPU request. Compiler stages two and three match.
