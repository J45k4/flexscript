// RDNA4: two 16x16x16 WMMA tiles per wave, retaining the 16-row/24-token
// launch layout and split-K partial-output contract of the portable prefill.
import "common.flex";
fn rw_half(p) {let a=gpu_load_u64(p);return ll_half_pair(a)|(ll_half_pair(a>>32)<<32);}
fn rw_weight(row,k,width,tiled) {
    if tiled {return gpu_launch_word(0)+(row>>4)*width*32+(k>>3)*256+(row&15)*16+(k&7)*2;}
    return gpu_launch_word(0)+(row*width+k)*2;
}
fn rw_input(token,k,width,tiled) {
    if tiled {return gpu_launch_word(1)+(token>>3)*width*16+(k>>3)*128+(token&7)*16+(k&7)*2;}
    return gpu_launch_word(1)+(token*width+k)*2;
}
fn rw_pair(pair,token,row,rows,depth,limit,split) {
    let out=gpu_launch_word(2)+(split*rows*depth+token*rows+row)*4;
    if token<depth && token<limit && row<rows {gpu_store_u32(out,pair);}
    if token+1<depth && token+1<limit && row<rows {gpu_store_u32(out+rows*4,pair>>32);}return 0;
}
fn kernel(index,input,output,count) {
    let lane=gpu_lane();let column=lane&15;let group=lane>>4;
    let rows=gpu_launch_word(4)&4294967295;let width=gpu_launch_word(3)&4294967295;let depth=gpu_launch_word(5)&4294967295;
    let row=(gpu_block_x()*(gpu_block_dim_x()>>5)+(gpu_thread_x()>>5))*16+column;
    let token=gpu_block_y()*24+column;let limit=gpu_block_y()*24+24;let split=gpu_block_z();let shift=gpu_launch_word(6)&7;
    let length=width>>shift;let begin=split*length;let shared=gpu_thread_x()*24;
    let tiled=gpu_launch_word(7);let c0=0;let c1=0;let c2=0;let c3=0;let d0=0;let d1=0;let d2=0;let d3=0;
    let at=0;while at<length {
        let k=at+group*8;let w0=0;let w1=0;let a0=0;let a1=0;let b0=0;let b1=0;
        if k<length {
            if row<rows {let p=rw_weight(row,begin+k,width,tiled);w0=rw_half(p);w1=rw_half(p+8);}
            if token<depth {let p=rw_input(token,begin+k,width,tiled);a0=gpu_load_u64(p);a1=gpu_load_u64(p+8);}
            if token+16<depth && token+16<limit {let p=rw_input(token+16,begin+k,width,tiled);b0=gpu_load_u64(p);b1=gpu_load_u64(p+8);}
        }
        c0=gpu_rdna_wmma_f16x8(a0,a1,w0,w1,c0,c1,c2,c3,shared);
        c1=gpu_shared_load64(shared);c2=gpu_shared_load64(shared+8);c3=gpu_shared_load64(shared+16);
        d0=gpu_rdna_wmma_f16x8(b0,b1,w0,w1,d0,d1,d2,d3,shared);
        d1=gpu_shared_load64(shared);d2=gpu_shared_load64(shared+8);d3=gpu_shared_load64(shared+16);at=at+16;
    }
    token=gpu_block_y()*24+group*8;
    rw_pair(c0,token,row,rows,depth,limit,split);rw_pair(c1,token+2,row,rows,depth,limit,split);
    rw_pair(c2,token+4,row,rows,depth,limit,split);rw_pair(c3,token+6,row,rows,depth,limit,split);
    rw_pair(d0,token+16,row,rows,depth,limit,split);rw_pair(d1,token+18,row,rows,depth,limit,split);
    rw_pair(d2,token+20,row,rows,depth,limit,split);rw_pair(d3,token+22,row,rows,depth,limit,split);return 0;
}
fn main(){return 78;}
