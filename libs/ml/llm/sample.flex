// GPU greedy sampler appended to application graphs. Resident-model benchmarks
// leave this disabled and continue timing the original logits-producing graph.
global lm_sampling_enabled=0;
global lm_sampling_result=0;
global lm_sampling_host=0;
global lm_sampling_args=0;
global lm_sampling_configs=0;
fn lm_sampling_setup() {
    let partials=(lm_output_size+1023)/1024;let partial=lm_alloc(partials*8);lm_sampling_result=lm_alloc(8);lm_sampling_host=alloc(8);
    lm_sampling_args=h_take(16);lm_sampling_configs=h_take(16);let phase=0;
    while phase<2 {
        let descriptor=h_take(64);let source=lm_output;let output=partial;let n=lm_output_size;let gx=partials;
        if phase {source=partial;output=lm_sampling_result;n=partials;gx=1;}
        store64(descriptor,source);store64(descriptor+8,output);store64(descriptor+16,n);store64(descriptor+24,phase);
        let values=h_take(24);store64(values+16,gx*128);let args=h_take(88);let i=0;
        while i<3 {store64(args+i*8,values+i*8);i=i+1;}i=0;while i<8 {store64(args+24+i*8,descriptor+i*8);i=i+1;}
        store64(lm_sampling_args+phase*8,args);store64(lm_sampling_configs+phase*8,device_config(gx,1,1,128,1,1,32,lm_stream));lm_check(device_status);phase=phase+1;
    }
    return 0;
}
fn lm_sampling_dispatch() {
    let phase=0;while phase<2 {lm_check(device_dispatch(load64(lm_functions+26*8),load64(lm_sampling_configs+phase*8),load64(lm_sampling_args+phase*8)));phase=phase+1;}return 0;
}
fn lm_sample_greedy() {
    lm_check(device_download(lm_sampling_host,lm_sampling_result,8));let id=4294967295-(load64(lm_sampling_host)&4294967295);
    h_assert(id<lm_output_size,"nonfinite model logit");return id;
}
