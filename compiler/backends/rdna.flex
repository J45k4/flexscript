import "rdna-linear.flex";
import "rdna-elf.flex";
import "rdna-word.flex";
import "rdna-norm.flex";
import "rdna-resident.flex";
// Specialized linear kernels retain their compact instruction fast paths.
// Other kernels lower Word IR directly, without invoking HIPRTC or LLVM.
fn rdna_finish() {
    if global_count || vm_heap_used>16 {fail("direct RDNA target does not support globals or static data");}
    let kernel=find(functions,function_count,"kernel",6);
    if kernel<0 || load64(functions+kernel*32+24)!=4 {fail("direct RDNA requires kernel(index,input,output,count)");}
    p_code=output;p_size=output_size;let pc=load64(functions+kernel*32+16)+16;let end=p_end(kernel);
    let kind=0;if pc+32<=end && load64(p_code+pc)==8 && load64(p_code+pc+16)==9 {kind=gpu_intrinsic(load64(p_code+pc+8));}
    if kind<72 || kind>75 {return rw_lower(kernel);}
    if load64(functions+load64(p_code+pc+8)*32+24) {fail("wrong direct RDNA intrinsic arity");}
    // The frontend appends a default return even after an explicit return.
    pc=pc+32;while pc<end {let op=load64(p_code+pc);if op!=1 && op!=9 {fail("direct RDNA kernel must contain only its native intrinsic return");}pc=pc+16;}
    output=alloc(output_limit);output_size=0;if output<0 {fail("cannot allocate direct RDNA instructions");}
    let registers=28;
    if kind==75 {rn_rms_add();registers=32;}else if kind==73 {rd_linear(kind,0);}else if kind==74 {rd_linear(kind,0);registers=20;}else {
        // Wider chunks improve global-load throughput for aligned dimensions;
        // keep the eight-weight path for positive widths congruent to 256.
        rd_sload(1,2,48);emit32(0xbfc70000);rd_sop(0x8b000000,2,2,255);emit32(511);emit32(0xbf068002);
        let wide=rd_branch(0xbfa20000);rd_linear(kind,0);rd_patch(wide,output_size);rd_linear(kind,1);registers=32;
    }
    rd_sgprs=32;rd_elf(registers);return 0;
}
