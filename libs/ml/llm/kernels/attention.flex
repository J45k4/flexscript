// Descriptor: Q, retained K, retained V, output, position, KV row width,
// log2(query heads / KV heads). Head width 128. Sixteen warps per query head.
// Each warp computes an online softmax over every sixteenth cache row; shared
// partials are merged with the same stable softmax rescaling rule.
import "common.flex";
fn kernel(index,input,output,count) {
    let lane=index&31;let warp=(index&511)>>5;let head=index>>9;let q=gpu_launch_word(0)+head*512+lane*4;
    let q0=gpu_load_u32(q);let q1=gpu_load_u32(q+128);let q2=gpu_load_u32(q+256);let q3=gpu_load_u32(q+384);
    let a0=0;let a1=0;let a2=0;let a3=0;let denom=0;let maximum=4286578688;
    let position=gpu_load_u32(gpu_launch_word(4));let stride=(gpu_launch_word(5)&4294967295)*4;
    let offset=((head>>(gpu_launch_word(6)&4294967295))*128+lane)*4+warp*stride;
    let k=gpu_launch_word(1)+offset;let v=gpu_launch_word(2)+offset;
    let t=(position+16-warp)>>4;stride=stride*16;while t {
        let score=gpu_f32_mul(q0,gpu_load_u32(k));
        score=gpu_f32_fma(q1,gpu_load_u32(k+128),score);
        score=gpu_f32_fma(q2,gpu_load_u32(k+256),score);
        score=gpu_f32_fma(q3,gpu_load_u32(k+384),score);
        score=gpu_f32_mul(ll_sum(score),1035273459);
        let next=ll_max(maximum,score);let alpha=ll_exp(gpu_f32_sub(maximum,next));let beta=ll_exp(gpu_f32_sub(score,next));
        denom=gpu_f32_fma(denom,alpha,beta);maximum=next;
        a0=gpu_f32_fma(gpu_load_u32(v),beta,gpu_f32_mul(a0,alpha));
        a1=gpu_f32_fma(gpu_load_u32(v+128),beta,gpu_f32_mul(a1,alpha));
        a2=gpu_f32_fma(gpu_load_u32(v+256),beta,gpu_f32_mul(a2,alpha));
        a3=gpu_f32_fma(gpu_load_u32(v+384),beta,gpu_f32_mul(a3,alpha));t=t-1;k=k+stride;v=v+stride;
    }
    let shared=warp*1024+lane*8;
    gpu_shared_store64(shared,a0);gpu_shared_store64(shared+256,a1);gpu_shared_store64(shared+512,a2);gpu_shared_store64(shared+768,a3);
    if !lane {gpu_shared_store64(16384+warp*16,maximum);gpu_shared_store64(16392+warp*16,denom);}gpu_barrier();
    if (index&511)<128 {
    maximum=4286578688;
    maximum=ll_max(maximum,gpu_shared_load64(16384));
    maximum=ll_max(maximum,gpu_shared_load64(16400));
    maximum=ll_max(maximum,gpu_shared_load64(16416));
    maximum=ll_max(maximum,gpu_shared_load64(16432));
    maximum=ll_max(maximum,gpu_shared_load64(16448));
    maximum=ll_max(maximum,gpu_shared_load64(16464));
    maximum=ll_max(maximum,gpu_shared_load64(16480));
    maximum=ll_max(maximum,gpu_shared_load64(16496));
    maximum=ll_max(maximum,gpu_shared_load64(16512));
    maximum=ll_max(maximum,gpu_shared_load64(16528));
    maximum=ll_max(maximum,gpu_shared_load64(16544));
    maximum=ll_max(maximum,gpu_shared_load64(16560));
    maximum=ll_max(maximum,gpu_shared_load64(16576));
    maximum=ll_max(maximum,gpu_shared_load64(16592));
    maximum=ll_max(maximum,gpu_shared_load64(16608));
    maximum=ll_max(maximum,gpu_shared_load64(16624));
    shared=(index&127)*8;let value=0;denom=0;
    let scale0=ll_exp(gpu_f32_sub(gpu_shared_load64(16384),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16392),scale0,denom);value=gpu_f32_fma(gpu_shared_load64(shared+0),scale0,value);
    let scale1=ll_exp(gpu_f32_sub(gpu_shared_load64(16400),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16408),scale1,denom);value=gpu_f32_fma(gpu_shared_load64(shared+1024),scale1,value);
    let scale2=ll_exp(gpu_f32_sub(gpu_shared_load64(16416),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16424),scale2,denom);value=gpu_f32_fma(gpu_shared_load64(shared+2048),scale2,value);
    let scale3=ll_exp(gpu_f32_sub(gpu_shared_load64(16432),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16440),scale3,denom);value=gpu_f32_fma(gpu_shared_load64(shared+3072),scale3,value);
    let scale4=ll_exp(gpu_f32_sub(gpu_shared_load64(16448),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16456),scale4,denom);value=gpu_f32_fma(gpu_shared_load64(shared+4096),scale4,value);
    let scale5=ll_exp(gpu_f32_sub(gpu_shared_load64(16464),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16472),scale5,denom);value=gpu_f32_fma(gpu_shared_load64(shared+5120),scale5,value);
    let scale6=ll_exp(gpu_f32_sub(gpu_shared_load64(16480),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16488),scale6,denom);value=gpu_f32_fma(gpu_shared_load64(shared+6144),scale6,value);
    let scale7=ll_exp(gpu_f32_sub(gpu_shared_load64(16496),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16504),scale7,denom);value=gpu_f32_fma(gpu_shared_load64(shared+7168),scale7,value);
    let scale8=ll_exp(gpu_f32_sub(gpu_shared_load64(16512),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16520),scale8,denom);value=gpu_f32_fma(gpu_shared_load64(shared+8192),scale8,value);
    let scale9=ll_exp(gpu_f32_sub(gpu_shared_load64(16528),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16536),scale9,denom);value=gpu_f32_fma(gpu_shared_load64(shared+9216),scale9,value);
    let scale10=ll_exp(gpu_f32_sub(gpu_shared_load64(16544),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16552),scale10,denom);value=gpu_f32_fma(gpu_shared_load64(shared+10240),scale10,value);
    let scale11=ll_exp(gpu_f32_sub(gpu_shared_load64(16560),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16568),scale11,denom);value=gpu_f32_fma(gpu_shared_load64(shared+11264),scale11,value);
    let scale12=ll_exp(gpu_f32_sub(gpu_shared_load64(16576),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16584),scale12,denom);value=gpu_f32_fma(gpu_shared_load64(shared+12288),scale12,value);
    let scale13=ll_exp(gpu_f32_sub(gpu_shared_load64(16592),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16600),scale13,denom);value=gpu_f32_fma(gpu_shared_load64(shared+13312),scale13,value);
    let scale14=ll_exp(gpu_f32_sub(gpu_shared_load64(16608),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16616),scale14,denom);value=gpu_f32_fma(gpu_shared_load64(shared+14336),scale14,value);
    let scale15=ll_exp(gpu_f32_sub(gpu_shared_load64(16624),maximum));
    denom=gpu_f32_fma(gpu_shared_load64(16632),scale15,denom);value=gpu_f32_fma(gpu_shared_load64(shared+15360),scale15,value);
    let y=gpu_launch_word(3)+head*512+(index&127)*4;gpu_store_u32(y,gpu_f32_mul(value,gpu_f32_rcp_approx(denom)));}return 0;
}
fn main(){return 78;}
