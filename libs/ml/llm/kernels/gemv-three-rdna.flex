// AMD packed projections with eight contiguous weights per lane.
import "common.flex";
fn narrow(index,input,output,count) {
    let row=index>>5;let lane=index&31;let n=(gpu_launch_word(7)&4294967295);
    let w=gpu_launch_word(1);let y=gpu_launch_word(4);
    if row>=input {row=row-input;w=gpu_launch_word(2);y=gpu_launch_word(5);
        if row>=output {row=row-output;w=gpu_launch_word(3);y=gpu_launch_word(6);}}
    w=w+row*n*2+lane*8;let x=gpu_launch_word(0)+lane*16;
    let k=(n+127-lane*4)>>7;let acc=0;
    while k&4294967294 {
        let packed=gpu_load_stream_u64(w);let a=gpu_load_u64(x);let b=gpu_load_u64(x+8);
        let packed2=gpu_load_stream_u64(w+256);let c=gpu_load_u64(x+512);let d=gpu_load_u64(x+520);
        acc=gpu_f32_fma(ll_w0(packed),a,acc);acc=gpu_f32_fma(ll_w1(packed),a>>32,acc);
        acc=gpu_f32_fma(ll_w0(packed>>32),b,acc);acc=gpu_f32_fma(ll_w1(packed>>32),b>>32,acc);
        acc=gpu_f32_fma(ll_w0(packed2),c,acc);acc=gpu_f32_fma(ll_w1(packed2),c>>32,acc);
        acc=gpu_f32_fma(ll_w0(packed2>>32),d,acc);acc=gpu_f32_fma(ll_w1(packed2>>32),d>>32,acc);
        w=w+512;x=x+1024;k=k-2;
    }
    if k&1 {
        let packed=gpu_load_stream_u64(w);let a=gpu_load_u64(x);let b=gpu_load_u64(x+8);
        acc=gpu_f32_fma(ll_w0(packed),a,acc);
        acc=gpu_f32_fma(ll_w1(packed),a>>32,acc);
        acc=gpu_f32_fma(ll_w0(packed>>32),b,acc);
        acc=gpu_f32_fma(ll_w1(packed>>32),b>>32,acc);
    }
    acc=ll_sum(acc);if !lane {gpu_store_u32(y+row*4,acc);}return 0;
}
fn kernel(index,input,output,count) {
    let n=gpu_launch_word(7)&4294967295;if n&7 {return narrow(index,input,output,count);}
    let row=index>>5;let lane=index&31;let w=gpu_launch_word(1);let y=gpu_launch_word(4);if row>=input {row=row-input;w=gpu_launch_word(2);y=gpu_launch_word(5);if row>=output {row=row-output;w=gpu_launch_word(3);y=gpu_launch_word(6);}}
    w=w+row*n*2+lane*16;let x=gpu_launch_word(0)+lane*32;let k=(n+255-lane*8)>>8;let acc0=0;let acc1=0;
    while k&4294967295 {
        let p=gpu_load_stream_u64(w);let q=gpu_load_stream_u64(w+8);let a=gpu_load_u64(x);let b=gpu_load_u64(x+8);let c=gpu_load_u64(x+16);let d=gpu_load_u64(x+24);
        acc0=gpu_f32_fma(ll_w0(p),a,acc0);acc1=gpu_f32_fma(ll_w1(p),a>>32,acc1);
        acc0=gpu_f32_fma(ll_w0(p>>32),b,acc0);acc1=gpu_f32_fma(ll_w1(p>>32),b>>32,acc1);
        acc0=gpu_f32_fma(ll_w0(q),c,acc0);acc1=gpu_f32_fma(ll_w1(q),c>>32,acc1);
        acc0=gpu_f32_fma(ll_w0(q>>32),d,acc0);acc1=gpu_f32_fma(ll_w1(q>>32),d>>32,acc1);
        w=w+512;x=x+1024;k=k-1;
    }
    let acc=ll_sum(gpu_f32_add(acc0,acc1));if !lane {gpu_store_u32(y+row*4,acc);}return 0;
}
fn main(){return 78;}
