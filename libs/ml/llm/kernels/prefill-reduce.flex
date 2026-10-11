// Disjoint K partitions combined deterministically in FP32 without atomics.
import "common.flex";
fn kernel(index,input,output,count) {
    if index>=gpu_launch_word(2) {return 0;}
    let stride=gpu_launch_word(2)*4;let p=gpu_launch_word(0)+index*4;let left=0;let right=0;let k=gpu_launch_word(3)>>1;
    if !k {left=gpu_load_u32(p);}
    while k&4294967295 {let a=gpu_load_u32(p);let b=gpu_load_u32(p+stride);left=gpu_f32_add(left,a);right=gpu_f32_add(right,b);p=p+stride*2;k=k-1;}
    gpu_store_u32(gpu_launch_word(1)+index*4,gpu_f32_add(left,right));return 0;
}
fn main(){return 78;}
