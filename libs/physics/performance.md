# Initial diagnostic timings, 2026-10-15

These historical samples were taken before cylinder support enlarged the
kernel and per-world GPU scratch from 256 KiB to 1 MiB. They do not establish
performance of the current cylinder-capable kernel.

RX 9070 XT, gfx1201, ROCm 7.2.4. `tests/benchmark.flex` creates one floor and
3/50/100 thin cuboids with half extents 105 × 12 × 2 mm, mass 24 g, alternating
±45° yaw, deterministic x/y offsets and staggered initial heights. This is
**not the complete wristband scene**: there are no cylindrical pads or tool.

The shader advances 500 × 2 ms steps, then one GPU-event measurement covers
another 50 steps (100 ms of simulated time). Setup, compilation, upload,
download, rendering, detection, control, codecs and recording are excluded.
Each target's benchmark ran alone. These are single diagnostic samples, not
statistical performance estimates. Piles still have motion after that interval.

| Thin cuboids | HIP, 100 ms simulated | Direct RDNA, 100 ms simulated | Contacts at end |
| --- | ---: | ---: | ---: |
| 3 | 20.42 ms | 71.47 ms | 8 |
| 50 | 95.31 ms | 554.16 ms | 143 |
| 100 | 218.61 ms | 1,329.05 ms | 295 |

The shader uses a 64-thread workgroup per world, canonical contact ordering,
body-pair manifold coloring and register intermediates. Bounded axis selection
avoids generic signed division; the fixed reciprocal/rsqrt refinements are
unrolled. Contact/state math is shared between these targets. HIP's optimizing
compiler currently produces substantially faster code than the direct word-IR
encoder. Direct RDNA is functional; it is not currently the fastest option.

The 100-body pile's largest linear speed was about 0.27 m/s after the timed
interval. These runs check finite state and expose performance costs; they do
not establish realistic dense-pile settling or equivalence to MuJoCo. No
end-to-end speedup claim follows from these numbers.

Reproduce from the repository root, after building a current compiler and the
physics test artifacts as described in [README](README.md):

```sh
/tmp/flex-physics-compiler libs/physics/tests/benchmark.flex -o /tmp/physics-benchmark
/tmp/physics-benchmark build/physics/rollout-hip
/tmp/physics-benchmark build/physics/rollout-rdna-gfx1201
```

The program prints event times in microseconds, contact count, min/max body
height and maximum linear speed. Run targets sequentially to avoid overlapping
GPU benchmark work. Future performance work should profile stage costs, improve
direct compiler code size/control flow and test throughput across many worlds.


## Compound-wristband scheduling update, 2026-10-15

RoboGym measured the actual compound strap/circular-pad/tool/tray scene on the
same RX 9070 XT with 48 solver iterations and 2 ms steps. Seven-sample HIP
medians after 500 warm-up steps, with profiling disabled. All counts use
pile mode, seed 1; the baseline reproduces the exact published kernel hash:

| Wristbands | Baseline GPU interval | Color ranges + pair batches | Latency reduction |
| --- | ---: | ---: | ---: |
| 3 | 73.244 ms | 71.426 ms | approximately unchanged within run variation |
| 50 | 555.712 ms | 467.409 ms | 15.9% |
| 100 | 1177.095 ms | 840.979 ms | 28.6% |

These intervals include 50 physics steps (100 ms simulated), two 512-square
ray cameras, a 256-square ResNet-18 and candidate selection. They exclude
visual-policy dispatch, recording/readbacks/codecs/browser work. Physics alone
changed from 547.355 to 459.009 ms for 50 bands, and 1167.380 to 831.206 ms
for 100 bands. The numerical timestep, iterations, contact tolerances and
geometry were unchanged. This is a 1.40x pipeline speedup for the measured
100-band seed-1 scene; dense single worlds still run below real time.

The first stage profile attributed roughly 596 ms to constraints, 457 ms to
collision and 94 ms to preparation/sorting/coloring for 100 bands. Stable
per-color ranges remove repeated all-manifold scans; bounded candidate queues
improve useful narrow-phase work within the existing 64-lane group. A tested
sweep-and-prune variant regressed this workload and was discarded. Broad-phase
complexity remains quadratic; sleeping and multi-workgroup worlds are not
implemented by this update. No speedup is claimed for unmeasured workloads.

The retained application comparison has bit-identical every-step trajectories
for a full single pickup, 50/100-band piles and the learned three-band visual
collection (40,000 fault-free physics/policy records). The diagnostic API in
[README](README.md#optional-stage-profiling) separates remaining collision,
constraint, contact-ordering and other costs without adding host feedback.


## Single-world grid-wide narrow phase

A subsequent staged adapter now distributes one world's eligible collision
pairs across 32 blocks of 64 threads, with a work queue for uneven narrow-phase
jobs. One group still prepares and solves each step. Reusable 50-step HIP
graphs supply dispatch dependencies without intermediate state readbacks.
Parallel workgroup index sorting replaces the serial GPU heap sort when
contact capacity permits padding. No timestep, iteration or tolerance was
reduced. Small RoboGym scenes retain the one-dispatch schedule because staging
was slower at 3, 6 and 12 wristbands; the application selects staging at 24+.
The original batch adapter is unchanged.

On RX9070XT gfx1201, an initial unprofiled seven-sample check measured the
100-band combined GPU interval at 389 ms and 50 bands at 283 ms per 100 ms
simulated. These include two 512-square cameras, 256-square ResNet-18 and
candidate selection, and exclude codecs/recording/readbacks/policy dispatch.
The root RoboGym single-world performance diary records final paired timings
and regression evidence. These are workload measurements, not occupancy or
bandwidth measurements, and dense single-world runs remain below real time.

## Bounded working set and small-scene staging, 2026-10-16

The optional shared-memory/register solver and pair-class prefix compaction
preserve the original global-memory solver and batch adapter. RoboGym's final
paired HIP measurements on RX9070XT, seven samples after 500 warm-up steps,
48 iterations and 2 ms steps:

| Wristbands | Previous | Final | Simulated time / wall time |
| --- | ---: | ---: | ---: |
| 3 | 72.643 ms | 49.358 ms | 2.026x |
| 12 | 145.092 ms | 86.599 ms | 1.155x |
| 24 | 180.434 ms | 101.233 ms | 0.988x |
| 50 | 283.768 ms | 153.241 ms | 0.653x |
| 100 | 389.905 ms | 201.500 ms | 0.496x |

Intervals include 100 ms simulated, both 512-square cameras, 256-square
ResNet-18 and candidate selection; recording, readbacks, codecs, browser and
visual-policy dispatch are excluded. This update gives approximately 1.94x
speed for the 100-band measured workload, which still needs another 2.02x to
reach the compute budget. No real-time browser-recording claim is made.

A separate instrumented 100-band run attributes approximately 122 ms to
constraints, 44 ms to collision and 16 ms to prepare/order/color. The solver
remains the main bottleneck. A 1/3/6/12/24-band scheduling sweep favored the
new staged path at every tested size, so RoboGym now defaults to it for all
scene sizes. The fused reference remains selectable; the generic library's
batch adapter remains unchanged. Default application workspace is about
32 MiB plus the bounded pair queue, with 64 KiB reused shared memory.

Both GPU targets reproduced the saved complete pickup and 50/100-band pile
trajectories byte for byte. Working-set boundary, signed-word, 65-color,
8193-contact and 480/481-shape pair/guard regressions pass on both targets.
RoboGym's complete 121-case retained suite passed before the final default
selection; all nine affected runtime/session cases passed after that change.
The production build, TypeScript and 200 Bun tests pass. Measurements and the
precise validation scope are recorded in RoboGym's
`diary/2026_10_16_realtime_gpu_physics.md` and ignored benchmark artifacts.


## Native CPU lowering, 2026-10-16

Explicit symbol bindings replace the portable scalar wrappers and ordered dot
products with SSE2 on native x86-64. The compiler contains no physics-specific
operations. Reference mode preserves software arithmetic; geometry, timestep,
48 iterations and scalar solver scheduling remain unchanged.

RoboGym physics-only median wall time per 100 ms simulated, seed-1 pile, 500
warm-up steps, three fifty-step samples on Ryzen 9 5900X / RX9070XT:

| Bands | Software CPU | Native CPU | MuJoCo CPU | Flexscript GPU |
| --- | ---: | ---: | ---: | ---: |
| 3 | 856.653 ms | 19.396 ms | 0.927 ms | 45.976 ms |
| 12 | 4414.388 ms | 83.030 ms | 8.110 ms | 86.178 ms |
| 24 | 9691.753 ms | 187.121 ms | 24.158 ms | 105.462 ms |
| 50 | 24028.906 ms | 472.890 ms | 86.629 ms | 164.339 ms |
| 100 | 53989.902 ms | 1060.919 ms | 234.975 ms | 206.518 ms |

Native CPU is 44–53x faster than the preserved software reference; 3/12 bands
reach realtime in this physics-only workload. MuJoCo CPU remains faster at all
sizes, by about 4.52x at 100 bands. GPU is about 14% faster than MuJoCo at 100.
MuJoCo uses Newton with cap 48/tolerance 1e-8, a different contact/convergence
model. CPU/GPU Flexscript start from the identical settled snapshot, whereas
MuJoCo settles the same initial geometry independently. Every sample restores
its baseline outside the timer. No equal-fidelity claim is made. All final
Flexscript body-state arrays match both the saved software baseline and GPU
exactly at all five sizes. Cameras, inference, controller, recording, setup and
transfers are excluded. This scope differs from the combined GPU intervals above.

Raw results and hashes are in RoboGym's ignored
`target/flex/physics-comparison-native-final/`; the software baseline is preserved
in `target/flex/physics-comparison-final/`. The full protocol and compiler/test
scope are documented in RoboGym's native-lowering diary and benchmark README.
