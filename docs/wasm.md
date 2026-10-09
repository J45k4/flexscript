# WebAssembly target

The self-hosted compiler emits WebAssembly modules directly:

```sh
build/flex-publish compiler/main.flex -o build/flex-wasm
build/flex-wasm --target wasm32 examples/wasm/hello.flex -o examples/wasm/hello.wasm
```

No Rust compiler, C compiler, assembler, linker, Emscripten or external WASM
toolchain participates in emission. The same parser, import graph, diagnostics
and word-based intermediate representation serve the VM and WebAssembly backend.
WASM functions contain i64 arithmetic, loads/stores and ordinary function calls.
Branches use a basic-block `br_table` dispatcher. This first backend does not yet
reconstruct structured control flow or perform optimization.

## Module interface

Each source function is exported under its own name. Its arguments and result
are i64 values, represented by JavaScript `BigInt`. The module also exports:

| Export | Interface |
| --- | --- |
| `memory` | WASM32 linear memory, initially enough pages for static data, maximum 1 GiB |
| `__flex_alloc` | `(size: i64) -> i64`; returns an aligned pointer, `-22` for zero size, `-12` on failure |
| `main` | `() -> i64` or `(argc: i64, argv: i64) -> i64` |

`memory` and `__flex_alloc` are reserved function export names for this target.
Globals and writable zero-terminated UTF-8 strings live in linear memory.
Pointers remain 64-bit language words, but their addresses must fit WASM32.
Memory builtins trap for addresses below 16, addresses above `0xffffffff`, or
accesses beyond the current linear memory. Allocations grow memory as needed,
remain zero-initialized, and last for the instance lifetime; there is no free.
Hosts must reacquire memory views after calls because allocation can grow memory.

Integer wrapping, signed comparisons, arithmetic shifts and division traps match
the native target. In particular, both `MIN / -1` and `MIN % -1` trap. Native
hardware intrinsics and `native_callback` are unavailable. Floating-point types
are not part of the current Flexscript language on either target.

This is a host-neutral module ABI, **not WASI**. No entry function runs during
instantiation: the host calls `main` or another export. `flex run` continues to
run Flexscript source in the existing VM; it does not load `.wasm` files.

## Browser and Linux JavaScript hosts

`platform/wasm-host.js` is a small platform adapter, usable as a browser ES module
or from Bun. Its JavaScript handles host operations; it does not implement the
language or compiler.

```js
import { instantiateFlexscript } from './platform/wasm-host.js'

const response = await fetch('./hello.wasm')
if (!response.ok) throw new Error(`WASM fetch failed: ${response.status}`)
const decoder = new TextDecoder()
const app = await instantiateFlexscript(await response.arrayBuffer(), {
    stdout(bytes) { console.log(decoder.decode(bytes)) },
    stderr(bytes) { console.error(decoder.decode(bytes)) },
})

app.run(['hello.wasm', 'argument'])
// Other exported functions also take BigInt arguments.
```

`app.run` constructs argc/argv in linear memory when needed and returns a BigInt
result. `app.alloc(size)` and `app.string(text)` allocate host inputs. Repeated
calls share instance globals and heap state. `examples/wasm/index.html` displays
the hello example; serve the repository root over HTTP after building its
`hello.wasm`. Keep generated modules out of source control.

Pure programs have no host imports. Programs using `syscall` import
`flex.syscall`, taking seven i64 arguments and returning i64. The default adapter
implements writes to fd 1/2 through the supplied callbacks, and exit/exit_group
through `app.run`. A missing output callback returns `-9`; other operations
return `-38` (ENOSYS). Calling an export directly instead of `app.run` also means
handling the exit exception directly. Custom `host.syscall(number,a,b,c,d,e,f)`
replaces the adapter; its `this` is the application, including `this.memory` and
`this.defaultSyscall(...)` for fallback. Networking, windowing, graphics and audio
need platform implementations; the browser cannot execute Linux syscalls.

Unresolved FFI intrinsics become imports from `flex`: `ffi_open`, `ffi_symbol`,
`ffi_call`, `ffi_call_i32`, `ffi_call_u32`, with the source argument counts.
The i32/u32 call forms normalize their result to the appropriate 32-bit value.
Named source functions still override these intrinsics. Hosts can implement
virtual library/symbol handles and dispatch to platform APIs. A missing handler
throws an explicit capability error when called. Native library pointers and
System V callbacks cannot cross into WebAssembly.

## Compiler inside WebAssembly

The full compiler itself can be compiled to WebAssembly:

```sh
build/flex-wasm --target wasm32 compiler/main.flex -o build/compiler.wasm
```

`platform/wasm-files.js` supplies the compiler's required open/read/write/close,
fstat, truncate and mode operations over a virtual file map. It never opens host
files. Load source files, including local imports, into that map before compiling:

```js
import { createMemoryHost } from './platform/wasm-files.js'

const host = createMemoryHost({
    'app.flex': 'fn main(){return 42;}',
}, { stderr(bytes) { console.error(new TextDecoder().decode(bytes)) } })
const compiler = await instantiateFlexscript(compilerBytes, host)
const status = compiler.run(['flex', '--target', 'wasm32', 'app.flex', '-o', 'app.wasm'])
if (status !== 0n) throw new Error(`Compilation failed: ${status}`)
const applicationBytes = host.readFile('app.wasm')
const application = await instantiateFlexscript(applicationBytes)
application.run() // 42n
```

Use a fresh compiler instance for each invocation, as for the native command-line
process. The file adapter is sufficient for compilation and local imports, not
an implementation of all Linux services. URL fetching, upgrades, VM/JIT execution
and native FFI need additional host services. The compiler can emit native ELF
as well; that output still runs on its native target.

## Verification

The test driver and assertions are written in Flexscript. Bun supplies a
headless WebAssembly engine through `scripts/wasm-runner.js`:

```sh
build/flex-wasm scripts/test-wasm.flex -o build/test-wasm
build/test-wasm build/flex-wasm --report build/wasm-tests.json
```

The suite covers the existing valid and invalid source corpus, full-word native
differential arithmetic, nested control flow, short-circuit call arguments,
globals, imports, strings, argc/argv, memory growth, traps, virtual file I/O and
explicit host FFI. It also compiles the compiler to WASM, runs its self-build in
WASM, compares the rebuilt module byte-for-byte, and runs an application produced
by that rebuilt compiler. CI runs the suite after the native bootstrap.
The WASM-hosted compiler is also checked producing a native Linux ELF executable.

This target is a foundation for a future Setaworld/FlexOS port. It does not yet
provide Setaworld's physics, rendering or platform services, or replace its
existing SetaScript engine/content implementation.
