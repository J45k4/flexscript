// Four adjacent BF16 weights per lane, loaded as one aligned 64-bit word.
// The lowering selects this kernel only for inner dimensions divisible by four.
import "common.flex";
fn kernel(index,input,output,count) {
    let row=index>>5;let lane=index&31;let n=(gpu_launch_word(3)&4294967295);
    let w=gpu_launch_word(0)+(row>>4)*n*32+(row&15)*16+(lane>>1)*256+(lane&1)*8;
    let x=gpu_launch_word(1)+lane*16;let k=(n+127-lane*4)>>7;let acc=0;
    while k&4294967294 {
        let packed=gpu_load_u64(w);let a=gpu_load_u64(x);let b=gpu_load_u64(x+8);
        let packed2=gpu_load_u64(w+4096);let c=gpu_load_u64(x+512);let d=gpu_load_u64(x+520);
        acc=gpu_f32_fma(ll_w0(packed),a,acc);acc=gpu_f32_fma(ll_w1(packed),a>>32,acc);
        acc=gpu_f32_fma(ll_w0(packed>>32),b,acc);acc=gpu_f32_fma(ll_w1(packed>>32),b>>32,acc);
        acc=gpu_f32_fma(ll_w0(packed2),c,acc);acc=gpu_f32_fma(ll_w1(packed2),c>>32,acc);
        acc=gpu_f32_fma(ll_w0(packed2>>32),d,acc);acc=gpu_f32_fma(ll_w1(packed2>>32),d>>32,acc);
        w=w+8192;x=x+1024;k=k-2;
    }
    if k&1 {
        let packed=gpu_load_u64(w);let a=gpu_load_u64(x);let b=gpu_load_u64(x+8);
        acc=gpu_f32_fma(ll_w0(packed),a,acc);
        acc=gpu_f32_fma(ll_w1(packed),a>>32,acc);
        acc=gpu_f32_fma(ll_w0(packed>>32),b,acc);
        acc=gpu_f32_fma(ll_w1(packed>>32),b>>32,acc);
    }
    acc=ll_sum(acc);if !lane {gpu_store_u32(gpu_launch_word(2)+row*4,acc);}return 0;
}
fn main(){return 78;}
