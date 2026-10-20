import "../../../lib/gpu.flex";
// Fixed-order split-K merge; included in the benchmark event interval.
fn kernel(index,input,output,count) {
    if index<count {let elements=gpu_launch_word(0);let parts=gpu_launch_word(1);let group=index/elements;let at=index%elements;let sum=0;let part=0;while part<parts {sum=gpu_f32_add(sum,gpu_load_u32(input+((group*parts+part)*elements+at)*4));part=part+1;}gpu_store_u32(output+index*4,sum);}return 0;
}
fn main(){return 78;}
