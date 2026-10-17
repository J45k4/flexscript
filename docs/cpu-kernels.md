# Optimizing CPU kernels

`--target cpu-cxx` emits C++17 source from the same validated word IR used by
other backends. Compile that intermediate with Clang to let its optimizer
inline helpers and allocate registers. The kernel and physics engine remain
Flexscript source; no Python runtime or hand-written C++ physics is involved.

```sh
build/flex --target cpu-cxx kernel.flex -o build/kernel.cpp
clang++ -std=c++17 -O3 -march=native -fno-fast-math -ffp-contract=off \
  -fno-math-errno -shared -fPIC build/kernel.cpp -o build/kernel.so -lm
```

The current target is little-endian Linux x86-64 with 64-bit words. `kernel`
accepts zero to six words and returns one word. The shared library exports
`flex_kernel`, `flex_kernel_abi()` (1), and `flex_kernel_arity()`. A native
Flexscript host can open it with `ffi_open`, resolve the symbols and call the
kernel once for a complete batch of steps. Pointers use the host address space;
callers supply valid, sufficiently sized input/output arenas.

Only reachable pure word functions and memory operations are accepted. Host
I/O, FFI, allocation, recursion, globals and static data are rejected. This
initial target accepts Flexscript source, rather than FIR or external frontends.
Normal source extensions execute in their existing restricted compile-time VM.

Registered scalar `f32`/`f64` operations, ordered dot products, word operations
and native atomic memory operations lower to host instructions. Internal values
defer NaN canonicalization until their word bits become observable; packed
low/high FP32 lanes retain their independent canonical words and signed-NaN bit
operations. Cross-precision interpretation materializes the source word first.
No fast math or fused multiply-add is permitted by this contract. The exported
entry establishes nearest-even, gradual-underflow SSE arithmetic and restores
the caller's MXCSR afterward. Leave `-fno-fast-math -ffp-contract=off` enabled.

`lib/f32x2.flex` supplies two FP32 lanes packed low/high in a word. Its add,
subtract and multiply operations use explicit `cpu-cxx` bindings. Other targets
execute the portable scalar bodies. Backend code contains no application names,
layouts or physics algorithms.

## Physics adapter

An isolated CPU kernel may import `libs/physics/cpu.flex` and call the usual
`ph_advance(w,steps)`. The adapter uses the public source-extension API to
select the existing register contact solver, specialize static-body masses,
and select host contact-memory access. It also reuses the GPU implementation's
prepared weld solver, caching coefficients once per step. Sixteen 128-byte
records fit in scratch that is dead after coloring and warm start; more welds
retain the original scalar path. World layout, timestep, iterations, contact
order, friction algorithm and checkpoint ABI are unchanged.

Use this adapter in its own CPU kernel module. GPU shared-memory contact handles
are not valid host addresses. The existing GPU adapters and the direct native
hardware/reference modes remain separate compilation choices.

## Verification

```sh
build/flex scripts/test-cpu-cxx.flex -o build/test-cpu-cxx
build/test-cpu-cxx build/flex
```

The suite compares 368,670 randomized and directed results with both direct
native and software-reference execution, including unaligned memory, polluted
high words, FP32/FP64 NaNs, signed zero, subnormals, packed lanes, shifts and
cross-precision bit interpretation. It also checks ABI metadata, preservation
of the caller's rounding mode and rejection without overwriting existing files.
RoboGym's physics benchmark verifies actual trajectories on shared CPU/GPU
snapshots and reports compiler/artifact hashes with the timings.
