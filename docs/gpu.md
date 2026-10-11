# Experimental GPU compilation

Flexscript emits NVIDIA PTX directly from its existing word IR:

```sh
build/flex compiler/main.flex -o build/flex-gpu
build/flex-gpu --target ptx examples/gpu/vector.flex -o build/vector.ptx
```

The compiler, backend and CUDA host adapter are written in Flexscript. Emitting
PTX requires no CUDA toolkit, CUDA C, LLVM, assembler, driver or GPU. Device
instructions use registers, branches and calls; the GPU does not interpret
Flexscript bytecode.

## Kernel interface

```flex
fn kernel(index, input, output, count) {
    let value = load64(input + index * 8);
    store64(output + index * 8, value * 3 + 7);
    return 0;
}
```

The source must define `kernel` with four parameters. A `main` function is
optional for this target. The generated entry point is named `flex_kernel`,
with three 64-bit launch arguments: input device pointer, output device pointer,
and element count. It computes a block-major linear `index` from three-dimensional block/thread
coordinates and returns before calling the source kernel when `index >= count`.
The kernel return value is discarded; results go into output memory.

Each GPU lane executes one invocation. Kernels choose their own addressing;
the example treats each element as an eight-byte word. Input/output pointers
refer to device allocations, never ordinary CPU pointers. The launch guard
limits the lane index; explicit pointer arithmetic has no bounds checks.
The same source function can be imported and called on CPU buffers for testing.
Unreachable host functions are omitted from the PTX module.

Supported operations:

- Wrapping 64-bit integer arithmetic, signed comparisons and division/remainder.
- Bitwise operations and shifts, with shift counts masked to six bits.
- Locals, parameter mutation, loops, branches, short-circuit expressions and
  nonrecursive helper calls, including forward calls and local imports.
- `load8`, `load64`, `store8`, `store64` on global device memory. Word accesses
  decompose into bytes to retain unaligned little-endian behavior; stores return
  their original value, including `store8` values wider than a byte.

Division by zero and signed `MIN / -1` or `MIN % -1` emit device traps. CUDA
reports a failed kernel/context rather than a per-lane Flexscript exception.

Kernel-reachable allocation, syscalls, FFI and recursion are rejected. This first
backend also rejects globals and string literals anywhere in the compilation
unit. Input can be Flexscript or an external frontend returning
[FSX1 generated source](frontend-extensions.md#fsx1-source-producing-domain-frontends),
such as the [Pup tensor frontend](../libs/ml/pup/README.md). Portable FIR frontend
results are not GPU kernel IR. Advanced GPU intrinsics now
expose floating-point operations, atomics, shared
memory, barriers, warp operations, tensor fragments and texture fetches. The
host adapter supports multidimensional launches; see [GPU features](gpu-features.md).
There is no optimizer yet.
Loops have no GPU fuel/deadline checks. Use bounded loops and avoid races between
lanes. This is a trusted-code experiment.

## Native GPU machine code

PTX is NVIDIA's virtual instruction set. The CUDA driver can compile it to the
device's native instructions when loading the module. Alternatively, `ptxas`
produces an architecture-specific ELF cubin ahead of time:

```sh
ptxas -arch=sm_75 -v build/vector.ptx -o build/vector.cubin
file build/vector.cubin
```

`sm_75` targets Turing GPUs such as the RTX 2070. Choose the architecture for
your actual device and an assembler version that supports it. The backend
emits PTX 6.0 with a baseline `.target sm_50`; the assembler's `-arch` option
selects the native target. CUDA 12's assembler supports this baseline.
A cubin is native NVIDIA machine code. It still needs a host to allocate device
memory, upload data, dispatch work and retrieve results.

The PTX pipeline is `Flexscript -> word IR -> PTX -> native cubin`. Flexscript
emits PTX itself; NVIDIA's driver/assembler performs native instruction selection,
register allocation and binary packaging. There is also an experimental
[direct Turing SASS backend](sass-sm75.md), selected with `--target sass-sm75`,
which emits instruction bytes and the cubin container itself. It supports a
smaller subset of the language. The Vulkan ray-query runtime accepts SPIR-V shaders compiled externally;
Flexscript-to-SPIR-V and AMD code generation remain future work.

References: [NVIDIA PTX ISA](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html),
[CUDA module loading](https://docs.nvidia.com/cuda/cuda-driver-api/cuda_driver_api/group__CUDA__MODULE.html).

## Run and compare against the CPU

```sh
build/flex-gpu scripts/gpu-run.flex -o build/gpu-run
build/gpu-run build/vector.ptx
build/gpu-run build/vector.cubin
```

The runner checks 4,099 full-width words against the original CPU function,
including signed extremes, wrapping arithmetic and an incomplete final block.
It also checks an output canary beyond the count. Use the artifact built from
`examples/gpu/vector.flex`; this example runner imports that CPU reference.
It prints the CUDA error and exits 77 when no usable device/context is available.
Module, launch, transfer or comparison failures exit unsuccessfully.

`lib/cuda.flex` loads `libcuda.so.1` through the existing integer/pointer FFI.
It exposes context/module creation, buffer allocation, transfers, synchronous and asynchronous
three-dimensional launch, streams/events, pinned transfers, device queries and cleanup. Launch uses CUDA 12+'s `cuLaunchKernelEx`,
whose four arguments fit the existing FFI. No C shim, CUDA runtime library,
`nvcc` or toolkit is needed to run PTX with a compatible NVIDIA driver.
Cubins additionally must match the device architecture. Loading PTX retains
NVIDIA's driver JIT dependency.

## Verification

```sh
build/flex-gpu scripts/test-gpu.flex -o build/test-gpu
# Compiler/diagnostic checks, requiring no GPU or CUDA tooling:
build/test-gpu --compiler build/flex-gpu --report build/gpu-tests.json
# Also assemble every positive fixture to real native code, without a GPU:
build/test-gpu --compiler build/flex-gpu --ptxas /path/to/ptxas --arch sm_75
# On an NVIDIA host: compare each fixture with its CPU implementation:
build/test-gpu --compiler build/flex-gpu --ptxas /path/to/ptxas --arch sm_75 --gpu
```

The suite covers every integer operator, branches/loops, nested expressions,
helper calls, unaligned memory, byte operations, discarded host functions,
unsupported operations and preservation of an existing output on failure.
`--gpu` requires successful device execution; unavailable CUDA fails the suite.
Reports count PTX programs, assembled native cubins and completed device runs
separately. Assembly establishes executable format and ISA validity;
GPU/CPU runtime parity requires device execution.

Initial verification on an RTX 2070 passed 140 checks: 26 fixtures assembled to
`sm_75` native cubins and matched their CPU references in 52 physical-device
runs (PTX and cubin for every fixture). The vector example also matched all
4,099 words through both paths. The existing native (84), VM (457) and WASM
(821) regression checks passed, including compiler self-hosting. These are
correctness checks, not performance measurements.

The execution sandbox hides GPU device nodes: `CUDA_ERROR_NO_DEVICE` inside it
does not establish that the host lacks a GPU. Physical verification used the
host's normal NVIDIA device access.
