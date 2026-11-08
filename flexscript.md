# Flexscript language reference

This document describes Flexscript as released in **0.0.6**. It is the current
reference for ordinary `.flex` source, its execution models and the compiler's
extension points. Target-specific interfaces are linked where their behavior
differs. A release tag preserves the source and documentation for that release;
changes on `master` do not retroactively change a published compiler.

Flexscript is an imperative, self-hosted language. Its core values are 64-bit
words, with explicit memory access and named functions. The compiler, VM/JIT,
frontend extensions and code generators are implemented in Flexscript.

```flex
global calls = 0;

fn twice(value) {
    calls = calls + 1;
    return value * 2;
}

fn main() {
    let answer = twice(21);
    if calls == 1 && answer == 42 {
        return answer;
    }
    return 1;
}
```

Saved as `answer.flex`, this program returns 42:

```sh
flexscript answer.flex -o answer
./answer
flexscript run answer.flex
flexscript run --interpret answer.flex
flexscript run --jit answer.flex
```

On Linux, the return value becomes the process exit status modulo 256. A
nonzero result such as 42 is intentional in these examples. WebAssembly exports
return the full word to their host.

## Source and lexical rules

Source is a byte sequence. Identifiers use ASCII letters or `_`, followed by
ASCII letters, digits or `_`. Identifiers are case-sensitive. Spaces, tabs,
carriage returns and newlines separate tokens. `//` starts a comment ending at
the next newline. Block comments are not part of the core syntax.

Decimal integer literals range from `0` through `9223372036854775807`.
Hexadecimal literals use the lowercase prefix `0x` followed by hexadecimal
digits and may represent any 64-bit pattern. For example,
`0x8000000000000000` is the signed minimum word. Negative expressions use unary
`-`; the sign is not part of the literal token.

Double-quoted strings contain bytes, normally UTF-8 text. They cannot contain
literal newlines, carriage returns or zero bytes. The supported escapes are
`\n`, `\r`, `\t`, `\0`, `\\` and `\"`. The compiler appends a zero byte;
embedded zero bytes introduced with `\0` do not truncate the stored literal.
A string expression evaluates to its storage address, not a managed string
object. Core memory operations can modify this storage.

Core declaration names reserve `fn`, `global`, `let`, `if`, `else`, `while`,
`return`, `import`, the six core builtins listed below, and the bare-metal
hardware builtin names, including `native_callback`. `extend` and `with` are
recognized in module headers. FFI intrinsic names can be overridden by ordinary
function definitions, as required by the static bootstrap core.

There are no core `true`, `false` or `null` literals: use word values such as
`1` and `0`. There are no core floating-point literals or type annotations.

## Values, arithmetic and evaluation

Every core value is one 64-bit word. Integer arithmetic and ordering interpret
words as signed two's-complement integers; pointers and floating-point bit
patterns are represented by the same words. The language does not distinguish
them with static types.

| Operation | Semantics |
| --- | --- |
| `+`, `-`, `*`, unary `-` | Wrap modulo 2^64. |
| `/` | Signed division, truncated toward zero. |
| `%` | Signed remainder, with the dividend's sign. |
| `/` or `%` with zero, or signed minimum divided by `-1` | Trap, including the corresponding remainder overflow case. |
| `<<`, `>>` | Use the low six bits of the shift count; `>>` is arithmetic. |
| `&`, `^`, `\|`, `~` | Word bitwise operations. |
| `==`, `!=`, `<`, `<=`, `>`, `>=` | Produce `0` or `1`; ordering is signed. |
| `!`, `&&`, `\|\|` | Treat zero as false and every other word as true; produce `0` or `1`. |

Operands and function arguments evaluate left to right. `&&` evaluates its
right operand only when the left operand is nonzero. `||` evaluates its right
operand only when the left operand is zero.

Precedence, highest first:

| Level | Operators |
| --- | --- |
| 1 | Named calls and parenthesized expressions |
| 2 | Unary `-`, `!`, `~` |
| 3 | `*`, `/`, `%` |
| 4 | `+`, `-` |
| 5 | `<<`, `>>` |
| 6 | `<`, `<=`, `>`, `>=` |
| 7 | `==`, `!=` |
| 8 | `&` |
| 9 | `^` |
| 10 | `\|` |
| 11 | `&&` |
| 12 | `\|\|` |

Binary operators associate left. Assignment is a statement, not an expression.
There is no core compound assignment, increment/decrement or ternary operator.

## Declarations, scope and control flow

`global name = literal;` declares a mutable global word. Its initializer must
be an integer literal, optionally preceded by `-`, rather than a general
expression. Each module places globals before its function definitions.
Globals and functions share one namespace across the entire import graph.
Duplicate declarations in that namespace are errors.

`fn name(parameters) { ... }` declares a named function with word parameters
and a word result. Calls can refer to functions declared later, including
functions in other modules. Recursion and mutual recursion are supported by
the CPU language; execution budgets and GPU target restrictions still apply.
Argument counts must match. Reaching the end of a function returns zero.
Functions are not first-class values, and ordinary call syntax does not call
a pointer stored in a local variable.

`let name = expression;` declares a mutable local in the current block.
Parameters are mutable locals and share a scope with the outer function body.
Nested blocks can shadow outer locals or globals. An initializer is evaluated
before its new local binding becomes visible: an inner `let x = x + 1;` can
refer to an outer `x`. Redeclaring a local or parameter in the same scope, or
using an undefined variable, is an error.

Supported statements are declarations, assignment to a named local or global,
expression statements, `return expression;`, nested blocks,
`if expression { ... } else { ... }`, `else if`, and
`while expression { ... }`. Conditions do not require parentheses. Braces are
required for control-flow bodies; expression statements, assignments,
declarations and returns end with `;`.

The core has no `for`, `break`, `continue`, exceptions, classes, aggregate
literals, indexing syntax or closures. Such syntax in an extension or another
frontend does not implicitly become ordinary Flexscript syntax.

### Core grammar

This grammar describes the ordinary frontend before any extension-provided
syntax expansion. `identifier`, `integer` and `string` follow the lexical
rules above; reserved declaration names are excluded where appropriate.
The expression rule is subject to the precedence and associativity table.

```ebnf
module       = { header }, { global }, { function } ;
header       = "import", string, ";"
             | "extend", string, [ "with", string ], ";" ;
global       = "global", identifier, "=", [ "-" ], integer, ";" ;
function     = "fn", identifier, "(", [ parameters ], ")", block ;
parameters   = identifier, { ",", identifier } ;
block        = "{", { statement }, "}" ;
statement    = "let", identifier, "=", expression, ";"
             | identifier, "=", expression, ";"
             | "return", expression, ";"
             | conditional
             | "while", expression, block
             | block
             | expression, ";" ;
conditional  = "if", expression, block, [ "else", ( block | conditional ) ] ;
expression   = primary
             | unary, expression
             | expression, binary, expression ;
primary      = integer | string | identifier
             | identifier, "(", [ arguments ], ")"
             | "(", expression, ")" ;
arguments    = expression, { ",", expression } ;
unary        = "-" | "!" | "~" ;
binary       = "+" | "-" | "*" | "/" | "%" | "<<" | ">>"
             | "<" | "<=" | ">" | ">=" | "==" | "!="
             | "&" | "^" | "|" | "&&" | "||" ;
```

## Modules and program extensions

Imports and extension declarations appear in the module header, before globals
and functions. Header declarations can be interleaved.

`import "path.flex";` loads definitions into the shared program namespace.
Relative paths resolve against the importing file, not the process's working
directory. Repeated local imports are deduplicated by file identity, including
aliases and symlinks. Cyclic imports are errors. Imports do not introduce
runtime module loading, aliases or selective exports.

HTTP and HTTPS source URLs are supported. Relative imports in downloaded
modules resolve against the final source URL. HTTPS verifies certificates and
hostnames through OpenSSL 3. Source downloads are enabled for ordinary native
compilation and trusted VM execution; `--no-url-imports` disables them for VM
execution, and restricted execution requires `--allow-url-imports` to opt in.
There is no persistent source download cache. See [imports](docs/imports.md)
for URL normalization, redirects and graph limits.

`extend "extension.flex" with "configuration";` invokes a program extension;
the configuration is optional. Syntax hooks run before ordinary parsing, and
program hooks inspect word IR and submit source edits. Generated source is
checked again for normal name, arity and target rules. Extension execution is
bounded and isolated from application execution; it does not rewrite source
files on disk. See [program transformations](docs/program-transforms.md) for
hook ordering, the SDK, composition and autodiff.

## Memory and core builtins

Core pointers are word values. Address units are bytes; `p + 8` advances eight
bytes. `load64` and `store64` use little-endian words and allow unaligned
accesses. There is no implicit pointer scaling.

| Builtin | Arguments and result |
| --- | --- |
| `load8(address)` | Read one byte and zero-extend it to a word. |
| `load64(address)` | Read an eight-byte word. |
| `store8(address, value)` | Write the low byte and return the original full word `value`. |
| `store64(address, value)` | Write a word and return `value`. |
| `alloc(bytes)` | Request zero-initialized storage; return its address or a negative error. |
| `syscall(number, a, b, c, d, e, f)` | Invoke the execution target's syscall interface; all seven arguments are required. |

Allocation and address validity are execution-model contracts. Native Linux
and trusted VM code use host addresses and can access process memory directly.
Restricted VM code uses checked offsets into a private heap. WebAssembly uses
checked addresses in instance linear memory. Invalid native accesses can fault
the process; invalid guest accesses trap. Restricted memory isolates a guest
from its host but does not isolate objects within the same guest heap.

There is no core garbage collector, ownership system, automatic object lifetime
or `free` builtin. Native code can release mappings through platform syscalls;
the restricted VM and WebAssembly allocators have their own documented limits.

On Linux x86-64, raw syscalls use Linux numbers, return negative errno on
failure, and run with the process's permissions:

```flex
fn main() {
    let message = "Hello, Flexscript!\n";
    let written = syscall(1, 1, message, 19, 0, 0, 0);
    if written != 19 { return 1; }
    return 0;
}
```

This write also works through the supplied restricted VM and WebAssembly stdout
adapters. Other Linux operations require the appropriate VM grants or host
implementation; a browser does not implement arbitrary Linux syscalls.

### Foreign calls and hardware operations

The Linux compiler resolves undeclared `ffi_open(name)` and
`ffi_symbol(handle, name)` calls to dynamic-library operations. It also provides
`ffi_call(pointer, a, b, c, d, e, f)`, `ffi_call_i32(...)` and
`ffi_call_u32(...)`. All six argument slots are required; unused slots are zero.
The latter two normalize C signed/unsigned 32-bit results to words.
An ordinary function definition with one of these names takes precedence.

Native FFI supports integer/pointer arguments through the System V AMD64 ABI.
It does not provide automatic C headers, floating-point argument registers,
variadic calls or aggregates passed by value. Dynamic-library loading requires
the glibc loader and libc. WebAssembly turns unresolved FFI operations into
host imports rather than exposing native library pointers. Restricted VM
execution rejects raw FFI; its host grants cover selected services rather than
arbitrary library loading or function-pointer calls.
See [FFI](docs/ffi.md) and [VM permissions](docs/vm.md).

The bare-metal target additionally provides `port_in8`, `port_out8`, their
16/32-bit variants, and `cpu_halt`. These are not general Linux or VM operations.
See [bare metal](docs/baremetal.md) for their exact signatures.

`native_callback(function_name)` produces a six-word System V AMD64 callback
address for native x86-64 code, including Linux and bare metal. The named
Flexscript function must take six arguments. This is not a VM or portable-target
function pointer. The [Linux thread library](libs/thread/README.md) uses these
callbacks to start shared-memory kernel threads and provides joining, native
atomics, and futex-backed mutexes. Its initial support is native Linux x86-64;
ordinary compilation of threading code does not establish concurrency safety.

## Entry points and execution models

An ordinary CPU program defines `fn main()` or `fn main(argc, argv)`.
`argc` includes the program name; `argv` points to an array of zero-terminated
string addresses. Linux native startup and trusted VM startup also provide
the native-style environment layout after the argument terminator. Restricted
VM startup supplies an empty environment.

| Mode | Contract |
| --- | --- |
| Native Linux, default compilation target | Direct x86-64 ELF emission. Programs using no dynamic-library loading need no libc; host addresses and syscalls are unrestricted by the compiler. |
| `flexscript run app.flex` | Trusted VM execution with native pointers, syscalls and FFI, subject to the VM's execution limits. |
| `run --interpret` / `run --jit` | Select interpretation or eager compilation of eligible functions; ordinary word semantics stay the same. The default mode JIT-compiles eligible hot functions. |
| `run --restricted` | Checked guest memory, explicit host capabilities, fuel and deadline enforcement. |
| `--target wasm32` | WASM32 module with i64 values and exported functions/memory. Its host calls the entry point; instantiation does not run `main`. This is not a WASI ABI. |
| `--target baremetal-x86_64` | Multiboot x86-64 image with a zero-argument `main`; hardware access replaces Linux allocation and syscalls. |

`flexscript app.flex [args...]` is a shortcut for VM execution with default
settings. Use explicit `run` to set VM options. The VM does not load `.wasm`
files; a WebAssembly host instantiates those modules separately.

The VM's heap, call stack, fuel and deadline limits differ from unrestricted
native execution. A function can remain interpreted when it is not eligible
for JIT compilation. Trusted blocking host calls are not interrupted by the
VM deadline. See [VM/JIT](docs/vm.md) and [WebAssembly](docs/wasm.md) for budgets,
grants, exports and host adapters.

## Compiler targets and other frontends

```sh
flexscript --target wasm32 answer.flex -o answer.wasm
flexscript --target baremetal-x86_64 kernel.flex -o kernel.bin
flexscript --target ptx examples/gpu/vector.flex -o vector.ptx
flexscript --target sass-sm75 examples/gpu/vector.flex -o vector.cubin
flexscript --target hip examples/gpu/vector.flex -o vector.hip
flexscript --target rdna-gfx1201 examples/gpu/vector.flex -o vector.hsaco
flexscript --target glsl examples/seta/shaders/triangle-vertex.seta -o triangle.vert
flexscript --target glsl-es examples/seta/shaders/triangle-vertex.seta -o triangle-es.vert
flexscript --target wgsl examples/seta/shaders/triangle-vertex.seta -o triangle.wgsl
```

GPU compute targets accept `kernel(index, input, output, count)` and its
supported helper graph rather than requiring `main`. Kernel-reachable
allocation, host syscalls, FFI and recursion are rejected; globals, strings and
individual operations have additional backend restrictions. Device pointers
are not CPU pointers. PTX is a virtual instruction format, `sass-sm75` emits a
Turing cubin, `hip` emits HIP C++ source for runtime compilation, and
`rdna-gfx1201` emits an AMDHSA code object directly. These are experimental
subsets with different device requirements and intrinsic coverage:
[GPU compilation](docs/gpu.md), [GPU features](docs/gpu-features.md),
[Turing SASS](docs/sass-sm75.md), [HIP/RDNA](docs/rdna.md).

The bundled **SetaScript** frontend is selected by `.seta` or `--language seta`.
Its CPU forms provide typed declarations and checked persistent state/table
operations lowered to validated FIR. Its separate shader frontend provides
typed scalars, vectors, matrices, structs, textures and stage interfaces for
GLSL, GLSL ES and WGSL. Shader types and syntax are not ordinary `.flex` syntax;
shader targets require SetaScript input. See
[frontend extensions and FIR](docs/frontend-extensions.md) and
[shader syntax and targets](docs/shaders.md).

`--frontend parser.flex` loads an external source frontend. It returns validated
FIR or FSX1 generated Flexscript source. FIR serves CPU/VM/WebAssembly execution;
FSX1 uses the ordinary parser and supported targets. `--target ir` serializes
FIR frontend output; it is not an ordinary `.flex` output target. Frontend
programs run in a bounded restricted environment, separately from the compiled
application. A Wasm-hosted compiler supports the bundled frontend but not the
Linux external-frontend process transport.

## Libraries and numerical code

Library imports supply higher-level facilities without changing core syntax:

| Facility | Source / reference |
| --- | --- |
| Binary64 arithmetic and mathematical helpers | `lib/f64.flex`, `lib/f64-math*.flex`; [numerical contract](docs/f64.md) |
| TCP, TLS and HTTP | `lib/net.flex`, `lib/tls.flex`; [networking](docs/networking.md), [HTTP](docs/http.md) |
| Native windows, canvas and OpenGL | `libs/gui`; [GUI](docs/gui.md) |
| Terminal UI | `libs/tui`; [TUI](docs/tui.md) |
| ML, autodiff and Pup graphs | `libs/ml`; [ML library](libs/ml/README.md), [Pup](libs/ml/pup/README.md), [transforms](docs/program-transforms.md) |

Portable floating-point helpers receive and return IEEE 754 bit patterns in
ordinary words. `+` remains integer addition even when a word contains a
floating-point encoding; use the numerical helper functions:

```flex
import "lib/f64.flex";

fn main() {
    let numerator = f64_from_i64(84);
    let denominator = f64_from_i64(2);
    return f64_to_i64_trunc(f64_div(numerator, denominator));
}
```

This returns 42 on native, interpreted, JIT and WebAssembly execution.
GPU floating-point intrinsics likewise use named operations with their
documented representations; typed shader arithmetic is a separate frontend.

## Diagnostics, limits and verification

The public executable name is `flexscript`. `--help` describes command options;
`--version` reports the embedded release version. Invalid source or I/O failures
produce nonzero compiler status and stderr diagnostics. Source errors include
a path or URL, line and byte column. Compilation and validation precede output
replacement; source/output aliases and output symlinks are rejected.

For the ordinary 0.0.6 `.flex` frontend, combined source must be smaller than
16 MiB. Limits include 256 source modules, an active import chain of 64 modules,
2,048 globals, 2,048 functions, 4,096 local slots per function, 65,536 call sites
and nesting depth 128 for expressions, blocks and conditional chains. Native
ELF output is bounded at 64 MiB. These are implementation bounds; frontend FIR,
VM memory, shader and GPU backends have their own documented capacities.

The implementation and verification sources are:

- [Core parser, resolver and native emitter](compiler/main.flex).
- [VM/interpreter](vm/runtime.flex) and [JIT](vm/jit.flex).
- [Shared valid/invalid fixtures](tests/cases.json) and [core checks](scripts/test.flex).
- [Imports](scripts/test-imports.flex), [FFI](scripts/test-ffi.flex),
  [VM](scripts/test-vm.flex) and [WebAssembly](scripts/test-wasm.flex) checks.
- [Frontend](scripts/test-extensions.flex), [program transformation](scripts/test-transforms.flex)
  and [shader](scripts/test-shaders.flex) checks.
- [GPU](scripts/test-gpu.flex), [Turing](scripts/test-sass.flex),
  [bare-metal](scripts/test-baremetal.flex) and [KVM](scripts/test-kvm.flex) checks.

The [bootstrap procedure](docs/bootstrapping.md) uses published compiler binaries,
checks byte-identical self-hosted stages, and verifies the static core without
a toolchain or libc. Rust is the historical stage-zero implementation archived
in tag `0.0.1`; current compiler builds and normal language execution do not
require it. [Release signing](docs/signing.md) covers version-bound signed
checksums and [installation](docs/installation.md) covers the public command.
