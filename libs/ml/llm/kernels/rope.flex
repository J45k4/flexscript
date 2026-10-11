// Descriptor: F32 input/output, [capacity,64,cos/sin] table, position pointer.
// Split-half rotary embedding, head width 128. One thread writes a pair.
import "common.flex";
fn kernel(index,input,output,count) {
    let head=index>>6;let dim=index&63;let offset=head*512+dim*4;
    let x=gpu_launch_word(0)+offset;let y=gpu_launch_word(1)+offset;
    let table=gpu_launch_word(2)+(gpu_load_u64(gpu_launch_word(3))*64+dim)*8;
    let c=gpu_load_u32(table);let s=gpu_load_u32(table+4);
    let a=gpu_load_u32(x);let b=gpu_load_u32(x+256);
    gpu_store_u32(y,gpu_f32_sub(gpu_f32_mul(a,c),gpu_f32_mul(b,s)));
    gpu_store_u32(y+256,gpu_f32_add(gpu_f32_mul(b,c),gpu_f32_mul(a,s)));return 0;
}
fn main(){return 78;}
