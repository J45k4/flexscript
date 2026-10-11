// CUDA event measurements of each stage, without changing the Pup graph.
import "../libs/ml/llm/pup.flex";
fn main(argc,argv) {
    h_environment(argc,argv);h_timeout=300000;
    lm_select_backend(b_option(argc,argv,"--backend","sass"));
    let directory=b_option(argc,argv,"--checkpoint",0);h_assert(directory,"provide --checkpoint");
    let fixture=j_parse(h_read(b_option(argc,argv,"--tokens","build/llm/final-chat.json")));
    let input=j_need(fixture,"input_ids");let generated=j_need(fixture,"generated_ids");
    let iterations=lw_int(b_option(argc,argv,"--iterations","3"));
    h_assert(iterations>0 && iterations<=32 && j_count(input)+iterations<=256,"invalid profile length");
    let weight_mode=b_option(argc,argv,"--weights","f16");h_assert(h_equal(weight_mode,"bf16") || h_equal(weight_mode,"f16") || h_equal(weight_mode,"f16-tiled"),"--weights must be bf16, f16 or f16-tiled");lm_weight_format=h_equal(weight_mode,"f16");if h_equal(weight_mode,"f16-tiled") {lm_weight_format=2;}
    let names=lm_kernel_names();let compiler=b_option(argc,argv,"--compiler","build/flex-llm");let kernel=0;h_mkdir("build/llm");
    lm_compile_kernels(compiler,"build/llm");
    lm_start("build/llm",256);lw_load(directory);lw_rotary();lp_parse("libs/ml/examples/qwen3-inference.pup");lm_prepare();
    let mode=b_option(argc,argv,"--mode","decode");h_assert(h_equal(mode,"decode") || h_equal(mode,"prefill"),"invalid profile mode");
    let i=0;let steps=lm_steps;
    if h_equal(mode,"prefill") {let tokens=h_vec();while i<j_count(input) {h_add(tokens,j_value(j_at(input,i)));i=i+1;}lm_prefill(tokens);steps=lm_prompt_steps;}
    else {while i<j_count(input) {lm_execute(j_value(j_at(input,i)),i,i==j_count(input)-1);i=i+1;}}
    let starts=h_take(h_count(steps)*8);let ends=h_take(h_count(steps)*8);let total=h_take(h_count(names)*8);let calls=h_take(h_count(names)*8);
    i=0;while i<h_count(steps) {lm_check(cuda_call("cuEventCreate",starts+i*8,0,0,0,0,0));lm_check(cuda_call("cuEventCreate",ends+i*8,0,0,0,0,0));i=i+1;}
    let elapsed=alloc(8);let start=lm_now();let run=0;
    while run<iterations {
        store64(lm_host_state,j_count(input)+run);store64(lm_host_state+8,j_value(j_at(generated,run%j_count(generated))));lm_check(cuda_upload_async(lm_state,lm_host_state,16,lm_stream));
        i=0;while i<h_count(steps) {let step=h_at(steps,i);
            lm_check(cuda_call("cuEventRecord",load64(starts+i*8),lm_stream,0,0,0,0));
            lm_check(cuda_dispatch(load64(lm_functions+load64(step)*8),load64(step+88),load64(step+80)));
            lm_check(cuda_call("cuEventRecord",load64(ends+i*8),lm_stream,0,0,0,0));i=i+1;}
        lm_check(cuda_synchronize());i=0;
        while i<h_count(steps) {let kind=load64(h_at(steps,i));lm_check(cuda_call("cuEventElapsedTime",elapsed,load64(starts+i*8),load64(ends+i*8),0,0,0));
            let ns=f64_to_i64_trunc(f64_mul(gpu_f32_unpack(gpu_load_u32(elapsed)),f64_from_i64(1000000)));
            store64(total+kind*8,load64(total+kind*8)+ns);store64(calls+kind*8,load64(calls+kind*8)+1);i=i+1;}run=run+1;
    }
    let report=j_object();lm_report_backend(report);j_set(report,"mode",j_string(mode));j_set(report,"weight_storage",j_string(weight_mode));j_set(report,"wall_ms",j_int(lm_now()-start));j_set(report,"iterations",j_int(iterations));let kernels=j_array();
    i=0;while i<h_count(names) {let item=j_object();j_set(item,"kernel",j_string(h_at(names,i)));j_set(item,"nanoseconds",j_int(load64(total+i*8)));j_set(item,"calls",j_int(load64(calls+i*8)));
        j_set(item,"registers",j_int(cuda_function_attribute(load64(lm_functions+i*8),4)));lm_check(cuda_status);
        let shared=0;if i==1 || i==6 || i==9 || i==24 {shared=32;}else if i==4 {shared=16640;}else if i==11 || i==21 {shared=lm_prompt_block*8;}
        j_set(item,"block_threads",j_int(lm_block(i)));j_set(item,"blocks_per_sm",j_int(cuda_occupancy(load64(lm_functions+i*8),lm_block(i),shared)));lm_check(cuda_status);j_push(kernels,item);i=i+1;}
    j_set(report,"kernels",kernels);j_save(b_option(argc,argv,"--report","build/llm/profile.json"),report);
    i=0;while i<h_count(steps) {lm_check(cuda_event_close(load64(starts+i*8)));lm_check(cuda_event_close(load64(ends+i*8)));i=i+1;}
    lm_close();return 0;
}
