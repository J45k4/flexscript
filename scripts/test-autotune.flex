import "lib/harness.flex";
import "../libs/autotune/tests/core.flex";
fn ac_call(binary,action,repo,config,output,extra) {let args=h_args(binary,action,"--repo",repo,"--config",config);h_add(args,"--output");h_add(args,output);if extra {let i=0;while i<h_count(extra) {h_add(args,h_at(extra,i));i=i+1;}}return h_run(args);}
fn ac_rejected(binary,repo,config,output,text) {let p=ac_call(binary,"generate",repo,config,output,0);t_assert(h_status(p)!=0 && h_has(h_err(p),text),h_cat("invalid config not rejected: ",text));return 0;}
fn suite(compiler) {
    t_init(compiler);h_timeout=300000;t_checks=ac_core();let repo=h_real(".");let binary=h_join(t_work,"autotune");h_compile(t_compiler,"scripts/autotune.flex",binary);let config=j_parse(h_read("libs/autotune/examples/gemm.json"));let config_path=h_join(t_work,"config with spaces.json");j_save(config_path,config);let output=h_join(t_work,"candidates with spaces");
    let old_path=h_getenv("PATH");h_setenv("PATH","/no-bun-python-or-build-tools");h_check(ac_call(binary,"generate",repo,config_path,output,0),0,0);h_setenv("PATH",old_path);let manifest_path=h_join(output,"manifest.json");let manifest=j_parse(h_read(manifest_path));t_assert(j_count(j_need(manifest,"candidates"))==2,"wrong production candidate count");
    h_check(ac_call(binary,"check",repo,config_path,output,0),0,0);t_checks=t_checks+1;let first=j_at(j_need(manifest,"candidates"),0);let source=j_s(first,"source");let image=j_s(first,"image");let bytes=h_read(source);h_ok(h_args(t_compiler,"--target","hip",source,"-o",image));t_checks=t_checks+1;
    h_check(ac_call(binary,"generate",repo,config_path,output,h_args("--sweep","compute",0,0,0,0)),0,0);manifest=j_parse(h_read(manifest_path));t_assert(j_count(j_need(manifest,"candidates"))==26,"wrong bounded sweep size");
    h_save(source,h_cat(bytes,"// changed\n"));let p=ac_call(binary,"check",repo,config_path,output,0);t_assert(h_status(p)!=0 && h_has(h_err(p),"generated kernel differs"),"source drift was not rejected");
    h_check(ac_call(binary,"generate",repo,config_path,output,0),0,0);manifest=j_parse(h_read(manifest_path));first=j_at(j_need(manifest,"candidates"),0);j_set(first,"sharedBytes",j_int(4));j_save(manifest_path,manifest);
    let extra=h_args("--manifest",manifest_path,"--compiler",t_compiler,0,0);p=ac_call(binary,"bench",repo,config_path,h_join(t_work,"results"),extra);t_assert(h_status(p)!=0 && h_has(h_err(p),"launch contract"),"manifest ABI drift was not rejected before execution");
    h_check(ac_call(binary,"generate",repo,config_path,output,0),0,0);extra=h_args("--manifest",manifest_path,"--compiler","/bin/false",0,0);p=ac_call(binary,"bench",repo,config_path,h_join(t_work,"failed build"),extra);t_assert(h_status(p)!=0 && h_has(h_err(p),"autotune child failed"),"compiler failure did not propagate");t_assert(h_exists(h_join(t_work,"failed build/build-bench.log")) && !h_exists(h_join(t_work,"failed build/results.json")),"failed build reported a result");
    config=j_parse(h_read("libs/autotune/examples/gemm.json"));j_set(j_at(j_need(config,"candidates"),0),"name",j_string("../escape"));j_save(config_path,config);ac_rejected(binary,repo,config_path,output,"invalid candidate name");
    config=j_parse(h_read("libs/autotune/examples/gemm.json"));j_set(j_at(j_need(config,"candidates"),0),"m",j_int(33));j_save(config_path,config);ac_rejected(binary,repo,config_path,output,"tile exceeds");
    config=j_parse(h_read("libs/autotune/examples/gemm.json"));j_set(j_at(j_need(config,"candidates"),1),"name",j_string("gemm-tiled"));j_save(config_path,config);ac_rejected(binary,repo,config_path,output,"duplicate candidate");
    config=j_parse(h_read("libs/autotune/examples/gemm.json"));j_set(j_at(j_need(config,"candidates"),0),"precision",j_string("fp16"));j_save(config_path,config);ac_rejected(binary,repo,config_path,output,"unsupported precision");
    return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
