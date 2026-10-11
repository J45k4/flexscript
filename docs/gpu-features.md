# GPU features and host APIs

[Compile-time program extensions](program-transforms.md) can generate ordinary
GPU functions, including forward derivatives, through the same PTX/SASS paths.

Flexscript now has experimental support in every category below. Each entry is
an explicit operation or API; this is not a complete CUDA, OpenGL or Vulkan
implementation, and graphics shaders do not pass through our SASS compiler.

| Capability | Direct `sass-sm75` | `ptx` | Host/API path |
| --- | --- | --- | --- |
| All word integer operators, branches, loops, nonrecursive helpers | Yes | Yes | `kernel(index,input,output,count)` |
| 1D/2D/3D launch geometry and thread/block coordinates | Yes | Yes | `cuda_config`, `cuda_launch_config` |
| Dynamic shared memory and block barrier | Yes | Yes | `gpu_shared_*`, `gpu_barrier` |
| 64-bit atomic add/and/or/xor/exchange/min/max/CAS | Yes | Yes | `gpu_atomic_*64` |
| Active mask, ballot, 64-bit shuffle, warp synchronization | Yes | Yes | `gpu_active_mask`, `gpu_ballot`, `gpu_shuffle`, `gpu_warp_sync` |
| FP32/FP64 add, subtract, multiply, fused multiply-add | Yes | Yes | `gpu_f32_*`, `gpu_f64_*` |
| FP32/FP64 conversions to/from signed i64 | Yes | Yes | `gpu_f*_from_i64`, `gpu_f*_to_i64` |
| FP32/FP64 divide and square root | Yes, integer SASS routines | Yes | `gpu_f*_div`, `gpu_f*_sqrt` |
| Tensor-core FP16 matrix multiply, FP32 accumulation | Yes | Yes | `gpu_mma_f16`, one warp fragment shape |
| Bindless 1D float texture fetch | Yes | Yes | `cuda_texture_f32`, `gpu_texture_fetch` |
| Streams, pinned transfers, events, occupancy and device queries | Same runtime | Same runtime | `lib/cuda.flex` |
| Textured raster graphics, GLSL programs, RGBA framebuffer readback | Separate graphics API | Separate graphics API | `lib/graphics.flex`, EGL/OpenGL 4.5 |
| Hardware ray queries and triangle/instance acceleration structures | Separate ray API | Separate ray API | `lib/vulkan.flex`, Vulkan KHR extensions |

Only SM75 has been verified for direct machine-code emission. Advanced GPU
intrinsics select PTX 6.5 / SM75; plain integer PTX retains the SM50 baseline.
Floating-point values are IEEE bit patterns stored in ordinary words. Integer
operators keep their usual integer meaning: use `gpu_f32_add`, for example,
rather than `+` for floating-point addition. FP32 results occupy the low 32 bits
and have a zero high half. Native operations use round-to-nearest-even; float
conversions to integer truncate. NaN payloads and exceptional conversion results
follow the device/PTX rules, with one explicit exception: direct SASS divide and
square root return canonical positive quiet NaNs for invalid operations and
binary32 NaN inputs; binary64 NaN inputs retain the first NaN operand's sign and
payload with its quiet bit set. NaN payload bits are not portable between targets.

Direct SASS divide and square root use restoring integer algorithms with guard,
round and sticky bits. They round directly to the requested precision, including
gradual underflow, and preserve signed zeros. They need no PTX, driver compiler
or external assembler. Kernels using either operation reserve 16 additional
scratch words (32 physical registers); this correctness-first implementation is
slower than an optimized reciprocal/refinement sequence. Register-budget limits
still apply. The other floating-point intrinsics use native float instructions.

## Compile and discover the device

```sh
build/flex compiler/main.flex -o build/flex-gpu
build/flex-gpu scripts/gpu-info.flex -o build/gpu-info
build/gpu-info
```

On the verified RTX 2070 this reports 36 multiprocessors, 32 threads per warp,
1,024 maximum threads/block, 1,024 maximum resident threads/multiprocessor,
49,152 shared bytes/block and 65,536 registers/block. The memory query returns
CUDA-addressable memory; it can be smaller than the board's advertised VRAM.

`cuda_device_count`, `cuda_device_name`, `cuda_device_attribute` and
`cuda_device_memory` query the driver. `cuda_device_info(ordinal)` returns an
88-byte record: name pointer, ordinal, SM count, warp width, max threads/block,
max resident threads/SM, shared bytes/block, registers/block, memory bytes,
compute-capability major, minor. Every field occupies eight bytes.

`cuda_context_device(ordinal)` chooses a device; `cuda_context()` chooses 0.
`cuda_context_set(context)` switches the calling thread between contexts.
Buffers, modules, streams and events belong to their context; release them
while that context is current. Multiple NVIDIA GPUs can be enumerated/selected,
but physical verification here used one GPU. Peer access and multi-GPU transfer
helpers are not implemented.

## Launch controls

The existing convenience call remains synchronous and uses 128 threads/block:

```flex
cuda_launch(module, input, output, count);
```

A synchronous launch with another block size:

```flex
cuda_launch_threads(module, input, output, count, 256);
```

A three-dimensional asynchronous launch with dynamic shared memory:

```flex
let stream = cuda_stream();
let config = cuda_config(4, 3, 2, 8, 4, 2, 512, stream);
//                       grid      block   shared bytes
cuda_launch_config(module, input, output, count, config);
cuda_stream_wait(stream);
```

Always check returned statuses (`cuda_error()` gives the driver error name).
`cuda_config` validates basic launch bounds; the driver additionally checks the
selected GPU's and kernel's resource limits. Allocate enough device memory and
launch enough threads for `count`.

The generated index is block-major, with x fastest within both the grid and
the block:

```text
block  = bx + gridX * (by + gridY * bz)
thread = tx + blockX * (ty + blockY * tz)
index  = block * (blockX * blockY * blockZ) + thread
```

Threads with `index >= count` exit before the source kernel. Coordinates and
dimensions remain available through `gpu_thread_x/y/z`, `gpu_block_x/y/z`,
`gpu_block_dim_x/y/z` and `gpu_grid_dim_x/y/z` from `lib/gpu.flex`.

For arbitrary CUDA entry points, `cuda_function(module,name)` gets a function,
then `cuda_dispatch(function,config,parameter_pointers)` enqueues it. The pointer
array must match that function's ABI. The Flexscript convenience wrapper uses
`flex_kernel(input,output,count)`.

`cuda_function_attribute(function,4)` reports registers/thread;
`cuda_occupancy(function,threads,shared)` reports the maximum active blocks/SM.
`cuda_function_set_attribute` exposes driver attributes, including opt-in
shared-memory limits. These queries establish resource limits, not the fastest
launch configuration.

## Cooperative kernels

```flex
import "../../lib/gpu.flex";
fn kernel(index,input,output,count) {
    let t = gpu_thread_x();
    gpu_shared_store64(t*8, load64(input+index*8));
    gpu_barrier();
    let next = (t+1) % gpu_block_dim_x();
    store64(output+index*8, gpu_shared_load64(next*8));
    return 0;
}
```

Launch with at least `blockX*8` shared bytes for this one-dimensional example.
Shared offsets and atomic pointers must be eight-byte aligned; shared offsets
must remain within the launched allocation. The shared-memory
size is per block, not per grid. Reach a block barrier with every non-exited
thread in that block; do not place it in a condition reached by only some lanes.
Use full blocks here: the example's neighbor read is not defined for a partial
last block because the missing neighbor never writes its shared slot.

Atomics return the previous 64-bit word. `gpu_atomic_min64` and `max64` compare
unsigned words. `gpu_atomic_cas64(pointer,compare,replacement)` replaces only
when the old word equals `compare`. `gpu_fence()` orders global memory within
the GPU; it does not replace a thread barrier.

`gpu_shuffle(value,source_lane,member_mask)` exchanges a full word within one
warp. `gpu_ballot(predicate,member_mask)` returns the 32-bit vote mask in a word.
`gpu_lane()` and `gpu_active_mask()` provide lane and active-lane information.
All participating lanes must execute a warp operation with the same member
mask, and the shuffle source must participate. Masks do not make arbitrary
partial-warp algorithms valid.

GPU intrinsic names are reserved by the backends and must have the signatures
in `lib/gpu.flex`. GPU geometry and cooperation stubs exit 78 if invoked on CPU;
they are never silently emulated as serial CPU operations. Basic float helpers
have CPU references for ordinary finite arithmetic; fused multiply-add requires
GPU execution for a fused reference.

## Tensor cores and textures

`gpu_mma_f16(a,b,c,d)` performs one warp-cooperative
`m16n8k8.row.col.f32.f16.f16.f32` operation. These arguments point to each lane's
fragment, not to complete row-major matrices:

- `a`: two packed FP16 pairs, eight bytes, aligned to eight bytes.
- `b`: one packed FP16 pair, four bytes, aligned to four bytes.
- `c`: four FP32 accumulators, sixteen bytes, aligned to sixteen bytes.
- `d`: four FP32 outputs, sixteen bytes, aligned to sixteen bytes.

All 32 lanes execute the operation together. Lane fragment layouts follow the
[NVIDIA PTX MMA specification](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#warp-level-matrix-instructions-mma).
The SASS backend emits HMMA directly; this is a primitive for building matrix
kernels, not an automatic matrix tiler or a BLAS implementation.

`cuda_texture_f32(device_pointer,bytes)` creates a one-channel float texture over
an existing linear allocation. `gpu_texture_fetch(texture,index)` fetches one
FP32 bit pattern with an integer texel index. Destroy the object with
`cuda_texture_close` before freeing its backing allocation. Multidimensional
CUDA array textures, arbitrary formats and sampler controls are not exposed by
this convenience API; the graphics path separately supports 2D RGBA textures.

## Streams and transfers

`cuda_host_buffer(bytes)` allocates pinned host memory for
`cuda_upload_async`, `cuda_download_async` and `cuda_copy_async` (device/device).
Keep both source and destination allocations alive until `cuda_stream_wait` or
another synchronization confirms completion. Free pinned buffers with
`cuda_host_free`, not the device allocator.

`cuda_event`, `cuda_event_record`, `cuda_event_wait`,
`cuda_stream_wait_event` and `cuda_event_close` provide cross-stream ordering.
`cuda_event_elapsed_f32(start,end)` returns elapsed milliseconds as FP32 bits.
`cuda_stream_close` destroys a stream; `cuda_synchronize` waits for the current
context. Streams enable overlap but do not guarantee hardware overlap.

## Graphics and hardware ray queries

```sh
build/flex-gpu scripts/graphics-run.flex -o build/graphics-run
build/graphics-run

# glslang is the open-source Khronos shader compiler, a ray-shader build dependency.
glslangValidator -V --target-env vulkan1.2 examples/gpu/shaders/ray-query.comp -o build/ray-query.spv
build/flex-gpu scripts/ray-run.flex -o build/ray-run
build/ray-run build/ray-query.spv
```

The graphics example creates an EGL device display and OpenGL 4.5 core context,
compiles GLSL vertex/fragment stages, samples a 2D texture, rasterizes into an
RGBA8 framebuffer and checks every pixel. `lib/graphics.flex` provides shader,
program, texture, drawing, readback and cleanup helpers, plus raw integer/pointer
entry-point calls. It is currently an offscreen API; window creation, swapchains
and a scene/material system are not implemented.

The ray example uses `lib/vulkan.flex` to create a Vulkan device, allocate
buffers, build bottom-level triangle and top-level instance acceleration
structures, dispatch a SPIR-V compute shader with hardware ray queries and read
back the result. It verifies hit/miss coverage against a CPU reference and
writes `build/ray-query.ppm`. This is actual acceleration-structure traversal,
not a software ray/sphere intersection routine in a CUDA kernel.

The ray adapter requires Vulkan 1.2 plus `VK_KHR_acceleration_structure`,
`VK_KHR_ray_query`, `VK_KHR_deferred_host_operations`,
`VK_KHR_synchronization2` and `VK_KHR_push_descriptor`. Its convenience pipeline
has an acceleration structure at binding 0 and an output storage buffer at
binding 1. It owns one current device and retains buffers/pipelines until
`vk_close`; call that after success or an initialization failure.

Graphics shaders use GLSL through the graphics driver. The ray shader uses
GLSL -> SPIR-V through glslang. The host programs and ABI adapters are Flexscript.
These paths neither consume CUDA cubins nor extend the Flexscript SASS frontend
to graphics/ray shader stages. Ray-generation/miss/closest-hit pipelines, custom
intersection shaders, acceleration-structure updates/compaction and device-loss
recovery remain future work.

## Verification

```sh
build/flex-gpu scripts/test-gpu-features.flex -o build/test-gpu-features
# Compile every feature fixture without drivers, GPUs or NVIDIA tools:
build/test-gpu-features --compiler build/flex-gpu --report build/gpu-features.json
# Require native decoding, PTX assembly and real GPU results:
build/test-gpu-features --compiler build/flex-gpu \
  --ptxas /path/to/ptxas --nvdisasm /path/to/nvdisasm --gpu \
  --report build/gpu-features-device.json
# Dedicated bitwise divide/sqrt corpus; omit --gpu for tool-free emission tests:
build/flex-gpu scripts/test-sass-float.flex -o build/test-sass-float
build/test-sass-float --compiler build/flex-gpu --gpu \
  --nvdisasm /path/to/nvdisasm --report build/sass-float-device.json
```

Tests cover 3D indexing, shared neighbor exchange, divergent paths before warp
operations, atomic contention and old-value semantics, scalar float operations,
integer conversions, tensor fragments, textures, pinned transfers, streams,
events and occupancy queries. Hardware runs compare both backends with known
results. The integer SASS suite separately checks operator semantics, unaligned
accesses, loops, helper calls and compiler rejections.

On the RTX 2070, 44 feature programs/device runs passed 11,461 checks, including
isolated division-by-zero and signed-overflow traps. The integer SASS suite
passed 357 checks over 36 cubins and 77 GPU runs. The device-free feature suite
compiled all 44 programs and passed its diagnostic/output-preservation checks.

The dedicated floating divide/sqrt suite compares 20,480 inputs per fixture:
all pairs of 64 boundary patterns plus 16,384 deterministic random pairs. Four
fixtures cover both precisions and operations; a fifth checks nested helpers,
divergence and values live across multiple math sites. Results match PTX bitwise
except for permitted NaN payload differences; binary64 also matches the
independent portable library. Binary32 inputs include nonzero upper word bits.
This suite passed 184,340 checks across 10 device launches on the RTX 2070.
Device-free checks also verify deterministic emission and scratch-register
budget rejection without overwriting the existing cubin.

The graphics and ray examples both matched 4,096 pixels on the RTX 2070, with
512 covered/hit pixels. The native emitters use conservative scheduling and
fixed register frames; correctness results are not performance claims.

References: [CUDA Driver API](https://docs.nvidia.com/cuda/cuda-driver-api/index.html),
[PTX ISA](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html),
[EGL device platform](https://registry.khronos.org/EGL/extensions/EXT/EGL_EXT_platform_device.txt),
[Vulkan ray queries](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_ray_query.html).
