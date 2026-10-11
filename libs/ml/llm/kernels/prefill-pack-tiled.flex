// FP16 activation tiles: eight prompt rows by eight inner elements.
import "common.flex";
fn kernel(index,input,output,count) {
    let pair=gpu_block_x()*128+gpu_thread_x();let token=gpu_block_y();let width=gpu_launch_word(3)&4294967295;
    if pair>=width>>1 {return 0;}
    let value=0;if token<gpu_launch_word(4) {value=gpu_f32x2_to_f16x2(gpu_load_u64(gpu_launch_word(0)+token*width*4+pair*8));}
    let target=gpu_launch_word(1)+(token>>3)*width*16+(pair>>2)*128+(token&7)*16+(pair&3)*4;
    gpu_store_u32(target,value);return 0;
}
fn main(){return 78;}
