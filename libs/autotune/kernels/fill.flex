import "../../../lib/gpu.flex";
// Exactly representable signed inputs. The CPU oracle accumulates integer
// products independently, then divides by 64 once per sampled output cell.
fn kernel(index,input,output,count) {if index<count {gpu_store_u32(output+index*4,gpu_f32_mul(gpu_f32_from_i64(index%11-5),1040187392));}return 0;}
fn main(){return 78;}
