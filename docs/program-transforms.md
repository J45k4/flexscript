# Compile-time program extensions

An `extend` declaration loads a Flexscript program that inspects and extends
ordinary application functions. For example:

```flex
extend "../extensions/compose.flex" with "step";
fn step(x) {return x+7;}
fn main() {return step_twice(28);}
```

The extension generates `step_twice`; the application returns 42. Paths resolve
relative to the declaring module. `with` supplies an optional configuration
string. Put extension declarations in the module header alongside imports.
The compiler contains no composition or autodiff special cases.

```sh
build/flex-gpu compiler/main.flex -o build/flex-transform
build/flex-transform examples/transforms/compose.flex -o build/compose
build/flex-transform run --jit examples/transforms/compose.flex
build/flex-transform --target wasm32 examples/transforms/compose.flex -o build/compose.wasm
build/flex-transform --target sass-sm75 examples/transforms/gpu.flex -o build/compose.cubin
```

## Hooks and ordering

An extension exports either or both two-argument hooks:

```flex
import "../compiler/transform-sdk.flex";
fn transform_program(context,version) {
    ext_init(context,version);
    let function=ext_find_function(ext_config());
    if function<0 {ext_error("unknown function");}
    // Inspect instructions and submit source edits with the SDK.
    return ext_finish();
}
```

After loading application imports, the compiler runs all `transform_syntax`
hooks in declaration/load order. They receive source bytes before ordinary
parsing, with empty function/instruction tables. They can implement new syntax.
It then runs each `transform_program` hook, supplying an inspection-only word
IR of the current source. Previous edits are visible to later hooks.

Generated source is compiled again normally, including name/arity checks and
backend restrictions. The interpreter and JIT use the same expansion path.
This initial interface returns source edits, rather than executable bytes or
replacement IR. It exposes word IR, not a typed SSA graph. Named float calls
retain their mathematical identity before software/ISA lowering; ordinary
integer operators keep their integer semantics.

Inspection snapshots allow unresolved calls to functions an extension will
generate. Final compilation must resolve them. Snapshots are not executable
frontend FIR. String/global pointer operands are virtual analysis offsets, not
host addresses; their memory image is not exposed.

## SDK API1

| API | Purpose |
| --- | --- |
| `ext_init(context,version)`, `ext_finish()` | Initialize context; serialize edits |
| `ext_phase()`, `ext_config()`, `ext_request_module()` | Phase0/1, configuration and declaring module |
| `ext_module_count()`, `ext_module_path(i)`, `ext_module_text(i)`, `ext_module_size(i)` | Inspect loaded modules |
| `ext_module_declarations(i)` | First editable declaration byte offset |
| `ext_function_count()`, `ext_find_function(name)` | Enumerate/find functions; missing lookup returns -1 |
| `ext_function_name(i)`, `ext_function_arity(i)`, `ext_function_slots(i)` | Function metadata |
| `ext_function_module(i)`, `ext_function_offset(i)`, `ext_function_size(i)` | Definition source span |
| `ext_function_source(i)` | Definition bytes; use its separate size |
| `ext_function_effects(i)` | Conservative direct effects |
| `ext_function_instruction_count(i)`, `ext_op(i,pc)`, `ext_arg(i,pc)` | Instructions by index |
| `ext_call_name(call)`, `ext_call_arity(call)`, `ext_call_function(call)` | Call symbol; missing function index is -1 |
| `ext_edit(module,start,end,text,size)` | Replace bytes; equal endpoints insert |
| `ext_replace_function(i,text)`, `ext_append(module,text)` | Replace/append declarations |
| `ext_begin()`, `ext_emit(text)`, `ext_emit_number(n)`, `ext_append_output(module)` | Bounded source builder |
| `ext_error(message)`, `ext_error_at(module,offset,message)` | Located diagnostic |

Instructions are 16-byte `(opcode,operand)` records: 1 constant, 2 push, 3/4 local
load/store,5/6 global load/store,7 integer binary operation,8 call,9 return,
10/11/12 branches,13 boolean normalization,14 integer negation,15 logical not,
16 complement,17 builtin and18 frame. A call operand indexes the snapshot call
table, not the function table. Branches use absolute instruction-section byte
offsets. Function spans include the frame and implicit final return.

Effect bits are global read1, global write2, memory read4, memory write8,
allocation16, syscall32, call64 and string literal128. Float primitives also
set the call bit. These flags are direct; extensions must analyze callees or
require explicit contracts before treating calls as pure.

Edits refer to snapshot byte offsets. Disjoint edits may be submitted in any
order; same-offset insertions preserve submission order. Overlapping replacements
are rejected. Existing imports/extension headers cannot be edited. Generated
declarations use existing application imports. Disk source files are unchanged.

## Autodiff extension

```flex
import "../lib/gpu.flex";
extend "../extensions/autodiff.flex" with "f64:loss";
fn loss(x) {
    return gpu_f64_add(gpu_f64_mul(x,x),gpu_f64_mul(gpu_f64_from_i64(3),x));
}
// Generated loss_grad(x) evaluates 2*x + 3.
```

Use `f32:name` or `f64:name`. The generated `name_grad` has the original
parameters and returns the forward derivative with respect to parameter0;
other parameters are held constant. Values/derivatives are IEEE bit-pattern
words, as in `lib/gpu.flex`. No float literal or operator syntax is added.
Binary64 also recognizes the portable `f64_*` math family and generates matching
portable calls; `examples/transforms/portable.flex` requires only `lib/f64.flex`.

Supported: straight-line functions, mutable locals and add/subtract/multiply/
divide/sqrt/FMA primitives. The extension differentiates mathematical operations
with floating-point evaluation, rather than discrete bit-level rounding.
Singular inputs follow the generated float operations' NaN/infinity behavior.
Branches, loops, active integer bit arithmetic/conversions, strings and direct
memory/global effects are rejected. Reverse mode, tapes, tensor rules and alias
analysis remain future work; arbitrary programs are not differentiable yet.

Custom calls use a normal `NAME_jvp` function receiving alternating argument
values and tangents. For example:

```flex
fn cube(x) {return gpu_f64_mul(gpu_f64_mul(x,x),x);}
fn cube_jvp(x,dx) {
    return gpu_f64_mul(gpu_f64_mul(gpu_f64_from_i64(3),gpu_f64_mul(x,x)),dx);
}
```

Custom rules take precedence over built-in rules and require twice the primal
arity. Their authors own the mathematical/effect contract. CPU fallbacks retain
existing `lib/gpu.flex` restrictions, including GPU-only FMA. Generated GPU
derivatives use the ordinary PTX/direct-SASS backends, with no extra toolchain.
See `examples/transforms/autodiff.flex` for CPU and GPU entry points.

## Limits and tests

Hooks run in separate restricted VMs with 256 MiB guest heaps, 50 million
instruction fuel, five-second execution deadlines and 1 MiB diagnostic output.
Guest file/network/raw FFI grants are absent. Static imports use the normal
compiler loader; URL imports and nested extensions are disabled for extensions.
External frontend programs cannot activate nested program extensions either.

Limits: 16 extension declarations, 256 edits per hook, 32 MiB inspection snapshots,
less than 16 MiB combined transformed source and 1 MiB text-builder fragments.
Source/extension identities, including imported extension files and hard links,
are checked before truncating output. Failed hooks preserve existing artifacts.

This version requires a Linux compiler host and ordinary Flexscript input.
Native, VM/JIT, WASM output, PTX and SM75 SASS are supported. Wasm-hosted extension
loading and bare-metal output report explicit errors. Programs without extensions
retain their existing compilation routes.

```sh
build/flex-transform scripts/test-transforms.flex -o build/test-transforms
build/test-transforms --compiler build/flex-transform --report build/transform-tests.json
build/test-transforms --compiler build/flex-transform --gpu --report build/transform-tests-device.json
```

Tests cover ordering, imports, composition, replacement, custom derivatives,
scalar float rules, interpreter/JIT/native/WASM parity, GPU output, malformed
edits, capability/fuel limits and output identity preservation. CI runs the
device-free suite with Bun.

On the RTX 2070, the final suite passed 2,713 checks across ten GPU launches
(PTX and direct SASS for composition, FP32/FP64 polynomial derivatives, FMA,
and a division/square-root chain). The device-free suite passed153 checks.
Native84, import46, VM457, WASM821 and existing frontend-extension529 checks
also passed. Native and Wasm compiler self-builds remained byte-identical.
