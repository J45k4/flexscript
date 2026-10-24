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

The primitive GPU frontend supports static inference. It does not yet implement
Puppygrad's full language, `def`, loops, comparisons, integer tensors, exp/log,
graph `grad`, training or dynamic shapes. Unsupported syntax is rejected with
a located diagnostic. The existing eager `libs/ml` autodiff library remains
available separately. This primitive scheduler does not yet implement tiled
contractions or formal equivalence proofs; the independent primitive interpreter
and GPU comparisons currently check lowering correctness.

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

## Named CNN training graphs

`pup_parse_network(text,size,path)` selects an additional, platform-free network
frontend. It uses the same lexer, bindings and expression parser, preserving the
original primitive/CUDA/SASS path through `pup_parse`. The network backend emits
a native Flexscript model factory with `pn_lower_host(function_name)`. The host
provides the differentiable execution backend; this is not a CNN extension to
the original `pup_gpu_open` CUDA runtime.

```pup
batch = config("batch",4)
size = config("image_size",256)
images = input("images",[batch,3,size,size])
targets = input("targets",[batch,1,size/2,size/2])
c = conv2d(images,"stem",64,7,2,3,0)
b = batchnorm(c,"stem_bn")
p = maxpool2d(relu(b),3,2,1)
logits = conv_transpose2d(p,"heatmap",1,4,2,1,1)
objective = spatial_balanced_bce(logits,targets)
optimizer = adam(objective,config("learning_rate",0.0001))
output logits,objective,optimizer
```

The named layer prefix is the checkpoint namespace. A backend creates the
corresponding weights/biases and BatchNorm affine/running state. Each layer name
must be unique. Shapes, NCHW ranks, convolution groups, residual compatibility,
heatmap targets and optimizer objective/rates are checked before source emission.
Malformed models retain located diagnostics and do not replace an existing
artifact. Static input dimension expressions support integer arithmetic;
`config` values can be specialized by the backend at model construction.

| Network expression | Semantics |
| --- | --- |
| `config("name",number)` | Scalar default overridden by the host backend. |
| `conv2d(x,"name",channels,kernel,stride,padding,bias[,groups])` | Named square-kernel NCHW convolution; bias is 0 or 1. |
| `conv_transpose2d(...)` | Corresponding transpose, without output padding. |
| `batchnorm(x,"name")` | Named affine BatchNorm and tracked running state. |
| `maxpool2d(x,kernel,stride,padding)` | Explicit zero-padded square pooling. |
| `relu(x)`, `a+b` | ReLU and same-shape residual addition. |
| `hardswish(x)`, `hardsigmoid(x)` | Hard activations with differentiable backend execution. |
| `global_avgpool2d(x)` | Spatial mean retaining singleton H/W axes. |
| `linear4d(x,"name",width)` | Named linear projection of N,C,1,1; checkpoint weights remain rank two. |
| `x*gate` | NCHW multiplication by a matching N,C,1,1 channel gate. |
| `checkpoint_alias(optimizer,"source.","alias.")` | Additional checkpoint names sharing parameter storage; no duplicate optimizer updates. |
| `spatial_balanced_bce(logits,targets)` | Scalar spatial-balanced heatmap BCE. |
| `adam(objective,lr[,head_lr])` | Adam training policy, optionally a separate head rate. |

Generated factories call `pup_input`, `pup_config_f32`, `pup_i64`,
`pup_conv2d`, `pup_batchnorm`, `pup_maxpool2d`, `pup_relu`, `pup_add`,
`pup_hardswish`, `pup_hardsigmoid`, `pup_global_avgpool2d`, `pup_linear4d`,
`pup_channel_mul`, `pup_checkpoint_alias`, `pup_spatial_balanced_bce`,
`pup_adam` and `pup_finish`. A runtime supplies
those functions and owns values, gradients, optimizer buffers and serialization.
`pup_finish` receives named input pairs and ordered output handles. The frontend
stores metadata and does not allocate the primitive interpreter's material
workspace for network graphs. The network graph depth bound is 256; primitive
graphs retain 64.

The Roboband native HIP backend uses this source of truth for the exact current
ResNet-18 backbone/four-stage heatmap head and its objective/Adam policy. Its
forward and reverse-mode kernels, BatchNorm updates, gradients and Adam moments
match the original Tinygrad reference within documented FP32 tolerances;
same-input checkpoint resume is byte-identical. The whole model retains all
146 state names and 13,962,785 trainable scalars. Changing a `.pup` layer width
changes the executing native model, rather than annotating a hardcoded builder.

The MobileNetV4 heatmap graph additionally uses grouped/depthwise convolutions,
hard activations, linear squeeze-and-excitation gates and checkpoint aliases.
It preserves the existing 630 state entries, including both block namespaces.
Full-model logits/loss and selected gradients are verified against Tinygrad.

Current limitations: the Roboband adapter supports 3×3/stride-2/pad-1
pooling, spatial-balanced BCE and Adam. It has no general graph `grad` expression,
layer sharing, loops, dynamic ranks, mixed precision or automatic CNN lowering
to the primitive CUDA/SASS runtime. Other backends must implement the stated
contracts and verify their gradients. The scalar loss in the current Roboband
backend is computed on the host; forward/backward/Adam run on the GPU.

Device-free network checks:

```sh
build/flex libs/ml/pup/tests/network.flex -o build/pup-network-tests
build/pup-network-tests
```

The device-free Pup suite also executes the named network checks.
Actual ResNet training and malformed/modified-model checks live in Roboband's
`flex/tests/test_training.py` and `flex/tests/test_pup.py`.


## Static named inference graphs

`pup_parse_inference(text,size,path)` reuses the named-network parser and emits
factories with `pn_lower_host`. Existing `pup_parse` primitive inference and
`pup_parse_network` training behavior remain separate. The host implements the
emitted functions and owns tensor storage/execution. This path supports rank
zero through four and a graph depth of 512; the existing training limit is 256.

Additional operations are `tensor("name",[shape...])` for checkpoint constants,
`sigmoid(x)`, `concat(a,b,axis)`, `slice(x,axis,start,end)` (unit-step, exclusive
end), `upsample2d(x,integer_scale)` (nearest/asymmetric), `softmax(x,axis)` and
`batch_matmul(a,b)` (equal batch prefixes). Negative softmax/concat/slice axes
are normalized. Reshape, permutation and scalar/singleton broadcasting use the
existing primitive shape rules. Invalid shapes/axes/intervals fail before a
factory is emitted. Max pooling follows the host contract; the YOLO backend
uses negative-infinity padding.

Factories call `pup_tensor`, `pup_shape`, `pup_scalar`, `pup_binary`,
`pup_reshape`, `pup_permute`, the existing convolution/pooling helpers, and
`pup_sigmoid`, `pup_concat`, `pup_slice`, `pup_upsample2d`, `pup_softmax`,
`pup_batch_matmul`. The input/output registration convention is unchanged.
No gradients or training objective are inferred in this mode.

Puppybot's `flex/vision/` supplies the first CPU/HIP backend and a real YOLO26n
model, imported from an official checkpoint without Torch. Its small independent
CPU/HIP fixture and full-model tinygrad comparisons live in Puppybot's
`flex/tests/vision.py` and `flex/tests/yolo.py`.

## Named-tensor inference specialization

The complementary [static tensor GPU compiler](gpu/README.md) specializes named
CNN/attention graph inventories, with shared-memory/register tiles, fusion,
buffer placement and PTX/native SASS/HIP output. It is exposed as
`libs/ml/pup/gpu.flex` and `scripts/pup-codegen.flex`, without an application
runtime dependency. The primitive frontend above retains its existing ABI.
