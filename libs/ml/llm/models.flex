// Model catalog shared by selection, checkpoint discovery and downloads.
import "checkpoint.flex";
fn qm_valid(id) {return h_equal(id,"qwen3-1.7b") || h_equal(id,"qwen3-4b");}
fn qm_title(id) {if h_equal(id,"qwen3-4b") {return "Qwen3-4B";}return "Qwen3-1.7B";}
fn qm_manifest(id) {h_assert(qm_valid(id),"supported models: qwen3-1.7b, qwen3-4b");return j_parse(h_read(h_cat3("libs/ml/examples/",id,".model.json")));}
fn qm_config_id() {
    // The checkpoint reader accepts fractional/scientific config numbers;
    // the bounded application JSON reader intentionally accepts integers only.
    if !h_has(lw_config,"Qwen3ForCausalLM") || lw_config_int("head_dim")!=128 || lw_config_int("rope_theta")!=1000000 {return 0;}
    let width=lw_config_int("hidden_size");let layers=lw_config_int("num_hidden_layers");let inner=lw_config_int("intermediate_size");let heads=lw_config_int("num_attention_heads");let kv=lw_config_int("num_key_value_heads");
    if width==2048 && layers==28 && inner==6144 && heads==16 && kv==8 {return "qwen3-1.7b";}
    if width==2560 && layers==36 && inner==9728 && heads==32 && kv==8 {return "qwen3-4b";}return 0;
}
fn qm_detect(directory) {
    let file=h_join(directory,"config.json");if !h_exists(file) {return 0;}
    let previous=lw_config;lw_config=h_read(file);let id=qm_config_id();lw_config=previous;return id;
}
fn qm_ready(directory) {
    if !h_exists(h_join(directory,"config.json")) || !h_exists(h_join(directory,"tokenizer.json")) || !h_exists(h_join(directory,"model.safetensors.index.json")) {return 0;}
    let index=j_parse(h_read(h_join(directory,"model.safetensors.index.json")));let fields=j_value(j_need(index,"weight_map"));if !h_count(fields) {return 0;}
    let i=0;while i<h_count(fields) {let name=j_value(load64(h_at(fields,i)+8));if h_has(name,"/") || h_has(name,"..") || !h_exists(h_join(directory,name)) {return 0;}i=i+1;}return 1;
}
fn qm_matches(directory,id) {if !qm_ready(directory) {return 0;}let detected=qm_detect(directory);return detected && h_equal(detected,id);}
fn qm_directory(id) {
    let spec=j_need(qm_manifest(id),"checkpoint");let home=h_getenv("HOME");
    if home {let cached=h_join(home,h_cat3(".cache/puppygrad/models/",id,h_cat("/",j_s(spec,"revision"))));if qm_matches(cached,id) {return cached;}}
    let local=h_cat("build/llm/models/",id);if qm_matches(local,id) {return local;}
    let puppy=h_cat("../puppygrad/models/",id);if qm_matches(puppy,id) {return h_real(puppy);}return local;
}
