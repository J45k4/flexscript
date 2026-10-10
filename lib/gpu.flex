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
