// RMSNorm with retained FP32 output and tiled FP16 activation staging.
// One 128-thread block per prompt row; words 6/7 are staging pointer/depth.
import "common.flex";
fn kernel(index,input,output,count) {
    let n=(gpu_launch_word(3)&4294967295);let lane=index&127;let row=index>>7;let group=128;let shift=7;
    if row>=gpu_launch_word(7) {let pair=lane;while pair<(n>>1) {let target=gpu_launch_word(6)+(row>>3)*n*16+(pair>>2)*128+(row&7)*16+(pair&3)*4;gpu_store_u32(target,0);pair=pair+128;}return 0;}
    let x=gpu_launch_word(0)+row*n*4+lane*16;let p=x;let remaining=((n>>2)+group-1-lane)>>shift;
    let k=remaining;let sum=0;
    while k {
        let a=gpu_load_u64(p);let b=gpu_load_u64(p+8);
        sum=gpu_f32_fma(a,a,sum);sum=gpu_f32_fma(a>>32,a>>32,sum);
        sum=gpu_f32_fma(b,b,sum);sum=gpu_f32_fma(b>>32,b>>32,sum);p=p+group*16;k=k-1;
    }
    sum=ll_sum(sum);
    {
        if !(lane&31) {gpu_shared_store64((lane>>5)*8,sum);}gpu_shared_barrier();
        sum=gpu_f32_add(gpu_f32_add(gpu_shared_load64(0),gpu_shared_load64(8)),gpu_f32_add(gpu_shared_load64(16),gpu_shared_load64(24)));
    }
    let scale=gpu_f32_rsqrt_approx(gpu_f32_add(gpu_f32_mul(sum,(gpu_launch_word(4)&4294967295)),(gpu_launch_word(5)&4294967295)));
    let w=gpu_launch_word(1)+lane*8;let y=gpu_launch_word(2)+row*n*4+lane*16;p=x;k=remaining;let column=lane*4;
    while k {
        let a=gpu_load_u64(p);let b=gpu_load_u64(p+8);let weights=gpu_load_u64(w);
        let v0=gpu_f32_mul(gpu_f32_mul(a,scale),ll_w0(weights));let v1=gpu_f32_mul(gpu_f32_mul(a>>32,scale),ll_w1(weights));
        let v2=gpu_f32_mul(gpu_f32_mul(b,scale),ll_w0(weights>>32));let v3=gpu_f32_mul(gpu_f32_mul(b>>32,scale),ll_w1(weights>>32));
        gpu_store_u32(y,v0);gpu_store_u32(y+4,v1);gpu_store_u32(y+8,v2);gpu_store_u32(y+12,v3);
        let target=gpu_launch_word(6)+(row>>3)*n*16+(column>>3)*128+(row&7)*16+(column&7)*2;
        gpu_store_u32(target,gpu_f32x2_to_f16x2(v0|(v1<<32)));gpu_store_u32(target+4,gpu_f32x2_to_f16x2(v2|(v3<<32)));column=column+group*4;
        p=p+group*16;w=w+group*8;y=y+group*16;k=k-1;
    }return 0;
}
fn main(){return 78;}
