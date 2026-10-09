# Flexscript frontend extensions

An extension is a Flexscript program that parses another language and returns
FIR1, the first version of Flexscript's portable word IR. The compiler validates
the result before passing its instructions to the existing interpreter/JIT,
the native x86-64 ELF emitter, or the WebAssembly emitter. Extensions do not
generate Flexscript source or invoke a Rust or C compiler.

```text
source -> Flexscript frontend -> validated FIR1
                                  | interpreter / JIT
                                  | native Linux x86-64 ELF
                                  | WebAssembly
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
zero-terminated source path. The returned word points to a complete FIR1 blob
in guest memory. Import paths in the frontend use normal Flexscript module
resolution. `examples/extensions/seta.flex` wraps the same parser that is bundled
in the compiler; both routes produce byte-identical IR.

On a Linux compiler host, an external frontend runs in a separate process's
restricted Flexscript VM with a 64 MiB guest heap, 100 million instruction fuel,
30-second execution deadline and 1 MiB diagnostic output budget. It receives the
source as memory and has no guest file, network or raw FFI grants. These bounds
apply to frontend execution; source loading uses the normal compiler loader.
The frontend can report a located error with `ir_error(message, byte_offset)`.
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
