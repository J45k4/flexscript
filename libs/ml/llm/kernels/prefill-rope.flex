// Token-major split-half rotary for a prompt starting at cache position zero.
import "common.flex";
fn kernel(index,input,output,count) {
    let width=gpu_launch_word(3);let token=gpu_block_y();let local=gpu_block_x()*128+gpu_thread_x();if local>=(width>>1) {return 0;}let head=local>>6;let dim=local&63;let offset=token*width*4+head*512+dim*4;
    let x=gpu_launch_word(0)+offset;let y=gpu_launch_word(1)+offset;let table=gpu_launch_word(2)+(token*64+dim)*8;
    let c=gpu_load_u32(table);let s=gpu_load_u32(table+4);let a=gpu_load_u32(x);let b=gpu_load_u32(x+256);
    gpu_store_u32(y,gpu_f32_sub(gpu_f32_mul(a,c),gpu_f32_mul(b,s)));gpu_store_u32(y+256,gpu_f32_add(gpu_f32_mul(b,c),gpu_f32_mul(a,s)));return 0;
}
fn main(){return 78;}
