// Stage one immutable activation tensor as FP16 pairs, reused by projections.
import "common.flex";
fn kernel(index,input,output,count) {
    if index>=gpu_launch_word(2) {return 0;}
    let value=gpu_f32x2_to_f16x2(gpu_load_u64(gpu_launch_word(0)+index*8));gpu_store_u32(gpu_launch_word(1)+index*4,value);return 0;
}
fn main(){return 78;}
