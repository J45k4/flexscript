import "../../../../lib/gpu.flex";
fn ll_sum(x) {return gpu_warp_sum_f32(x);}
fn ll_max(a,b) {return gpu_f32_max(a,b);}
fn ll_exp(x) {return gpu_f32_exp2_approx(gpu_f32_mul(x,1069066811));}

fn ll_weight(p) {return gpu_load_bf16(p);}
fn ll_w0(p) {return p<<16;}
fn ll_w1(p) {return p&4294901760;}
fn ll_half_pair(p) {return gpu_bf16x2_to_f16x2(p);}
