# SetaScript shader targets

SetaScript shader modules compile directly to **GLSL 450 core** for desktop
OpenGL, **GLSL ES 300** for WebGL2, or **WGSL** for WebGPU. The shared typed frontend and emitters are
written in Flexscript. Emission needs no graphics driver or external shader
compiler; the graphics API compiles the resulting text when creating a program
or pipeline. The self-hosted WebAssembly compiler emits identical shader text.

```sh
build/stage2 --target glsl examples/seta/shaders/triangle-vertex.seta -o build/triangle.vert
build/stage2 --target glsl-es examples/seta/shaders/triangle-vertex.seta -o build/triangle-es.vert
build/stage2 --target wgsl examples/seta/shaders/triangle-vertex.seta -o build/triangle.wgsl
```

`.seta` selects SetaScript automatically; `--language seta` also works. Each file
contains an empty `plugin ... v1 {}` header and one shader module. Compile each
stage separately. These targets accept shader modules, not ordinary CPU
programs, and cannot be combined with `--word-io buffered` or another target.

## A fragment shader

```seta
plugin visuals.tinted_texture v1 {}

shader fragment {
    input uv: vec2f location(0)
    output pixel: vec4f location(0)
    texture image binding(0)
    uniform tint: vec4f binding(2)

    fn main() -> void {
        pixel = sample(image, uv) * tint
    }
}
```

This is typed SetaScript, with no embedded GLSL or WGSL strings. Helpers,
arithmetic, branches and bounded loops compile from the same source for both
targets. The entry point in both outputs is `main`. Generated internal names
are deliberately mangled; bind resources and attributes using their declared
binding numbers and locations.

WebGL2 has no shader-side binding qualifiers for textures or uniform buffers.
For `glsl-es`, bind uniform block `sw_blockN` using `uniformBlockBinding`, and
assign sampler uniform `sw_r4000+N` to texture unit N (for example binding 2
produces `sw_r4002`). Vertex attributes and fragment outputs keep their explicit
locations. Interstage varyings link by location-derived names. Resource names
are also binding-derived, so changing declaration order across stages cannot
create conflicting global names. WebGL2 supports vertex/fragment stages only;
compute modules and storage buffers require desktop GLSL or WGSL.

## Types and functions

The initial shader subset supports `bool`, `i32`, `u32`, `f32`, `vec2f`/`vec3f`/
`vec4f`, corresponding `vecNi` and `vecNu` integer vectors, and `mat4f`.
Functions declare their parameter and return types; `void` is available for
functions, and `main` must have no parameters and return `void`.

```seta
fn tint(value: vec3f, amount: f32) -> vec3f {
    let result = vec3f(0.0)
    for step in 0..2 { result += value * amount }
    return clamp(result, vec3f(0.0), vec3f(1.0))
}
```

- Locals are mutable and optionally annotated (`let x: f32 = 1.0`). Function
  parameters can also be assigned. Block scopes support shadowing.
- Bare integer literals are `i32`; append `u` for `u32`. Decimal or exponent
  literals are `f32` (`1.0`, `1e-3`). Exponent magnitudes are limited to 38.
  Literals outside the finite f32 range are rejected. Shader integer widths
  are actual 32-bit types, independent of the CPU frontend's word representation.
- Use explicit numeric scalar constructors for conversions: `f32(index)`.
  Bool/numeric conversions require an `if`. Vector constructors support scalar
  splats and combinations of matching scalar/vector components. `mat4f` takes
  four `vec4f` columns. Read components with `xyzw` or `rgba` swizzles.
- Arithmetic requires matching types, with scalar/vector multiplication and
  `mat4f * vec4f` or `mat4f * mat4f` also supported. Comparisons produce scalar
  bools. `and`, `or`, `not` preserve short circuit evaluation.
- Structs group typed fields; see [Structs](#structs).
- `if`/`else`, returns, assignments, compound assignments and literal-bounded
  `for i in low..high` loops are supported. Loop indices are read-only; bounds
  and iteration counts are limited to one million.
- Helper calls may refer to later definitions. Recursion is rejected, and
  non-void functions must return on every path. Outputs start at zero before
  the entry function, including conditionally assigned outputs.

Math builtins: `sin`, `cos`, `abs`, `sqrt`, `floor`, `ceil`, `fract`, `normalize`,
`length`, `dot`, `cross`, `min`, `max`, `clamp`, `mix`, `pow`.
`sample(texture, uv)` uses implicit LOD and is fragment-only;
`sample_level(texture, uv, lod)` uses an explicit f32 LOD in any stage.
`array_length(buffer)` returns a `u32` element count.
`sample_compare(depth, uv, reference)` returns the `f32` result of comparing
`reference` against a declared `depth_texture` (1.0 where the comparison passes)
for shadow maps; it is fragment-only. The host sets the comparison function and
filtering: OpenGL `GL_TEXTURE_COMPARE_MODE`/`GL_TEXTURE_COMPARE_FUNC` on the
texture, WebGPU a `compare` sampler. Linear filtering gives hardware 2x2 PCF.

## Structs

```seta
struct Light { color: vec3f, intensity: f32, direction: vec2f }
struct Particle { position: vec3f, light: Light, id: u32 }
uniform sun: Light binding(0)
buffer particles: Particle binding(1) read_write
```

Struct declarations precede functions, alongside the interface declarations.
Fields are separated by commas or newlines. They can use any value type
except `void`, including structs declared earlier, but a struct cannot contain itself. Construct a
struct with every field in declaration order, as in `Light(color, 1.0, dir)`. Read
and assign fields with `value.field`, and chain field access through nested
structs. Structs can be locals, parameters, return values, uniforms and storage
buffer elements. They cannot be interstage inputs/outputs, and they cannot be compared
or used in arithmetic.

Structs without `bool` fields are host-shareable. They use one layout on every
target, following std140 rules:
scalars align to 4 bytes, `vec2` to 8, `vec3`/`vec4`/`mat4f` and nested structs
to 16 bytes, and a struct's size rounds up to 16 bytes. A `vec3f` followed by a
scalar packs into its last four bytes. GLSL declares struct storage buffers
`std140` (scalar buffers stay `std430`), so the array stride equals the struct
size. WGSL members carry explicit `@size` padding so they land on the same offsets.
Each emitted struct carries the layout as a comment, which is the host ABI:

```text
// layout Particle size 64: position@0 light@16 id@48
```

`tests/shaders/structs-compute.seta` is executed on OpenGL and WebGPU, and the
host checks the result bytes at these offsets on both.

## Stages and interfaces

Interfaces precede function definitions. Locations are 0–15. Vertex outputs
and fragment inputs at the same location must have matching types; integer
varyings use flat interpolation. Fragment color outputs are `vec4f`.

| Declaration | Stage and direction | Type |
| --- | --- | --- |
| `builtin(position)` | Vertex output; fragment input | `vec4f` |
| `builtin(vertex_index)` | Vertex input | `u32` |
| `builtin(instance_index)` | Vertex input | `u32` |
| `builtin(front_facing)` | Fragment input | `bool` |
| `builtin(frag_depth)` | Fragment output | `f32` |
| `builtin(global_id)` | Compute input | `vec3u` |
| `builtin(local_id)` | Compute input | `vec3u` |
| `builtin(workgroup_id)` | Compute input | `vec3u` |

Vertex shaders require a `builtin(position)` output. Compute modules declare
their workgroup size: `shader compute(64, 1, 1) { ... }`. Each dimension must be
1–256 and their product at most 256. Inputs are read-only.

The host still owns camera transforms, draw calls, visibility, attachments,
resource creation and pipeline layout. Coordinate conventions follow each API:
OpenGL clip depth is −1…1 and WebGPU clip depth is 0…1, with differing viewport
and texture conventions. Renderer adapters must account for these conventions;
the compiler does not silently modify positions or UVs.

## Resource ABI

Bindings are 0–31 and share one namespace in the source; overlapping bindings
are rejected. WGSL uses bind group 0. Device-specific resource and attachment
limits are checked when the host creates its pipeline.

| Source declaration | GLSL/OpenGL | WGSL/WebGPU |
| --- | --- | --- |
| `uniform value: TYPE binding(N)` | One std140 uniform block at N | Uniform buffer at group 0, binding N |
| `buffer data: TYPE binding(N) read` | Read-only std430 storage block at N | Read-only storage buffer at N |
| `buffer data: TYPE binding(N) read_write` | Writable std430 storage block at N | Writable storage buffer at N |
| `texture image binding(N)` | Combined `sampler2D` at texture unit N | `texture_2d<f32>` at N and sampler at N+1 |
| `depth_texture shadow binding(N)` | `sampler2DShadow` at texture unit N | `texture_depth_2d` at N and `sampler_comparison` at N+1 |

Textures and depth textures reserve **both N and N+1** in the source for portability, even for
GLSL. The host configures filtering and addressing. Texture and buffer
resources cannot be copied into locals or passed to user functions.

Uniforms support numeric scalars, vectors, column-major `mat4f` and
host-shareable structs; bools are not host-shareable. Each uniform has its own
buffer: pad scalars/vectors to a 16-byte allocation for std140 compatibility; a
`mat4f` uses 64 bytes. Group related values in a struct to share one buffer.

Storage buffers currently support compute-stage runtime arrays of scalar
`i32`, `u32` or `f32` (four-byte stride) or of host-shareable structs (stride
equals the padded struct size). Indexing requires an integer;
read-only buffer writes are rejected. Guard indices explicitly using
`array_length`, as in [vector-compute.seta](../examples/seta/shaders/vector-compute.seta).
The compiler does not add cross-API bounds behavior or synchronize buffer access.

## Verification

Install `glslangValidator` (for example Debian's `glslang-tools`), then run:

```sh
build/stage2 scripts/test-shaders.flex -o build/test-shaders
build/test-shaders build/stage2

mkdir -p build/shaders
for source in examples/seta/shaders/*.seta tests/shaders/*.seta; do
  name=$(basename "$source" .seta)
  build/stage2 --target glsl "$source" -o "build/shaders/$name.glsl"
  build/stage2 --target wgsl "$source" -o "build/shaders/$name.wgsl"
done
build/stage2 scripts/shader-gpu-run.flex -o build/shader-gpu-run
build/shader-gpu-run --dir build/shaders
bun scripts/shader-webgpu-test.js --dir build/shaders --browser chromium
```

The native check uses EGL/OpenGL 4.5. The browser adapter uses an isolated,
temporary Chromium profile and localhost endpoint, then closes both. It selects
SwiftShader for reproducible WebGPU checks. Each execution check verifies 8,192
pixels across color and texture/uniform pipelines and 129 f32 compute outputs
across a partial final workgroup. WGSL modules additionally pass the browser's
independent shader validator. These software-adapter checks do not establish
hardware performance. `scripts/test-wasm.flex` verifies shader output equality
from native and self-hosted Wasm compilers.

The shared high-level water configuration is in
[`libs/render/material.flex`](../libs/render/material.flex). Setaworld's pool
uses SetaScript water vertex/fragment modules compiled for all three backends;
its adapters capture scene color and a clipped planar reflection before drawing
the water. Appearance lives in the material configuration and SetaScript shader.

## Current boundaries

This is a general shader compiler target with an initial typed subset. It does
not yet provide a material DSL or automatically replace Setaworld's handwritten
shaders. Shader files currently cannot import CPU modules. User arrays,
atomics, barriers, dynamic loops, shifts, swizzle assignments, `discard` and
conditional `?:` expressions are not implemented. Use `if`/`else` for conditional
values; WGSL's eager `select` is not used to approximate lazy expressions.

Numeric edge cases, constant-expression legality and derivative uniformity
also follow the target shader language and device validator. This frontend
does not promise CPU word arithmetic, bit-exact floating point across APIs or
identical handling of undefined operations. GLSL/WGSL target specifications:
[GLSL 4.60](https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.60.pdf)
and [WGSL](https://www.w3.org/TR/WGSL/).
