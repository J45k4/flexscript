# Pup model compilation

An optional domain frontend written entirely in Flexscript. It compiles static
F32 tensor expressions to PTX or direct NVIDIA Turing SASS and runs MNIST
inference using a trained Puppygrad checkpoint.

```text
model.pup -> primitive tensor graph -> execution plan -> Flexscript kernel source
                                                        -> word IR -> SASS cubin
                                                                  -> PTX
```

The layers are separate: `parser.flex` builds the model graph; `nn.flex`
defines matrix multiplication and dense layers from primitives; `graph.flex`
plans materialization and provides the independent CPU interpreter;
`lower.flex` emits scheduled kernel source; `runtime.flex` binds parameters
and dispatches stages through the CUDA Driver API. `frontend.flex` only adapts
this library to the compiler's generic FSX1 protocol. Adding this domain did
not add ML syntax or ML operations to the core compiler.

## Model syntax

[mnist-inference.pup](../examples/mnist-inference.pup) describes a static
`784 -> 64 -> 10` classifier with a batch size of 128:

```pup
images = input("images", [128,784])
w1 = input("w1", [784,64])
b1 = input("b1", [64])
w2 = input("w2", [64,10])
b2 = input("b2", [10])
hidden = max(dense(images,w1,b1),0.0)
logits = dense(hidden,w2,b2)
output logits
```

Inputs are immutable named bindings supplied by the host. Explicit shapes in
`input(name,shape)` are a Flexscript extension to Puppygrad's host-specialized
`input(name)` convention: this allows compiling a standalone cubin before
opening a checkpoint. All bindings precede output declarations. Expressions
occupy one line, with optional `#` comments. Parentheses and ordinary arithmetic
precedence work. Decimal/scientific literals become finite F32 values.

| Expression | Behavior |
| --- | --- |
| `input("name",[shape...])` | Named F32 input with a static shape |
| `param(slot,f32,size)` | Flat F32 input, named `slotN`; unique slot 0..63 |
| `const(number)`, `number` | Scalar constant |
| `a+b`, `a-b`, `a*b`, `a/b`, `-a` | F32 arithmetic with singleton broadcasting from the right |
| `add`, `sub`, `mul`, `fdiv`, `max` | Two-argument elementwise functions |
| `relu(a)` | `max(a,0)`; max propagates canonical NaN and prefers positive zero |
| `reshape(a,[shape...])` | Same flat elements, different static shape |
| `permute(a,[axes...])` | Reorder axes; an index view |
| `reduce(a,add,n)`, `reduce(a,max,n)` | Reduce the first `n` axes in row-major order |
| `dim(a,axis)` | Static dimension as an integer constant |
| `stack(dimensions...)` | Shape-list compatibility helper |
| `cast(a,f32)` | Identity; F32 is the only supported dtype |
| `matmul(a,b)` | `[M,K] @ [K,N] -> [M,N]` |
| `dense(x,w,b)` | Matrix product plus broadcast bias |
| `linear(x,w,b)` | Dense with weights stored as `[outputs,inputs]` |
| `output a,b,...` | Ordered outputs, including parameters or intermediate values |

Matrix multiplication expands to reshape, permute, multiply and leading-axis
sum reduction. There is no matrix-multiply graph opcode. The scheduler may
recognize the contraction and emit its equivalent row/column/K loop. F32
multiplication and addition are separate operations, without FMA reassociation.
Reductions and selected shared intermediates materialize in dependency order;
other elementwise operations and views inline into their consumers. The MNIST
plan has four stages and a 1,361,496-byte workspace, without allocating either
broadcast product tensor.

This first frontend supports static inference. It does not yet implement
Puppygrad's full language, `def`, loops, comparisons, integer tensors, exp/log,
graph `grad`, training or dynamic shapes. Unsupported syntax is rejected with
a located diagnostic. The existing eager `libs/ml` autodiff library remains
available separately. Tiling, tensor-core selection, graph rewrites and formal
equivalence proofs are future work; the independent primitive interpreter and
GPU comparisons currently check lowering correctness.

## Build and compile

From the repository root, using a compiler with the FSX1 source protocol:

```sh
build/flex-transform compiler/main.flex -o build/flex-pup
build/flex-pup --frontend libs/ml/pup/frontend.flex --target sass-sm75 \
  libs/ml/examples/mnist-inference.pup -o build/mnist.cubin
build/flex-pup scripts/mnist-infer.flex -o build/mnist-infer
```

Compilation requires no GPU, CUDA toolkit, `nvcc`, PTX, `ptxas` or external
assembler. SASS output is specific to SM75; execution needs a compatible NVIDIA
GPU and driver exposing `libcuda.so.1`. Choose `--target ptx` for driver JIT
compilation on other compatible NVIDIA architectures. See the
[direct SASS backend](../../../docs/sass-sm75.md) for its architecture limits.

Pup's generated source contains GPU intrinsic declarations that deliberately
exit 78 on the CPU. Compiling it as a native executable does not provide a CPU
inference binary. For CPU validation, use `pup_parse` and `pg_execute`; the
primitive interpreter itself works on native, interpreted, JIT and Wasm hosts.

## Run MNIST

The runner accepts uncompressed official MNIST IDX images/labels and a named
F32 safetensors checkpoint with `w1:[784,64]`, `b1:[64]`, `w2:[64,10]`,
`b2:[10]`. It checks tensor shapes and payload bounds, normalizes input bytes
to F32 `[0,1]`, uploads weights once, runs padded batches and classifies logits
with argmax. It is a named F32 tensor loader, not a complete safetensors format
validator. Dataset count, dimensions, exact file lengths and labels are checked.

The prepared local assets are ignored build files:

```sh
build/mnist-infer --compiler build/flex-pup \
  --checkpoint build/mnist-assets/state.safetensors \
  --images build/mnist-assets/t10k-images-idx3-ubyte \
  --labels build/mnist-assets/t10k-labels-idx1-ubyte \
  --min-accuracy-bps 9500 --report build/mnist-sm75-full.json
```

This command compiles the model through the frontend before loading the cubin.
`--verify-reference N` checks the first N examples' logits against the primitive
interpreter, with absolute plus relative tolerance `1e-5`; default N is 1,
maximum 128, and 0 skips the CPU pass. The CPU pass evaluates the whole first
batch to preserve general graph semantics. `--limit N` limits test examples.
`--target ptx --output build/mnist.ptx` selects PTX. `--model path` selects a
compatible classifier. `--min-accuracy-bps 9500` fails below 95% accuracy.

JSON reports contain source, artifact, checkpoint and dataset hashes, stage
sizes/offsets, workspace bytes, accuracy, reference-logit count and elapsed time.
Elapsed time includes host preparation, transfers, launches, downloads and any
requested CPU reference evaluation; it is not a kernel-only benchmark.

Verified on the RTX 2070 using the cached Puppygrad
`.cache/train/mnist-autodiff-native-5epochs/state.safetensors` checkpoint:
**9,545 / 10,000 correct (95.45%)**, matching its recorded test accuracy. The
first eight examples' 80 logits matched the independent reference. Assets were
copied from the sibling Puppygrad cache; compressed IDX files were decompressed
without changing their contents. Weights and datasets are not bundled in Git.
To prepare them again from that cache:

```sh
mkdir -p build/mnist-assets
cp ../puppygrad/.cache/train/mnist-autodiff-native-5epochs/state.safetensors \
  build/mnist-assets/state.safetensors
gzip -dc ../puppygrad/.cache/mnist/data/t10k-images-idx3-ubyte.gz \
  > build/mnist-assets/t10k-images-idx3-ubyte
gzip -dc ../puppygrad/.cache/mnist/data/t10k-labels-idx1-ubyte.gz \
  > build/mnist-assets/t10k-labels-idx1-ubyte
```

Checkpoint SHA256:
`d9dbc8736b973f256140faa811e9b9f1d409ea4a003b565f84ef87fdc6e57d92`.
The runner accepts another trained checkpoint with these names and shapes;
accuracy then depends on those weights.

## Host API and verification

Import `parser.flex` for `pup_parse(text,size,path)`, or `lower.flex` to also
access `pup_lower()`. Parsed graph metadata uses the `pg_*` globals. Allocate
`pg_words*8` reference storage, populate each input at its node's material
offset (`load64(node+64)` words), and call `pg_execute(memory)`. Output nodes
are in `pg_outputs`; their size is `pg_size(node)` and storage uses the same
offset convention. F32 bit patterns occupy the low 32 bits of each 64-bit
word in both host and GPU storage. Views do not imply contiguous physical copies.

For CUDA, create a context and load the compiled module, then use
`pup_gpu_open(module)`, `pup_parameter(name)`,
`pup_gpu_bind(run,parameter,data,elements)`, `pup_gpu_execute(run)`,
`pup_gpu_read(run,output_index,data)` and `pup_gpu_close(run)`.
All inputs must be initialized before dispatch. Stages execute synchronously
in topological order in one device workspace. The caller owns the module and
context and unloads/closes them afterward. One parsed graph is active at a
time: do not reparse while a session uses its metadata. Parameters should be
looked up from that same graph. Parsing and reference buffers are ordinary
allocations; long-running native callers should provide process/arena lifecycle
management. This is an initial experimental host API.

Limits: 4,096 nodes, 64 parameters, 32 outputs, rank eight, graph/expression depth
64, 16,777,216 logical elements per tensor, 128 MiB workspace and 2 MiB generated
kernel source. Static integers are exact within `[-16777216,16777216]`. External
frontend VM fuel, memory and time budgets also apply.

```sh
build/flex-pup scripts/test-pup.flex -o build/test-pup
build/test-pup --compiler build/flex-pup --report build/pup-tests.json
build/test-pup --compiler build/flex-pup --gpu --report build/pup-device-tests.json
```

Device-free tests exercise hand-calculated primitive and matrix results,
native/interpreter/JIT/Wasm reference execution, malformed models, FSX1
validation, frontend capabilities, alias protection and both kernel targets.
Device tests compare all output values for odd-sized matrix products, multiple
outputs, nested broadcasting, views, reductions, division, NaNs and signed zeros
on both PTX and direct SASS. No dataset or checkpoint is needed by the suite.
The GPU suite also constructs a known-class MNIST checkpoint and 129 synthetic
images to exercise loading and padded batches, then checks accuracy-threshold,
bad-shape, nonfinite-logit and truncated-IDX rejection.
