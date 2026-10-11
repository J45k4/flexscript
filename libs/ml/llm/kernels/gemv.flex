// Descriptor: BF16 [rows,inner] weights, F32 input, F32 output, inner.
// One full warp per row; strided lanes read contiguous weights and inputs.
import "common.flex";
fn kernel(index,input,output,count) {
    let row=index>>5;let lane=index&31;
    let n=(gpu_launch_word(3)&4294967295);
    let w=gpu_launch_word(0)+row*n*2+lane*2;let x=gpu_launch_word(1)+lane*4;
    let acc=0;let k=lane;
    while k+96<n {
        let w0=gpu_load_u16(w);let w1=gpu_load_u16(w+64);let w2=gpu_load_u16(w+128);let w3=gpu_load_u16(w+192);
        let a0=gpu_load_u32(x);let a1=gpu_load_u32(x+128);let a2=gpu_load_u32(x+256);let a3=gpu_load_u32(x+384);
        acc=gpu_f32_fma(ll_w0(w0),a0,acc);acc=gpu_f32_fma(ll_w0(w1),a1,acc);
        acc=gpu_f32_fma(ll_w0(w2),a2,acc);acc=gpu_f32_fma(ll_w0(w3),a3,acc);
        w=w+256;x=x+512;k=k+128;
    }
    while k<n {
        acc=gpu_f32_fma(ll_weight(w),gpu_load_u32(x),acc);w=w+64;x=x+128;k=k+32;
    }
    acc=ll_sum(acc);if !lane {gpu_store_u32(gpu_launch_word(2)+row*4,acc);}return 0;
}
fn main(){return 78;}
