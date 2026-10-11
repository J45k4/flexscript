import "../libs/ml/llm/runtime.flex";
import "../libs/ml/llm/tests/kernels.flex";
import "../libs/ml/llm/tests/plan.flex";
global lt_checks=0;
global lt_launch_extra=0;
global lt_suffix=0;
fn lt_near(actual,expected) {
    let a=gpu_f32_unpack(actual);let b=gpu_f32_unpack(expected);
    h_assert(f64_is_finite(a) && f64_le(f64_magnitude(f64_sub(a,b)),f64_mul(f64_add(0x3ff0000000000000,f64_magnitude(b)),0x3ee4f8b588e368f1)),"LLM kernel differs from reference");lt_checks=lt_checks+1;return 0;
}
fn lt_buffer(host,n) {let p=lm_alloc(n);lm_check(cuda_upload(p,host,n));return p;}
fn lt_launch(name,descriptor,threads) {
    let module=cuda_module(h_read(h_cat3("build/llm/",name,lt_suffix)));lm_check(cuda_status);let device=0;
    let shared=0;if h_equal(name,"rms") || h_equal(name,"rms-wide") || h_equal(name,"rms-add") {shared=32;}else if h_equal(name,"attention") {shared=16640;}
    let kind=0;let i=0;let names=lm_kernel_names();while i<h_count(names) {if h_equal(name,h_at(names,i)) {kind=i;}i=i+1;}
    let block=lm_block(kind);lm_check(cuda_launch_words(module,lt_launch_extra&4294967295,lt_launch_extra>>32,threads,cuda_config((threads+block-1)/block,1,1,block,1,1,shared,0),descriptor));lm_check(cuda_unload(module));return 0;
}
fn main(argc,argv) {
    lt_suffix=".cubin";
    h_environment(argc,argv);h_timeout=300000;h_mkdir("build/llm");let reject=b_option(argc,argv,"--reject-case",0);if reject {return lt_plan_bad(reject);}lt_plan_test(load64(argv));let compiler=b_option(argc,argv,"--compiler","build/flex-llm");let names=lm_kernel_names();let i=0;
    h_mkdir("build/llm");while i<h_count(names) {let name=h_at(names,i);h_ok(h_args(compiler,"--target","sass-sm75",h_cat3("libs/ml/llm/kernels/",name,".flex"),"-o",h_cat3("build/llm/",name,".cubin")));
        h_ok(h_args(compiler,"--target","ptx",h_cat3("libs/ml/llm/kernels/",name,".flex"),"-o",h_cat3("build/llm/",name,".ptx")));i=i+1;}
    let gpu=0;i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {gpu=1;}i=i+1;}
    if !gpu {h_print(1,"LLM kernels compiled to direct SASS and PTX; eight Pup planning checks passed.\n");return 0;}
    lm_start("build/llm",64);let a=alloc(512);let w=alloc(256);i=0;
    while i<128 {gpu_store_u32(a+i*4,1065353216);store8(w+i*2,128);store8(w+i*2+1,63);i=i+1;}
    let x=lt_buffer(a,512);let weight=lt_buffer(w,256);let y=lm_alloc(512);let host=alloc(512);let d=alloc(64);
    store64(d,weight);store64(d+8,x);store64(d+16,y);store64(d+24,128);lt_launch("gemv",d,32);lm_check(cuda_download(host,y,4));lt_near(gpu_load_u32(host),gpu_f32_from_i64(128));
    store64(d,x);store64(d+8,weight);store64(d+24,128);store64(d+32,gpu_f32_div(1065353216,gpu_f32_from_i64(128)));store64(d+40,0);
    lt_launch("rms",d,128);lm_check(cuda_download(host,y,512));i=0;while i<128 {lt_near(gpu_load_u32(host+i*4),1065353216);i=i+1;}
    // Zero-angle rotary leaves every input pair unchanged.
    let table=alloc(512);i=0;while i<64 {gpu_store_u32(table+i*8,1065353216);i=i+1;}let trig=lt_buffer(table,512);
    lm_check(cuda_upload(lm_state,lm_host_state,16));store64(d,x);store64(d+8,y);store64(d+16,trig);store64(d+24,lm_state);
    lt_launch("rope",d,64);lm_check(cuda_download(host,y,512));i=0;while i<128 {lt_near(gpu_load_u32(host+i*4),1065353216);i=i+1;}
    // A one-token attention cache returns V exactly, independent of Q/K.
    store64(d,x);store64(d+8,x);store64(d+16,x);store64(d+24,y);store64(d+32,lm_state);store64(d+40,128);store64(d+48,0);
    lt_launch("attention",d,512);lm_check(cuda_download(host,y,512));i=0;while i<128 {lt_near(gpu_load_u32(host+i*4),1065353216);i=i+1;}
    // SiLU(1), exercising native EX2 and RCP approximations.
    store64(d,x);store64(d+8,0);store64(d+16,y);store64(d+24,3);lt_launch("element",d,128);lm_check(cuda_download(host,y,512));
    let expected=gpu_f32_pack(f64_div(0x3ff0000000000000,f64_add(0x3ff0000000000000,f64_exp(0xbff0000000000000))));
    i=0;while i<128 {lt_near(gpu_load_u32(host+i*4),expected);i=i+1;}lt_more();lt_suffix=".ptx";lt_more();lm_close();h_print(1,h_cat3("LLM GPU checks: ",h_int(lt_checks),"\n"));return 0;
}
