# Flexscript frontend extensions

To extend ordinary Flexscript programs, use [compile-time program extensions](program-transforms.md).
They provide source/function-IR hooks through `extend`, with composition and autodiff examples.

An extension is a Flexscript program that parses another language and returns
portable FIR word IR or an FSX1 generated-source result. The compiler validates
the result before passing it to the existing backends. FIR supports the
interpreter/JIT, native x86-64 ELF and WebAssembly. FSX1 uses the ordinary
Flexscript parser and also supports PTX and direct SM75 SASS. Neither route
invokes a Rust or C compiler.

```text
source -> Flexscript frontend -> validated FIR1
                                  | interpreter / JIT
                                  | native Linux x86-64 ELF
                                  | WebAssembly

source -> Flexscript frontend -> validated FSX1 -> ordinary Flexscript compiler
                                                  | interpreter / JIT / native / Wasm
                                                  | PTX / SM75 cubin
```

The compiler bundles the SetaScript frontend. `.seta` selects it automatically;
`--language seta` selects it explicitly. The compiler and this frontend are
both written in Flexscript, including the Wasm build of the compiler.

```sh
build/flex-extensions run examples/seta/policy.seta
build/flex-extensions run --jit --stats examples/seta/policy.seta
build/flex-extensions --language seta examples/seta/policy.seta -o build/policy
build/flex-extensions --target wasm32 examples/seta/policy.seta -o build/policy.wasm
```

`policy.seta` returns 42 (also its Linux process exit status). Its mode helper
illustrates the kind of pure frame policy used by Setaworld. This is the compiler
extension foundation; the Setaworld engine has not yet been ported.

## External frontends

No compiler rebuild is needed to load a frontend:

```sh
build/flex-extensions run --frontend examples/extensions/postfix.flex examples/extensions/answer.postfix
build/flex-extensions --frontend examples/extensions/postfix.flex examples/extensions/answer.postfix -o build/answer
build/flex-extensions --frontend examples/extensions/postfix.flex --target wasm32 examples/extensions/answer.postfix -o build/answer.wasm
```

The extension exports one function and does not need a `main`:

```flex
import "../../compiler/extension-sdk.flex";

fn frontend_compile(text, size, version, path) {
    ir_init(text, size, path, version);
    ir_begin("main", 4, 0);
    ir_emit(1, 42);
    ir_emit(9, 0);
    ir_end(0);
    return ir_finish();
}
```

The arguments are source bytes, byte count, API version (currently 1), and a
zero-terminated source path. The returned word points to a complete FIR or FSX1 blob
in guest memory. Import paths in the frontend use normal Flexscript module
resolution. `examples/extensions/seta.flex` wraps the same parser that is bundled
in the compiler; both routes produce byte-identical IR.

On a Linux compiler host, an external frontend runs in a separate process's
restricted Flexscript VM with a 256 MiB guest heap, one billion instruction fuel,
60-second execution deadline and 1 MiB diagnostic output budget. It receives the
source as memory and has no guest file, network or raw FFI grants. These bounds
apply to frontend execution; source loading uses the normal compiler loader.
The frontend can report a located error with `ir_error(message, byte_offset)`.

## FSX1: source-producing domain frontends

Import `compiler/source-sdk.flex` and return `frontend_source(text,size)` from
the same `frontend_compile` entry point. The source must be self-contained:
`global` and `fn` declarations, without `import` or `extend` headers. Frontend
implementation imports still use the ordinary loader. Generated source is
compiled with the same symbol, arity and target checks as handwritten source.
GPU-reachable allocation, syscalls, FFI and recursion remain rejected.

The [Pup tensor frontend](../libs/ml/pup/README.md) uses this route to lower a
primitive graph and execution plan to ordinary Flexscript kernels. The compiler
contains no Pup parser, tensor operations or model-specific code.

All header fields are little-endian 64-bit words:

| Byte offset | Value |
| --- | --- |
| 0 | Magic `0x31585346` (FSX1) |
| 8 | Total bytes, exactly `64 + source_size` |
| 16 | Source offset, exactly 64 |
| 24 | Source size, less than 16 MiB |
| 32, 40, 48, 56 | Reserved, zero |

Source bytes follow the header without a terminator; embedded NUL bytes are
rejected. Validation and compilation happen before replacing an existing
artifact. Original input and frontend dependency file identities remain
protected against output aliases. Parser errors in generated source use its
line/column under the original input path; frontends should report their own
domain errors against the original bytes before lowering.

`--target ir` accepts FIR only. FIR is not GPU kernel IR and is rejected for
GPU targets. FSX1 bare-metal output is not supported yet. FSX1 itself does not
restrict generated code to portable word operations: application execution
uses the normal target capabilities, including the usual restrictions of
`flex run --restricted`. Native output has the ordinary native trust model.
The frontend process always retains its restricted VM and budgets.

`scripts/test-pup.flex` covers native, interpreter, JIT, Wasm and both GPU
compilation routes, malformed headers, forbidden generated headers, frontend
capabilities and output preservation.
The loader copies its result and validates it; guest pointers never become
native code addresses. Fork/pipe transport currently requires Linux, so external
frontend loading is unavailable inside a Wasm-hosted compiler. The bundled Seta
frontend works there without that transport.

Guest application permissions still follow `flex run` options. Native and Wasm
AOT output are not fuel-metered; the embedding host controls their execution.

## Initial SetaScript subset

Supported:

- One empty `plugin name[.name...] v1 {}` header.
- `fn` and `cosmetic fn`, typed `i32`/`bool` parameters and return values,
  forward calls and return-type checks. `main() -> i32` is required.
- Inferred or annotated `let`, mutable locals, lexical scopes, assignment and
  `+=`, `-=`, `*=`, `/=`.
- Integer arithmetic, comparisons, bitwise operations, `and`/`or`/`not`, and
  typed ternary expressions. Boolean operators short-circuit.
- `if`/`else`, `else if`, `for i in <literal>..<literal>`, and `repeat(<literal>)`.
  Loop indices are read-only; literal bounds and spans are limited to one million.
- Every function returns on every path. Recursion, including mutual recursion,
  is rejected.

As in the existing SetaScript runtime's integer IR, this first frontend backs
`i32` values with signed 64-bit words. Arithmetic wraps at 64 bits; shifts mask
their count to six bits. Division/remainder trap on zero and signed MIN/-1.
This does not claim 32-bit arithmetic or full parity with the original checker.
Decimal integer literals are supported; hexadecimal, floats and unit-bearing
literals are not supported yet.

Floats/fixed point, vectors, records, collections, replicated actors, handlers,
assets, host calls, imports and nonempty plugin configuration currently produce
errors. Typed floating-point/aggregate IR and host-service interfaces are the
next steps before compiling the actual Setaworld engine and content. Supported
syntax is parsed and type-checked, rather than silently skipping other features.

## FIR1 and the builder API

`compiler/extension-sdk.flex` supplies:

| Function | Purpose |
| --- | --- |
| `ir_init(text,size,path,version)` | Reset the builder and diagnostic context |
| `ir_begin(name,size,arity)` | Begin a function, return its zero-based index |
| `ir_emit(op,operand)` | Append an instruction, return its byte offset |
| `ir_patch(instruction,operand)` | Patch an instruction operand |
| `ir_end(local_slots)` | Finish its frame description |
| `ir_finish()` | Return the serialized FIR1 blob |
| `ir_error(message,offset)` | Print a located diagnostic and terminate |

`ir_code_size` exposes the current instruction byte offset for branch patching.
Functions appear in declaration order; calls use their zero-based indices.
`ir_begin` inserts a frame header and zero accumulator initialization; emit a
return before `ir_end`. Source parameters occupy the first local slots in order.
All remaining slots start at zero. The SDK allows 2048 functions, 4096 slots per
function, 255-byte names and a 1 MiB instruction stream.

Save and replay a frontend result independently:

```sh
build/flex-extensions --target ir examples/seta/policy.seta -o build/policy.fir
build/flex-extensions run --language ir build/policy.fir
build/flex-extensions --language ir build/policy.fir -o build/policy
build/flex-extensions --language ir --target wasm32 build/policy.fir -o build/policy.wasm
```

All fields are little-endian 64-bit words. The 64-byte header contains magic
`0x31524946` (FIR1), total size, function count, instruction offset/size, name
offset/size, and a reserved zero word. A function has a 64-byte record containing
name offset within the name section, name size, entry byte offset within the
instruction section, argument count, local-slot count, and three reserved zero
words. The function table follows the header, then instructions, then names;
names are identifier bytes without terminators. Each instruction is two words.

| Opcode | Operation |
| --- | --- |
| 1 / 2 | Set accumulator to constant / push accumulator |
| 3 / 4 | Load / store local slot |
| 7 | Binary operation: pop left operand, accumulator is right |
| 8 / 9 | Call function index / return accumulator |
| 10 / 11 / 12 | Jump / jump if zero / jump if nonzero |
| 13 / 14 / 15 / 16 | Normalize boolean / negate / logical not / bitwise not |
| 18 | Function frame header (builder-managed) |

Binary operand codes use ASCII for `+ - * / % & | ^ < >`, and 259/260/261/262
for `== != <= >=`, 265/266 for `<< >>`. Calls consume pushed arguments in source
order. Branch operands are instruction-section byte offsets and must stay in
their function. Stack heights must agree at control-flow joins; returns leave
no pending expression operands. Every function begins with its frame header
and a zero accumulator initialization; physical function endings cannot fall
through. `main` takes zero arguments. Names must be unique identifiers.

The portable profile intentionally excludes memory, globals, allocation, host
syscalls and FFI opcodes. Raw VM IR is a broader internal interface and is not
accepted as FIR1. Extending the portable profile requires a versioned format
and consistent semantics in all consumers. Existing Flexscript source retains
its established native backend; portable frontend output uses the new IR
lowering, sharing the x86 instruction emitters.

## FIR2: persistent state and platform messages

The engine profile extends FIR1 with magic `0x32524946` (FIR2). Header word 56
contains a state-word count (0..2048); that many little-endian initial values
follow the name section. The SDK's `ir_state_word(value)` adds a word and returns
its zero-based index. Loading a module creates independent mutable state, then
relocates instruction operands in a private instruction copy. Saving/replaying
IR preserves the original artifact bytes.

| Opcode | Operation |
| --- | --- |
| 5 / 6 | Load / store a checked state-word index |
| 19 | Write accumulator as one eight-byte little-endian platform message |
| 20 | Read one eight-byte platform message into the accumulator |

Message instructions have a zero operand. Native output uses stdin/stdout and
retries interrupted/partial reads and writes; input EOF/error returns -1. VM
execution uses the existing stdin grant and output/fuel/time budgets. Wasm
imports `flex.read_word() -> i64` and `flex.write_word(i64) -> i64`; embeddings
provide these capabilities explicitly. A successful write returns its word;
native/VM I/O failure returns -1. Wasm host exceptions propagate. The application
protocol decides how to encode input and render commands; FIR2 contains no
game-specific opcodes and still exposes no raw pointers or general syscalls.

SetaScript's engine extension adds one module-owned state block before its
functions:

```seta
plugin demo v1 {}
state { count: i32 = 0 enabled: bool = true }
fn frame(input: i32) -> i32 {
    state.count += 1
    write_word(state.count)
    return 0
}
fn main() -> i32 {
    repeat (1000000) {
        let input = read_word()
        if input < 0 { return 0 }
        frame(input)
    }
    return 0
}
```

This singleton `state` block is a new engine-module extension, separate from
the original language's replicated actor state. Initializers are typed literal
values; fields use explicit `state.name` access. The same state persists across
exported Wasm `frame` calls. Pure source continues to emit FIR1.

`scripts/test-extensions.flex` tests execution routes, saved-IR replay, frontend
identity, type errors, invalid IR and capability/budget failures. CI runs it
after installing the same Bun host used by the Wasm tests.

## FIR3: bounded indexed state and initialized tables

FIR3 (`0x33524946`) retains the FIR2 layout, with up to 262,144 state
words (2 MiB). The complete artifact remains bounded to 4 MiB, and code to
1 MiB. FIR1 and FIR2 remain accepted with their original limits.

```seta
state {
    actors: i32[16384] = 0
    stops: i32[3] = [12, 34, 56]
    enabled: bool[2] = [true, false]
}
```

A literal initializer fills every element. An explicit initializer must contain
exactly the declared number of typed literals. Array capacity is a positive
literal; the module owns all storage. `state.actors[index]` supports loads,
assignment and compound assignment. Index expressions run once. There are no
raw pointers, implicit resizing or host allocations in the guest protocol.

| Opcode | Operation |
| --- | --- |
| 21 | Checked array load: accumulator is index, result replaces accumulator |
| 22 | Checked array store: pop index, store accumulator, retain accumulator |

The serialized operand packs the first state-word index in its low 32 bits and
the positive word span in its high 32 bits. Validation requires the complete
span to fit inside module state, and verifies the store's expression-stack
consumption on all control-flow edges. Relocation occurs only in a private
instruction copy; indexed instructions use module-relative byte offsets.
Negative, out-of-span and full-width indices trap before accessing memory:
SIGILL (`ud2`) in native ELF, VM memory trap in interpreter/JIT, and Wasm
`unreachable`. No index is truncated to 32 bits before validation. These bounds
checks and loads/stores lower to a constant number of instructions independent
of table capacity, including the actual JIT path.

All numeric values still use signed i64 word semantics. Setaworld deliberately
uses millimetres and millidegrees; this extension does not add floats, rich
records, actor syntax or collections. The extension suite checks large tables,
explicit/broadcast initializers, type errors, index evaluation once, real JIT
execution, all four bounds routes, module isolation, serialized-IR replay and
malformed spans. The Wasm suite compiles FIR3 Seta source inside a byte-identical
self-built Wasm compiler and executes its native and Wasm outputs.

## FIR4: complete world tables

FIR4 (`0x34524946`) uses the same checked state and indexed operations as FIR3,
with up to 1,048,576 state words (8 MiB) and a 16 MiB serialized artifact.
Instruction code remains bounded to 1 MiB. FIR1, FIR2 and FIR3 retain their
earlier state and artifact limits; an artifact that exceeds those limits must
declare FIR4. The builder selects it automatically when necessary.

The SetaScript frontend permits 1,024 nonrecursive functions. Its call graph,
state arrays, typed initializers and checked access rules remain bounded. An
external frontend originally used a 64 MiB guest heap and a 30-second deadline;
FIR5's larger transport now uses the bounded budgets below. Application `--memory` limits continue to apply independently: a module
whose state cannot fit fails before execution.

Setaworld's complete countryside collider inventory and original population
tables exceed FIR3's aggregate capacity. FIR4 preserves these data sets instead
of reducing the simulated world. The extension suite checks the maximum state,
overflow rejection, saved-IR replay, old-profile rejection, both frontend paths,
explicit guest budgets, 1,024-function call graphs and all execution backends.
The Wasm suite also builds and executes a maximum-state application through
the byte-identical self-built Wasm compiler.

## FIR5: complete native scene data

FIR5 (`0x35524946`) permits 2,097,152 state words (16 MiB) and a 32 MiB
serialized artifact. Checked state opcodes, one-MiB instruction limit, function
and local limits are unchanged. FIR1 through FIR4 retain their earlier bounds;
the SDK selects FIR5 automatically when state exceeds 1,048,576 words or an
artifact exceeds 16 MiB. Validation rejects older profile tags on oversized
artifacts before relocation or backend emission.

Frontend source files (SetaScript, external frontend input and saved IR) may be
smaller than 64 MiB for bundled SetaScript or 32 MiB for an external frontend. Flexscript source/import graphs retain their 16 MiB limit.
External frontends use a 128 MiB restricted heap, one billion instructions and
a 60-second deadline, with no new device capabilities. Native/Wasm/IR compilation
uses a 32 MiB state-image budget. Application execution retains the default
16 MiB guest limit and explicit `--memory` limits: maximum-state FIR5 programs
need `flex run --memory=32m ...`. Small and older-profile artifacts serialize
unchanged.

The preserved Setaworld native scene has 199,723 static cuboids, including
city/storey floors, subway, Skyway and countryside props. Its exact binary32
records, normalized quaternion pool, AABB bounds and cell index require
1,132,446 words before other world state, and 19,851,287 bytes of generated
table source. FIR5 allows the complete import without dropping colliders.

The extension suite checks maximum state on all four routes, checked spans,
aggregate/single-array overflow, older-profile rejection, saved-IR replay,
bundled/external equality, application-memory limits and frontend-source bounds.
The Wasm suite builds maximum-state FIR5 native and Wasm applications using
the self-built compiler running inside Wasm, then executes both outputs.

## FIR6: larger engine instruction streams

FIR6 (`0x36524946`) permits 4 MiB of instruction code, 8,388,608 state words
(64 MiB), and a 128 MiB serialized artifact. Function, local-slot, checked-array,
execution-fuel and application-memory limits remain
unchanged. FIR1 through FIR5 still reject instruction streams above 1 MiB.

The SDK allocates a bounded 4 MiB instruction buffer and selects FIR6 as soon
as code exceeds 1 MiB, state exceeds 2,097,152 words, or the serialized artifact
exceeds 32 MiB. Appending state after code preserves that selection.
Smaller programs continue to serialize with their existing profile tags.
The restricted external-frontend heap is bounded at 256 MiB, with the same
one-billion-instruction and 60-second limits. Compilation uses a 128 MiB
state-image budget and FIR6 native/Wasm output bound; earlier profiles keep
their 64 MiB output bound. Application execution retains its default 16 MiB budget.
Maximum-state FIR6 programs require `flex run --memory=128m ...`. Frontend source
is smaller than 64 MiB for the bundled SetaScript frontend (32 MiB for external frontend source); saved IR input may be smaller than 128 MiB.

Artifacts are validated before relocation or execution on every backend;
changing a larger artifact's tag to an older profile is rejected.

This permits a complete engine to include movement, replication, trains,
vehicle models and camera logic without removing features to fit the previous
code bound. It does not change native or Wasm output formats.

The extension suite exercises a large Seta source through bundled and
restricted external frontends; interpreter, JIT, native and Wasm execution;
byte-identical saved-IR replay; a native SDK fixture with exact 4 MiB code
combined with maximum state;
overflow and malformed-instruction rejection; and the unchanged guest-memory
budget. Compiler stage2 and stage3 must remain byte-identical.

## Bounded Seta function graphs

The Seta frontend accepts at most 1,024 functions, including `main`. Its fixed
call-graph matrix uses 1,048,576 bytes and rejects direct or mutual recursion
before producing output, including edges between the highest function indices.
The SDK and FIR validator retain their 2,048-function bound; no IR version,
state, source, local-slot or instruction limits change.

Interpreter and JIT permit 1,024 simultaneous frames, so a nonrecursive chain
through every Seta function executes consistently with native and Wasm output.
The VM still limits all active locals to 8 MiB, individual frames to 4,096 local
slots, and the operand stack to 65,536 words. A graph within the function limit
can therefore exceed other explicit runtime budgets. Flexscript recursion is
still supported; entering a 1,025th VM frame traps with a stack-limit error.

The extension suite checks the maximum-width graph and maximum-depth chain,
both bundled and external frontend routes, saved IR on all four backends,
1,025-function rejection without replacing existing output, and high-index
direct/mutual recursion. The VM suite checks the frame boundary independently.
