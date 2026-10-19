# Shared IR optimization

`compiler/ir-opt.flex` optimizes resolved word IR before backend lowering or VM
execution. The same passes serve the interpreter/JIT, WebAssembly, CPU C++, PTX,
SASS, HIP, RDNA and ESP32 backends. Native Linux Flexscript builds now use this
stage by default too, then lower through `compiler/native-ir.flex`. SetaScript
and portable FIR also use this stage when lowered to native x86-64. Shader
source generation follows its own path.

```text
source/frontends -> word IR -> symbol resolution/validation
                            -> shared optimization -> backend/execution
```

The default is `--ir-opt basic`. Use `--ir-opt none` to disable this stage for
comparison and debugging. Both forms work with compilation commands; `run`
also accepts `--ir-opt=basic` and `--ir-opt=none`.

```sh
build/flex --target wasm32 --ir-opt basic app.flex -o app.wasm
build/flex run --interpret --ir-opt none --stats app.flex
build/flex run --jit --ir-opt=basic --stats app.flex
```

For native Linux compilation, `--native-pipeline ir` explicitly selects the
default. `--native-pipeline direct` selects the original source emitter for
reference comparisons. Both produce standalone ELF machine-code executables.
The native IR path supports native pointers, globals, mutable binary string
literals, allocation, Linux syscalls, FFI and registered hardware lowerings.
It reuses the existing x86 register cache, arithmetic/address peepholes, direct
comparison branches and short-branch encoding. Static-address literals use an
internal relocation opcode so numeric constants cannot be mistaken for pointers;
this adds no portable FIR format version or VM execution opcode.

`examples/ir-optimization.flex` provides a small example of constant folding
and dead-branch removal. Both modes return 42; `--stats` shows the reduction.

The pipeline contains four passes and a relocation step:

- **Local folding:** fold constant binary/unary word expressions, overwritten
  constants and redundant boolean normalization within basic blocks.
- **Common subexpressions:** `compiler/ir-cse.flex` numbers pure arithmetic
  values within a basic block and reuses an equal result still held in a local.
- **Branch simplification:** resolve constant conditional branches, thread
  jumps through unconditional jumps, and remove jumps to the next instruction.
- **Reachability:** remove instructions unreachable from each function entry.
- **Relocation:** compact code and remap branch targets, function entries and
  surviving call sites. Function indices, parameter counts and local layouts
  remain stable.

RDNA currently keeps its structured branch joins: it uses local folding, CSE
and reachability but skips jump threading. Its backend derives execution-mask
reconvergence from those joins; scalar-equivalent shortcuts can bypass lane
restoration. Other backends retain jump threading.

Folding preserves wrapping 64-bit arithmetic, signed comparisons, truncating
signed division and masked shift counts. Division by zero and `INT64_MIN / -1`
(including remainder) are left as runtime traps. Basic-block boundaries protect
instructions that have other incoming edges. Calls and memory/host operations
are never evaluated by the optimizer; unreachable operations may be removed.
Name/arity resolution and frontend validation happen before optimization, so
unreachable undefined calls remain errors.

For example, `let a=x*y; let b=x*y+1;` reuses `a` for the second multiplication.
Value numbering tracks local assignments, copied values, nested expressions,
unary operators and commutative arithmetic/comparisons. It replaces only a
contiguous pure producer span without incoming branch edges. Reassignment
invalidates a local's availability as a result holder. Calls, memory operations,
globals, static addresses and control-flow boundaries clear availability.
Division/remainder are excluded from CSE, including deletion as part of a larger
expression, so their traps stay in place.

This initial CSE pass uses existing locals: it does not add temporary locals,
eliminate expressions across blocks, reuse memory loads, or infer pure calls.
It leaves portable IR opcodes and frame layouts unchanged. A bounded hash table
caps lookup work; saturation misses optimization opportunities without changing
results. Scratch buffers are reused between functions and compilations.

Serialized FIR output (`--target ir`) and source transformation snapshots stay
unchanged. Optimization works on the execution/backend instruction stream;
there are no new FIR opcodes or format versions. Raw FIR input bytes are not
overwritten. Scratch uses a reusable arena so the compiler can itself execute
inside a restricted VM without requiring an extra host capability.

`run --stats` reports instruction counts before/after optimization and counts
of folds, common expressions reused, branch rewrites and unreachable instructions
removed. Fuel measures
the instructions in the selected optimized or unoptimized stream; interpreter
and JIT use the same stream and retain matching accounting.

This is a small shared pass pipeline, not yet an SSA optimizer. It does not do
cross-block constant propagation, inlining, alias analysis, function removal or
portable comparison-and-branch fusion. Instruction selection, physical
register allocation and branch encoding remain backend responsibilities.

Run the differential suite with:

```sh
FLEX_COMPILER=build/flex python3 scripts/test-ir-opt.py
FLEX_COMPILER=build/flex python3 scripts/test-ir-cse.py
```

It compares optimization modes in the interpreter/JIT, WebAssembly and native
FIR, executes CPU kernels, compiles GPU targets, checks independent full-width
word results and preserves traps, side effects, platform bindings and incoming
branch targets. GPU compilation checks do not claim physical-device execution.
Differential verification uses Python, Bun and g++.

The CSE suite checks wrapping arithmetic, masked shifts, signed comparisons,
reassignment, overwritten holders, nested expressions, calls, memory effects,
loop/branch boundaries, traps and an independently evaluated random program.
Add `--gpu` to execute its RDNA corpus on an AMD device. It also checks that a
duplicated multiplication compiles to the same size as explicit result reuse.

`FLEX_COMPILER=build/flex python3 scripts/test-native-pipeline.py` also compares
the native pipelines, including binary/NUL strings and mutation, globals,
startup arguments, signed/unsigned FFI, recursive calls and output preservation
on compilation failure.
