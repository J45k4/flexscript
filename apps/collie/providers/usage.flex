// Optional display metadata. Never infer tokens from bytes or sum past requests.
import "../lib/json.flex";

fn co_count(object,key) {
    if !object || j_kind(object)!=4 {return -1;}let n=j_get(object,key);
    if !n || j_kind(n)!=1 || j_value(n)<0 || j_value(n)>1000000000 {return -1;}return j_value(n);
}
fn co_usage(value) {
    let input=co_count(value,"input_tokens");let output=co_count(value,"output_tokens");if input<0 || output<0 {return 0;}
    let total=co_count(value,"total_tokens");if total<0 {total=input+output;}
    let result=j_object();j_set(result,"input_tokens",j_int(input));j_set(result,"output_tokens",j_int(output));j_set(result,"total_tokens",j_int(total));if c_flag(value,"estimated") {j_set(result,"estimated",j_bool(1));}return result;
}
fn co_model_limits(model,config) {
    // Same fallback and 95% usable / 90% compaction formulas as Codex.
    let window=co_count(model,"context_window");let maximum=co_count(model,"max_context_window");if window<=0 {window=maximum;}if window<=0 {window=272000;}if maximum<=0 {maximum=window;}
    let override=co_count(config,"model_context_window");if override>0 {window=override;if window>maximum {window=maximum;}}
    let percent=co_count(model,"effective_context_window_percent");if percent<=0 || percent>100 {percent=95;}
    let compact=window*9/10;let limit=co_count(model,"auto_compact_token_limit");let configured=co_count(config,"model_auto_compact_token_limit");if configured>0 {limit=configured;}if limit>=0 && limit<compact {compact=limit;}
    let result=j_object();j_set(result,"context_window",j_int(window));j_set(result,"max_context_window",j_int(maximum));j_set(result,"usable_context_window",j_int(window*percent/100));j_set(result,"auto_compact_token_limit",j_int(compact));j_set(result,"effective_context_window_percent",j_int(percent));return result;
}
fn co_model_info(config) {
    let fallback=j_object();j_set(fallback,"context_window",j_int(272000));let maximum=272000;if h_starts(j_s(config,"model"),"gpt-6") {maximum=872000;}j_set(fallback,"max_context_window",j_int(maximum));
    let result=co_model_limits(fallback,config);
    // Keep the default model on Codex's bundled short window (89461ea), even
    // when another Codex client has cached an expanded server-side window.
    // --context-window is the explicit opt-in to a larger window.
    if h_equal(j_s(config,"model"),"gpt-6.1-sol") {return result;}
    let path=h_join(h_dir(j_s(config,"auth_file")),"models_cache.json");let text=c_read(path,8388608);if !text {return result;}
    let cache=c_json(text);if j_kind(cache)!=4 {return result;}let models=j_get(cache,"models");if !models || j_kind(models)!=3 {return result;}
    let i=0;while i<j_count(models) {let model=j_at(models,i);let slug=c_string(model,"slug");if slug && h_equal(slug,j_s(config,"model")) {return co_model_limits(model,config);}i=i+1;}return result;
}
