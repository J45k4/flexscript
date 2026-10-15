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
