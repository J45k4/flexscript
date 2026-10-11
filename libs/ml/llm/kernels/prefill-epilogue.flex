// Two FP32 outputs per lane; optional retained SiLU/product and FP16 staging.
// Words: partials, raw output, rows|depth<<32, parts, extra output, op,
//        second product input, optional tiled FP16 destination.
import "common.flex";
fn kernel(index,input,output,count) {
    let rows=gpu_launch_word(2)&4294967295;let depth=gpu_launch_word(2)>>32;let token=gpu_block_y();let col=(gpu_block_x()*128+gpu_thread_x())*2;
    if col>=rows {return 0;}let half=gpu_launch_word(7);let target=half+(token>>3)*rows*16+(col>>3)*128+(token&7)*16+(col&7)*2;
    if token>=depth {if half {gpu_store_u32(target,0);}return 0;}
    let at=(token*rows+col)*4;let p=gpu_launch_word(0)+at;let stride=rows*depth*4;let k=gpu_launch_word(3)>>1;
    let l0=0;let l1=0;let r0=0;let r1=0;
    if !k {let a=gpu_load_u64(p);l0=a&4294967295;l1=a>>32;}
    while k&4294967295 {let a=gpu_load_u64(p);let b=gpu_load_u64(p+stride);
        l0=gpu_f32_add(l0,a);l1=gpu_f32_add(l1,a>>32);r0=gpu_f32_add(r0,b);r1=gpu_f32_add(r1,b>>32);p=p+stride*2;k=k-1;}
    let v0=gpu_f32_add(l0,r0);let v1=gpu_f32_add(l1,r1);gpu_store_u32(gpu_launch_word(1)+at,v0);gpu_store_u32(gpu_launch_word(1)+at+4,v1);
    let op=gpu_launch_word(5);
    if op==3 {v0=gpu_f32_mul(v0,gpu_f32_rcp_approx(gpu_f32_add(1065353216,ll_exp(v0^2147483648))));v1=gpu_f32_mul(v1,gpu_f32_rcp_approx(gpu_f32_add(1065353216,ll_exp(v1^2147483648))));}
    else if op==2 {let other=gpu_load_u64(gpu_launch_word(6)+at);v0=gpu_f32_mul(v0,other);v1=gpu_f32_mul(v1,other>>32);}
    if op {gpu_store_u32(gpu_launch_word(4)+at,v0);gpu_store_u32(gpu_launch_word(4)+at+4,v1);}
    if half {gpu_store_u32(target,gpu_f32x2_to_f16x2(v0|(v1<<32)));}return 0;
}
fn main(){return 78;}
