// One-time checkpoint staging: BF16 pairs -> FP16 pairs in place.
import "common.flex";
fn kernel(index,input,output,count) {
    if index>=gpu_launch_word(1) {return 0;}
    let p=gpu_launch_word(0)+index*4;gpu_store_u32(p,gpu_bf16x2_to_f16x2(gpu_load_u32(p)));return 0;
}
fn main(){return 78;}
