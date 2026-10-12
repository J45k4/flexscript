// Resident chat worker. JSON-lines isolate inference failures from the terminal.
import "capacity.flex";
import "tokenizer.flex";
global ct_demo=0;
global ct_rng=1;
global ct_memory_plan=0;
global ct_memory_reserve=0;
fn ct_event(kind) {let e=j_object();j_set(e,"event",j_string(kind));return e;}
fn ct_send(e) {h_print(1,j_dump(e));h_print(1,"\n");return 0;}
fn ct_status(text) {let e=ct_event("status");j_set(e,"text",j_string(text));return ct_send(e);}
fn ct_progress(text,done,total) {let e=ct_event("progress");j_set(e,"text",j_string(text));j_set(e,"completed",j_int(done));j_set(e,"total",j_int(total));return ct_send(e);}
fn ct_line() {
    let b=h_buffer();let byte=h_take(1);while 1 {let n=syscall(0,0,byte,1,0,0,0);if n==-4 {}else if n<=0 {return 0;}else if load8(byte)==10 {return h_data(b);}else {if h_size(b)>=4194304 {return 0;}h_append(b,byte,1);}}return 0;
}
fn ct_cancelled() {
    let poll=h_take(8);store64(poll,1<<32);if syscall(7,poll,1,0,0,0,0)>0 {let line=ct_line();if !line {return 1;}let e=j_parse(line);return h_equal(j_s(e,"op"),"cancel");}return 0;
}
fn ct_prompt(turns,start,thinking) {
    let out=h_buffer();let i=start;while i<j_count(turns) {let turn=j_at(turns,i);let role=j_s(turn,"role");h_assert(h_equal(role,"user") || h_equal(role,"assistant"),"invalid chat role");
        h_text(out,h_cat3("<|im_start|>",role,"\n"));let content=j_s(turn,"content");
        // Keep the seeded empty prefix: it avoids the reproduced greeting-only
        // greedy response. This replay policy differs from Qwen's Jinja template,
        // which strips older thinking blocks when rebuilding conversation history.
        if h_equal(role,"assistant") && !h_starts(content,"<think>") {h_text(out,"<think>\n\n</think>\n\n");}
        h_text(out,content);h_text(out,"<|im_end|>\n");i=i+1;}
    h_text(out,"<|im_start|>assistant\n");if !thinking {h_text(out,"<think>\n\n</think>\n\n");}return h_data(out);
}
fn ct_order(bits) {if bits&2147483648 {return (~bits)&4294967295;}return bits^2147483648;}
fn ct_sample(logits,n,temperature) {
    let ids=h_take(40*8);let scores=h_take(40*8);let count=0;let i=0;
    while i<n {let bits=gpu_load_u32(logits+i*4);h_assert((bits&2147483647)<2139095040,"nonfinite model logit");let key=ct_order(bits);
        if count<40 || key>load64(scores+39*8) {let at=count;if at>=40 {at=39;}
            while at>0 && key>load64(scores+(at-1)*8) {store64(scores+at*8,load64(scores+(at-1)*8));store64(ids+at*8,load64(ids+(at-1)*8));at=at-1;}
            store64(scores+at*8,key);store64(ids+at*8,i);if count<40 {count=count+1;}}
        i=i+1;}
    if !temperature {return load64(ids);}
    let weights=h_take(40*8);let best=gpu_f32_unpack(gpu_load_u32(logits+load64(ids)*4));let total=0;i=0;
    while i<count {let value=gpu_f32_unpack(gpu_load_u32(logits+load64(ids+i*8)*4));let weight=f64_exp(f64_div(f64_sub(value,best),f64_div(f64_from_i64(temperature),f64_from_i64(1000))));store64(weights+i*8,weight);total=f64_add(total,weight);i=i+1;}
    ct_rng=ct_rng^(ct_rng<<13);ct_rng=ct_rng^(ct_rng>>7);ct_rng=ct_rng^(ct_rng<<17);let random=f64_div(f64_from_i64(ct_rng&0x1fffffffffffff),f64_from_i64(0x20000000000000));let target=f64_mul(total,random);let cumulative=0;i=0;
    while i<count-1 {cumulative=f64_add(cumulative,load64(weights+i*8));if f64_lt(target,cumulative) {return load64(ids+i*8);}i=i+1;}return load64(ids+(count-1)*8);
}
fn ct_generate(request) {
    let turns=j_need(request,"turns");let thinking=j_n(request,"thinking");let maximum=j_n(request,"max_tokens");let temperature=j_n(request,"temperature");
    h_assert(j_count(turns)>0 && j_count(turns)%2==1 && maximum>=0 && maximum<ll_context_max() && temperature>=0 && temperature<=2000,"invalid generation request");
    let started=lm_now_us();let generated=j_array();let output=h_buffer();let first=0;let cancelled=0;let reason="limit";let count=0;
    if ct_demo {let text="This is the demo chat worker. Streaming, editing, saved conversations and cancellation work without loading a GPU model.";if thinking {text=h_cat("<think>Demo reasoning is synthetic.</think>\n\n",text);}let i=0;
        while load8(text+i) && !cancelled {if ct_cancelled() {cancelled=1;reason="cancelled";}else {let e=ct_event("token");j_set(e,"text",j_string(h_slice(text+i,1)));ct_send(e);h_text(output,h_slice(text+i,1));i=i+1;count=count+1;h_sleep(8);}}
    }else {
        let start=0;let tokens=0;let reserve=maximum;if !reserve || reserve>lm_capacity/2 {reserve=lm_capacity/2;}
        let searching=1;while searching {qt_limit=lm_capacity-1;tokens=qt_encode_bounded(ct_prompt(turns,start,thinking));if !qt_overflow && h_count(tokens)+reserve<=lm_capacity {searching=0;}
            else if start+2<j_count(turns) {start=start+2;}else {searching=0;}}
        if qt_overflow || h_count(tokens)>=lm_capacity {let e=ct_event("error");j_set(e,"text",j_string("This prompt exceeds the context. Shorten it or increase --context."));ct_send(e);return 0;}
        let memory=device_memory_info();lm_check(device_status);let budget=load64(memory)-ct_memory_reserve;syscall(11,memory,16,0,0,0,0);
        if cap_scratch(ct_memory_plan,h_count(tokens))>budget {let e=ct_event("error");j_set(e,"text",j_string("Not enough free GPU memory for this prompt. Close another GPU app, shorten the prompt or reload the model."));ct_send(e);return 0;}
        let available=lm_capacity-h_count(tokens);if !maximum || maximum>=available {maximum=available;reason="context";}
        let archived=0;let offset=j_get(request,"history_offset");if offset {archived=j_value(offset);}let usage=ct_event("context");j_set(usage,"prompt_tokens",j_int(h_count(tokens)));j_set(usage,"trimmed_turns",j_int(start/2+archived));j_set(usage,"max_tokens",j_int(maximum));ct_send(usage);
        ct_status("Prefilling conversation");lm_prefill(tokens);let prefill=lm_now_us()-started;let logits=h_take(lm_output_size*4);let position=h_count(tokens);
        let generating=1;while count<maximum && generating {
            if ct_cancelled() {cancelled=1;reason="cancelled";generating=0;}else {
            let id=0;if !temperature {id=lm_sample_greedy();}else {lm_check(device_download(logits,lm_output,lm_output_size*4));id=ct_sample(logits,lm_output_size,temperature);}j_push(generated,j_int(id));count=count+1;if !first {first=lm_now_us()-started;}
            if id==151645 || id==151643 {reason="eos";generating=0;}
            else {let piece=qt_decode(id);h_text(output,h_data(piece));let e=ct_event("token");j_set(e,"id",j_int(id));j_set(e,"text",j_string(h_data(piece)));ct_send(e);
            if count<maximum {lm_execute(id,position,1);position=position+1;}}}
        }
        let e=ct_event("done");lm_report_backend(e);j_set(e,"prefill_us",j_int(prefill));let input=j_array();let i=0;while i<h_count(tokens) {j_push(input,j_int(h_at(tokens,i)));i=i+1;}j_set(e,"input_ids",input);j_set(e,"generated_ids",generated);
        j_set(e,"tokens",j_int(count));j_set(e,"elapsed_us",j_int(lm_now_us()-started));j_set(e,"first_token_us",j_int(first));j_set(e,"reason",j_string(reason));j_set(e,"text",j_string(h_data(output)));ct_send(e);return 0;
    }
    let e=ct_event("done");j_set(e,"tokens",j_int(count));j_set(e,"elapsed_us",j_int(lm_now_us()-started));j_set(e,"first_token_us",j_int(0));j_set(e,"reason",j_string(reason));j_set(e,"text",j_string(h_data(output)));ct_send(e);return 0;
}
fn ct_worker(argc,argv) {
    lm_progress_json=1;
    ct_demo=lw_int(b_option(argc,argv,"--demo","0"));lm_select_backend(b_option(argc,argv,"--backend",lm_default_backend()));lm_device_ordinal=lw_int(b_option(argc,argv,"--device","0"));
    ct_rng=net_now()^syscall(39,0,0,0,0,0,0);if !ct_rng {ct_rng=1;}
    let setting=b_option(argc,argv,"--context","auto");let automatic=h_equal(setting,"auto");let capacity=ll_context_max();if !automatic {capacity=lw_int(setting);}h_assert(capacity>=32 && capacity<=ll_context_max(),"context must be auto or 32..40960");
    if !ct_demo {let weight=b_option(argc,argv,"--weights","f16");h_assert(h_equal(weight,"bf16") || h_equal(weight,"f16") || h_equal(weight,"f16-tiled"),"invalid weights");lm_weight_format=h_equal(weight,"f16");if h_equal(weight,"f16-tiled") {lm_weight_format=2;}
        let directory=b_option(argc,argv,"--checkpoint",0);h_assert(directory,"provide checkpoint");ct_status("Planning GPU memory");let model=b_option(argc,argv,"--model","libs/ml/examples/qwen3-inference.pup");let args=h_args(h_real(load64(argv)),"--capacity-plan",directory,"--weights",weight,"--model");h_add(args,model);let p=h_run(args);h_assert(!h_status(p),h_err(p));ct_memory_plan=j_parse(h_out(p));
        ct_status("Compiling GPU kernels");lm_compile_kernels(b_option(argc,argv,"--compiler",lm_default_compiler()),"build/llm");
        ct_status("Loading tokenizer");qt_open(h_join(directory,"tokenizer.json"));ct_status("Initializing GPU");lm_start("build/llm",32);
        ct_status("Sizing context from free GPU memory");
        let memory=device_memory_info();lm_check(device_status);ct_memory_reserve=cap_reserve(load64(memory+8));let budget=load64(memory)-ct_memory_reserve;syscall(11,memory,16,0,0,0,0);
        if automatic {capacity=cap_pick(ct_memory_plan,budget,j_n(ct_memory_plan,"max_context"));}else if capacity>j_n(ct_memory_plan,"max_context") || cap_bytes(ct_memory_plan,capacity)>budget {capacity=0;}
        if !capacity {let e=ct_event("error");j_set(e,"text",j_string("Insufficient free GPU memory for the model and context, including working space. Close another GPU app or use --context auto."));ct_send(e);lm_close();return 0;}
        lm_capacity=capacity;ct_status("Loading model weights");lw_load(directory);memory=device_memory_info();lm_check(device_status);budget=load64(memory)+lm_bytes-ct_memory_reserve;syscall(11,memory,16,0,0,0,0);
        if automatic {capacity=cap_pick(ct_memory_plan,budget,capacity);}else if cap_bytes(ct_memory_plan,capacity)>budget {capacity=0;}
        if !capacity {let e=ct_event("error");j_set(e,"text",j_string("Available GPU memory changed while loading; close another GPU app and retry."));ct_send(e);lm_close();return 0;}
        lm_capacity=capacity;lw_rotary();ct_status("Preparing execution graph");lp_parse(model);lm_sampling_enabled=1;lm_prepare();
        ct_status("Warming model");lm_execute(0,0,1);
    }
    else {let i=0;while i<=4 {ct_progress("Loading demo model",i,4);h_sleep(100);i=i+1;}ct_status("Warming demo worker");h_sleep(150);}
    if ct_demo {lm_capacity=capacity;}let ready=ct_event("ready");lm_report_backend(ready);j_set(ready,"resident_bytes",j_int(lm_bytes));j_set(ready,"context_capacity",j_int(lm_capacity));j_set(ready,"memory_reserve_bytes",j_int(ct_memory_reserve));ct_send(ready);
    let running=1;while running {let mark=h_mark();let line=ct_line();if !line {running=0;}else {let request=j_parse(line);let op=j_s(request,"op");
        if h_equal(op,"generate") {ct_generate(request);if !ct_demo {lm_prompt_clear();}let idle=ct_event("idle");j_set(idle,"resident_bytes",j_int(lm_bytes));let buffers=0;if !ct_demo {buffers=h_count(lm_buffers);}j_set(idle,"buffer_count",j_int(buffers));ct_send(idle);}
        else if h_equal(op,"shutdown") {running=0;}}
        h_reset(mark);
    }
    if !ct_demo {lm_close();}return 0;
}
