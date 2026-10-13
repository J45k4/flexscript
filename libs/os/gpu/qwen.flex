// Runnable Qwen proof of the GPU OS request protocol.
import "runtime.flex";
import "../../ml/llm/pup.flex";
import "../../ml/llm/tokenizer.flex";
fn main(argc,argv) {
    h_environment(argc,argv);h_timeout=300000;
    let argument=1;while argument<argc {if h_equal(load64(argv+argument*8),"--help") {h_print(1,"GPU OS Qwen: --checkpoint DIR --prompt TEXT --max-tokens 32 --context 256\nOptional: --compiler build/flex --image PATH --rebuild 1 --verify 1 --profile 1 --workers N --device N --cancel-after N --report PATH\n");return 0;}argument=argument+1;}
    let directory=b_option(argc,argv,"--checkpoint","build/llm/models/qwen3-1.7b");let compiler=b_option(argc,argv,"--compiler",lm_default_compiler());
    let capacity=lw_int(b_option(argc,argv,"--context","256"));let maximum=lw_int(b_option(argc,argv,"--max-tokens","32"));
    h_assert(capacity>=32 && capacity<=ll_context_max() && maximum>0 && maximum<capacity,"invalid context or token limit");
    let verify=lw_int(b_option(argc,argv,"--verify","0"));h_assert(verify==0 || verify==1,"--verify must be 0 or 1");let cancel_after=lw_int(b_option(argc,argv,"--cancel-after","0"));h_assert(cancel_after>=0 && cancel_after<maximum,"invalid cancellation point");
    lm_select_backend("rdna");lm_device_ordinal=lw_int(b_option(argc,argv,"--device","0"));lm_weight_format=1;lm_fusion=0;
    go_workers=lw_int(b_option(argc,argv,"--workers","0"));
    let image=b_option(argc,argv,"--image","build/gpu-os/resident.hsaco");
    if !h_exists(image) || lw_int(b_option(argc,argv,"--rebuild","0")) {let args=h_args(compiler,"libs/os/gpu/build.flex","--compiler",compiler,"--output",h_dir(image));h_add(args,"--target");h_add(args,b_option(argc,argv,"--gpu-os-target","auto"));h_ok(args);}
    lm_compile_kernels(compiler,"build/llm");
    qt_open(h_join(directory,"tokenizer.json"));
    let prompt=b_option(argc,argv,"--prompt","Say hello in one short sentence.");
    let text=h_cat3("<|im_start|>user\n",prompt,"<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n");
    qt_limit=capacity-maximum;let tokens=qt_encode(text);h_assert(h_count(tokens)>0 && h_count(tokens)+maximum<=capacity,"prompt plus generation exceeds context");
    lm_start("build/llm",capacity);lw_load(directory);lw_rotary();lp_parse(b_option(argc,argv,"--model","libs/ml/examples/qwen3-inference.pup"));lm_sampling_enabled=1;lm_prepare();
    let handle=go_open(image,lm_steps,lm_state,lm_output,lm_output_size,capacity,lm_device_ordinal);
    h_print(2,h_cat3("GPU OS resident workers: ",h_int(load64(handle+56)),"; one cooperative launch per request\n"));
    let started=lm_now_us();lm_prefill(tokens);let prefill=lm_now_us()-started;
    let expected=h_vec();
    if verify {
        let finished=0;let i=0;while i<maximum && !finished {let id=lm_sample_greedy();h_add(expected,id);i=i+1;
            if id==151645 || id==151643 {finished=1;}else if i<maximum {lm_execute(id,h_count(tokens)+i-1,1);}}
        lm_prefill(tokens);
    }
    let profiling=lw_int(b_option(argc,argv,"--profile","0"));h_assert(profiling==0 || profiling==1,"--profile must be 0 or 1");go_profile(handle,profiling);
    started=lm_now_us();go_submit(handle,h_count(tokens),maximum,151645,151643);
    let generated=j_array();let output=h_buffer();let read=0;let cancelled=0;let first=0;
    let polling=1;while polling {
        let produced=go_produced(handle);
        while read<produced {
            let id=go_token(handle,read);j_push(generated,j_int(id));read=read+1;if !first {first=lm_now_us()-started;}
            if id!=151645 && id!=151643 {let piece=qt_decode(id);h_write(1,h_data(piece),h_size(piece));h_append(output,h_data(piece),h_size(piece));}
            if cancel_after && read>=cancel_after && !cancelled {go_cancel(handle);cancelled=1;}
        }
        if go_status(handle)>=2 {if go_produced(handle)==read {polling=0;}}
        if polling {h_sleep(1);}
    }
    let reason=go_wait(handle);let elapsed=lm_now_us()-started;h_assert(go_status(handle)!=3,"nonfinite GPU OS logits");
    if verify && !cancel_after {h_assert(read==h_count(expected),"GPU OS/reference token count differs");let i=0;while i<read {h_assert(j_value(j_at(generated,i))==h_at(expected,i),h_cat("GPU OS/reference token differs at ",h_int(i)));i=i+1;}}
    h_print(1,"\n");let report=j_object();j_set(report,"runtime",j_string("gpu-os-v1"));j_set(report,"worker_target",j_string(go_target(handle)));
    j_set(report,"workers",j_int(load64(handle+56)));j_set(report,"generated_ids",generated);j_set(report,"text",j_string(h_data(output)));
    j_set(report,"tokens",j_int(read));j_set(report,"decode_us",j_int(elapsed));j_set(report,"prefill_us",j_int(prefill));j_set(report,"first_token_us",j_int(first));
    let calls=0;if read {calls=read-1;}j_set(report,"decode_calls",j_int(calls));j_set(report,"decode_tokens_per_second_x1000",j_int(calls*1000000000/(elapsed+1)));
    j_set(report,"decode_launches",j_int(1));j_set(report,"reason",j_int(reason));j_set(report,"verified",j_int(verify && !cancel_after));
    if profiling {j_set(report,"gpu_profile",go_profile_records(handle,0));}
    j_save(b_option(argc,argv,"--report","build/gpu-os/report.json"),report);
    h_print(2,h_cat3("GPU OS decode: ",h_int(read),h_cat3(" tokens in ",h_int(elapsed)," us\n")));
    go_close(handle);lm_close();return 0;
}
