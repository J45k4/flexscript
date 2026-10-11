// One warp per query head and token. Stable causal online softmax; FP32 KV.
import "common.flex";
fn kernel(index,input,output,count) {
    let lane=index&31;let heads=gpu_launch_word(4)>>7;let token=gpu_block_y();let head=gpu_block_x()*4+(gpu_thread_x()>>5);if head>=heads {return 0;}
    let q=gpu_launch_word(0)+(token*gpu_launch_word(4)+head*128+lane)*4;
    let q0=gpu_load_u32(q);let q1=gpu_load_u32(q+128);let q2=gpu_load_u32(q+256);let q3=gpu_load_u32(q+384);
    let a0=0;let a1=0;let a2=0;let a3=0;let denom=0;let maximum=4286578688;let stride=gpu_launch_word(5)*4;
    let offset=((head>>gpu_launch_word(6))*128+lane)*4;let k=gpu_launch_word(1)+offset;let v=gpu_launch_word(2)+offset;let t=token+1;
    while t&4294967295 {
        let score=gpu_f32_mul(q0,gpu_load_u32(k));score=gpu_f32_fma(q1,gpu_load_u32(k+128),score);score=gpu_f32_fma(q2,gpu_load_u32(k+256),score);score=gpu_f32_fma(q3,gpu_load_u32(k+384),score);score=gpu_f32_mul(ll_sum(score),1035273459);
        let next=ll_max(maximum,score);let alpha=ll_exp(gpu_f32_sub(maximum,next));let beta=ll_exp(gpu_f32_sub(score,next));denom=gpu_f32_fma(denom,alpha,beta);maximum=next;
        a0=gpu_f32_fma(gpu_load_u32(v),beta,gpu_f32_mul(a0,alpha));a1=gpu_f32_fma(gpu_load_u32(v+128),beta,gpu_f32_mul(a1,alpha));
        a2=gpu_f32_fma(gpu_load_u32(v+256),beta,gpu_f32_mul(a2,alpha));a3=gpu_f32_fma(gpu_load_u32(v+384),beta,gpu_f32_mul(a3,alpha));t=t-1;k=k+stride;v=v+stride;
    }
    let y=gpu_launch_word(3)+(token*gpu_launch_word(4)+head*128+lane)*4;let scale=gpu_f32_rcp_approx(denom);
    gpu_store_u32(y,gpu_f32_mul(a0,scale));gpu_store_u32(y+128,gpu_f32_mul(a1,scale));gpu_store_u32(y+256,gpu_f32_mul(a2,scale));gpu_store_u32(y+384,gpu_f32_mul(a3,scale));return 0;
}
fn main(){return 78;}
