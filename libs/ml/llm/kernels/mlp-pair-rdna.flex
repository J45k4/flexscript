// AMD contiguous eight-weight loads and independent accumulation chains.
import "common.flex";
fn narrow(index,input,output,count) {
    let row=index>>5;let lane=index&31;let n=(gpu_launch_word(3)&4294967295);
    let gate=gpu_launch_word(0)+row*n*2+lane*8;let up=gpu_launch_word(1)+row*n*2+lane*8;
    let x=gpu_launch_word(2)+lane*16;let k=(n+127-lane*4)>>7;let g=0;let u=0;
    while k&4294967295 {
        let gw=gpu_load_stream_u64(gate);let uw=gpu_load_stream_u64(up);let a=gpu_load_u64(x);let b=gpu_load_u64(x+8);
        let gw0=ll_w0(gw);
        let gw1=ll_w1(gw);
        let gw2=ll_w0(gw>>32);
        let gw3=ll_w1(gw>>32);
        let uw0=ll_w0(uw);
        let uw1=ll_w1(uw);
        let uw2=ll_w0(uw>>32);
        let uw3=ll_w1(uw>>32);
        g=gpu_f32_fma(gw0,a,g);u=gpu_f32_fma(uw0,a,u);
        g=gpu_f32_fma(gw1,a>>32,g);u=gpu_f32_fma(uw1,a>>32,u);
        g=gpu_f32_fma(gw2,b,g);u=gpu_f32_fma(uw2,b,u);
        g=gpu_f32_fma(gw3,b>>32,g);u=gpu_f32_fma(uw3,b>>32,u);
        gate=gate+256;up=up+256;x=x+512;k=k-1;
    }
    g=ll_sum(g);u=ll_sum(u);
    if !lane {
        let activated=gpu_f32_mul(g,gpu_f32_rcp_approx(gpu_f32_add(1065353216,ll_exp(g^2147483648))));
        gpu_store_u32(gpu_launch_word(4)+row*4,g);gpu_store_u32(gpu_launch_word(5)+row*4,activated);
        gpu_store_u32(gpu_launch_word(6)+row*4,u);gpu_store_u32(gpu_launch_word(7)+row*4,gpu_f32_mul(activated,u));
    }return 0;
}
fn kernel(index,input,output,count) {
    let n=gpu_launch_word(3)&4294967295;if n&7 {return narrow(index,input,output,count);}
    let row=index>>5;let lane=index&31;let gate=gpu_launch_word(0)+row*n*2+lane*16;let up=gpu_launch_word(1)+row*n*2+lane*16;let x=gpu_launch_word(2)+lane*32;let k=(n+255-lane*8)>>8;let g0=0;let g1=0;let u0=0;let u1=0;
    while k&4294967295 {
        let gp=gpu_load_stream_u64(gate);let gq=gpu_load_stream_u64(gate+8);let up0=gpu_load_stream_u64(up);let uq=gpu_load_stream_u64(up+8);let a=gpu_load_u64(x);let b=gpu_load_u64(x+8);let c=gpu_load_u64(x+16);let d=gpu_load_u64(x+24);
        g0=gpu_f32_fma(ll_w0(gp),a,g0);u0=gpu_f32_fma(ll_w0(up0),a,u0);g1=gpu_f32_fma(ll_w1(gp),a>>32,g1);u1=gpu_f32_fma(ll_w1(up0),a>>32,u1);
        g0=gpu_f32_fma(ll_w0(gp>>32),b,g0);u0=gpu_f32_fma(ll_w0(up0>>32),b,u0);g1=gpu_f32_fma(ll_w1(gp>>32),b>>32,g1);u1=gpu_f32_fma(ll_w1(up0>>32),b>>32,u1);
        g0=gpu_f32_fma(ll_w0(gq),c,g0);u0=gpu_f32_fma(ll_w0(uq),c,u0);g1=gpu_f32_fma(ll_w1(gq),c>>32,g1);u1=gpu_f32_fma(ll_w1(uq),c>>32,u1);
        g0=gpu_f32_fma(ll_w0(gq>>32),d,g0);u0=gpu_f32_fma(ll_w0(uq>>32),d,u0);g1=gpu_f32_fma(ll_w1(gq>>32),d>>32,g1);u1=gpu_f32_fma(ll_w1(uq>>32),d>>32,u1);
        gate=gate+512;up=up+512;x=x+1024;k=k-1;
    }
    let g=ll_sum(gpu_f32_add(g0,g1));let u=ll_sum(gpu_f32_add(u0,u1));if !lane {
        let activated=gpu_f32_mul(g,gpu_f32_rcp_approx(gpu_f32_add(1065353216,ll_exp(g^2147483648))));gpu_store_u32(gpu_launch_word(4)+row*4,g);gpu_store_u32(gpu_launch_word(5)+row*4,activated);gpu_store_u32(gpu_launch_word(6)+row*4,u);gpu_store_u32(gpu_launch_word(7)+row*4,gpu_f32_mul(activated,u));
    }return 0;
}
fn main(){return 78;}
