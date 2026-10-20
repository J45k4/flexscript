# Native kernel autotuning

Reusable kernel generation, compilation, correctness checks, timing and report
collection, written in Flexscript. The CLI and GPU harness run as native binaries;
Bun, Node and Python are not required. No application or model runtime is imported.
The CLI invokes the specified Flexscript compiler through argv vectors and a
native benchmark child process. Linux/OpenSSL SHA256 and HIP/ROCm are used.

The first adapter is FP32 GEMM. It generates packed-LDS tiles parameterized by
M/N/K, block threads and lane columns; a direct 4x4/stride-2/padding-1 transpose
convolution family shares the generator. The latter requires its application's
operator tests and is deliberately excluded from the GEMM benchmark adapter.

Optimization buckets are **compute**, memory, execution, fusion and precision.
The current generator implements compute; additional buckets should add explicit
adapters and contracts rather than silently changing arithmetic. This is library
and CLI tooling, not a compiler optimization pass. The compiler handles hardware
lowering; the library generates alternative parallel algorithms for it to compile.

From the Flexscript repository root:

```sh
build/flex scripts/autotune.flex -o build/autotune-tool
build/autotune-tool generate --config libs/autotune/examples/gemm.json --output build/autotune/candidates --sweep compute
build/autotune-tool bench --config libs/autotune/examples/gemm.json --manifest build/autotune/candidates/manifest.json --output build/autotune/results --candidates gemm-tiled,gemm-wide --samples 10 --warmup 5
```

`--repo PATH` selects the Flexscript source root when invoked elsewhere;
`--compiler FILE` selects the compiler (default `REPO/build/flex`). Paths with
spaces work. `generate --sweep production` emits exactly the declared candidates;
`compute` adds a bounded 24-tile grid. An application may keep its own JSON config:

```json
{
  "version": 1,
  "candidates": [
    {"name":"gemm-wide","family":"gemm","m":64,"n":64,"k":16,
     "threads":128,"laneColumns":16}
  ],
  "shapes": [
    {"name":"example","m":128,"n":1024,"k":65536,
     "flags":2,"groups":1,"chunk":512}
  ]
}
```

`flags` bit 0 transposes A, bit 1 transposes B. Groups have independent A/B/output
matrices. A zero chunk uses the full K loop; a positive chunk splits K and must be
a multiple of the generated reduction tile K. Each partial is merged in a fixed
order. Native launch metadata is explicit: threads, shared bytes, dimensions and
split alignment. The runner binds this metadata to regenerated source before
executing it. Candidate/shape names are bounded filename components. Config and
source drift, malformed tiles, backend failures and timeouts fail the run.

`generate` writes sources and a manifest with their launch contracts/hashes;
`--manifest FILE` can place the manifest outside a checked-in source directory.
`check` verifies exact reproduction without changing the sources or searching.
`bench` compiles selected GEMM candidates sequentially, checks sampled output
cells and all groups against an independent exact integer dot product / 64, and
records HIP-event intervals. Input values are `(physical_index % 11 - 5) / 8`;
the oracle applies each physical transpose/group mapping independently. It also
checks final rows/columns, finite results and absolute/relative error bounds.

Reports use integer **nanoseconds**, avoiding a decimal-JSON dependency; divide
by 1e6 for milliseconds. `gflops = flops / median_ns`, an integer rounded down;
divide by 1000 for TFLOP/s. Raw samples, mean/median/minimum, CPU-reference status,
GPU name/architecture, exact per-case requests, generated source/image hashes,
compiler/config hashes and harness source hashes are retained. `bestByShape`
ranks measured candidates; it never changes an application's production choices.

Timings cover GEMM and any split merge, exclude loading/compilation/reference
checks, and are not whole-training throughput or MFU. Warm up first, use sufficient
samples on an idle GPU, and confirm winners with the actual workload. The numeric
oracle samples outputs; independent randomized full-output/gradient/optimizer
checks remain the application's responsibility. No claim of detector accuracy or
universal bit identity follows from a microbenchmark.

The HIP adapter uses the existing gfx1201 HIPRTC runtime path; `--target hip`
generates HIP source and `--target rdna-gfx1201` generates native AMD code objects.
Both load through HIP. The direct RDNA compiler currently rejects large unrolled
tiles that exceed its physical register budget; `examples/rdna.json` provides a
small tested tile. The production 32x64/64x64 tiles use the HIP path. A rejected
candidate fails with its compiler log; the runner does not silently change the
backend or rank a failed candidate. NVIDIA and other devices/adapters are unverified. Tile
geometry is an algorithm choice and may perform differently on each architecture.

Native CPU/CLI regression checks (including a PATH without Bun/Python/toolchains):

```sh
build/flex scripts/test-autotune.flex -o build/test-autotune
build/test-autotune build/flex
```

The GPU correctness/timing checks are the `bench` invocation above. Applications
should also test generated transpose convolutions and benchmark full execution.
`import "autotune";` exposes the host API; `tiles.flex` and `common.flex` can be
imported separately. `scripts/build-tools.flex` includes both CLI binaries.
