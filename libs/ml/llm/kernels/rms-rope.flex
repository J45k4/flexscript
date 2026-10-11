// One warp normalizes a 128-wide head and applies split-half rotary embedding.
// Descriptor: input, BF16 scales, rotary output, epsilon, table, state, norm output.
// Retain the unfused normalization output for any other graph consumers.
import "common.flex";
fn kernel(index,input,output,count) {
    let head=index>>5;let dim=(index&31)*2;let offset=head*512+dim*4;
    let x=gpu_launch_word(0)+offset;let w=gpu_launch_word(1)+dim*2;
    let a=gpu_load_u64(x);let b=gpu_load_u64(x+256);
    let sum=gpu_f32_fma(a,a,gpu_f32_mul(a>>32,a>>32));
    sum=gpu_f32_fma(b,b,sum);sum=gpu_f32_fma(b>>32,b>>32,sum);
    let scale=gpu_f32_rsqrt_approx(gpu_f32_add(gpu_f32_mul(ll_sum(sum),1006632960),(gpu_launch_word(3)&4294967295)));
    let wa=gpu_load_u32(w);let wb=gpu_load_u32(w+128);
    let a0=gpu_f32_mul(gpu_f32_mul(a,scale),ll_w0(wa));let a1=gpu_f32_mul(gpu_f32_mul(a>>32,scale),ll_w1(wa));
    let b0=gpu_f32_mul(gpu_f32_mul(b,scale),ll_w0(wb));let b1=gpu_f32_mul(gpu_f32_mul(b>>32,scale),ll_w1(wb));
    let norm=gpu_launch_word(6)+offset;
    gpu_store_u32(norm,a0);gpu_store_u32(norm+4,a1);gpu_store_u32(norm+256,b0);gpu_store_u32(norm+260,b1);
    let table=gpu_launch_word(4)+(gpu_load_u64(gpu_launch_word(5))*64+dim)*8;
    let trig0=gpu_load_u64(table);let trig1=gpu_load_u64(table+8);let y=gpu_launch_word(2)+offset;
    gpu_store_u32(y,gpu_f32_sub(gpu_f32_mul(a0,trig0),gpu_f32_mul(b0,trig0>>32)));
    gpu_store_u32(y+256,gpu_f32_add(gpu_f32_mul(b0,trig0),gpu_f32_mul(a0,trig0>>32)));
    gpu_store_u32(y+4,gpu_f32_sub(gpu_f32_mul(a1,trig1),gpu_f32_mul(b1,trig1>>32)));
    gpu_store_u32(y+260,gpu_f32_add(gpu_f32_mul(b1,trig1),gpu_f32_mul(a1,trig1>>32)));return 0;
}
fn main(){return 78;}
