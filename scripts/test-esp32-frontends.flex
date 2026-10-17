import "lib/esp32-test.flex";
global ts_linker=0;
global ts_ld=0;
global ts_rom=0;
global ts_language=0;
global ts_frontend=0;
global ts_platform=0;
fn ts_flags(target) {te_legacy=!h_starts(target,"esp32s3");te_btdm=h_equal(target,"esp32-btdm-elf");te_s3_sdk=h_equal(target,"esp32s3-sdk-elf");te_s3_xip=h_equal(target,"esp32s3-xip-elf");te_xip=te_btdm || h_equal(target,"esp32-xip-elf") || te_s3_xip;return 0;}
fn ts_cache_module() {if te_s3_xip {return h_absolute("lib/platform/esp32s3-xip.flex");}return h_absolute("lib/platform/esp32-xip.flex");}
fn ts_args(source,target,out) {
    let a=h_args(te_compiler,"--target",target,0,0,0);
    if ts_language {h_add(a,"--language");h_add(a,ts_language);}if ts_frontend {h_add(a,"--frontend");h_add(a,ts_frontend);}
    if ts_platform {h_add(a,"--esp32-platform");h_add(a,ts_platform);}h_add(a,source);h_add(a,"-o");h_add(a,out);return a;
}
fn ts_build(source,target) {
    ts_flags(target);if h_has(target,"-elf") {let native=h_join(te_work,"native.elf");h_ok(ts_args(source,target,native));let a=h_args(ts_linker,"--firmware",native,"--output",h_join(te_work,"linked.elf"),"--ld");h_add(a,ts_ld);h_add(a,"--rom");h_add(a,h_join(ts_rom,"esp32.rom.ld"));if te_xip {h_add(a,"--xip");}h_add(a,"--image");h_add(a,te_binary);h_ok(a);}else {h_ok(ts_args(source,target,te_binary));}return 0;
}
fn ts_bad(text,target,message) {let file=h_join(te_work,"bad.seta");h_save(file,h_cat("plugin esp32.negative v1 {}\n",text));h_save(te_binary,"preserve existing output");let before=h_sha(te_binary);let p=h_run(ts_args(file,target,te_binary));h_check(p,1,0);te_assert(h_has(h_err(p),message),h_err(p));te_assert(h_equal(before,h_sha(te_binary)),"frontend rejection preserves output");return 0;}
fn ts_source_plugin(source) {
    let file=h_join(te_work,"source-plugin.flex");let text=h_cat3("fn frontend_compile(text,size,version,path){let source=",j_dump(j_string(source)),";let n=");text=h_cat3(text,h_int(h_len(source)),";let p=alloc(64+n);store64(p,0x31585346);store64(p+8,64+n);store64(p+16,64);store64(p+24,n);let i=0;while i<n{store8(p+64+i,load8(source+i));i=i+1;}return p;}");h_save(file,text);return file;
}
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"requires --compiler PATH --ld PATH --rom DIRECTORY [--qemu PATH] [--report PATH]");te_init(compiler);te_qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));ts_ld=b_option(argc,argv,"--ld","xtensa-esp32-elf-ld");ts_rom=b_option(argc,argv,"--rom",0);h_assert(ts_rom,"requires --rom DIRECTORY");ts_linker=h_join(te_work,"link");h_compile(te_compiler,"scripts/esp32-link.flex",ts_linker);
    let state="tests/esp32/frontend-state.seta";let io="tests/esp32/frontend-io.seta";let targets=h_args("esp32","esp32s3","esp32-elf","esp32s3-elf","esp32-radio-elf","esp32-xip-elf");h_add(targets,"esp32-btdm-elf");h_add(targets,"esp32s3-sdk-elf");h_add(targets,"esp32s3-xip-elf");
    let native=h_join(te_work,"native");h_compile(te_compiler,state,native);h_check(h_run(h_args(native,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    let fir=h_join(te_work,"state.fir");h_ok(h_args(te_compiler,"--target","ir",state,"-o",fir));let saved=h_sha(fir);let i=0;
    while i<h_count(targets) {
        let target=h_at(targets,i);h_print(1,h_cat3("Frontend target: ",target,"\n"));ts_flags(target);ts_platform=0;if te_xip {ts_platform=ts_cache_module();}
        ts_build(state,target);te_run(te_binary,0,0);
        ts_language="ir";ts_build(fir,target);te_run(te_binary,0,0);ts_language=0;te_assert(h_equal(saved,h_sha(fir)),"target relocation preserves saved FIR");
        ts_build(io,target);te_image(te_binary);let a=h_args("python3","tests/esp32/frontend-peer.py","--qemu",te_qemu,"--image",te_binary);h_add(a,"--report");h_add(a,h_join(te_work,"uart-peer.json"));h_print(1,h_out(h_ok(a)));te_checks=te_checks+1;te_runs=te_runs+1;
        ts_platform=0;let reference="tests/esp32/frontend-state.flex";if te_xip {reference=h_join(te_work,"reference.flex");h_save(reference,h_cat3(h_cat3("import \"",ts_cache_module(),"\";import \""),h_absolute("tests/esp32/frontend-state.flex"),"\";"));}ts_build(reference,target);te_run(te_binary,0,0);i=i+1;
    }
    i=0;while i<h_count(targets) {let target=h_at(targets,i);ts_flags(target);ts_platform=h_absolute("tests/esp32/frontend-platform.flex");if te_xip {let adapter=h_join(te_work,"platform.flex");h_save(adapter,h_cat3(h_cat3("import \"",ts_cache_module(),"\";import \""),ts_platform,"\";"));ts_platform=adapter;}ts_build("tests/esp32/frontend-platform.seta",target);te_run(te_binary,0,0);i=i+1;}
    ts_platform=0;ts_frontend="examples/extensions/seta.flex";ts_build(state,"esp32");te_run(te_binary,0,0);ts_build(state,"esp32s3");te_run(te_binary,0,0);ts_frontend=0;
    ts_frontend=ts_source_plugin("fn main(){let state=esp32_state();let cycles=esp32_cycles();return state==0 || cycles==0;}");ts_build("examples/extensions/answer.postfix","esp32");te_run(te_binary,0,0);ts_build("examples/extensions/answer.postfix","esp32s3");te_run(te_binary,0,0);ts_frontend=0;
    i=0;while i<2 {let target="esp32";if i {target="esp32s3";}let index=h_args("-1","4","4294967296","9223372036854775807",0,0);let j=0;
        while j<h_count(index) {let source=h_join(te_work,"bounds.seta");let text=h_cat3("state {a:i32[4]=[1,2,3,4] guard:i32=99} fn main()->i32{return state.a[",h_at(index,j),"]}");h_save(source,h_cat("plugin esp32.bounds v1 {}\n",text));ts_build(source,target);te_run(te_binary,1,0);text=h_cat3("state {a:i32[4]=[1,2,3,4] guard:i32=99} fn main()->i32{state.a[",h_at(index,j),"]=7 return 0}");h_save(source,h_cat("plugin esp32.bounds v1 {}\n",text));ts_build(source,target);te_run(te_binary,1,0);j=j+1;}i=i+1;
    }
    ts_bad("state {a:i32[8192]=0} fn main()->i32{return state.a[0]}","esp32","static data exceeds 64 KiB");ts_bad("state {a:i32[4096]=0} fn main()->i32{return state.a[0]}","esp32-radio-elf","radio static data overlaps reserved");ts_bad("fn main()->i32{return 0}","esp32-xip-elf","requires esp_xip_enable");
    ts_bad("state {a:i32[2048]=0} fn main()->i32{return state.a[0]}","esp32s3-sdk-elf","static data exceeds 16 KiB");
    let adapter=h_join(te_work,"bad-platform.flex");ts_platform=adapter;h_save(adapter,"fn esp_platform_init(value){return 0;}");ts_bad("fn main()->i32{return 0}","esp32","esp_platform_init must take no parameters");
    h_save(adapter,"global main=0;");ts_bad("fn main()->i32{return 0}","esp32","duplicate global");h_save(adapter,"fn main(){return 0;}");ts_bad("fn main()->i32{return 0}","esp32","duplicate function");
    h_save(adapter,"fn esp_platform_init(){return -1;}");ts_build(state,"esp32");te_run(te_binary,1,0);ts_platform=0;
    let constant=h_join(te_work,"constant.seta");h_save(constant,"plugin esp32.constant v1 {} fn main()->i32{return 0}");let constant_ir=h_join(te_work,"constant.fir");h_ok(h_args(te_compiler,"--target","ir",constant,"-o",constant_ir));let hash=h_sha(constant_ir);
    ts_platform=adapter;h_save(adapter,h_cat3("fn esp_platform_init(){let x=0;",h_repeat("x=x+1;",200),"return x-200;}"));ts_build(constant,"esp32");te_run(te_binary,0,0);ts_language="ir";ts_build(constant_ir,"esp32s3");te_run(te_binary,0,0);te_assert(h_equal(hash,h_sha(constant_ir)),"native adapter append preserves FIR1 names/code");ts_language=0;ts_platform=0;
    // Profiles4-6 retain the same checked indexed operations and state layout.
    let blob=h_read(fir);let bytes=h_file_size;let profile=4;while profile<=6 {store64(blob,0x30524946+(profile<<24));let path=h_join(te_work,"profile.fir");h_save_bytes(path,blob,bytes,420);ts_language="ir";ts_platform=ts_cache_module();ts_build(path,"esp32-xip-elf");te_run(te_binary,0,0);ts_platform=0;ts_build(path,"esp32s3");te_run(te_binary,0,0);profile=profile+1;}ts_language=0;
    let scalar=h_join(te_work,"scalar.seta");h_save(scalar,"plugin esp32.scalar v1 {} state {count:i32=40} fn main()->i32{state.count+=2 return state.count-42}");ts_build(scalar,"esp32");te_run(te_binary,0,0);ts_build(scalar,"esp32s3");te_run(te_binary,0,0);
    let plugin=ts_source_plugin("fn main(){return esp32_cycles()==0;}");i=0;while i<h_count(targets) {let target=h_at(targets,i);ts_flags(target);ts_platform=0;if te_xip {ts_platform=ts_cache_module();}ts_frontend="examples/extensions/seta.flex";ts_build(state,target);te_run(te_binary,0,0);ts_frontend=plugin;ts_build("examples/extensions/answer.postfix",target);te_run(te_binary,0,0);i=i+1;}ts_frontend=0;ts_platform=0;
    h_save(adapter,"fn esp_platform_init(){return 0;}");ts_platform=adapter;let before=h_sha(adapter);let result=h_run(ts_args(state,"esp32",adapter));h_check(result,1,0);te_assert(h_has(h_err(result),"source and output refer to the same file") && h_equal(before,h_sha(adapter)),"native platform input alias is preserved");ts_platform=0;
    ts_frontend=plugin;before=h_sha(plugin);result=h_run(ts_args("examples/extensions/answer.postfix","esp32",plugin));h_check(result,1,0);te_assert(h_has(h_err(result),"frontend source file") && h_equal(before,h_sha(plugin)),"source frontend input alias is preserved");ts_frontend=0;
    let postfix=h_join(te_work,"zero.postfix");h_save(postfix,"6 7 * 42 -");ts_frontend="examples/extensions/postfix.flex";i=0;while i<h_count(targets) {let target=h_at(targets,i);ts_flags(target);ts_platform=0;if te_xip {ts_platform=ts_cache_module();}ts_build(postfix,target);te_run(te_binary,0,0);i=i+1;}ts_frontend=0;ts_platform=0;
    let objdump=b_option(argc,argv,"--objdump",h_cat(h_slice(ts_ld,h_len(ts_ld)-2),"objdump"));let model=h_args("python3","tests/esp32/frontend-uart-model.py","--compiler",te_compiler,"--objdump",objdump);h_add(model,"--report");h_add(model,b_option(argc,argv,"--uart-model-report",h_join(te_work,"uart-model.json")));h_print(1,h_out(h_ok(model)));te_checks=te_checks+1;
    let report=b_option(argc,argv,"--report",0);if report {let r=j_object();j_set(r,"checks",j_int(te_checks));j_set(r,"boots",j_int(te_runs));j_set(r,"targets",j_int(h_count(targets)));j_set(r,"physical_hardware",j_bool(0));j_save(report,r);}
    h_print(1,"SetaScript/FIR state, checked arrays, full64-bit UART words, all9 ESP32 output profiles and source frontend intrinsics passed\n");te_done();return 0;
}
