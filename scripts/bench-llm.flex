// Resident model timing: exclude loading, compilation, sampling and text output.
// Each repetition overwrites the cache from position zero before decoding.
import "../libs/ml/llm/pup.flex";
fn main(argc,argv) {
    h_environment(argc,argv);h_timeout=300000;
    lm_select_backend(b_option(argc,argv,"--backend","sass"));
    let directory=b_option(argc,argv,"--checkpoint",0);h_assert(directory,"provide --checkpoint");
    let fixture=j_parse(h_read(b_option(argc,argv,"--tokens","build/llm/final-chat.json")));
    let input=j_need(fixture,"input_ids");let generated=j_need(fixture,"generated_ids");
    let count=lw_int(b_option(argc,argv,"--decode","64"));let repeats=lw_int(b_option(argc,argv,"--repeats","3"));
    let capacity=lw_int(b_option(argc,argv,"--context","256"));let depth=j_count(input);
    let split=b_option(argc,argv,"--prefill-split","auto");if !h_equal(split,"auto") {lm_prompt_split=lw_int(split);}h_assert(lm_prompt_split<=5,"prefill split exponent exceeds five");
    lm_fusion=lw_int(b_option(argc,argv,"--fusion","7"));h_assert(lm_fusion>=0 && lm_fusion<=7,"invalid fusion mask");
    h_assert(depth>0 && j_count(generated)>0 && count>0 && repeats>0 && repeats<=100 && capacity<=4096 && depth+count<=capacity,"invalid benchmark dimensions");
    let weight_mode=b_option(argc,argv,"--weights","f16");h_assert(h_equal(weight_mode,"bf16") || h_equal(weight_mode,"f16") || h_equal(weight_mode,"f16-tiled"),"--weights must be bf16, f16 or f16-tiled");lm_weight_format=h_equal(weight_mode,"f16");if h_equal(weight_mode,"f16-tiled") {lm_weight_format=2;}
    let i=0;
    let compiler=b_option(argc,argv,"--compiler","build/flex-llm");h_mkdir("build/llm");
    lm_compile_kernels(compiler,"build/llm");
    lm_start("build/llm",capacity);lw_load(directory);lw_rotary();lp_parse(b_option(argc,argv,"--model","libs/ml/examples/qwen3-inference.pup"));lm_prepare();
    i=0;while i<depth {let token=j_value(j_at(input,i));h_assert(token>=0 && token<lw_config_int("vocab_size"),"input token out of range");i=i+1;}
    i=0;while i<j_count(generated) {let token=j_value(j_at(generated,i));h_assert(token>=0 && token<lw_config_int("vocab_size"),"decode token out of range");i=i+1;}
    let prompt=h_vec();i=0;while i<depth {h_add(prompt,j_value(j_at(input,i)));i=i+1;}
    let mode=b_option(argc,argv,"--prefill","batch");h_assert(h_equal(mode,"batch") || h_equal(mode,"serial"),"--prefill must be batch or serial");
    if h_equal(mode,"batch") {lm_prompt_prepare(depth);}
    let report=j_object();j_set(report,"weight_storage",j_string(weight_mode));j_set(report,"prefill_mode",j_string(mode));j_set(report,"prefill_split",j_string(split));j_set(report,"prefill_block_threads",j_int(lm_prompt_block));lm_report_backend(report);j_set(report,"checkpoint",j_string(directory));
    j_set(report,"timing",j_string("synchronous model execution; excludes loading, compilation, sampling, logits download and printing"));
    j_set(report,"input_ids",input);j_set(report,"decode_token_cycle",generated);j_set(report,"prefill_tokens",j_int(depth));j_set(report,"decode_tokens",j_int(count));
    j_set(report,"context_capacity",j_int(capacity));j_set(report,"gpu_resident_bytes",j_int(lm_bytes));j_set(report,"warmup_runs",j_int(1));j_set(report,"kv_dtype",j_string("f32"));
    j_set(report,"fusion",j_int(lm_fusion));j_set(report,"kernel_count",j_int(h_count(lm_steps)));
    let samples=j_array();let run=0;
    while run<=repeats {
        let start=lm_now_us();if h_equal(mode,"batch") {lm_prefill(prompt);}else {i=0;while i<depth {lm_execute(j_value(j_at(input,i)),i,i==depth-1);i=i+1;}}let prefill_us=lm_now_us()-start;let prefill=prefill_us/1000;
        start=lm_now_us();i=0;while i<count {lm_execute(j_value(j_at(generated,i%j_count(generated))),depth+i,1);i=i+1;}let decode_us=lm_now_us()-start;let decode=decode_us/1000;
        if run {let sample=j_object();j_set(sample,"prefill_us",j_int(prefill_us));j_set(sample,"decode_us",j_int(decode_us));j_set(sample,"prefill_ms",j_int(prefill));j_set(sample,"decode_ms",j_int(decode));j_push(samples,sample);}
        h_print(2,h_cat3("Benchmark run ",h_int(run),h_cat3("; prefill ms ",h_int(prefill),h_cat3("; decode ms ",h_int(decode),"\n"))));run=run+1;
    }
    j_set(report,"samples",samples);j_save(b_option(argc,argv,"--report","build/llm/benchmark.json"),report);lm_close();return 0;
}
