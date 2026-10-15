# Flexscript physics

An experimental rigid-body engine written in ordinary Flexscript. Native CPU,
WebAssembly, HIP and directly encoded AMD RDNA use **the same solver source**.
There is no MuJoCo binding, C++ physics implementation or Python runtime here.

`physics.flex` constructs a world on the host; `solver.flex` advances a world
using only arithmetic and word memory operations. `kernels/rollout.flex` calls
that same solver on the GPU. The optional `hip.flex` adapter allocates/uploads
worlds, launches either HIP or direct RDNA images and explicitly downloads state.
HIP supplies the driver in both AMD modes. The `rdna-gfx1201` compiler emits the
machine-code image directly, without HIPRTC or LLVM compilation.

## Current engine

- Three-dimensional rigid bodies with position, quaternion, linear/angular
  velocity, mass and principal inertia; static, dynamic and kinematic bodies.
- Semi-implicit integration, gravity, persistent forces/torques and gyroscopic
  angular acceleration; quaternion normalization after every step.
- Compound bodies made of offset oriented boxes, spheres and circular finite
  cylinders. Box orientation follows the body's quaternion; the shape ABI also
  stores a local quaternion.
- AABB rejection, full 15-axis oriented-box SAT, clipped face manifolds and
  closest support-edge contacts. Sphere/sphere and box/sphere contacts include
  the case where a sphere center lies inside a box.
- Exact support mapping for finite circular cylinders. Analytical cylinder/sphere
  and parallel-cylinder queries, with MPR intersection and bounded EPA depth
  refinement for other cylinder pairs. Cap/face and side/face support manifolds
  resist torque; parallel and slightly tilted caps use their disk intersection
  and actual cap-plane intersections; parallel sides use their overlapping axial
  segment. Curves are not approximated with a polygon mesh.
- Iterated sequential impulses, angular contact response, Coulomb friction,
  restitution and bounded penetration correction through separate pseudo
  velocities. Contact position repair updates poses without adding kinetic
  velocity; restitution/friction act on physical velocities. A resident cache
  warm starts matching contacts from the previous frame, with unique nearest
  matches per body pair, normal checks, 1 mm position tolerance and 0.8 decay.
- Six-degree-of-freedom weld constraints that capture the current relative pose,
  follow moving kinematic bodies and can be released without resetting velocity.
- Adaptive compensated binary32 cross products for nearly collinear EPA
  triangles, connected visible-face expansion and consistent horizon winding.
  Tiny cylinder-axis components use scaled square roots to avoid subnormal
  refinement overflow. These remain shared source on all targets.
- Explicit contact-capacity, convex-convergence and nonfinite-state faults;
  no kernel allocation.

Units are metres, kilograms and seconds; Z points up. Quaternions are **x,y,z,w**.
Float arguments are low-word binary32 bit patterns, matching `lib/gpu.flex`.
Matrices are column-major. Arithmetic is deliberately shared across targets:
reciprocal and inverse square root use four Newton iterations with binary32
rounding. Native/Wasm currently use the software arithmetic reference, while
the GPU compiler lowers the same operations to device arithmetic. Bounded normal
inputs are required; this is not a replacement for a general IEEE math library.

## Example

```flexscript
import "libs/physics/physics.flex";
fn main() {
    let world=ph_world(8,8,128,2);
    // A floor, then a dynamic 1 kg cube, using binary32 word literals.
    ph_box_body(world,0,0,0,0xbf000000,0,0x41200000,0x41200000,0x3f000000);
    ph_box_body(world,1,0,0,0x3f800000,0x3f800000,0x3e800000,0x3e800000,0x3e800000);
    ph_advance(world,500); // default 2 ms steps, 12 solver iterations
    let fault=load64(world+192);
    ph_world_close(world);
    return fault;
}
```

Use `ph_body_add` plus multiple `ph_box`/`ph_sphere`/`ph_cylinder` calls for compound geometry.
Supply the aggregate body's principal inertia explicitly; the convenience
`ph_box_body`, `ph_sphere_body` and `ph_cylinder_body` compute it for one centered shape.
`ph_cylinder` takes radius and half-height, with its local axis along Z.
`ph_body_quaternion` sets/normalizes orientation. `ph_settings` sets timestep
(up to 10 ms), solver iterations (1–128), friction and restitution.
`ph_contact_patch_tolerance(world,squared_sine_bits)` optionally expands cap/face
support patches for small relative tilts. Values must be finite in 0–0.01;
zero preserves the conservative geometric query defaults. Expansion emits only
positive-depth physical support points, retaining witness-plane and face/disk
bounds. RoboGym opts into five degrees for stable thin compound stacks.

Friction uses a cached two-dimensional tangent effective-mass matrix. A Newton
step inside the Coulomb disk gives static friction; a projected step that would
increase kinetic energy switches to a trace-bounded projected gradient step.
This avoids energy injection from Euclidean projection with anisotropic inertia.
Set a body's linear/angular velocity at offsets 64/88 for kinematic motion.
`ph_weld(world,a,b)` captures the current relative pose and returns the joint ID;
`store64(ph_joint(world,id)+16,0)` releases it.

For the GPU, the caller creates the HIP context and loads the compiled module.
`ph_device_create(module,arenas,count,stride)` uploads equal-layout, contiguous
worlds once. `ph_device_advance(handle,steps)` queues one dispatch and returns
without downloading state. All requested integration/contact/constraint iterations
run on the device. `ph_device_read(handle,host)` explicitly waits/downloads the
arenas. Advancing again continues the existing VRAM state. The arena includes
one 128-byte prior-contact cache record per contact-capacity slot; advancing and
reuse of that cache need no host readback. The adapter exposes
the device arena at `load64(handle)` for another GPU stage to consume directly.
Close the handle before unloading the module or destroying its context.

## Build and validation

Run from the Flexscript repository root with a compiler rebuilt from current
source (the large rollout kernel needs RDNA long branches and live-mask reuse):

```sh
build/flex compiler/main.flex -o /tmp/flex-physics-compiler
/tmp/flex-physics-compiler scripts/test-physics.flex -o /tmp/test-physics
/tmp/test-physics --compiler /tmp/flex-physics-compiler --gpu
```

Without `--gpu`, the harness checks native and Wasm. With it, the same fixtures
also run through HIP and direct RDNA on a physical GPU. Fixtures cover analytic
free fall, floor settling, stacking, a tilted thin box, friction, elastic
spheres/momentum, a moving welded body, settling in a tray, upright/tilted
circular pads, a three-pad stack and actual compound wristband geometry/masses.
The thin three-pad stack uses 48 solver iterations; other fixtures use the
12-iteration default.
The GPU test runs fifteen worlds × 500 steps in **one dispatch**, checks CPU
trajectory parity within 1 mm / 0.001 state units, then verifies reuse without
reuploading state and resumption of a downloaded pad stack on the CPU,
including cached contacts. Bounded contact overflow,
guard bytes and nonfinite fault paths are exercised on the physical GPU too. See [layout](layout.md).

## Scope and limits

Each GPU world owns a **64-thread workgroup**. Forces, collider transforms,
broad-phase/narrow-phase pairs, contact preparation and integration run in
parallel. Contact indices are sorted canonically and body-pair manifolds are
greedily colored; disjoint manifolds solve concurrently, while points within
one manifold solve serially. The CPU uses the same order and colors. Coloring
and welds run in one lane; more than 64 colors uses the serial solver on the
GPU. Each world needs an additional 1 MiB of device scratch.

This is a correctness baseline, not a claim that a single 100-body pile is faster
than MuJoCo. Broad phase is quadratic. Contacts are rebuilt each step; their matched
support impulses are warm started from a canonical cache. Cache matching uses
binary search by body pair and a bounded search within the prior manifold.
Bodies do not sleep. There is no continuous collision detection:
choose small steps for thin/fast geometry. Very deep overlaps can select the
opposite separating direction; configure initial scenes without interpenetration.

EPA uses a 2 μm support-gap tolerance in SI units, at most 48 vertices,
96 faces and 64 refinement iterations. Skinny face normals use compensated
binary32 arithmetic below sin²(angle) = 1e-4. Interior closest points retain
the face's separating normal instead of renormalizing a cancellation-prone
interpolated witness delta; edge/vertex directions retain their closest-point
calculation. Failure sets sticky world fault 3;
there is no silent approximate contact or CPU fallback. This tolerance is
intended for the current centimetre-scale geometry, not arbitrary scene scales.

General convex meshes, articulated joints, soft bodies and MuJoCo's compliant
contact model are not implemented. The small fixtures alone do not validate
dense piles or end-to-end robotic pickup.

This library has no renderer, detector, browser server or application controller.
RoboBand supplies those application stages separately. Keeping physics state in
VRAM alone does not make a complete GPU rollout.

See [diagnostic timings](performance.md) for the initial single-world baseline
and its limits. GPU residency is verified; a full RoboGym speedup is not.

## Independent cylinder oracle and attribution

RoboBand's retained `flex/tests/test_portable_physics.py` uses MuJoCo only as
an independent double-precision test oracle: 6,000 deterministic randomized
cylinder/box, cylinder/cylinder and cylinder/sphere queries, analytic cap/rim/
containment/separation cases, physical support-manifold witnesses and 644
bit-identical CPU/HIP/direct RDNA contact snapshots. Application/runtime paths do not call this Python test driver.

MPR in `convex.flex` is adapted from Daniel Fiser's 2010–2012
[libccd implementation](https://github.com/danfis/libccd/blob/master/src/mpr.c).
Retain the [BSD copyright notice and license](licenses/libccd-BSD.txt) in source
and binary distributions. EPA and the engine do not load libccd at runtime.

## Application integration hooks

`workgroup.flex` exposes `ph_step_group(world,lane_scratch,lane)` for a
64-thread GPU workgroup. Every lane calls together, including fault paths;
return is zero on a sticky fault. Applications can run device-side control
before/after steps with barriers, retaining the arena in VRAM. A lane owns
16 KiB scratch. The ordinary rollout kernel is a thin wrapper around this API.

`ph_weld_capture_at(world,joint_index,a,b,scratch)` captures a relative pose in
an existing weld slot using only shared numerical code. The caller validates
IDs/capacity and supplies scratch before entering the device call. The host
`ph_weld` constructor retains those checks and allocates the next slot.

RoboBand's experimental `flex/simulation/gpu-engine.flex` builds the actual
compound wristband/tool/tray scene and uses these hooks for physical suction,
single-pick control, collection and every-step GPU telemetry. GPU ray cameras
feed a Pup detector in the same context, followed by resident sigmoid/local
maxima/NMS and visual control. A retained learned-detector run collected all
three wristbands into the tray, with no physics fault in its 40,000-step trace.
The application also has a browser worker and archive adapter; full React
workflow validation is separate from this library's test harness.

Compensated arithmetic in `precise.flex` follows the small Two_Diff/Split/
Two_Product transforms from Shewchuk's public-domain
[robust predicates](https://www.cs.cmu.edu/~quake/robust.html), adapted to binary32
with splitter 4097. Only poorly conditioned face normals use it. This bounded
two-component expansion is not a general exact geometric-predicate package.


## Portable ray queries

Import `libs/physics/ray.flex` after initializing and refreshing body/shape
caches. `ph_ray_world(world,ox,oy,oz,dx,dy,dz,minimum)` returns zero for a miss,
or packed `(shape_id+1)<<32 | distance_f32_bits`. The direction should be finite
and normalized if the result is to represent metres. Zero directions miss.
Rotated boxes, spheres and finite circular cylinders use their primitive
geometry; there is no mesh approximation. Rays originating inside shapes hit
the outward surface. `ph_ray_normal_component(shape,x,y,z,axis)` returns one
world-space outward normal component at the hit. These numerical routines run
unchanged on CPU, HIP and direct RDNA. The application test checks 1,800 MuJoCo
rays and exact cross-target snapshots, then independently checks both rendered
camera views against MuJoCo geometry.

Body offsets 192/216 hold temporary linear/angular contact-repair velocities,
reset before each step. Contact offsets 160/168 hold accumulated repair impulse
and bounded positional bias; 176 holds restitution velocity. These are separate
from the physical velocity and warm-start support impulse channels. Two added
fixtures verify overlap repair without injected kinetic motion. RoboGym's
retained 100-band seed-1, 48-iteration containment case now passes; other dense
seeds and 100-band detector-driven collection are not established by that test.
