// Two-stage greedy sampling. Preserve the lowest token ID on score ties and
// propagate a nonfinite-logit sentinel; only the final eight bytes reach CPU.
import "common.flex";
fn am_choose(a,b) {
    let ak=(a>>32)&4294967295;let bk=(b>>32)&4294967295;
    if bk>ak || (bk==ak && (b&4294967295)>(a&4294967295)) {return b;}return a;
}
fn kernel(index,input,output,count) {
    let lane=gpu_thread_x();let begin=gpu_block_x()*1024;let end=begin+1024;
    let n=gpu_launch_word(2)&4294967295;if end>n || gpu_launch_word(3) {end=n;}let at=begin+lane;let best=0;
    while at<end {
        let value=0;
        if gpu_launch_word(3) {value=gpu_load_u64(gpu_launch_word(0)+at*8);}
        else {
            let bits=gpu_load_u32(gpu_launch_word(0)+at*4);let key=bits^2147483648;let id=at;
            if bits&2147483648 {key=(~bits)&4294967295;}
            if (bits&2147483647)>=2139095040 {key=4294967295;id=4294967295;}
            value=(key<<32)|(4294967295-id);
        }
        best=am_choose(best,value);at=at+128;
    }
    let delta=16;while delta {best=am_choose(best,gpu_shuffle(best,(lane&31)^delta,4294967295));delta=delta>>1;}
    if !(lane&31) {gpu_shared_store64((lane>>5)*8,best);}gpu_barrier();
    if lane<32 {
        best=gpu_shared_load64((lane&3)*8);delta=2;
        while delta {best=am_choose(best,gpu_shuffle(best,lane^delta,4294967295));delta=delta>>1;}
        if !lane {store64(gpu_launch_word(1)+gpu_block_x()*8,best);}
    }
    return 0;
}
fn main(){return 78;}
