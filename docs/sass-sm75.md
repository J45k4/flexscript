# Direct NVIDIA Turing machine code

The experimental `sass-sm75` backend translates Flexscript word IR directly to
Turing SASS instructions and writes its own ELF cubin:

```sh
build/flex compiler/main.flex -o build/flex-sass
build/flex-sass --target sass-sm75 examples/gpu/direct.flex -o build/direct.cubin
build/flex-sass scripts/sass-run.flex -o build/sass-run
build/sass-run build/direct.cubin
```

No PTX, `ptxas`, `nvcc`, CUDA toolkit, external assembler/linker, instruction
database or precompiled cubin template is used during compilation. The backend
and container writer are implemented in `compiler/sass.flex`. Compiling needs
no GPU or CUDA library. The existing CUDA Driver API adapter loads the resulting
native instructions and dispatches them; execution still needs a compatible
NVIDIA GPU and driver with `libcuda.so.1`. There is no PTX JIT step for this
artifact. The runner's launch adapter needs CUDA 12+ driver interfaces.

The [Pup tensor frontend](../libs/ml/pup/README.md) also compiles model graphs
through this backend: `.pup -> primitive tensor graph -> scheduled Flexscript
kernel -> word IR -> SASS cubin`. Its MNIST runner loads named F32 safetensors
and launches the resulting stages through the same CUDA adapter.

This target is specific to SM75, verified on an RTX 2070. It does not produce
portable binaries for arbitrary NVIDIA GPUs. Use the PTX target when broader
device compatibility is needed.

## First supported tier

The kernel ABI matches the [PTX backend](gpu.md):

```flex
fn kernel(index, input, output, count) {
    let value = load64(input + index * 8);
    store64(output + index * 8, (value + 7) * 3);
    return 0;
}
```

`flex_kernel` receives three 64-bit arguments: input pointer, output pointer and
element count. Its generated prologue computes the block-major linear lane index
and exits lanes outside the count. The source kernel gets four word parameters;
its return value is discarded. `main` is optional for this target.

Supported source operations now include all word integer operators, unary
operations, locals and mutation, branches, loops, short-circuit expressions,
nonrecursive helper calls, local imports and global-memory byte/word accesses.
All integer arithmetic wraps at 64 bits; signed division/remainder trap on zero
and MIN/-1. Byte decomposition preserves unaligned little-endian memory access.
Helper calls are inlined into fixed register frames. Recursion, allocation,
syscalls and FFI in the kernel are rejected; globals and string literals are
rejected throughout the compilation unit. Only the Flexscript frontend is
accepted. Excessive register demand is rejected because spilling is not
implemented. No automatic fallback to PTX occurs.

The backend also emits native instructions for GPU coordinates, shared memory,
block/warp synchronization, masks/ballots/shuffles, 64-bit atomics, FP32/FP64
add/subtract/multiply/FMA, integer conversions, FP16 tensor fragments and 1D
float texture fetches. Floating divide and square root emit restoring integer
SASS routines with nearest-even rounding, subnormals, signed zeros and infinity
handling. These routines reserve 16 scratch words beyond the live helper frames
and favor correctness over speed; no PTX fallback or NVIDIA compiler is used.
Their NaN payload policy is documented in the feature guide.
See the [feature matrix and API guide](gpu-features.md) for signatures, alignment
and collective-participation rules. The wrapper supports three-dimensional
launch geometry and exits threads outside the count.

Each IR word gets an even-aligned physical register pair. Locals, accumulator,
pending operands and inlined helper frames have fixed pairs. Addition/subtraction
propagate carry between halves; multiplication combines 32-bit limb products;
signed division uses a bounded integer long-division sequence. Rejection happens
before opening the output file, preserving an existing artifact.

Scheduling is intentionally conservative: instructions wait on all dependency
scoreboards, yield, and stall 15 cycles. Loads and special-register reads set
write barrier 0; stores set read barrier 0 to protect their source registers.
These dependency barriers handle variable latency separately from fixed stalls.
No register reuse or latency-hiding optimization is attempted. The emitter
limits code to 1 MiB and exit metadata to 16,383 sites.

The ELF writer emits its own symbol/string tables, `.nv.info`, kernel parameter
and exit metadata, constant bank, executable section and program headers.
There are no instruction templates or binary container fixtures loaded at
compile time. The CUDA launch parameters retain the conventional constant-bank
offsets `0x160`, `0x168` and `0x170`.

## Verification

```sh
build/flex-sass scripts/test-sass.flex -o build/test-sass
# Runs without a GPU, CUDA libraries or NVIDIA tools:
build/test-sass --compiler build/flex-sass --report build/sass-tests.json
# Optional independent decoding, without executing on a GPU:
build/test-sass --compiler build/flex-sass --nvdisasm /path/to/nvdisasm
# Require physical-device parity with CPU and driver-compiled PTX references:
build/test-sass --compiler build/flex-sass --nvdisasm /path/to/nvdisasm --gpu
```

The suite covers carry/borrow, signed extremes, wrapping products, bitwise
operations, unaligned reads/writes, byte stores returning full-width values,
locals, imports, register exhaustion and unsupported operations. It compiles
with an empty toolchain search path and checks deterministic bytes, ELF bounds,
non-executable file permissions and preservation of output files on rejection.
Physical runs include zero elements, counts 1/127/128/129 and 4,099 elements,
and check an output canary beyond the allocation's logical payload. `--gpu`
requires successful device execution; it fails if the device is unavailable.

On an RTX 2070 with NVIDIA 610.57.04, the original 19 direct SASS kernels passed independent
`nvdisasm` decoding and CPU/PTX parity, with 225 checks and 43 physical-device
runs. The compiler also rebuilt byte-identically. Existing native (84), PTX
compiler (114) and WASM (821) checks passed. These establish correctness for
the tested subset; no performance advantage is claimed.

Encoding research used [turingas's Turing instruction descriptions](https://github.com/daadaada/turingas/blob/master/turingas/grammar.py)
and [CuAssembler's scheduling/container guide](https://github.com/cloudcores/CuAssembler/blob/master/UserGuide.md).
The implementation was checked against [NVIDIA nvdisasm](https://docs.nvidia.com/cuda/cuda-binary-utilities/)
and physical-device results. NVIDIA tools are optional development verifiers,
not dependencies of the Flexscript compilation path.

The expanded integer suite passed 357 checks over 36 cubins and 77 physical
runs. The GPU-feature suite passed 11,461 checks over 44 programs/device runs,
including isolated division traps. Native (84), VM (457), PTX assembly/compiler
(140), WASM (821) and host harness (29) checks passed; self-hosting remained
byte-identical. See [GPU features](gpu-features.md) for the newer APIs.

The dedicated floating divide/sqrt corpus passed 184,340 checks over 10 device
launches, including randomized inputs, subnormals, rounding ties, NaNs, signed
zeros and nested helper frames. Non-NaN results matched PTX bitwise; binary64
also matched the independent portable library.
