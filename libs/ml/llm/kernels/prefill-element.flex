// Batch embedding and pointwise operations; cache append starts at position 0.
import "common.flex";
fn kernel(index,input,output,count) {
    let a=gpu_launch_word(0);let b=gpu_launch_word(1);let y=gpu_launch_word(2)+index*4;let op=gpu_launch_word(3);let width=gpu_launch_word(5);let v=0;let token=gpu_block_y();let local=gpu_block_x()*128+gpu_thread_x();if local>=width {return 0;}index=token*width+local;y=gpu_launch_word(2)+index*4;
    if op==4 {v=ll_weight(a+(gpu_load_u64(b+token*8)*width+local)*2);}
    else {v=gpu_load_u32(a+index*4);if op==1 {v=gpu_f32_add(v,gpu_load_u32(b+index*4));}
        else if op==2 {v=gpu_f32_mul(v,gpu_load_u32(b+index*4));}
        else if op==3 {v=gpu_f32_mul(v,gpu_f32_rcp_approx(gpu_f32_add(1065353216,ll_exp(v^2147483648))));}}
    gpu_store_u32(y,v);return 0;
}
fn main(){return 78;}
