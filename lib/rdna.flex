// Whole-kernel native gfx1201 wave32 primitives for rdna-direct-gfx1201.
// Launch: one-dimensional blocks of 32..1024 threads, multiple of 32;
// count = rows * 32, N > 0 and N % 256 == 0, row offsets fit uint32.
// Matrix storage is row-major F16; inputs/outputs remain F32.
import "gpu.flex";
// Launch words: weights, x, y, N (remaining words unused).
fn gpu_rdna_gemv_f16() {return gpu_host_only();}
// Launch words: gate, up, x, N, gate_raw, gate_silu, up_raw, product.
fn gpu_rdna_mlp_f16() {return gpu_host_only();}
// input = Q rows, output = K/V rows; count = (Q rows + 2*K rows) * 32.
// Launch words: x, Q weights, K weights, V weights, Qy, Ky, Vy, N.
fn gpu_rdna_gemv_three_f16() {return gpu_host_only();}
// Separate primitive: width 2048, 128 threads/row, 32 bytes dynamic LDS.
// Launch words: a,b,normalized,2048,inverse width,epsilon,F16 scale,residual.
fn gpu_rdna_rms_add_f16() {return gpu_host_only();}
