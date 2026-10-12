import "../../../../lib/rdna.flex";
fn kernel(index,input,output,count) {return gpu_rdna_gemv_three_f16();}
