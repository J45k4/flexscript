// Validate the real Pup recipe and compiler diagnostics without CUDA/weights.
import "../pup.flex";
fn lt_weight(name,rows,width) {let v=lm_value(1,lm_alloc(rows*width*2),rows*width,width);store64(v+32,rows);j_set(lw_tensors,name,v);return 0;}
fn lt_plan_fixture() {
    lm_dry_run=1;lm_start("",16);lm_table=lm_alloc(16*512);lw_tensors=j_object();
    lw_config="{\"num_hidden_layers\":2,\"rms_norm_eps\":1e-6,\"vocab_size\":64}";
    lt_weight("model.embed_tokens.weight",64,256);lt_weight("model.norm.weight",1,256);j_set(lw_tensors,"lm_head.weight",lw_weight("model.embed_tokens.weight"));let i=0;
    while i<2 {let p=h_cat3("model.layers.",h_int(i),".");lt_weight(h_cat(p,"input_layernorm.weight"),1,256);lt_weight(h_cat(p,"post_attention_layernorm.weight"),1,256);
        lt_weight(h_cat(p,"self_attn.q_proj.weight"),256,256);lt_weight(h_cat(p,"self_attn.k_proj.weight"),128,256);lt_weight(h_cat(p,"self_attn.v_proj.weight"),128,256);
        lt_weight(h_cat(p,"self_attn.q_norm.weight"),1,128);lt_weight(h_cat(p,"self_attn.k_norm.weight"),1,128);lt_weight(h_cat(p,"self_attn.o_proj.weight"),256,256);
        lt_weight(h_cat(p,"mlp.gate_proj.weight"),512,256);lt_weight(h_cat(p,"mlp.up_proj.weight"),512,256);lt_weight(h_cat(p,"mlp.down_proj.weight"),256,512);i=i+1;}
    return 0;
}
fn lt_plan_bad(which) {
    lt_plan_fixture();let text=h_read("libs/ml/examples/qwen3-inference.pup");
    if h_equal(which,"weight") {text=h_replace(text,"model.norm.weight","missing.weight");}
    else if h_equal(which,"shape") {text=h_replace(text,"self_attn.q_proj.weight","self_attn.q_norm.weight");}
    else if h_equal(which,"element") {text=h_replace(text,"gate * up","gate * x");}
    else if h_equal(which,"operation") {text=h_replace(text,"silu(","unknown(");}
    else if h_equal(which,"output") {text=h_cat(text,"x = x\n");}
    else if h_equal(which,"ratio") {lt_weight("model.layers.0.self_attn.q_proj.weight",384,256);}
    else if h_equal(which,"loop") {lw_config="{\"num_hidden_layers\":129,\"rms_norm_eps\":1e-6,\"vocab_size\":64}";}
    else {h_die("unknown rejection fixture");}
    let path=h_cat3("build/llm/reject-",which,".pup");h_save(path,text);lp_parse(path);h_die("invalid Pup unexpectedly accepted");return 0;
}
fn lt_plan_test(executable) {
    lt_plan_fixture();lp_parse("libs/ml/examples/qwen3-inference.pup");h_assert(h_count(lm_steps)==43 && lm_output_size==64,"static layer graph expansion differs");
    lm_prepare();h_assert(h_count(lm_steps)==25,"fused schedule expansion differs");let fused=0;let pairs=0;let at=0;
    while at<h_count(lm_steps) {let step=h_at(lm_steps,at);if load64(step)==7 {h_assert(load64(step+64) && load64(step+32)!=load64(step+64),"fusion must retain both graph outputs");fused=fused+1;}else if load64(step)==8 {pairs=pairs+1;}at=at+1;}
    h_assert(fused==4 && pairs==2,"expected graph fusions missing");lm_fuse();h_assert(h_count(lm_steps)==25,"schedule fusion must be idempotent");lt_checks=lt_checks+1;
    let names=h_args("weight","shape","element","operation","output","ratio");h_add(names,"loop");let messages=h_args("missing checkpoint tensor","linear weight shape mismatch","elementwise shape mismatch","unsupported model operation","output must be the final declaration","attention head ratio");h_add(messages,"invalid layer count");let i=0;
    while i<h_count(names) {let result=h_run(h_args(executable,"--reject-case",h_at(names,i),0,0,0));h_check(result,1,0);h_assert(h_has(h_err(result),h_at(messages,i)),h_err(result));lt_checks=lt_checks+1;i=i+1;}
    lm_dry_run=0;return 0;
}
