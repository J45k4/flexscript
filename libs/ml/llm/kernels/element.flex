// Descriptor: a,b,out,operation,state,width. Operations: add,mul,SiLU,
// embedding gather (BF16 -> F32), append one F32 row to a retained KV cache.
import "common.flex";
fn kernel(index,input,output,count) {
    let a=gpu_launch_word(0);let b=gpu_launch_word(1);let y=gpu_launch_word(2)+index*4;
    let op=gpu_launch_word(3);let v=0;
    if op==4 {v=ll_weight(a+(gpu_load_u64(b+8)*gpu_launch_word(5)+index)*2);}
    else {
        v=gpu_load_u32(a+index*4);
        if op==1 {v=gpu_f32_add(v,gpu_load_u32(b+index*4));}
        else if op==2 {v=gpu_f32_mul(v,gpu_load_u32(b+index*4));}
        else if op==3 {v=gpu_f32_mul(v,gpu_f32_rcp_approx(gpu_f32_add(1065353216,ll_exp(v^2147483648))));}
        else if op==5 {y=y+gpu_load_u64(gpu_launch_word(4))*gpu_launch_word(5)*4;}
    }
    gpu_store_u32(y,v);return 0;
}
fn main(){return 78;}
