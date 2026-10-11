// Native Flexscript CLI: Pup schedule -> selected GPU backend -> Qwen3 decoding.
import "../libs/ml/llm/pup.flex";
import "../libs/ml/llm/tokenizer.flex";
fn li_best(logits,n) {
    let best=0;let key=0;let i=0;while i<n {let bits=gpu_load_u32(logits+i*4);h_assert((bits&2147483647)<2139095040,"nonfinite model logit");
        let order=bits^2147483648;if bits&2147483648 {order=(~bits)&4294967295;}if !i || order>key {best=i;key=order;}i=i+1;}return best;
}
fn main(argc,argv) {
    h_environment(argc,argv);h_timeout=300000;
    lm_select_backend(b_option(argc,argv,"--backend",lm_default_backend()));
    let directory=b_option(argc,argv,"--checkpoint",0);h_assert(directory,"provide --checkpoint with a Hugging Face Qwen3 checkpoint directory");
    let model=b_option(argc,argv,"--model","libs/ml/examples/qwen3-inference.pup");let compiler=b_option(argc,argv,"--compiler",lm_default_compiler());
    let prompt=b_option(argc,argv,"--prompt","Say hello in one short sentence.");let max_tokens=lw_int(b_option(argc,argv,"--max-tokens","32"));let capacity=lw_int(b_option(argc,argv,"--context","256"));
    h_assert(capacity>=1 && capacity<=ll_context_max() && max_tokens>0 && max_tokens<capacity,"invalid context or generation length");
    let raw=lw_int(b_option(argc,argv,"--raw","0"));h_assert(raw==0 || raw==1,"--raw must be 0 or 1");
    let weight_mode=b_option(argc,argv,"--weights","f16");h_assert(h_equal(weight_mode,"bf16") || h_equal(weight_mode,"f16") || h_equal(weight_mode,"f16-tiled"),"--weights must be bf16, f16 or f16-tiled");lm_weight_format=h_equal(weight_mode,"f16");if h_equal(weight_mode,"f16-tiled") {lm_weight_format=2;}
    let names=lm_kernel_names();h_mkdir("build/llm");let i=0;
    lm_compile_kernels(compiler,"build/llm");
    let plan_only=lw_int(b_option(argc,argv,"--plan-only","0"));h_assert(plan_only==0 || plan_only==1,"--plan-only must be 0 or 1");
    if plan_only {
        lm_dry_run=1;lm_start("build/llm",capacity);lw_load(directory);lw_rotary();lp_parse(model);lm_prepare();
        let plan=j_object();j_set(plan,"weight_storage",j_string(weight_mode));lm_report_backend(plan);j_set(plan,"model_sha256",j_string(h_sha(model)));j_set(plan,"gpu_resident_bytes",j_int(lm_bytes));j_set(plan,"context_capacity",j_int(capacity));
        let stages=j_array();i=0;while i<h_count(lm_steps) {let s=h_at(lm_steps,i);let item=j_object();j_set(item,"kernel",j_string(h_at(names,load64(s))));j_set(item,"threads",j_int(load64(s+8)));j_push(stages,item);i=i+1;}
        j_set(plan,"stages",stages);j_save(b_option(argc,argv,"--report","build/llm/plan.json"),plan);h_print(1,h_cat3("Validated Pup plan; GPU bytes: ",h_int(lm_bytes),"\n"));return 0;
    }
    h_print(2,"Reading tokenizer...\n");qt_open(h_join(directory,"tokenizer.json"));let text=prompt;
    if !raw {text=h_cat3("<|im_start|>user\n",prompt,"<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n");}
    qt_limit=capacity-max_tokens;let tokens=qt_encode(text);h_assert(h_count(tokens)>0 && h_count(tokens)+max_tokens<=capacity,"prompt plus generation exceeds --context");
    let report=j_object();j_set(report,"weight_storage",j_string(weight_mode));let input_ids=j_array();i=0;while i<h_count(tokens) {j_push(input_ids,j_int(h_at(tokens,i)));i=i+1;}j_set(report,"input_ids",input_ids);
    lm_start("build/llm",capacity);lw_load(directory);lw_rotary();lp_parse(model);lm_sampling_enabled=1;lm_prepare();
    h_print(2,h_cat3("Resident GPU bytes: ",h_int(lm_bytes),h_cat3("; kernel launches/token: ",h_int(h_count(lm_steps)),"\n")));
    let mode=b_option(argc,argv,"--prefill","batch");h_assert(h_equal(mode,"batch") || h_equal(mode,"serial"),"--prefill must be batch or serial");
    i=0;while i<h_count(tokens) {h_assert(h_at(tokens,i)>=0 && h_at(tokens,i)<lw_config_int("vocab_size"),"input token out of range");i=i+1;}
    if h_equal(mode,"batch") {lm_prompt_prepare(h_count(tokens));}
    let logits=alloc(lm_output_size*4);let start=lm_now();i=0;
    if h_equal(mode,"batch") {lm_prefill(tokens);}else {
    while i<h_count(tokens) {h_assert(h_at(tokens,i)>=0 && h_at(tokens,i)<lw_config_int("vocab_size"),"input token out of range");lm_execute(h_at(tokens,i),i,i==h_count(tokens)-1);
        h_print(2,h_cat3("Prefill ",h_int(i+1),h_cat3("/",h_int(h_count(tokens)),"\n")));i=i+1;}
    }
    let prefill_ms=lm_now()-start;let generated=j_array();let output=h_buffer();let position=h_count(tokens);let finished=0;let decode_start=lm_now();let produced=0;let decode_calls=0;
    while produced<max_tokens && !finished {
        let dump=b_option(argc,argv,"--logits",0);let prefix=b_option(argc,argv,"--logits-prefix",0);
        if (!produced && dump) || prefix {lm_check(device_download(logits,lm_output,lm_output_size*4));}
        if !produced && dump {h_save_bytes(dump,logits,lm_output_size*4,420);}
        if prefix {h_save_bytes(h_cat3(prefix,h_int(produced),".f32"),logits,lm_output_size*4,420);}
        let token=lm_sample_greedy();j_push(generated,j_int(token));produced=produced+1;
        if token==151645 || token==151643 {finished=1;}else {let piece=qt_decode(token);h_write(1,h_data(piece),h_size(piece));h_append(output,h_data(piece),h_size(piece));
            if produced<max_tokens {lm_execute(token,position,1);position=position+1;decode_calls=decode_calls+1;}}
    }
    let decode_ms=lm_now()-decode_start;h_print(1,"\n");j_set(report,"generated_ids",generated);j_set(report,"text",j_string(h_data(output)));lm_report_backend(report);
    j_set(report,"model_sha256",j_string(h_sha(model)));j_set(report,"gpu_resident_bytes",j_int(lm_bytes));j_set(report,"launches_per_token",j_int(h_count(lm_steps)));
    j_set(report,"prefill_mode",j_string(mode));j_set(report,"prefill_ms",j_int(prefill_ms));j_set(report,"decode_ms",j_int(decode_ms));j_set(report,"decode_calls",j_int(decode_calls));j_set(report,"context_capacity",j_int(capacity));
    j_set(report,"generated_tokens",j_int(produced));j_set(report,"decode_tokens_per_second_x1000",j_int(decode_calls*1000000/(decode_ms+1)));
    let report_path=b_option(argc,argv,"--report","build/llm/report.json");j_save(report_path,report);
    h_print(2,h_cat3("Prefill ms: ",h_int(prefill_ms),h_cat3("; decode ms: ",h_int(decode_ms),"\n")));lm_close();return 0;
}
