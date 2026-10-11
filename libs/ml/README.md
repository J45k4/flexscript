# ML in Flexscript

A small working deep-learning library implemented in ordinary Flexscript.
Import `ml.flex` for portable CPU tensors, reverse-mode autodiff, dense layers
and SGD. Import `cuda.flex` separately for the optional GPU matrix product.
Neither entry point requires a compiler extension or ML-specific syntax.

For a static model blueprint that compiles to GPU kernels, use the optional
[Pup domain frontend](pup/README.md). It includes a primitive F32 tensor graph,
reference interpreter, scheduling, PTX/direct SASS lowering and a working
MNIST inference runner with safetensors checkpoints. The eager binary64 API
below remains a separate library; Pup graph autodiff and training are not yet
connected to it.

## Train the example

From the repository root, using a current compiler:

```sh
build/flex-transform libs/ml/examples/xor.flex -o build/ml-xor
build/ml-xor
```

The example trains a seeded `2 -> 8 -> 1` network with ReLU, mean squared error
and SGD for 1,200 steps. It checks that loss is finite, falls by at least 100x,
ends below 0.001 and classifies all four XOR inputs correctly. It exits nonzero
if any check fails. Inputs, parameters and the arena stay allocated; each step
reuses the temporary graph storage.

## Tensor and gradient basics

Every tensor is a contiguous, row-major `[rows,cols]` binary64 matrix. A scalar
is `[1,1]`. Float arguments and results are IEEE binary64 bit-pattern words,
matching `lib/f64.flex`; use its helpers instead of integer `+`, `*`, etc.
There are no float literals, aggregate types or overloaded operators involved.

```flex
import "libs/ml/ml.flex"; // Relative to this application's source file.
fn main() {
    let ctx=ml_context(65536);
    let x=ml_scalar(ctx,f64_from_i64(3),1); // Trainable leaf.
    let mark=ml_mark(ctx);
    let loss=ml_square(x);
    ml_backward(loss);                     // x.grad = 6.
    ml_sgd(x,f64_div(f64_from_i64(1),f64_from_i64(4)));
    ml_reset(mark);                        // Discard loss; keep updated x.
    return f64_to_i64_nearest(ml_item(x)); // Returns 2 (x is now 1.5).
}
```

Tensor operations build an eager reverse-mode graph when recording is enabled
and at least one input requires gradients. `ml_backward(loss)` accepts a
trainable scalar, validates its reachable graph, clears **all** gradient buffers
in that context and propagates a seed of one. Shared subexpressions accumulate
correctly within that backward pass. Separate backward calls do not accumulate
gradients across batches. Use `ml_sum` or `ml_mean` to reduce a vector loss.

Only leaf tensors can be changed with `ml_set`, `ml_fill` or `ml_sgd`.
Changing a leaf after a recorded forward operation makes a subsequent backward
through that operation fail; recompute the forward graph after updates.
`ml_data` exposes a read-only-by-contract pointer. Writing through it bypasses
version checking and is unsupported while a graph references the tensor.
ReLU's derivative is zero at zero; nonfinite arithmetic otherwise follows the
numeric operations' behavior.

## API

| Function | Behavior |
| --- | --- |
| `ml_context(bytes)` | Allocate a fixed-capacity arena, initially recording |
| `ml_tensor(ctx,rows,cols,requires_grad)` | Zero-filled tensor; last argument is boolean |
| `ml_scalar(ctx,value,requires_grad)` | Filled `[1,1]` tensor |
| `ml_rows(t)`, `ml_cols(t)`, `ml_size(t)` | Shape and element count |
| `ml_get(t,i)`, `ml_grad(t,i)`, `ml_item(t)` | Flat value, flat gradient, scalar value |
| `ml_set(t,i,value)`, `ml_fill(t,value)` | Checked leaf mutation |
| `ml_add(a,b)`, `ml_sub(a,b)`, `ml_mul(a,b)`, `ml_div(a,b)` | Elementwise operations with singleton broadcasting in either dimension |
| `ml_square(a)`, `ml_relu(a)` | Elementwise operations |
| `ml_matmul(a,b)` | `[M,K] @ [K,N] -> [M,N]` |
| `ml_sum(a)`, `ml_mean(a)` | Reduce all elements to a scalar |
| `ml_transpose(a)`, `ml_reshape(a,rows,cols)` | Copy into a new contiguous tensor; both differentiate |
| `ml_mse(prediction,target)` | Broadcast subtraction, square, then mean |
| `ml_backward(loss)`, `ml_zero_grad(ctx)` | Reverse pass / explicitly clear gradients |
| `ml_record(ctx,enabled)` | Enable/disable graph recording; return previous flag |
| `ml_mark(ctx)`, `ml_reset(mark)`, `ml_used(ctx)` | Checkpoint/reuse arena storage and inspect used bytes |
| `ml_seed(ctx,seed)`, `ml_random(ctx)` | Deterministic LCG initialization, uniform `[0,1)` |
| `ml_linear(ctx,inputs,outputs)` | Dense layer with Xavier-uniform weights and zero bias |
| `ml_weight(layer)`, `ml_bias(layer)` | Trainable parameter tensors |
| `ml_linear_forward(layer,input)` | Matrix product plus broadcast bias |
| `ml_sgd(parameter,rate)`, `ml_linear_step(layer,rate)` | Apply SGD using current gradients |

Shapes must be positive and tensors must belong to the same context. Zero-size
tensors, arbitrary ranks/strides and views are not supported yet. The LCG is a
reproducible initializer, not a statistical-quality data-generation facility.

## Memory ownership

A context owns its tensors, gradients, layers and marks in one allocation.
The allocation has process/instance lifetime, like Flexscript's `alloc`;
there is no implicit collection or context destructor. Allocate parameters and
training inputs once, create a reusable mark, then reset after each step.
`ml_reset` invalidates every tensor/layer/mark created after the checkpoint and
restores graph recording. Never retain these pointers across a reset.
Contexts are independent and are not safe for concurrent mutation.

Tensor records cost 128 bytes plus eight bytes per value and another eight per
gradient when needed. A mark costs 32 bytes. Arena exhaustion, bad dimensions,
incompatible contexts/shapes, invalid access and invalid gradient use produce
an `ml:` diagnostic and exit status 1. This initial API does not return errors
for recovery. The fixed arena keeps training graphs from growing unbounded.

## Optional GPU matrix multiplication

```sh
build/flex-transform --target ptx libs/ml/kernels/matmul.flex -o build/ml-matmul.ptx
build/flex-transform --target sass-sm75 libs/ml/kernels/matmul.flex -o build/ml-matmul.cubin
```

Import `libs/ml/cuda.flex`, create a CUDA context and load either artifact with
the existing `lib/cuda.flex` API, then call `ml_cuda_matmul(module,a,b)`.
The caller owns the current context and module and must check their creation
statuses and release them. The adapter owns/frees its device buffers and reuses
temporary host packing storage from the tensor arena. Driver errors fail with
the same `ml:` diagnostic.

The result participates in the ordinary reverse graph. **Only its forward
matrix product runs on the GPU; backward operations and the other tensor
operations run on the CPU.** Each call transfers inputs and output; there is
no persistent device tensor storage or automatic backend selection yet.
The kernel uses scalar FP64 arithmetic, one output per thread, with no tiling,
tensor-core use or performance claim. Direct SASS currently targets SM75.
GPU execution still requires NVIDIA's driver and `libcuda`; the portable
entry point has no GPU dependencies.

## Tests and next steps

```sh
build/flex-transform scripts/test-ml.flex -o build/test-ml
build/test-ml --compiler build/flex-transform --report build/ml-tests.json
build/test-ml --compiler build/flex-transform --gpu --report build/ml-tests-device.json
```

Tests include finite-difference gradients for every operation and both operand
broadcast directions, shared graph branches, ReLU boundaries, repeated
backward, mutation validation, arena reuse, native/interpreter/JIT/WASM
execution and successful XOR training. Device-free tests compile the matrix
kernel for both backends; `--gpu` requires physical execution and compares its
forward results and both input gradients with the CPU reference.

The initial suite passed 325 device-free checks and 893 checks with physical
GPU execution, including both PTX and direct SM75 SASS matrix kernels.
The XOR example reached all four correct predictions with final MSE below
one millionth.

The next layers are FP32/device-resident tensors, GPU backward kernels, tiled
matrix products, additional activations/losses and Adam. Convolution,
normalization, attention, serialization, data loaders and distributed training
are not implemented. The general compiler extension API can later generate or
fuse kernels without moving tensor/training semantics into the language.
