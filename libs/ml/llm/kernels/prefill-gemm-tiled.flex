// Warp tiles: sixteen output rows by 24 prompt tokens, FP16 products/FP32 sums.
// The common weight helper selects BF16 conversion or resident FP16 values.
import "common.flex";
fn kernel(index,input,output,count) {
    let lane=index&31;let rows=gpu_launch_word(4)&4294967295;let n=gpu_launch_word(3)&4294967295;let depth=gpu_launch_word(5)&4294967295;
    let tile=gpu_block_y();let row=(gpu_block_x()*(gpu_block_dim_x()>>5)+(gpu_thread_x()>>5))*16+(lane>>2);
    let column=tile*24+(lane>>2);let inner=(lane&3)*2;
    let wr=row;if wr>=rows {wr=0;}let wr2=row+8;if wr2>=rows {wr2=0;}
    let weight_tile=row>>4;if weight_tile*16>=rows {weight_tile=0;}let w=gpu_launch_word(0)+weight_tile*n*32+lane*4;let w2=w+128;let x=gpu_launch_word(1)+inner*2;
    // Align accumulator quartets for native register coalescing.
    let alignment=0;let alignment2=0;let c0=0;let d0=0;let c1=0;let d1=0;let c2=0;let d2=0;let shared=gpu_thread_x()*8;let split=gpu_block_z();let shift=gpu_launch_word(6)&7;let length=n>>shift;w=w+split*length*32;w2=w2+split*length*32;x=x+split*length*2;let k=length>>3;
    let x0=gpu_launch_word(1)+tile*3*n*16+lane*4+split*length*16;
    let x1=x0+n*16;
    let x2=x1+n*16;
    while k&4294967295 {
        let p0=gpu_load_u32(w+0);let q0=gpu_load_u32(w2+0);let v00=gpu_load_u32(x0+0);let v01=gpu_load_u32(x1+0);let v02=gpu_load_u32(x2+0);
        let a0=ll_half_pair(p0)|(ll_half_pair(q0)<<32);
        c0=gpu_mma_f16x4(a0,v00,c0,d0,shared);d0=gpu_shared_load64(shared);
        c1=gpu_mma_f16x4(a0,v01,c1,d1,shared);d1=gpu_shared_load64(shared);
        c2=gpu_mma_f16x4(a0,v02,c2,d2,shared);d2=gpu_shared_load64(shared);
        w=w+256;w2=w2+256;x0=x0+128;x1=x1+128;x2=x2+128;k=k-1;}
    let out=gpu_launch_word(2)+(split*rows*depth+row)*4;let token=tile*24+(lane&3)*2;
    if row+0<rows && token+0<depth {gpu_store_u32(out+0+(token+0)*rows*4,c0);}
    if row+0<rows && token+1<depth {gpu_store_u32(out+0+(token+1)*rows*4,c0>>32);}
    if row+8<rows && token+0<depth {gpu_store_u32(out+32+(token+0)*rows*4,d0);}
    if row+8<rows && token+1<depth {gpu_store_u32(out+32+(token+1)*rows*4,d0>>32);}
    if row+0<rows && token+8<depth {gpu_store_u32(out+0+(token+8)*rows*4,c1);}
    if row+0<rows && token+9<depth {gpu_store_u32(out+0+(token+9)*rows*4,c1>>32);}
    if row+8<rows && token+8<depth {gpu_store_u32(out+32+(token+8)*rows*4,d1);}
    if row+8<rows && token+9<depth {gpu_store_u32(out+32+(token+9)*rows*4,d1>>32);}
    if row+0<rows && token+16<depth {gpu_store_u32(out+0+(token+16)*rows*4,c2);}
    if row+0<rows && token+17<depth {gpu_store_u32(out+0+(token+17)*rows*4,c2>>32);}
    if row+8<rows && token+16<depth {gpu_store_u32(out+32+(token+16)*rows*4,d2);}
    if row+8<rows && token+17<depth {gpu_store_u32(out+32+(token+17)*rows*4,d2>>32);}
    return 0;
}
fn main(){return 78;}
