import "lib/harness.flex";
import "lib/build.flex";
global gc_test_compiler=0;
global gc_test_root=0;
global gc_test_rocm=0;
global gc_test_log=0;
fn gt_args(source,output) {let args=h_args(gc_test_compiler,"--target","hip","--emit","code-object","--gpu-arch");h_add(args,"gfx90a");h_add(args,"--rocm-root");h_add(args,gc_test_rocm);h_add(args,source);h_add(args,"-o");h_add(args,output);return args;}
fn gt_length(path) {h_read(path);return h_file_size;}
fn gt_reject(args,path,message) {
    let digest=h_sha(path);let before=gt_length(gc_test_log);let process=h_run(args);t_assert(h_status(process)!=0,"invalid GPU invocation succeeded");t_assert(h_has(h_err(process),message),h_err(process));t_assert(h_equal(digest,h_sha(path)),"rejected GPU invocation changed destination");t_assert(gt_length(gc_test_log)==before,"invalid invocation started GPU tools");return 0;
}
fn suite(compiler) {
    h_timeout=300000;gc_test_compiler=h_real(compiler);gc_test_root=h_real(".");t_checks=0;t_work=h_temp();let source=h_join(t_work,"kernel with ' $().flex");let destination=h_join(t_work,"kernel.hsaco");h_save(source,"fn kernel(index,input,output,count){store64(output+index*8,load64(input+index*8)+1);return 0;}");let source_hash=h_sha(source);let text=h_join(t_work,"kernel.hip");
    h_ok(h_args(gc_test_compiler,"--target","hip",source,"-o",text));let plain=h_sha(text);let explicit=h_args(gc_test_compiler,"--target","hip","--emit","source",source);h_add(explicit,"-o");h_add(explicit,text);h_ok(explicit);t_assert(h_equal(plain,h_sha(text)),"explicit source emission changed HIP output");t_assert(h_has(h_read(text),"__global__ void flex_kernel"),"default HIP target no longer emits source");
    gc_test_rocm=h_join(t_work,"rocm root with spaces");h_mkdir(h_join(gc_test_rocm,"bin"));h_mkdir(h_join(gc_test_rocm,"llvm/bin"));let tool=h_join(t_work,"tool");h_compile(gc_test_compiler,"tests/tooling/gpu-codeobject/tool.flex",tool);h_ok(h_args("ln","-s",tool,h_join(gc_test_rocm,"bin/hipcc"),0,0));h_ok(h_args("ln","-s",tool,h_join(gc_test_rocm,"llvm/bin/clang-offload-bundler"),0,0));gc_test_log=h_join(t_work,"tools.log");h_save(gc_test_log,"");h_setenv("FLEX_GPU_TEST_LOG",gc_test_log);
    h_ok(gt_args(source,destination));t_assert(gt_length(destination)==64,"code-object output has wrong size");t_assert(gt_length(gc_test_log)==2,"code-object build did not own both tool invocations");t_assert(syscall(21,destination,1,0,0,0,0)!=0,"GPU code object is executable");t_assert(h_equal(source_hash,h_sha(source)),"GPU compilation changed source");
    let failures=h_args("hipcc","bundler","invalid","missing",0,0);let i=0;while i<h_count(failures) {h_setenv("FLEX_GPU_TEST_FAILURE",h_at(failures,i));let digest=h_sha(destination);let process=h_run(gt_args(source,destination));t_assert(h_status(process)!=0,"failed GPU tool was accepted");t_assert(h_equal(digest,h_sha(destination)),"GPU tool failure replaced existing output");let args=h_args("find",t_work,"-maxdepth","1","-name",".flexscript-gpu-*");t_assert(!h_len(h_out(h_ok(args))),"failed GPU build leaked staging directory");i=i+1;}h_setenv("FLEX_GPU_TEST_FAILURE",0);
    let args=h_args(gc_test_compiler,"--target","hip","--emit","code-object",source);h_add(args,"-o");h_add(args,destination);gt_reject(args,destination,"requires --gpu-arch");
    args=gt_args(source,destination);h_add(args,"--emit");h_add(args,"source");gt_reject(args,destination,"Usage:");
    args=h_args(gc_test_compiler,"--target","hip","--gpu-arch","gfx1201",source);h_add(args,"-o");h_add(args,destination);gt_reject(args,destination,"require --emit code-object");
    args=h_args(gc_test_compiler,"--target","hip","--emit","code-object","--gpu-arch");h_add(args,"gfx1201;bad");h_add(args,source);h_add(args,"-o");h_add(args,destination);gt_reject(args,destination,"invalid GPU architecture");
    args=h_args(gc_test_compiler,"--target","ptx","--emit","code-object",source);h_add(args,"-o");h_add(args,destination);gt_reject(args,destination,"require --target hip");
    let alias=h_join(t_work,"source-alias");h_ok(h_args("ln",source,alias,0,0,0));gt_reject(gt_args(source,alias),alias,"same file");syscall(87,alias,0,0,0,0,0);h_ok(h_args("ln","-s",destination,alias,0,0));gt_reject(gt_args(source,alias),destination,"symlink");
    let imported=h_join(t_work,"import.flex");h_save(imported,"fn value(){return 7;}\n");h_save(source,h_cat3("import \"",imported,"\";fn kernel(i,x,y,n){store64(y+i*8,value());return 0;}"));h_ok(h_args("ln",imported,h_join(t_work,"import-alias"),0,0,0));gt_reject(gt_args(source,h_join(t_work,"import-alias")),imported,"same file");
    h_save(source,"fn kernel( broken");gt_reject(gt_args(source,destination),destination,"error:");h_remove(t_work);return t_checks;
}
fn main(argc,argv) {return t_entry(argc,argv);}
