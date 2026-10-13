// GPU-only operations. Import this file in kernels; the GPU backends lower
// these reserved names to instructions. Geometry/cooperation require a GPU.
import "f64.flex";
fn gpu_host_only() {syscall(231,78,0,0,0,0,0);return 0;}
fn gpu_thread_x(){return gpu_host_only();}
fn gpu_thread_y(){return gpu_host_only();}
fn gpu_thread_z(){return gpu_host_only();}
fn gpu_block_x(){return gpu_host_only();}
fn gpu_block_y(){return gpu_host_only();}
fn gpu_block_z(){return gpu_host_only();}
fn gpu_block_dim_x(){return gpu_host_only();}
fn gpu_block_dim_y(){return gpu_host_only();}
fn gpu_block_dim_z(){return gpu_host_only();}
fn gpu_grid_dim_x(){return gpu_host_only();}
fn gpu_grid_dim_y(){return gpu_host_only();}
fn gpu_grid_dim_z(){return gpu_host_only();}
fn gpu_lane(){return gpu_host_only();}
fn gpu_active_mask(){return gpu_host_only();}
fn gpu_barrier(){return gpu_host_only();}
// Block rendezvous with shared-memory ordering; global ordering is not required.
fn gpu_shared_barrier(){return gpu_host_only();}
fn gpu_warp_sync(mask){return gpu_host_only();}
fn gpu_shared_load64(offset){return gpu_host_only();}
fn gpu_shared_store64(offset,value){return gpu_host_only();}
fn gpu_atomic_add64(pointer,value){return gpu_host_only();}
fn gpu_atomic_and64(pointer,value){return gpu_host_only();}
fn gpu_atomic_or64(pointer,value){return gpu_host_only();}
fn gpu_atomic_xor64(pointer,value){return gpu_host_only();}
fn gpu_atomic_exchange64(pointer,value){return gpu_host_only();}
fn gpu_atomic_min64(pointer,value){return gpu_host_only();}
fn gpu_atomic_max64(pointer,value){return gpu_host_only();}
fn gpu_atomic_cas64(pointer,compare,value){return gpu_host_only();}
fn gpu_shuffle(value,lane,mask){return gpu_host_only();}
fn gpu_ballot(value,mask){return gpu_host_only();}
fn gpu_fence(){return gpu_host_only();}
fn gpu_mma_f16(a,b,c,d){return gpu_host_only();}
fn gpu_texture_fetch(texture,index){return gpu_host_only();}
// Aligned packed memory. BF16 loads expand exactly to FP32 bit patterns.
fn gpu_load_u64(p){return load64(p);}
// Streaming cache hint for aligned words consumed once, such as large matrices.
fn gpu_load_stream_u64(p){return load64(p);}
fn gpu_load_u16(p){return load8(p)|(load8(p+1)<<8);}
fn gpu_load_u32(p){return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn gpu_store_u32(p,v){store8(p,v);store8(p+1,v>>8);store8(p+2,v>>16);store8(p+3,v>>24);return v;}
fn gpu_load_bf16(p){return (load8(p)|(load8(p+1)<<8))<<16;}
// Native SFU approximations, flush subnormal inputs/results. Explicitly distinct
// from the correctly rounded divide/sqrt intrinsics; no CPU approximation.
fn gpu_f32_exp2_approx(x){return gpu_host_only();}
fn gpu_f32_rcp_approx(x){return gpu_host_only();}
fn gpu_f32_rsqrt_approx(x){return gpu_host_only();}
// Floating values are IEEE bit patterns, consistent with lib/f64.flex.
// Host fallbacks provide a reference for ordinary finite arithmetic. GPU NaN
// payloads and conversion edge cases can differ from the software reference.
// Direct SASS div/sqrt canonicalize binary32/invalid NaNs and quiet binary64
// input NaNs while retaining their sign/payload; see docs/gpu-features.md.
fn gpu_f64_add(a,b){return f64_add(a,b);}
fn gpu_f64_sub(a,b){return f64_sub(a,b);}
fn gpu_f64_mul(a,b){return f64_mul(a,b);}
fn gpu_f64_div(a,b){return f64_div(a,b);}
fn gpu_f64_sqrt(a){return f64_sqrt(a);}
fn gpu_f64_fma(a,b,c){return gpu_host_only();}
fn gpu_f64_from_i64(a){return f64_from_i64(a);}
fn gpu_f64_to_i64(a){return f64_to_i64_trunc(a);}
fn gpu_f32_unpack(a) {
    let sign=(a&0x80000000)<<32;let exponent=(a>>23)&255;let fraction=a&0x7fffff;
    if exponent==255 {return sign|0x7ff0000000000000|(fraction<<29);}
    if exponent==0 {
        if fraction==0 {return sign;}
        exponent=1;while fraction<0x800000 {fraction=fraction<<1;exponent=exponent-1;}
        fraction=fraction&0x7fffff;
    }
    return sign|((exponent+896)<<52)|(fraction<<29);
}
fn gpu_f32_pack(a) {
    let sign=(a>>32)&0x80000000;let exponent=((a>>52)&2047)-896;let fraction=a&0xfffffffffffff;
    if f64_is_nan(a) {return 0x7fc00000;}
    if exponent>=255 {return sign|0x7f800000;}
    if exponent<=0 {
        if exponent< -23 {return sign;}
        fraction=fraction|0x10000000000000;let shift=30-exponent;
        let value=fraction>>shift;let rest=fraction&((1<<shift)-1);let halfway=1<<(shift-1);
        if rest>halfway || (rest==halfway && (value&1)) {value=value+1;}return sign|value;
    }
    let value=fraction>>29;let rest=fraction&0x1fffffff;
    if rest>0x10000000 || (rest==0x10000000 && (value&1)) {value=value+1;}
    if value>=0x800000 {exponent=exponent+1;value=0;}
    return sign|(exponent<<23)|value;
}
fn gpu_f32_add(a,b){return gpu_f32_pack(f64_add(gpu_f32_unpack(a),gpu_f32_unpack(b)));}
fn gpu_f32_sub(a,b){return gpu_f32_pack(f64_sub(gpu_f32_unpack(a),gpu_f32_unpack(b)));}
fn gpu_f32_mul(a,b){return gpu_f32_pack(f64_mul(gpu_f32_unpack(a),gpu_f32_unpack(b)));}
fn gpu_f32_div(a,b){return gpu_f32_pack(f64_div(gpu_f32_unpack(a),gpu_f32_unpack(b)));}
fn gpu_f32_sqrt(a){return gpu_f32_pack(f64_sqrt(gpu_f32_unpack(a)));}
fn gpu_f32_fma(a,b,c){return gpu_host_only();}
fn gpu_f32_from_i64(a){
    if a==0x8000000000000000 {return 0xdf000000;}
    let sign=0;if a<0 {sign=0x80000000;a=-a;}if !a {return sign;}
    let bit=0;let word=a;while word>=2 {word=word>>1;bit=bit+1;}
    let mant=a;
    if bit<=23 {mant=a<<(23-bit);}else {
        let shift=bit-23;mant=a>>shift;let rest=a&((1<<shift)-1);let halfway=1<<(shift-1);
        if rest>halfway || (rest==halfway && (mant&1)) {mant=mant+1;}
    }
    if mant>=0x1000000 {mant=mant>>1;bit=bit+1;}
    return sign|((bit+127)<<23)|(mant&0x7fffff);
}
fn gpu_f32_to_i64(a){return f64_to_i64_trunc(gpu_f32_unpack(a));}

// Numeric maximum: a lone NaN yields the numeric argument; +0 wins over -0.
// Like the other F32 intrinsics, arguments and result are low-word bit patterns.
fn gpu_f32_max(a,b) {
    a=a&4294967295;b=b&4294967295;
    if (a&2147483647)>2139095040 {return b;}
    if (b&2147483647)>2139095040 {return a;}
    if (a^b)&2147483648 {if a&2147483648 {return b;}return a;}
    if a&2147483648 {if a<b {return a;}return b;}
    if a>b {return a;}return b;
}

// Collective: all 32 lanes must participate. Broadcast a tree-reduced F32 sum.
fn gpu_warp_sum_f32(x){return gpu_host_only();}

// Optional eight by-value launch words. The index wraps modulo eight.
// Kernels using this intrinsic require cuda_launch_words or matching raw args.
fn gpu_launch_word(index){return gpu_host_only();}

// Pack two FP32 values into two round-to-nearest-even FP16 values.
fn gpu_f32_to_f16_bits(bits) {
    let sign=(bits>>16)&32768;let exponent=((bits>>23)&255)-112;let fraction=bits&8388607;
    if ((bits>>23)&255)==255 {if fraction {return sign|32256;}return sign|31744;}
    if exponent>=31 {return sign|31744;}
    let shift=13;if exponent<=0 {if exponent< -10 {return sign;}fraction=fraction|8388608;shift=14-exponent;exponent=0;}
    let value=fraction>>shift;let rest=fraction&((1<<shift)-1);let half=1<<(shift-1);
    if rest>half || (rest==half && (value&1)) {value=value+1;}
    return sign|(exponent<<10)+value;
}
fn gpu_f32x2_to_f16x2(value){return gpu_f32_to_f16_bits(value)|(gpu_f32_to_f16_bits(value>>32)<<16);}
// Full 16x8x8 FP16 tile: return the first FP32 pair and store the second pair
// to an eight-byte-aligned shared offset owned exclusively by this lane.
fn gpu_mma_f16x4(a,b,c,d,upper_offset){return gpu_host_only();}

// Convert two packed BF16 values directly to two RN-even FP16 values.
fn gpu_bf16x2_to_f16x2(value){return gpu_f32_to_f16_bits((value&65535)<<16)|(gpu_f32_to_f16_bits(value&4294901760)<<16);}

fn gpu_f16_to_f32_bits(bits) {
    let sign=(bits&32768)<<16;let exponent=(bits>>10)&31;let fraction=bits&1023;
    if exponent==31 {return sign|2139095040|(fraction<<13);}
    if !exponent {if !fraction {return sign;}exponent=113;while fraction<1024 {fraction=fraction<<1;exponent=exponent-1;}return sign|(exponent<<23)|((fraction&1023)<<13);}
    return sign|((exponent+112)<<23)|(fraction<<13);
}
// Expand the low two FP16 values to two packed FP32 values.
fn gpu_f16x2_to_f32x2(value){return gpu_f16_to_f32_bits(value&65535)|(gpu_f16_to_f32_bits((value>>16)&65535)<<32);}

// RDNA4 wave32 16x16x16 WMMA. A/B contain eight FP16 values per lane;
// C contains eight FP32 values. Return the first pair and write the other three
// pairs at the caller's lane-private shared offset. All 32 lanes participate.
fn gpu_rdna_wmma_f16x8(a0,a1,b0,b1,c0,c1,c2,c3,offset){return gpu_host_only();}

// Cross-device/host publication. Pointers must be aligned, coherent memory.
// These are stronger than gpu_fence (which only orders device global memory).
fn gpu_system_fence(){return gpu_host_only();}
// GPU wall clock, with host-provided ticks/kHz calibration in the profile ABI.
fn gpu_clock(){return gpu_host_only();}
fn gpu_system_load_acquire64(pointer){return gpu_host_only();}
fn gpu_system_store_release64(pointer,value){return gpu_host_only();}
fn gpu_system_exchange64(pointer,value){return gpu_host_only();}
fn gpu_system_add64(pointer,value){return gpu_host_only();}

// Runtime-provided cooperative grid barrier (currently HIP). Every thread
// participates; fallbacks can instead use the portable generation barrier.
fn gpu_cooperative_barrier(){return gpu_host_only();}

// Device-scope ordering for GPU-owned synchronization scratch.
fn gpu_device_load_acquire64(pointer){return gpu_host_only();}
fn gpu_device_store_release64(pointer,value){return gpu_host_only();}
fn gpu_device_add64(pointer,value){return gpu_host_only();}
fn gpu_device_fence(){return gpu_host_only();}
// Relaxed coherent polling; pair observation with an acquire fence before
// consuming data. Release fences publish earlier reads/writes before signaling.
fn gpu_device_load_relaxed64(pointer){return gpu_host_only();}
fn gpu_device_release_fence(){return gpu_host_only();}
fn gpu_device_acquire_fence(){return gpu_host_only();}
