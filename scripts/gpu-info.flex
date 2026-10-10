import "lib/build.flex";
import "../lib/cuda.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let count=cuda_device_count();
    if count<0 {h_print(2,h_cat3("CUDA: ",cuda_error(),"\n"));return 77;}
    let i=0;while i<count {
        let info=cuda_device_info(i);if !info {h_print(2,cuda_error());return 1;}
        h_print(1,h_cat3("Device ",h_int(i),h_cat3(": ",load64(info),"\n")));
        h_print(1,h_cat3("  Compute capability: ",h_int(load64(info+72)),h_cat3(".",h_int(load64(info+80)),"\n")));
        h_print(1,h_cat3("  VRAM MiB: ",h_int(load64(info+64)/1048576),"\n"));
        h_print(1,h_cat3("  Multiprocessors: ",h_int(load64(info+16)),"\n"));
        h_print(1,h_cat3("  Warp width: ",h_int(load64(info+24)),"\n"));
        h_print(1,h_cat3("  Maximum threads/block: ",h_int(load64(info+32)),"\n"));
        h_print(1,h_cat3("  Maximum resident threads/SM: ",h_int(load64(info+40)),"\n"));
        h_print(1,h_cat3("  Shared bytes/block: ",h_int(load64(info+48)),"\n"));
        h_print(1,h_cat3("  Registers/block: ",h_int(load64(info+56)),"\n"));i=i+1;
    }return 0;
}
