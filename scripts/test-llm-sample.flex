// Greedy sampling boundaries, ties and nonfinite propagation on the real GPU.
import "lib/harness.flex";
import "../lib/hip.flex";
import "../lib/gpu.flex";
fn ts_check(status) {h_assert(!status,hip_error());return 0;}
fn ts_run(function,stream,input,partial,result,host,n,mode,expected) {
    let i=0;while i<n {gpu_store_u32(host+i*4,3221225472);i=i+1;}
    if mode==0 {gpu_store_u32(host+(n-1)*4,3212836864);}
    if mode==1 {gpu_store_u32(host,1065353216);gpu_store_u32(host+(n-1)*4,1065353216);}
    if mode==2 {gpu_store_u32(host+(n-1)*4,2143289344);}
    if mode==3 {gpu_store_u32(host+(n-1)*4,4286578688);}
    ts_check(hip_upload(input,host,n*4));let blocks=(n+1023)/1024;let phase=0;
    while phase<2 {
        let source=input;let output=partial;let count=n;let gx=blocks;
        if phase {source=partial;output=result;count=blocks;gx=1;}
        let values=h_take(88);store64(values+16,gx*128);store64(values+24,source);store64(values+32,output);store64(values+40,count);store64(values+48,phase);
        let args=h_take(88);i=0;while i<11 {store64(args+i*8,values+i*8);i=i+1;}
        let config=hip_config(gx,1,1,128,1,1,32,stream);ts_check(hip_status);ts_check(hip_dispatch(function,config,args));syscall(11,config,88,0,0,0,0);phase=phase+1;
    }
    ts_check(hip_stream_wait(stream));ts_check(hip_download(host,result,8));
    t_assert(4294967295-(load64(host)&4294967295)==expected,"GPU greedy sampling changed the selected token or lost a nonfinite sentinel");return 0;
}
fn suite(compiler) {
    t_init(compiler);let context=hip_context_device(0);ts_check(hip_status);
    let targets=h_args("rdna-gfx1201",0,0,0,0,0);let target=0;while target<h_count(targets) {
    let image=h_join(t_work,"argmax.hsaco");h_ok(h_args(t_compiler,"--target",h_at(targets,target),"libs/ml/llm/kernels/argmax.flex","-o",image));
    let module=hip_module(h_read(image));ts_check(hip_status);let function=hip_function(module,"flex_kernel");ts_check(hip_status);
    let stream=hip_stream();ts_check(hip_status);let input=hip_buffer(151936*4);ts_check(hip_status);let partial=hip_buffer(149*8);ts_check(hip_status);let result=hip_buffer(8);ts_check(hip_status);let host=alloc(151936*4);
    let sizes=h_args(1,33,1025,151936,0,0);let i=0;while i<4 {let n=h_at(sizes,i);let mode=0;while mode<4 {let expected=n-1;if mode==1 {expected=0;}if mode>=2 {expected=4294967295;}ts_run(function,stream,input,partial,result,host,n,mode,expected);mode=mode+1;}i=i+1;}
    syscall(11,host,151936*4,0,0,0,0);ts_check(hip_free(result));ts_check(hip_free(partial));ts_check(hip_free(input));ts_check(hip_stream_close(stream));ts_check(hip_unload(module));target=target+1;}ts_check(hip_close(context));return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
