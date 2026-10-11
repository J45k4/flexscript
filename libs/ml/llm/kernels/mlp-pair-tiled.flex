// Two BF16 projections share each F32 input load and independent FMA chains.
// Descriptor: gate weights, up weights, input, width, raw gate, SiLU gate, up, product.
// Retain all intermediate outputs for other consumers of the original graph.
import "common.flex";
fn kernel(index,input,output,count) {
    let row=index>>5;let lane=index&31;let n=(gpu_launch_word(3)&4294967295);
    let gate=gpu_launch_word(0)+(row>>4)*n*32+(row&15)*16+(lane>>1)*256+(lane&1)*8;let up=gpu_launch_word(1)+(row>>4)*n*32+(row&15)*16+(lane>>1)*256+(lane&1)*8;
    let x=gpu_launch_word(2)+lane*16;let k=(n+127-lane*4)>>7;let g=0;let u=0;
    while k&4294967295 {
        let gw=gpu_load_u64(gate);let uw=gpu_load_u64(up);let a=gpu_load_u64(x);let b=gpu_load_u64(x+8);
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
        gate=gate+4096;up=up+4096;x=x+512;k=k-1;
    }
    g=ll_sum(g);u=ll_sum(u);
    if !lane {
        let activated=gpu_f32_mul(g,gpu_f32_rcp_approx(gpu_f32_add(1065353216,ll_exp(g^2147483648))));
        gpu_store_u32(gpu_launch_word(4)+row*4,g);gpu_store_u32(gpu_launch_word(5)+row*4,activated);
        gpu_store_u32(gpu_launch_word(6)+row*4,u);gpu_store_u32(gpu_launch_word(7)+row*4,gpu_f32_mul(activated,u));
    }return 0;
}
fn main(){return 78;}
