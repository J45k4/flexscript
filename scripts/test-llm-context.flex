// Focused retained-cache bounds above 4K, including the final supported slot.
import "../libs/ml/llm/runtime.flex";
fn main(argc,argv) {
    h_environment(argc,argv);lm_select_backend(b_option(argc,argv,"--backend","rdna"));lm_start("build/llm",ll_context_max());
    let q=alloc(1024);let host=alloc(ll_context_max()*512);let query=lm_alloc(1024);let keys=lm_alloc(ll_context_max()*512);let values=lm_alloc(ll_context_max()*512);let output=lm_alloc(1024);
    lm_check(device_upload(query,q,1024));lm_check(device_upload(keys,host,ll_context_max()*512));let result=alloc(1024);let d=h_take(64);
    store64(d,query);store64(d+8,keys);store64(d+16,values);store64(d+24,output);store64(d+32,lm_state);store64(d+40,128);store64(d+48,1);
    let sizes=h_args(4097,8193,32769,40960,0,0);let i=0;while i<h_count(sizes) {let n=h_at(sizes,i);let j=0;
        // Zero Q/K gives uniform attention; only the last V row is nonzero.
        // Omitting the final cache row or truncating at 4K changes the result.
        while j<128 {gpu_store_u32(host+(n-1)*512+j*4,gpu_f32_from_i64(n));j=j+1;}
        lm_check(device_upload(values,host,n*512));store64(lm_host_state,n-1);lm_check(device_upload(lm_state,lm_host_state,16));
        lm_check(device_launch_words(load64(lm_modules+4*8),0,0,1024,device_config(2,1,1,512,1,1,16640,0),d));lm_check(device_download(result,output,1024));j=0;
        while j<256 {let v=gpu_f32_unpack(gpu_load_u32(result+j*4));h_assert(f64_is_finite(v) && f64_le(f64_magnitude(f64_sub(v,0x3ff0000000000000)),0x3eb0c6f7a0b5ed8d),"large-context attention truncated or read outside its cache");j=j+1;}
        j=0;while j<128 {gpu_store_u32(host+(n-1)*512+j*4,0);j=j+1;}i=i+1;
    }
    lm_close();h_print(1,"Large-context attention: 1024 checks passed\n");return 0;
}
