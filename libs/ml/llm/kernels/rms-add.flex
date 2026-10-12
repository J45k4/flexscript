// Add a residual and normalize each row without a separate pointwise launch.
// Descriptor: a, b, normalized output, width, inverse width, epsilon, BF16 scales,
// residual output. Retain the residual for all other graph consumers.
import "common.flex";
fn kernel(index,input,output,count) {
    let n=(gpu_launch_word(3)&4294967295);let lane=index&127;let row=index>>7;let offset=row*n*4+lane*16;
    let a=gpu_launch_word(0)+offset;let b=gpu_launch_word(1)+offset;let residual=gpu_launch_word(7)+offset;
    let k=((n>>2)+127-lane)>>7;let sum=0;
    while k {
        let av=gpu_load_u64(a);let ah=gpu_load_u64(a+8);let bv=gpu_load_u64(b);let bh=gpu_load_u64(b+8);
        let v0=gpu_f32_add(av,bv);let v1=gpu_f32_add(av>>32,bv>>32);let v2=gpu_f32_add(ah,bh);let v3=gpu_f32_add(ah>>32,bh>>32);
        sum=gpu_f32_fma(v0,v0,sum);sum=gpu_f32_fma(v1,v1,sum);sum=gpu_f32_fma(v2,v2,sum);sum=gpu_f32_fma(v3,v3,sum);
        gpu_store_u32(residual,v0);gpu_store_u32(residual+4,v1);gpu_store_u32(residual+8,v2);gpu_store_u32(residual+12,v3);
        a=a+2048;b=b+2048;residual=residual+2048;k=k-1;
    }
    sum=ll_sum(sum);if !(lane&31) {gpu_shared_store64((lane>>5)*8,sum);}gpu_shared_barrier();
    sum=gpu_f32_add(gpu_f32_add(gpu_shared_load64(0),gpu_shared_load64(8)),gpu_f32_add(gpu_shared_load64(16),gpu_shared_load64(24)));
    let scale=gpu_f32_rsqrt_approx(gpu_f32_add(gpu_f32_mul(sum,(gpu_launch_word(4)&4294967295)),(gpu_launch_word(5)&4294967295)));
    let w=gpu_launch_word(6)+lane*8;let y=gpu_launch_word(2)+offset;residual=gpu_launch_word(7)+offset;k=((n>>2)+127-lane)>>7;
    while k {
        let av=gpu_load_u64(residual);let ah=gpu_load_u64(residual+8);let weights=gpu_load_u64(w);
        gpu_store_u32(y,gpu_f32_mul(gpu_f32_mul(av,scale),ll_w0(weights)));gpu_store_u32(y+4,gpu_f32_mul(gpu_f32_mul(av>>32,scale),ll_w1(weights)));
        gpu_store_u32(y+8,gpu_f32_mul(gpu_f32_mul(ah,scale),ll_w0(weights>>32)));gpu_store_u32(y+12,gpu_f32_mul(gpu_f32_mul(ah>>32,scale),ll_w1(weights>>32)));
        residual=residual+2048;w=w+1024;y=y+2048;k=k-1;
    }return 0;
}
fn main(){return 78;}
