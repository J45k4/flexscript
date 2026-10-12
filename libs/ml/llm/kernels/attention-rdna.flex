// RDNA fused Q/K normalization, rotary, append and attention.
import "common.flex";
fn ra_head(p,head,shared,retain) {
    let dim=gpu_lane()*2;let offset=head*512+dim*4;
    let x=gpu_load_u64(p)+offset;let w=gpu_load_u64(p+8)+dim*2;
    let a=gpu_load_u64(x);let b=gpu_load_u64(x+256);
    let sum=gpu_f32_fma(a,a,gpu_f32_mul(a>>32,a>>32));sum=gpu_f32_fma(b,b,sum);sum=gpu_f32_fma(b>>32,b>>32,sum);
    let scale=gpu_f32_rsqrt_approx(gpu_f32_add(gpu_f32_mul(ll_sum(sum),1006632960),gpu_load_u64(p+24)));
    let wa=gpu_load_u32(w);let wb=gpu_load_u32(w+128);
    let a0=gpu_f32_mul(gpu_f32_mul(a,scale),ll_w0(wa));let a1=gpu_f32_mul(gpu_f32_mul(a>>32,scale),ll_w1(wa));
    let b0=gpu_f32_mul(gpu_f32_mul(b,scale),ll_w0(wb));let b1=gpu_f32_mul(gpu_f32_mul(b>>32,scale),ll_w1(wb));
    if retain {let norm=gpu_load_u64(p+48)+offset;gpu_store_u32(norm,a0);gpu_store_u32(norm+4,a1);gpu_store_u32(norm+256,b0);gpu_store_u32(norm+260,b1);}
    let position=gpu_load_u64(gpu_load_u64(p+40));let table=gpu_load_u64(p+32)+(position*64+dim)*8;
    let trig0=gpu_load_u64(table);let trig1=gpu_load_u64(table+8);
    a=gpu_f32_sub(gpu_f32_mul(a0,trig0),gpu_f32_mul(b0,trig0>>32));b=gpu_f32_add(gpu_f32_mul(b0,trig0),gpu_f32_mul(a0,trig0>>32));
    let c=gpu_f32_sub(gpu_f32_mul(a1,trig1),gpu_f32_mul(b1,trig1>>32));let d=gpu_f32_add(gpu_f32_mul(b1,trig1),gpu_f32_mul(a1,trig1>>32));
    if retain {let y=gpu_load_u64(p+16)+offset;gpu_store_u32(y,a);gpu_store_u32(y+4,c);gpu_store_u32(y+256,b);gpu_store_u32(y+260,d);}
    gpu_shared_store64(shared+dim*4,a|(c<<32));gpu_shared_store64(shared+dim*4+256,b|(d<<32));
    return 0;
}
fn ra_shared(p) {let bits=gpu_shared_load64(p&~7);if p&4 {return bits>>32;}return bits&4294967295;}
fn kernel(index,input,output,count) {
    let lane=index&31;let warp=(index&511)>>5;let head=index>>9;let metadata=gpu_launch_word(0);let p=metadata+160;
    let shift=gpu_load_u64(p+48)&4294967295;let kvhead=head>>shift;let primary=!(head&((1<<shift)-1));
    let position=gpu_load_u32(gpu_load_u64(p+32));let width=gpu_load_u64(p+40)&4294967295;
    if !warp {
        ra_head(metadata,head,16640,1);ra_head(metadata+64,kvhead,17152,primary);
        if primary {let dim=lane*2;let off=kvhead*512+dim*4;let at=position*width*4+off;let k=gpu_load_u64(metadata+128)+at;let v=gpu_load_u64(metadata+136)+off;let cache=gpu_load_u64(metadata+144)+at;
            let k0=gpu_shared_load64(17152+dim*4);let k1=gpu_shared_load64(17408+dim*4);gpu_store_u32(k,k0);gpu_store_u32(k+4,k0>>32);gpu_store_u32(k+256,k1);gpu_store_u32(k+260,k1>>32);
            let v0=gpu_load_u64(v);let v1=gpu_load_u64(v+256);gpu_store_u32(cache,v0);gpu_store_u32(cache+4,v0>>32);gpu_store_u32(cache+256,v1);gpu_store_u32(cache+260,v1>>32);
        }
    }
    gpu_shared_barrier();
    let q0=ra_shared(16640+lane*4);let q1=ra_shared(16768+lane*4);let q2=ra_shared(16896+lane*4);let q3=ra_shared(17024+lane*4);
    let a0=0;let a1=0;let a2=0;let a3=0;let denom=0;let maximum=4286578688;
    let stride=width*4;
    let offset=(kvhead*128+lane)*4+warp*stride;
    let k=gpu_load_u64(p+8)+offset;let v=gpu_load_u64(p+16)+offset;let row=warp;
    let t=(position+16-warp)>>4;stride=stride*16;while t {
        let k0=0;let k1=0;let k2=0;let k3=0;let source=v;
        if row==position {k0=ra_shared(17152+lane*4);k1=ra_shared(17280+lane*4);k2=ra_shared(17408+lane*4);k3=ra_shared(17536+lane*4);source=gpu_load_u64(metadata+136)+(kvhead*128+lane)*4;}
        else {k0=gpu_load_u32(k);k1=gpu_load_u32(k+128);k2=gpu_load_u32(k+256);k3=gpu_load_u32(k+384);}
        let score=gpu_f32_mul(q0,k0);score=gpu_f32_fma(q1,k1,score);score=gpu_f32_fma(q2,k2,score);score=gpu_f32_fma(q3,k3,score);
        score=gpu_f32_mul(ll_sum(score),1035273459);
        let next=ll_max(maximum,score);let alpha=ll_exp(gpu_f32_sub(maximum,next));let beta=ll_exp(gpu_f32_sub(score,next));
        denom=gpu_f32_fma(denom,alpha,beta);maximum=next;
        a0=gpu_f32_fma(gpu_load_u32(source),beta,gpu_f32_mul(a0,alpha));
        a1=gpu_f32_fma(gpu_load_u32(source+128),beta,gpu_f32_mul(a1,alpha));
        a2=gpu_f32_fma(gpu_load_u32(source+256),beta,gpu_f32_mul(a2,alpha));
        a3=gpu_f32_fma(gpu_load_u32(source+384),beta,gpu_f32_mul(a3,alpha));t=t-1;k=k+stride;v=v+stride;row=row+16;
    }
    let shared=warp*1024+lane*8;
    gpu_shared_store64(shared,a0);gpu_shared_store64(shared+256,a1);gpu_shared_store64(shared+512,a2);gpu_shared_store64(shared+768,a3);
    if !lane {gpu_shared_store64(16384+warp*16,maximum);gpu_shared_store64(16392+warp*16,denom);}gpu_shared_barrier();
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
    let y=gpu_load_u64(p+24)+head*512+(index&127)*4;gpu_store_u32(y,gpu_f32_mul(value,gpu_f32_rcp_approx(denom)));}return 0;
}
fn main(){return 78;}
