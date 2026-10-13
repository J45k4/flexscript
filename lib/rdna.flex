// Whole-kernel native gfx1201 wave32 primitives for rdna-gfx1201.
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
// Embedded wave primitive: all 32 lanes active, index / 32 is the output row.
// step points at [kind,threads,weights,x,y,N,...], uniform across the wave.
// N is a positive multiple of 256; row byte offsets fit uint32. The caller
// owns the bounds check, inter-stage synchronization and launch scheduling.
fn gpu_rdna_gemv_stage_f16(index,step) {return gpu_host_only();}
// Full 512-thread blocks; whole grid must be resident. Scratch arrival and
// generation words at work+960/+968 and the u32 phase/count at work+736
// must be zeroed before each launch. The generation remains u64; +960 is
// reserved and stays zero. All blocks must remain resident; at most 112.
fn gpu_rdna_grid_barrier(work) {return gpu_host_only();}
// Embedded complete matrix stage: full 512-thread blocks and positive N
// divisible by 256. The descriptor's thread count is rows*32; rows*N*2 fits
// uint32. Each wave walks its own grid-strided rows; no block/grid barrier.
fn gpu_rdna_gemv_grid_f16(index,step) {return gpu_host_only();}
// One complete 2048-wide RMSNorm row per full 512-thread block. Step contains
// [kind,threads,x,F16 weights,y,2048,inverse width,epsilon,...]. No residual.
fn gpu_rdna_rms_stage_f16(row,step) {return gpu_host_only();}

// One complete wave normalizes a 128-element FP32 row with F16 weights.
// The descriptor matches gpu_rdna_rms_stage_f16; index identifies row/lane.
fn gpu_rdna_rms_head_f16(index,step) {return gpu_host_only();}

// FP32 head width 128; index starts a complete aligned 512-thread head tile.
// step has the resident attention descriptor; all block threads participate.
fn gpu_rdna_attention_f32(index,step) {return gpu_host_only();}

// Resident FP32 element descriptor, F16 gather; row byte offsets fit u32.
fn gpu_rdna_element_f32(index,step) {return gpu_host_only();}

// Resident split-half rotary descriptor, 128-wide FP32 heads and tables.
fn gpu_rdna_rope_f32(index,step) {return gpu_host_only();}

// Immutable resident stage descriptor; all 512 block threads are active.
// Kinds 2/3/4/5/6/28; u32 indices; matrix widths are multiples of 256,
// RMS rows are 128 or 2048 wide. Caller validates shapes before dispatch.
fn gpu_rdna_stage(step) {return gpu_host_only();}
