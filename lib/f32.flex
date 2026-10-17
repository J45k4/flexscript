// Portable binary32 words; CPU and GPU backends may lower these functions.
import "gpu.flex";
lowering f32_add "f32.add";
lowering f32_sub "f32.sub";
lowering f32_mul "f32.mul";
lowering f32_div "f32.div";
lowering f32_sqrt "f32.sqrt";
lowering f32_dot3 "f32.dot3";
lowering f32_dot3_load "f32.dot3.load";
fn f32_add(a,b){return gpu_f32_add(a,b);}
fn f32_sub(a,b){return gpu_f32_sub(a,b);}
fn f32_mul(a,b){return gpu_f32_mul(a,b);}
fn f32_div(a,b){return gpu_f32_div(a,b);}
fn f32_sqrt(a){return gpu_f32_sqrt(a);}
// Three products, then (x*a + y*b) + z*c. No fused multiply-add.
fn f32_dot3(x,y,z,a,b,c){return f32_add(f32_add(f32_mul(x,a),f32_mul(y,b)),f32_mul(z,c));}
// Vectors use three word slots (8-byte stride); the low 32 bits hold FP32.
fn f32_dot3_load(a,b){return f32_dot3(load64(a),load64(a+8),load64(a+16),load64(b),load64(b+8),load64(b+16));}
