// Offline GPU toolchain driver. Source emission remains the default for HIP;
// --emit code-object owns the external tools and atomic artifact publication.
import "../scripts/lib/host.flex";
global gc_emit=0;
global gc_arch=0;
global gc_rocm=0;
fn gc_options() {
    if gc_emit || gc_arch || gc_rocm {
        if !hip_target || hp_machine {fail("GPU emission options require --target hip");}
        if gc_emit!=1 && (gc_arch || gc_rocm) {fail("--gpu-arch and --rocm-root require --emit code-object");}
        if gc_emit==1 {
            if !gc_arch {fail("code-object emission requires --gpu-arch gfx...");}
            let n=length(gc_arch);if n<4 || n>16 || !up_text(h_slice(gc_arch,3),"gfx") {fail("expected a base AMD GPU architecture such as gfx1201 or gfx90a");}
            let i=3;while i<n {let c=load8(gc_arch+i);if !((c>=48 && c<=57)||(c>=97 && c<=102)) {fail("invalid GPU architecture");}i=i+1;}
        }
    }return 0;
}
fn compiler_output_check(stat) {
    let i=0;while i<module_count {let module=modules+i*64;if load64(stat)==load64(module+24) && load64(stat+8)==load64(module+32) {select_module(i);token_start=0;fail("source and output refer to the same file");}i=i+1;}
    i=0;while i<frontend_input_count {if load64(stat)==load64(frontend_inputs+i*16) && load64(stat+8)==load64(frontend_inputs+i*16+8) {fail("output refers to a frontend source file");}i=i+1;}
    i=0;while i<tx_input_count {if load64(stat)==load64(tx_inputs+i*16) && load64(stat+8)==load64(tx_inputs+i*16+8) {fail("output refers to a transformation source file");}i=i+1;}return 0;
}
fn gc_destination(path) {
    let stat=h_take(144);let result=syscall(6,path,stat,0,0,0,0);if result==-2 {return 0;}if result {fail("cannot stat code-object output");}
    if (load64(stat+24)&61440)!=32768 {fail("code-object output must be a regular file, not a symlink");}compiler_output_check(stat);return 0;
}
fn gc_error(staging,message) {h_remove(staging);fail(message);return 1;}
fn gc_run(args,staging) {
    let process=h_run(args);if h_status(process) {h_print(2,h_out(process));h_print(2,h_err(process));return gc_error(staging,h_cat("GPU tool failed: ",h_at(args,0)));}return 0;
}
fn gc_compile(argc,argv,destination,data,size) {
    h_environment(argc,argv);h_timeout=300000;destination=h_absolute(destination);gc_destination(destination);
    let parent=h_dir(destination);let random=h_take(8);if syscall(318,random,8,0,0,0,0)!=8 {fail("cannot create GPU build nonce");}
    let staging=h_join(parent,h_cat(".flexscript-gpu-",h_hex(random,8)));if syscall(83,staging,448,0,0,0,0) {fail("cannot create GPU build staging directory");}
    let generated=h_join(staging,"kernel.hip");let bundle=h_join(staging,"kernel.bundle");let artifact=h_join(staging,"kernel.hsaco");h_save_bytes(generated,data,size,420);
    let rocm=gc_rocm;if !rocm {rocm="/opt/rocm";}
    let args=h_args(h_join(rocm,"bin/hipcc"),"--genco",h_cat("--offload-arch=",gc_arch),"-O3","-ffp-contract=off",generated);h_add(args,"-o");h_add(args,bundle);gc_run(args,staging);
    args=h_args(h_join(rocm,"llvm/bin/clang-offload-bundler"),"--unbundle","--type=o",h_cat("--targets=hipv4-amdgcn-amd-amdhsa--",gc_arch),h_cat("--input=",bundle),h_cat("--output=",artifact));gc_run(args,staging);
    if !h_exists(artifact) {return gc_error(staging,"GPU tool produced no code object");}let bytes=h_read(artifact);let n=h_file_size;
    if n<64 || load8(bytes)!=127 || !h_bytes(bytes+1,"ELF",3) || load8(bytes+4)!=2 || load8(bytes+5)!=1 || load8(bytes+18)!=224 || load8(bytes+19)!=0 {return gc_error(staging,"GPU tool produced an invalid AMD GPU ELF code object");}
    if syscall(90,artifact,420,0,0,0,0) {return gc_error(staging,"cannot set GPU code-object permissions");}
    gc_destination(destination);if syscall(82,artifact,destination,0,0,0,0) {return gc_error(staging,"cannot publish GPU code object");}h_remove(staging);return 0;
}
