// Packed RMSNorm: descriptor matches rms.flex, width must be divisible by four.
// 128-wide heads use one warp; larger rows use a 128-thread block.
import "common.flex";
fn kernel(index,input,output,count) {
    let n=(gpu_launch_word(3)&4294967295);let lane=index&127;let row=index>>7;let group=128;let shift=7;
    if n==128 {lane=index&31;row=index>>5;group=32;shift=5;}
    let x=gpu_launch_word(0)+row*n*4+lane*16;let p=x;let remaining=((n>>2)+group-1-lane)>>shift;
    let k=remaining;let sum=0;
    while k {
        let a=gpu_load_u64(p);let b=gpu_load_u64(p+8);
        sum=gpu_f32_fma(a,a,sum);sum=gpu_f32_fma(a>>32,a>>32,sum);
        sum=gpu_f32_fma(b,b,sum);sum=gpu_f32_fma(b>>32,b>>32,sum);p=p+group*16;k=k-1;
    }
    sum=ll_sum(sum);
    if n!=128 {
        if !(lane&31) {gpu_shared_store64((lane>>5)*8,sum);}gpu_barrier();
        sum=gpu_f32_add(gpu_f32_add(gpu_shared_load64(0),gpu_shared_load64(8)),gpu_f32_add(gpu_shared_load64(16),gpu_shared_load64(24)));
    }
    let scale=gpu_f32_rsqrt_approx(gpu_f32_add(gpu_f32_mul(sum,(gpu_launch_word(4)&4294967295)),(gpu_launch_word(5)&4294967295)));
    let w=gpu_launch_word(1)+lane*8;let y=gpu_launch_word(2)+row*n*4+lane*16;p=x;k=remaining;
    while k {
        let a=gpu_load_u64(p);let b=gpu_load_u64(p+8);let weights=gpu_load_u64(w);
        gpu_store_u32(y,gpu_f32_mul(gpu_f32_mul(a,scale),ll_w0(weights)));
        gpu_store_u32(y+4,gpu_f32_mul(gpu_f32_mul(a>>32,scale),ll_w1(weights)));
        gpu_store_u32(y+8,gpu_f32_mul(gpu_f32_mul(b,scale),ll_w0(weights>>32)));
        gpu_store_u32(y+12,gpu_f32_mul(gpu_f32_mul(b>>32,scale),ll_w1(weights>>32)));
        p=p+group*16;w=w+group*8;y=y+group*16;k=k-1;
    }return 0;
}
fn main(){return 78;}
