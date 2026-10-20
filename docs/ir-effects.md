# Shared function effects

The default shared IR optimizer infers effects for resolved function calls.
It uses those summaries to retain local arithmetic value numbers across a call
whose summary is zero. For example:

```flexscript
fn clean(x) {return x+1;}
fn compute(x,y) {
    let a=x*y;
    clean(x);
    let b=x*y; // Reuses a across clean().
    return a+b;
}
```

Calls and argument evaluation remain present, including unused calls. This pass
does not memoize function results, hoist loads or loops, or remove calls.
`--ir-opt none` disables the analysis and its CSE consumer. `run --stats` shows
the number of effect-free functions and functions that may trap or not return.
Counts describe the resolved stream before optimization; unreachable bodies and
edges can conservatively add effects.

## Representation

`compiler/ir-effects.flex` is independent of target names and register choices.
Its API is `ir_effect_analyze(code,size,functions,count,overrides)` followed by
`ir_effect_get(function_index)`. Instructions are the existing 16-byte word IR;
function records are 32 bytes with entry PC at +16 and arity at +24. An optional
word per function supplies a trusted replacement summary, with -1 selecting
ordinary body analysis. A replacement body contributes no call edges.

| Bit | Effect |
| --- | --- |
| 1 | Pointer memory read |
| 2 | Pointer memory write |
| 4 | Global read |
| 8 | Global write |
| 16 | Allocation |
| 32 | External I/O |
| 64 | Synchronization |
| 128 | Nondeterministic result |
| 256 | Possible trap |
| 512 | Possible nontermination |
| 1024 | Unknown operation |

The union of all bits, 2047, is the conservative fallback. Memory loads and
stores can trap. Integer division and remainder can trap even without writes.
A backward branch is treated as possibly nonterminating. Iterative call-graph
DFS detects recursion, which can fail to terminate or overflow the stack.
A reverse-edge worklist propagates effects to callers until no mask changes.
No native recursion is needed to analyze a recursive program.

The API expects structurally valid resolved IR, as do the compiler's other
optimization passes. It is not a bytecode verifier or a proof against resource
exhaustion. It checks table ranges, instruction alignment, local indices and
call indices; unknown instructions, invalid edges and invalid queries return
conservative masks. Allocation failure and limits of 65,536 functions or
1,048,576 instructions disable the proof. Scratch buffers grow geometrically
and are reused. Storage is O(functions + call sites), not a reachability matrix;
each effect bit propagates monotonically. Larger programs retain the original
call barrier behavior.

## Target operations

`compiler/ir-effect-targets.flex` supplies overrides using actual lowering
bindings. It accounts for native IR parsing through the VM frontend, CPU C++
operations and GPU intrinsics. Ordinary VM functions are analyzed by body;
an ordinary function's name does not imply purity.

Native word addition, XOR, high-bit lookup and the lowering-active constant
are effect-free. Memory primitives carry read/write and trap effects.
Other replacements, including native machine pointers, have all effect bits
until a more precise contract is provided. GPU intrinsics also conservatively
have all bits, protecting barriers, atomics, lane collectives, clock reads and
fused kernels despite their trivial portable placeholder bodies. CPU C++ atomic
replacements receive the same protection. Numeric floating-point replacements
are currently conservative too.

The CSE consumer only retains arithmetic identities across zero-mask calls.
It clears removable flags on pending operand spans, so a later rewrite cannot
delete a call or its arguments. It does not reuse call results. Existing
barriers for memory, globals and control flow remain.

## Verification

```sh
FLEX_COMPILER=build/flex python3 scripts/test-ir-effects.py
FLEX_COMPILER=build/flex python3 scripts/test-ir-cse.py
```

The effect suite compares generated call graphs against an independent Python
reachability oracle, including recursive components, disconnected nodes and
target overrides, plus 1,536-function chains with and without recursion. It
also checks conservative fallbacks, pending expressions,
effectful shadowed FFI names, unused trapping/diverging calls, native execution,
VM/JIT execution, Wasm compilation, and target adapter behavior. The existing
CSE suite executes the arithmetic corpus on native, VM/JIT, Wasm and CPU C++
and compiles it for PTX, SASS, HIP and RDNA.

On 2026-10-20, the effect suite passed 9,773 checks and CSE passed 12,245
including physical AMD execution. Core (84), VM (470), Wasm (918), frontend
extensions (633), transforms (153), lowering (208,521), shared IR (8,775),
liveness (9,849) and native pipeline (39) checks passed. Successive compiler
self-builds matched. A rebuilt RDNA GPU OS Qwen image generated 128 tokens
matching the ordinary decoder with `--verify 1`.

Against the preceding installed compiler, `examples/effect-aware-cse.flex`
shrunk from 294 to 279 bytes. PuppyLog stayed at 1,129,336 bytes with identical
sources and assets. The compiler grew from 598,880 to 605,136 bytes. These are
size measurements, not application throughput claims; this initial consumer
has deliberately narrow scope.
