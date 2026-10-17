# Shared native renderer

The renderer accepts caller-owned vertex/fragment shader source and geometry.
SetaScript shader modules compile through the installed compiler to GLSL,
GLSL ES or WGSL; the native backend consumes GLSL. Browser adapters can consume
the same SetaScript effect modules. The JS WebGL/WebGPU device implementations
remain in Setaworld in this first extraction.

## Device and lifetime

`render_open(title,width,height,flags)` owns a native OpenGL 4.5 window.
`render_attach(gui_window)` uses an existing window and leaves it alive on
`render_close(device)`. Programs, vertex buffers/arrays and depth targets created
through the renderer are tracked and released before the context. Close is
idempotent. A device remains a tombstone after closing so stale API calls can
return an error; callers should retain/reuse devices rather than repeatedly
creating them in a frame loop.

Failures return zero and expose `gui_error`; uniform lookup returns -1 when
absent. Raw `render_gl` results follow OpenGL (zero can mean success). Its
dispatch cache accepts **immutable symbol-name strings**. A valid context is
selected before using cached entry points, including after another device draws.
Caller-owned windows retain their normal GUI generation checks.

## Geometry and custom materials

`render_material(device,vertex_source,fragment_source)` compiles arbitrary GLSL.
`render_depth_variant(material,vertex_source,fragment_source)` supplies a matching
depth pass; custom vertex deformation can be shared between variants. Compilation
errors leave the renderer usable. `render_material_state(material,alpha,cull)`
sets straight-alpha blending and back-face culling. Pass 0 is opaque, pass 1 is
alpha, and pass 2 uses the depth variant. Applications submit transparent draws
in their chosen order.

`render_mesh(device,stride,attributes,count)` accepts up to 16 vertex attributes.
Each descriptor is six 64-bit words: location, component count, GL scalar type,
normalized, byte offset, integer-input flag. Integer shader inputs use
`glVertexAttribIPointer`; floating inputs use `glVertexAttribPointer`.
`render_mesh_upload(mesh,data,vertex_count,usage)` uploads interleaved vertices.
`render_mesh_draw(mesh,material,pass,first,count)` bounds-checks the range and
rejects a material from another device. The initial mesh API draws triangle
lists; index buffers, instance submission and automatic scene sorting are future
extensions. `render_array`, `render_buffer`, `render_upload`, `render_layout` and
`render_draw` provide the same primitives for existing retained-scene adapters.

`render_matrix(material,pass,name,matrix)` binds an ordinary GLSL matrix uniform.
`render_block(material,pass,name,binding,data,bytes)` owns/reuses uniform storage;
this supports the compiler's `sw_blockN` resources. Blocks for different passes
reuse a binding's buffer. `render_texture(material,pass,name,unit,target,texture)`
binds a caller-supplied texture; SetaScript sampler names are `sw_r4000+N`.
These names are compiler resource ABI, not application material IDs.

`render_depth_target(device,width,height)` creates a depth texture/FBO pair.
`render_begin(device,target,width,height)` binds/clears that target; a zero target
selects the window framebuffer. Targets expose their texture at word 1 for a
custom shadow sampler. The application chooses light cameras, shadow bias,
filtering and which objects cast/receive shadows. Close mesh/material/target
handles explicitly when they are retired, or let the device release remaining
GPU objects. The small handle allocations remain as stale-handle tombstones.

## Cameras and numbers

`render_camera(matrix,eye,target,up,width,height,focal,near,far)` writes a
column-major binary32 perspective view/projection matrix. Eye/target and clipping
distances are millimetres; up is a direction in millionths and focal is
`1/tan(vertical_FOV/2)` in millionths (1732051 is approximately 60 degrees).
The local frame supports coordinates within +/-1,000,000 metres and aspect
ratios within 1/64..64. Setaworld retains its planetary origin/camera adapter.
`render_identity` and `render_float` help construct matrices and binary32 vertex
data. The extracted `render_f32` retains Setaworld's half-up conversion for
positive denominators up to 1e9; `render_float` scales larger denominators first.

## Shared effects and provenance

`libs/render/shaders/{water,atmosphere}-{vertex,fragment}.seta` are byte-for-byte
extractions from Setaworld commit `d5c5899a2`. They contain reusable shader
algorithms with explicit uniforms: camera, sun, planetary up/radius, water tint,
roughness, refraction and reflection textures. Stream command numbers in their
comments describe the original adapter; the shaders depend only on their inputs.
Setaworld's surface patterns and material IDs stay in its custom surface shader.
Its shadow-cascade policy, stream decoding, visibility, incremental conversion,
world content and reflection scene orchestration remain application-owned.

The hot GL dispatch and rational conversion originated in Setaworld's
`src/native-render.flex`. Resource ownership, material/mesh APIs, arbitrary vertex
layouts, camera API and standalone demo are part of this extraction. Setaworld
uses the shared device for shader programs, retained/dynamic mesh allocation and
uploads, attribute layouts and scene draws; its existing shadows/reflections
continue through that device.

## Standalone integration and verification

Standalone consumers can vendor a pinned snapshot without depending on a
neighboring source checkout:

```sh
flexscript scripts/sync-render.flex -o /tmp/sync-render
/tmp/sync-render /path/to/application/src/platform
/tmp/sync-render /path/to/application/src/platform --check
```

The snapshot records source/content SHA256 values and relocates only the word
FFI import. Window/GL support is synchronized separately with `scripts/sync-gui.flex`.
Canonical updates originate in Flexscript. Generated shader output stays a build
artifact. The library bundle and installer include renderer sources and examples.

```sh
flexscript scripts/test-render.flex -o /tmp/test-render
/tmp/test-render --compiler /absolute/path/to/flexscript
SDL_VIDEODRIVER=offscreen /tmp/test-render --compiler /absolute/path/to/flexscript --gpu
```

The tests compile the eight demo/shared effect modules for all three shader
targets. Device checks exercise actual GL pixels, shadow/no-shadow differences,
camera movement, invalid draw ranges, shader failure recovery, multiple contexts,
resource closure and externally owned window generations. `offscreen` may use
software rendering; use the desktop X11 driver for a physical GPU acceptance run.
