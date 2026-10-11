// Descriptor: F32 input, BF16 scale[width], F32 output, width, inverse width,
// epsilon. One 128-thread block normalizes each row (including Q/K heads).
import "common.flex";
fn kernel(index,input,output,count) {
    let row=index>>7;let lane=index&127;let n=(gpu_launch_word(3)&4294967295);
    let x=gpu_launch_word(0)+row*n*4;let y=gpu_launch_word(2)+row*n*4;
    let sum=0;let k=lane;let p=x+lane*4;
    while k+384<n {
        let a=gpu_load_u32(p);let b=gpu_load_u32(p+512);let c=gpu_load_u32(p+1024);let d=gpu_load_u32(p+1536);
        sum=gpu_f32_fma(a,a,sum);sum=gpu_f32_fma(b,b,sum);
        sum=gpu_f32_fma(c,c,sum);sum=gpu_f32_fma(d,d,sum);p=p+2048;k=k+512;
    }
    while k<n {let a=gpu_load_u32(p);sum=gpu_f32_fma(a,a,sum);p=p+512;k=k+128;}
    sum=ll_sum(sum);if !(lane&31) {gpu_shared_store64((lane>>5)*8,sum);}gpu_barrier();
    sum=gpu_f32_add(gpu_f32_add(gpu_shared_load64(0),gpu_shared_load64(8)),gpu_f32_add(gpu_shared_load64(16),gpu_shared_load64(24)));
    let scale=gpu_f32_rsqrt_approx(gpu_f32_add(gpu_f32_mul(sum,gpu_launch_word(4)),gpu_launch_word(5)));
    let w=gpu_launch_word(1)+lane*2;p=x+lane*4;y=y+lane*4;
    k=lane;while k<n {gpu_store_u32(y,gpu_f32_mul(gpu_f32_mul(gpu_load_u32(p),scale),ll_weight(w)));k=k+128;p=p+512;y=y+512;w=w+256;}
    return 0;
}
fn main(){return 78;}
