import "../../../../lib/gpu.flex";
fn ll_sum(x) {return gpu_warp_sum_f32(x);}
fn ll_max(a,b) {return gpu_f32_max(a,b);}
fn ll_exp(x) {return gpu_f32_exp2_approx(gpu_f32_mul(x,1069066811));}

fn ll_weight(p) {return gpu_f16x2_to_f32x2(gpu_load_u16(p))&4294967295;}
fn ll_w0(p) {return gpu_f16x2_to_f32x2(p)&4294967295;}
fn ll_w1(p) {return gpu_f16x2_to_f32x2(p)>>32;}
fn ll_half_pair(p) {return p&4294967295;}
