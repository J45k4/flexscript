// Pack a matrix into contiguous 16-row by 8-column FP16 tiles.
import "common.flex";
fn kernel(index,input,output,count) {
    let n=gpu_launch_word(2)&4294967295;let col=gpu_block_x()*128+gpu_thread_x();let row=gpu_block_y();
    if col>=n>>2 {return 0;}
    let packed=gpu_load_u64(gpu_launch_word(0)+row*n*2+col*8);
    let target=gpu_launch_word(1)+(row>>4)*n*32+(col>>1)*256+(row&15)*16+(col&1)*8;
    gpu_store_u32(target,packed);gpu_store_u32(target+4,packed>>32);return 0;
}
fn main(){return 78;}
