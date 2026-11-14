# Static tensor GPU compiler

Reusable tensor lowering in native Flexscript. The library takes a static graph
inventory and emits specialized operation sources, a storage/execution plan,
and PTX, native SM75 SASS cubins or HIP source through the ordinary word IR.
It has no application model, weights, labels, decoder, camera or application
runtime dependency. Python, Node and Bun are not required by the tool.

```sh
build/stage2 scripts/pup-codegen.flex -o build/pup-codegen
build/pup-codegen graph.bin --repo "$PWD" --compiler "$PWD/build/stage2" \
  --output build/model-kernels --backend all
build/pup-codegen --repo "$PWD" --compiler "$PWD/build/stage2" \
  --output build/model-kernels --generic-only
```

`--repo` is the Flexscript source root; it defaults to the current directory.
`--backend` accepts `sass`, `cuda`, `hip` or `all`. `--emit-only` writes sources
and plans without compiling artifacts. Child compilers receive argv vectors;
paths with spaces are supported. Outputs default to `REPO/build/pup-kernels`.
Generic operation families and specialized plans share the same kernel ABI.
Kernel sources import `kernels/ops.flex` from this library by default.

Import `libs/ml/pup/gpu.flex` to embed the compiler and invoke `cg_main` with an
argv vector. Before that call, an adapter may set `cg_repository`,
`cg_output_root`, `cg_operations` and `cg_packer`. CLI `--operations FILE` and
`--packer FILE` provide equivalent source overrides. The operation-body module
can share an embedding host's binary64 ABI; `kernels/ops.flex` supplies the
standalone ABI. These are kernel modules, separate from the primitive Pup host
interpreter and its GPU API imports.

## Passes and options

`graph.flex` fuses single-consumer convolution/SiLU chains and optional residual
additions, converts contiguous slices into views, folds adjacent joins, and
places immutable shared operands directly in compatible concat destinations.
Existing aliases and competing destinations retain one physical placement.
`element.flex` emits scalar operations and warp softmax reductions;
`tiled.flex` emits register/shared-memory convolution and matrix-product tiles.
`indexing.flex` keeps device pointers wide while narrowing bounded coordinates.
`driver.flex` specializes, deduplicates and compiles sources and serializes plans.
The existing native autotuner remains an independent candidate/measurement API.

- `--tile TM,TN,TK,RM,RN` overrides block, reduction and register tile dimensions.
- `--unroll N` bounds unrolling using the largest reduction-tile divisor no larger
  than N; zero fully unrolls it. `--staging 0|1|2|4|8` batches independent loads.
- `--[no-]vector`, `--[no-]pipeline`, `--no-streaming` and
  `--[no-]batch-epilogue` control shared loads, prefetching and activation issue.
- `--patch-tiles`, `--packed-masks`, `--interior-stencil`, and
  `--convolution implicit|im2col` select additional convolution layouts.
- `--residual-fusion`, `--[no-]join-views` and `--[no-]shared-placement` control
  graph rewrites. Residual fusion defaults off; the placement passes default on.

Strict FP32 is the default. `--math fp32-tc` retains an explicitly approximate
three-product FP16 mode with FP32 accumulation. It has failed full-model
confidence tolerances in downstream validation and is not the validated FP32
path. Measure complete inference and independently check outputs before
adopting any tuned configuration. HIP output is compile-tested; no AMD hardware
measurement is claimed by the library tests.

## Inventory and plan ABI

The input consists of 224-byte records, each 28 little-endian signed words:
word 0 is the operation; words 8..11 the output shape, 12..15 and 16..19 the
operand shapes, 20..23 operation parameters, 24..25 producer indices (-1 for an
external binding), 26 the bias-presence flag, and 27 the output-binding flag.
Words 1..7 are retained host metadata and participate in the inventory hash.
Dimensions are padded to rank four; an unused second-operand shape may be zero. Supported operations are binary arithmetic
(3..7), permutation (10), convolution (12), max pool (14), sigmoid (24),
concat/slice (25/26), nearest resize (27), softmax (28) and matmul (29).

`plan-FINGERPRINT.bin` starts with `PPLN0001`, node count and 64 ASCII SHA256
characters (80 bytes), then one 128-byte record per node. Records contain a
64-byte kernel name followed by output target, threads, work items, shared
bytes, skip flag, numerical/preparation/residual flags, placement target plus
one, and byte displacement. `plan.json` records graph and scheduling metadata.
Generated-source hashes identify kernels. Regeneration invalidates installed
backend-specific plans for the same graph fingerprint; measured per-backend
plans must be reinstalled afterward.

The operation set and ABI are a static inference interface. Dynamic shapes,
checkpoint conversion, model parsing, image processing, detection decoding,
GPU allocation and graph replay remain separate layers. The primitive Pup
frontend retains its existing plan format; this inventory interface is the
complementary named-tensor inference lowering path.

## Validation

```sh
build/stage2 scripts/test-pup-codegen.flex -o build/test-pup-codegen
build/test-pup-codegen "$PWD/build/stage2"
```

The same checks run in `scripts/test-pup.flex` and its existing CI job. They
exercise pointer/index lowering, fusion dependencies, alias placement, native
CLI execution without scripting tools on PATH, paths with spaces, all three
GPU compile targets, portable FP32 CPU bodies and failure propagation. The
build-tools registry includes both `pup-codegen` and `test-pup-codegen`.
