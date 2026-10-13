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
        // Issue independent cache-row reads together before consuming them.
        let k0=gpu_load_u32(k);let k1=gpu_load_u32(k+128);let k2=gpu_load_u32(k+256);let k3=gpu_load_u32(k+384);
        let v0=gpu_load_u32(v);let v1=gpu_load_u32(v+128);let v2=gpu_load_u32(v+256);let v3=gpu_load_u32(v+384);
        let score=gpu_f32_mul(q0,k0);
        score=gpu_f32_fma(q1,k1,score);
        score=gpu_f32_fma(q2,k2,score);
        score=gpu_f32_fma(q3,k3,score);
        score=gpu_f32_mul(ll_sum(score),1035273459);
        let next=ll_max(maximum,score);let alpha=ll_exp(gpu_f32_sub(maximum,next));let beta=ll_exp(gpu_f32_sub(score,next));
        denom=gpu_f32_fma(denom,alpha,beta);maximum=next;
        a0=gpu_f32_fma(v0,beta,gpu_f32_mul(a0,alpha));
        a1=gpu_f32_fma(v1,beta,gpu_f32_mul(a1,alpha));
        a2=gpu_f32_fma(v2,beta,gpu_f32_mul(a2,alpha));
        a3=gpu_f32_fma(v3,beta,gpu_f32_mul(a3,alpha));t=t-1;k=k+stride;v=v+stride;
    }
    let shared=warp*1024+lane*8;
    gpu_shared_store64(shared,a0);gpu_shared_store64(shared+256,a1);gpu_shared_store64(shared+512,a2);gpu_shared_store64(shared+768,a3);
    if !lane {gpu_shared_store64(16384+warp*16,maximum);gpu_shared_store64(16392+warp*16,denom);}gpu_shared_barrier();
    if (index&511)<128 {
    maximum=4286578688;
    // Batch independent LDS reads while preserving ordinal max reduction.
    let m0=gpu_shared_load64(16384);
    let m1=gpu_shared_load64(16400);
    let m2=gpu_shared_load64(16416);
    let m3=gpu_shared_load64(16432);
    maximum=ll_max(maximum,m0);
    maximum=ll_max(maximum,m1);
    maximum=ll_max(maximum,m2);
    maximum=ll_max(maximum,m3);
    let m4=gpu_shared_load64(16448);
    let m5=gpu_shared_load64(16464);
    let m6=gpu_shared_load64(16480);
    let m7=gpu_shared_load64(16496);
    maximum=ll_max(maximum,m4);
    maximum=ll_max(maximum,m5);
    maximum=ll_max(maximum,m6);
    maximum=ll_max(maximum,m7);
    let m8=gpu_shared_load64(16512);
    let m9=gpu_shared_load64(16528);
    let m10=gpu_shared_load64(16544);
    let m11=gpu_shared_load64(16560);
    maximum=ll_max(maximum,m8);
    maximum=ll_max(maximum,m9);
    maximum=ll_max(maximum,m10);
    maximum=ll_max(maximum,m11);
    let m12=gpu_shared_load64(16576);
    let m13=gpu_shared_load64(16592);
    let m14=gpu_shared_load64(16608);
    let m15=gpu_shared_load64(16624);
    maximum=ll_max(maximum,m12);
    maximum=ll_max(maximum,m13);
    maximum=ll_max(maximum,m14);
    maximum=ll_max(maximum,m15);
    shared=(index&127)*8;let value=0;denom=0;
    let partial_max0=gpu_shared_load64(16384);let partial_denom0=gpu_shared_load64(16392);let partial_value0=gpu_shared_load64(shared+0);
    let scale0=ll_exp(gpu_f32_sub(partial_max0,maximum));
    denom=gpu_f32_fma(partial_denom0,scale0,denom);value=gpu_f32_fma(partial_value0,scale0,value);
    let partial_max1=gpu_shared_load64(16400);let partial_denom1=gpu_shared_load64(16408);let partial_value1=gpu_shared_load64(shared+1024);
    let scale1=ll_exp(gpu_f32_sub(partial_max1,maximum));
    denom=gpu_f32_fma(partial_denom1,scale1,denom);value=gpu_f32_fma(partial_value1,scale1,value);
    let partial_max2=gpu_shared_load64(16416);let partial_denom2=gpu_shared_load64(16424);let partial_value2=gpu_shared_load64(shared+2048);
    let scale2=ll_exp(gpu_f32_sub(partial_max2,maximum));
    denom=gpu_f32_fma(partial_denom2,scale2,denom);value=gpu_f32_fma(partial_value2,scale2,value);
    let partial_max3=gpu_shared_load64(16432);let partial_denom3=gpu_shared_load64(16440);let partial_value3=gpu_shared_load64(shared+3072);
    let scale3=ll_exp(gpu_f32_sub(partial_max3,maximum));
    denom=gpu_f32_fma(partial_denom3,scale3,denom);value=gpu_f32_fma(partial_value3,scale3,value);
    let partial_max4=gpu_shared_load64(16448);let partial_denom4=gpu_shared_load64(16456);let partial_value4=gpu_shared_load64(shared+4096);
    let scale4=ll_exp(gpu_f32_sub(partial_max4,maximum));
    denom=gpu_f32_fma(partial_denom4,scale4,denom);value=gpu_f32_fma(partial_value4,scale4,value);
    let partial_max5=gpu_shared_load64(16464);let partial_denom5=gpu_shared_load64(16472);let partial_value5=gpu_shared_load64(shared+5120);
    let scale5=ll_exp(gpu_f32_sub(partial_max5,maximum));
    denom=gpu_f32_fma(partial_denom5,scale5,denom);value=gpu_f32_fma(partial_value5,scale5,value);
    let partial_max6=gpu_shared_load64(16480);let partial_denom6=gpu_shared_load64(16488);let partial_value6=gpu_shared_load64(shared+6144);
    let scale6=ll_exp(gpu_f32_sub(partial_max6,maximum));
    denom=gpu_f32_fma(partial_denom6,scale6,denom);value=gpu_f32_fma(partial_value6,scale6,value);
    let partial_max7=gpu_shared_load64(16496);let partial_denom7=gpu_shared_load64(16504);let partial_value7=gpu_shared_load64(shared+7168);
    let scale7=ll_exp(gpu_f32_sub(partial_max7,maximum));
    denom=gpu_f32_fma(partial_denom7,scale7,denom);value=gpu_f32_fma(partial_value7,scale7,value);
    let partial_max8=gpu_shared_load64(16512);let partial_denom8=gpu_shared_load64(16520);let partial_value8=gpu_shared_load64(shared+8192);
    let scale8=ll_exp(gpu_f32_sub(partial_max8,maximum));
    denom=gpu_f32_fma(partial_denom8,scale8,denom);value=gpu_f32_fma(partial_value8,scale8,value);
    let partial_max9=gpu_shared_load64(16528);let partial_denom9=gpu_shared_load64(16536);let partial_value9=gpu_shared_load64(shared+9216);
    let scale9=ll_exp(gpu_f32_sub(partial_max9,maximum));
    denom=gpu_f32_fma(partial_denom9,scale9,denom);value=gpu_f32_fma(partial_value9,scale9,value);
    let partial_max10=gpu_shared_load64(16544);let partial_denom10=gpu_shared_load64(16552);let partial_value10=gpu_shared_load64(shared+10240);
    let scale10=ll_exp(gpu_f32_sub(partial_max10,maximum));
    denom=gpu_f32_fma(partial_denom10,scale10,denom);value=gpu_f32_fma(partial_value10,scale10,value);
    let partial_max11=gpu_shared_load64(16560);let partial_denom11=gpu_shared_load64(16568);let partial_value11=gpu_shared_load64(shared+11264);
    let scale11=ll_exp(gpu_f32_sub(partial_max11,maximum));
    denom=gpu_f32_fma(partial_denom11,scale11,denom);value=gpu_f32_fma(partial_value11,scale11,value);
    let partial_max12=gpu_shared_load64(16576);let partial_denom12=gpu_shared_load64(16584);let partial_value12=gpu_shared_load64(shared+12288);
    let scale12=ll_exp(gpu_f32_sub(partial_max12,maximum));
    denom=gpu_f32_fma(partial_denom12,scale12,denom);value=gpu_f32_fma(partial_value12,scale12,value);
    let partial_max13=gpu_shared_load64(16592);let partial_denom13=gpu_shared_load64(16600);let partial_value13=gpu_shared_load64(shared+13312);
    let scale13=ll_exp(gpu_f32_sub(partial_max13,maximum));
    denom=gpu_f32_fma(partial_denom13,scale13,denom);value=gpu_f32_fma(partial_value13,scale13,value);
    let partial_max14=gpu_shared_load64(16608);let partial_denom14=gpu_shared_load64(16616);let partial_value14=gpu_shared_load64(shared+14336);
    let scale14=ll_exp(gpu_f32_sub(partial_max14,maximum));
    denom=gpu_f32_fma(partial_denom14,scale14,denom);value=gpu_f32_fma(partial_value14,scale14,value);
    let partial_max15=gpu_shared_load64(16624);let partial_denom15=gpu_shared_load64(16632);let partial_value15=gpu_shared_load64(shared+15360);
    let scale15=ll_exp(gpu_f32_sub(partial_max15,maximum));
    denom=gpu_f32_fma(partial_denom15,scale15,denom);value=gpu_f32_fma(partial_value15,scale15,value);
    let y=gpu_launch_word(3)+head*512+(index&127)*4;gpu_store_u32(y,gpu_f32_mul(value,gpu_f32_rcp_approx(denom)));}return 0;
}
fn main(){return 78;}
