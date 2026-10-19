// Exercise actual native branches beyond Xtensa J's signed 18-bit range.
import "lib/esp32-test.flex";
import "lib/esp32-elf.flex";
global tj_link=0;
global tj_ld=0;
global tj_baseline=0;
global tj_results=0;
fn tj_compile(compiler,source,target,path) {h_ok(h_args(compiler,"--target",target,source,"-o",path));return 0;}
fn tj_case(target,name,text,large) {
    te_legacy=!h_starts(target,"esp32s3");te_s3_sdk=h_equal(target,"esp32s3-sdk-elf");te_s3_xip=h_equal(target,"esp32s3-xip-elf");te_xip=!te_s3_sdk;
    let source=h_join(te_work,"case.flex");let elf=h_join(te_work,"native.elf");
    if te_xip {let module="lib/platform/esp32-xip.flex";if te_s3_xip {module="lib/platform/esp32s3-xip.flex";}text=h_cat3(h_cat3("import \"",h_absolute(module),"\";"),text,"");}
    h_save(source,text);tj_compile(te_compiler,source,target,elf);let digest=h_sha(elf);tj_compile(te_compiler,source,target,elf);te_assert(h_equal(digest,h_sha(elf)),"deterministic relaxed branches");
    let bytes=h_read(elf);let parsed=ee_open(bytes,h_file_size);let section=".text";if te_xip {section=".flex.irom";}let code=ee_section(parsed,section);let size=ee_u32(code+20);
    if large {te_assert(size>131072,"fixture crosses the short-jump range");}
    if tj_baseline {
        let old=h_join(te_work,"old.elf");let result=h_run(h_args(tj_baseline,"--target",target,source,"-o",old));
        if large {h_check(result,1,0);te_assert(h_has(h_err(result),"Xtensa jump out of range"),h_err(result));}
        else {h_check(result,0,0);te_assert(h_equal(h_sha(old),digest),"compact native output remains byte-identical");}
    }
    let a=h_args(tj_link,"--firmware",elf,"--output",h_join(te_work,"linked.elf"),"--ld");h_add(a,tj_ld);h_add(a,"--rom");h_add(a,h_join(te_work,"empty.ld"));if te_xip {h_add(a,"--xip");}h_add(a,"--image");h_add(a,te_binary);h_ok(a);te_run(te_binary,0,0);
    let row=j_object();j_set(row,"target",j_string(target));j_set(row,"case",j_string(name));j_set(row,"native_bytes",j_int(size));j_set(row,"elf_sha256",j_string(digest));j_push(tj_results,row);h_print(1,h_cat3(h_cat3(target," ",name),": passed\n",""));return 0;
}
// Independent FIR1 records also exercise the final instruction and crossing
// edges that require more than one relaxation pass (6-byte constants).
fn tj_fir(instructions) {
    let size=132+instructions*16;let p=h_take(size);
    store64(p,0x31524946);store64(p+8,size);store64(p+16,1);store64(p+24,128);store64(p+32,instructions*16);store64(p+40,size-4);store64(p+48,4);store64(p+72,4);h_copy(p+size-4,"main",4);store64(p+128,18);return p;
}
fn tj_ir(target,name,p,large) {
    te_legacy=!h_starts(target,"esp32s3");te_s3_sdk=h_equal(target,"esp32s3-sdk-elf");te_s3_xip=h_equal(target,"esp32s3-xip-elf");te_btdm=h_equal(target,"esp32-btdm-elf");te_xip=te_s3_xip || te_btdm || h_equal(target,"esp32-xip-elf");
    let source=h_join(te_work,"case.fir");h_save_bytes(source,p,load64(p+8),420);let elf=h_join(te_work,"native.elf");let a=h_args(te_compiler,"--language","ir","--target",target,0);if te_xip {let module="lib/platform/esp32-xip.flex";if te_s3_xip {module="lib/platform/esp32s3-xip.flex";}h_add(a,"--platform");h_add(a,h_absolute(module));}h_add(a,source);h_add(a,"-o");h_add(a,elf);h_ok(a);
    let bytes=h_read(elf);let parsed=ee_open(bytes,h_file_size);let section=".text";if te_xip {section=".flex.irom";}let size=ee_u32(ee_section(parsed,section)+20);if large {te_assert(size>131072,"crossing FIR edges span short-jump range");}
    let link=h_args(tj_link,"--firmware",elf,"--output",h_join(te_work,"linked.elf"),"--ld");h_add(link,tj_ld);h_add(link,"--rom");h_add(link,h_join(te_work,"empty.ld"));if te_xip {h_add(link,"--xip");}h_add(link,"--image");h_add(link,te_binary);h_ok(link);te_run(te_binary,0,0);
    let row=j_object();j_set(row,"target",j_string(target));j_set(row,"case",j_string(name));j_set(row,"native_bytes",j_int(size));j_set(row,"elf_sha256",j_string(h_sha(elf)));j_push(tj_results,row);h_print(1,h_cat3(h_cat3(target," ",name),": passed\n",""));return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"requires --compiler PATH [--qemu PATH] [--ld PATH] [--baseline PATH] [--report PATH]");te_init(compiler);te_qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));tj_ld=b_option(argc,argv,"--ld","xtensa-esp32-elf-ld");tj_baseline=b_option(argc,argv,"--baseline",0);if tj_baseline {tj_baseline=h_real(tj_baseline);}tj_results=j_array();tj_link=h_join(te_work,"link");h_compile(te_compiler,"scripts/esp32-link.flex",tj_link);h_save(h_join(te_work,"empty.ld"),"/* No vendor objects or ROM imports. */\n");
    let body=h_repeat("x=x+1;",1800);let sum=h_cat3("0",h_repeat("+x",2200),"+1/x");let targets=h_args("esp32s3-sdk-elf","esp32-xip-elf","esp32s3-xip-elf",0,0,0);let i=0;
    while i<h_count(targets) {
        let target=h_at(targets,i);
        tj_case(target,"compact","fn main(){let x=0;while x<3 {x=x+1;if x==1 {x=x+0;}}return x-3;}",0);
        tj_case(target,"forward-fallthrough",h_cat3("fn main(){let x=0;if x==0 {",body,"}return x-1800;}"),1);
        tj_case(target,"forward-taken",h_cat3("fn main(){let x=1;if x==0 {",body,"}return x-1;}"),1);
        tj_case(target,"else-skip",h_cat3("fn main(){let x=0;if x==0 {}else {",body,"}return x;}"),1);
        tj_case(target,"backward",h_cat3("fn main(){let x=0;while x<3600 {",body,"}return x-3600;}"),1);
        tj_case(target,"relocated-calls",h_cat3("fn add(n){return n+1;}fn cb(n){return n+7;}fn main(){let x=0;while x<3600 {",body,"let f=esp32_callback(cb);if esp32_call(f,x)!=x+7 {return 9;}x=add(x);}return x-3602;}"),1);
        tj_case(target,"short-circuit-or",h_cat3("fn main(){let x=0;return (1||(",sum,"))-1;}"),1);
        tj_case(target,"short-circuit-and",h_cat3("fn main(){let x=0;return 0&&(",sum," );}"),1);
        i=i+1;
    }
    let terminal=tj_fir(6);let code=terminal+128;store64(code+16,1);store64(code+32,10);store64(code+40,80);store64(code+48,1);store64(code+64,9);store64(code+80,10);store64(code+88,48);
    let profiles=h_args("esp32-elf","esp32s3-elf","esp32-radio-elf","esp32-btdm-elf","esp32-xip-elf","esp32s3-sdk-elf");h_add(profiles,"esp32s3-xip-elf");i=0;while i<h_count(profiles) {tj_ir(h_at(profiles,i),"terminal-jump",terminal,0);i=i+1;}
    let n=21844;let cascade=tj_fir(n+9);code=cascade+128;store64(code+16,1);store64(code+32,1);store64(code+48,11);store64(code+56,(n+5)*16);store64(code+64,10);store64(code+72,(n+7)*16);let j=0;while j<n {store64(code+80+j*16,1);j=j+1;}store64(code+(n+5)*16,1);store64(code+(n+6)*16,9);store64(code+(n+7)*16,1);store64(code+(n+8)*16,9);
    i=0;while i<h_count(targets) {store64(code+(n+5)*16+8,0);store64(code+(n+7)*16+8,1);tj_ir(h_at(targets,i),"cascaded-zero",cascade,1);store64(code+40,1);store64(code+(n+5)*16+8,1);store64(code+(n+7)*16+8,0);tj_ir(h_at(targets,i),"cascaded-one",cascade,1);store64(code+40,0);i=i+1;}
    let report=b_option(argc,argv,"--report",0);if report {let r=j_object();j_set(r,"pass",j_bool(1));j_set(r,"checks",j_int(te_checks));j_set(r,"ROM_boots",j_int(te_runs));j_set(r,"cases",tj_results);j_set(r,"physical_hardware",j_bool(0));j_set(r,"emulator_implementation_changes",j_bool(0));j_save(report,r);}h_print(1,"PASS: distant ESP32/S3 branches and compact-output parity\n");te_done();return 0;
}
