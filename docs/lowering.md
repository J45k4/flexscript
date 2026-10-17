# Function lowering hooks

A source declaration binds an ordinary **resolved function symbol** to a backend
operation. Names have no special meaning unless explicitly registered (existing
reserved `gpu_*` intrinsics remain supported for compatibility):

```flex
import "../lib/f32.flex";
lowering game_add "f32.add";
fn game_add(a,b) {return f32_add(a,b);}
fn main() {return game_add(0x3f800000,0x40000000)==0x40400000;}
```

Put imports first, then globals/lowerings, then functions. A registration may
precede an imported function definition: the compiler binds and validates the
complete symbol table, including calls emitted before a definition. The language
currently has a global function namespace, so duplicate definitions are errors.
A registration requires a real function with the operation's arity; undefined
symbols, builtins, unknown operations/targets and conflicting registrations are
errors, including unused registrations. Compilation failures preserve an existing
output file. The function body must implement the declared operation's contract.
The compiler checks syntax and arity, not semantic equivalence.

An optional selector limits where the replacement is available:

```flex
lowering game_add "f32.add" "native-x86_64";
// Or: lowering game_add "f32.add" "gpu";
```

Omitting the selector permits all supporting backends. Unsupported backends use
the ordinary body. Interpreter, JIT, Wasm and bare-metal targets currently use
that body. Native Linux x86-64 emits SSE2; GPU registrations reuse the existing
HIP, RDNA, PTX and SASS operation emitters and their existing numerical contracts
and supported-operation limits. Vector/word operations below currently have
native emitters only, so GPU uses their bodies. Legacy reserved GPU intrinsics
retain their documented target restrictions.

| Operation | Arity | Native behavior |
| --- | ---: | --- |
| `f32.add/sub/mul/div` | 2 | Binary32 arithmetic on low-word IEEE bits |
| `f32.sqrt` | 1 | Binary32 square root |
| `f64.add/sub/mul/div` | 2 | Binary64 arithmetic on IEEE word bits |
| `f64.sqrt` | 1 | Binary64 square root |
| `f32.dot3` | 6 | `(x*a + y*b) + z*c`, separate binary32 rounding |
| `f32.dot3.load` | 2 | Same dot product; pointers to three 8-byte word slots |
| `word.add` | 2 | Wrapping 64-bit integer addition |
| `word.xor` | 2 | 64-bit exclusive-or |
| `lowering.active` | 0 | 1 when native lowering is enabled; body supplies fallback |

`lib/f32.flex` provides neutral `f32_add/sub/mul/div/sqrt/dot3/dot3_load` functions.
`lib/gpu.flex` registers its existing float helpers, and native-only bindings
for the imported `f64_add/sub/mul/div/sqrt` implementations. Importing only
`lib/f64.flex` retains the original bootstrap-safe software implementation.
Conversions, comparisons and FMA have not acquired native emitters here.
Words and the call ABI remain 64-bit; this does not introduce a language type
system or change array layout. `f32.dot3.load` requires two readable 24-byte
vectors and uses the low 32 bits of each word, with no writes.

Native ELF startup establishes MXCSR 0x1f80: nearest-even rounding, masked FP
exceptions, gradual subnormals, with neither DAZ nor FTZ. Arithmetic canonicalizes
NaNs to positive 0x7fc00000/0x7ff8000000000000, preserving signed zeros. Dot
products keep the portable expression's multiplication/addition order and do
not emit FMA. FP status flags are not part of the word API. Foreign functions
must preserve the floating-point control environment as required by the native
ABI. No AVX, host CPU detection or optional instruction extension is required.

Native direct source calls emit operations inline after evaluating arguments
once, left to right. Registered functions also receive an entry thunk so calls
from FIR platform adapters and ordinary linked call sites get the same lowering.
Software bodies remain parsed and validated. Reference mode disables both
replacement routes:

```sh
build/flex --lowering-mode reference program.flex -o program-reference
build/flex --lowering-mode hardware program.flex -o program-native
```

Hardware is the native default. The option is rejected for non-native output;
VM/Wasm naturally execute the fallback body. `native_lowering_active()` from
`lib/lowering.flex` returns the compiled mode (1 native hardware, 0 fallback).
It reports mode availability, not whether a particular operation has an emitter.

The generic boundary is in `compiler/lowering.flex`: operation registry,
declaration parsing, symbol/arity validation, target selection and native
emitters. `gpu_intrinsic()` consults explicit resolved-symbol registrations
before its compatibility name table. New hardware operations require adding an
operation contract and backend emitter in the compiler, not code in physics.
Existing sandboxed source extensions can emit `lowering` declarations through
their syntax-edit hook; they do not receive arbitrary machine-code access.

Run the regression suite after building the current compiler:

```sh
build/flex scripts/test-lowering.flex -o build/test-lowering
build/test-lowering build/flex
```

It covers custom names, software mode, VM/JIT/Wasm fallbacks, native FIR platform
calls, extension-generated declarations, invalid bindings/output preservation,
GPU compilation, 144,000 randomized scalar/vector comparisons, directed FP32
edge cases and the existing 64,498-record independent FP64 oracle. CI builds and
runs this suite alongside the original software arithmetic tests.

The [optimizing CPU kernel target](cpu-kernels.md) consumes the same symbol
bindings. `cpu-cxx` may also be named as a target selector. Its optional
`f32x2.add/sub/mul` operations pack two independent FP32 lanes into one word;
other targets retain the portable function bodies.
