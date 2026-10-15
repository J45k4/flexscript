// One 64-thread workgroup owns each world throughout the complete rollout.
import "../workgroup.flex";
fn kernel(index,input,output,count) {
    let lane=gpu_thread_x();
    let w=input+gpu_block_x()*gpu_launch_word(0);
    let t=gpu_launch_word(2)+(gpu_block_x()*64+lane)*16384;
    let step=0;
    while step<gpu_launch_word(1) {
        if !ph_step_group(w,t,lane) {
            return 0;
        }
        step=step+1;
    }
    return 0;
}
fn main() {
    return 78;
}
