# World arena ABI, version 1

All slots are little-endian 64-bit words. Float slots contain binary32 bits in
the low 32 bits; the upper 32 bits are zero, except for the explicitly packed
contact matrix and color-permutation cache fields below. All IDs and offsets are signed
integer words. There are **no pointers inside the world**, so copying one arena
to CPU, Wasm linear memory or VRAM preserves its layout. Separate worlds own
separate scratch regions. Concurrent stepping of the same arena is forbidden.
Callers construct arenas through `physics.flex`; validate capacities, IDs,
finite poses, positive mass/inertia and dimensions before GPU submission.

| Header byte offset | Value |
| --- | --- |
| 0 | Version: 1 |
| 8,16,24,32 | Body, shape, contact, weld counts |
| 40,48,56,64 | Corresponding capacities |
| 72,80,88,96,104 | Body, shape, contact, weld, scratch byte offsets |
| 112 | Total arena bytes (also GPU batch stride) |
| 120 | Integration timestep |
| 128,136,144 | Gravity x,y,z |
| 152,160 | Coulomb friction coefficient, restitution |
| 168 | Velocity solver iterations |
| 176,184 | Completed steps (integer), elapsed time (float) |
| 192 | Sticky fault: 0 OK, 1 contact overflow, 2 nonfinite state, 3 convex convergence/capacity |
| 200,208 | Contact penetration slop, stabilization coefficient |
| 216,224,232 | Internal GPU atomic-emission flag, color count, manifold count |
| 240,248 | Prior-contact cache count and arena byte offset |

Bodies start at header offset 72 and have a 448-byte stride:

| Body byte offset | Value |
| --- | --- |
| 0 | Kind: 0 static, 1 dynamic, 2 kinematic |
| 8 | Position, 3 floats |
| 32 | Quaternion x,y,z,w, 4 floats |
| 64,88 | Linear and angular velocity, 3 floats each |
| 112 | Inverse mass, zero for static/kinematic |
| 120 | Principal local inverse inertia, 3 floats |
| 144,168 | Persistent world force and torque, 3 floats each |
| 192,216 | Transient linear/angular position-repair velocities, 3 floats each |
| 256,328 | Cached world rotation and inverse inertia matrices, 9 floats each |
| 400 | Internal dynamic-body color mask |

Shapes have a 256-byte stride:

| Shape byte offset | Value |
| --- | --- |
| 0,8 | Body ID; kind: 1 box, 2 sphere, 3 circular cylinder |
| 16,40 | Body-local offset and quaternion x,y,z,w |
| 72 | Box half extents x,y,z; sphere radius; cylinder radius and half-height |
| 96,120 | Cached world center and rotation matrix |
| 192,216 | Cached AABB minimum and maximum |

Contacts have a 256-byte stride. Offsets 0/8 are body IDs, 16 the world contact
point, 40 a unit normal **from A toward B**, 64 penetration depth, 72 accumulated
normal impulse, 80 accumulated tangent impulse, 104/128 body-relative arms,
152 inverse effective normal mass, 160 accumulated position-repair impulse,
168 position-repair target velocity and 176 restitution target normal velocity. Vector fields occupy three float words. Offset 192 in the
contact slots stores a sorted index permutation; offsets 200/208/216 in the
first manifold-count slots store sorted contact range start/end and packed
color/permutation metadata. Offset 216 has the group color in its low 32 bits;
its high 32 bits, indexed by bucket position, map to a manifold descriptor.
`ph_color_group` resolves this mapping. These indices do not move the underlying
contact records or change canonical order within each color. Offset 224 stores a fixed
unit tangent (three float words). The other tangent is normal cross tangent.
Offset 184 packs tangent effective masses Kxx/Kyy into low/high binary32 halves;
offset 248 similarly packs Kxy and the inverse determinant. Preparation rebuilds
these private caches each step; warm-start records do not copy them.

Welds have a 128-byte stride: body IDs at 0/8, enabled at 16, body-A-local
relative position at 24, relative quaternion x,y,z,w at 48. Connected bodies
do not collide while the weld is enabled.

After the weld arena, each contact-capacity slot reserves a 128-byte prior-contact
cache record. Records retain the previous canonical contact order, body IDs,
world point, normal, depth and solved impulses at the same offsets 0–96 as
contacts. Offset 104 marks a record already matched this frame, ensuring one
old impulse cannot be reused twice. Matching occurs within the same body pair,
within 1 mm, with normal agreement above 0.95. Impulses decay by 0.8 and the
cached tangent is projected into the new contact plane. GPU manifolds claim
records serially within their group; different pairs have disjoint caches.
Changing settings through `ph_settings` invalidates previous contacts/caches.

The CPU arena scratch region is 16384 bytes. The GPU adapter additionally owns
64 × 16384 bytes of device scratch per world and frees it with the handle. The solver uses it for bounded MPR/EPA convex contact refinement, polygon clipping,
contact preparation and temporary vectors. Bytes 0–16351 are transient. During GPU collision generation, bytes 0–8191
hold at most 1,024 packed candidate pairs, 8192 holds their count, and 8200
holds the completed step's candidate total. Narrow phase uses the separate
lane scratch, so it cannot overwrite this queue. After collision generation,
CPU/GPU coloring uses bytes 14848–15359 for 64 range starts and 15360–15871
for range ends; contact solving does not use narrow-phase scratch. The
final 32 bytes of the arena scratch are persistent per-world options, not lane
scratch: offset 16352 stores the support-patch angular tolerance (binary32
squared sine). Zero selects the conservative geometric defaults. Set it through
`ph_contact_patch_tolerance`, which validates 0–0.01 and invalidates contacts and
warm caches. Callers must not store their own data in the scratch region.
Contacts and shape caches describe the most recent collision evaluation at the
start of the step; final body poses describe the completed integration. Forces
are not cleared automatically. Faulted worlds stop advancing; rebuild/reset
them rather than clearing a fault and consuming partially solved state.

On a convex fault, scratch byte offset 16000 holds one packed diagnostic word:
shape A ID in bits 0–15, shape B in 16–31 and reason in 32–63. A single word
keeps the pair together if several GPU lanes fail. Reasons 11–16 identify
cylinder/sphere or MPR degeneracy/iteration failures; EPA reasons are 21 no
witness, 22 invalid seed, 23 no active face, 24 vertex limit, 25 horizon limit,
26 empty horizon, 27 face limit and 28 iteration limit. Diagnostics are not
valid on a successful step and are cleared when rebuilding the world.

The optional staged collision adapter owns a separate complete pair queue and
16 KiB private scratch per collision worker (for example, 32 MiB for 2,048
workers). This does not change the relocatable arena layout or checkpoint ABI.
The workgroup bitonic sort uses contact index word 192 in valid and padded
slots up to the next power of two, bounded by contact capacity. All other
contact data and unused slots beyond that padding are preserved. CPU sorting
and GPU insufficient-padding-capacity cases use the existing heap order.
