// Native frame compaction: source slot identities survive argument lowering.
import "lib/esp32-test.flex";
import "lib/esp32-elf.flex";
global tc_link=0;
global tc_ld=0;
global tc_baseline=0;
global tc_results=0;
global tc_object=0;
global tc_trapped=0;
fn tc_flags(target) {te_legacy=!h_starts(target,"esp32s3");te_btdm=h_equal(target,"esp32-btdm-elf");te_s3_sdk=h_equal(target,"esp32s3-sdk-elf");te_s3_xip=h_equal(target,"esp32s3-xip-elf");te_xip=te_btdm || te_s3_xip || h_equal(target,"esp32-xip-elf");return 0;}
fn tc_args(compiler,source,target,language,path) {
    let a=h_args(compiler,"--target",target,0,0,0);
    if language {h_add(a,"--language");h_add(a,language);if te_xip {let module="lib/platform/esp32-xip.flex";if te_s3_xip {module="lib/platform/esp32s3-xip.flex";}h_add(a,"--platform");h_add(a,h_absolute(module));}}
    h_add(a,source);h_add(a,"-o");h_add(a,path);return a;
}
fn tc_native_size(path,elf) {let bytes=h_read(path);if elf {let parsed=ee_open(bytes,h_file_size);let name=".text";if te_xip {name=".flex.irom";}let section=ee_section(parsed,name);te_assert(section!=0,"native code section");return ee_u32(section+20);}return te_u32(bytes+28);}
fn tc_run(target,name,source,language,baseline_mode) {
    tc_flags(target);let elf=h_has(target,"-elf");let path=te_binary;if elf {path=h_join(te_work,"native.elf");}
    h_ok(tc_args(te_compiler,source,target,language,path));let digest=h_sha(path);let size=tc_native_size(path,elf);h_ok(tc_args(te_compiler,source,target,language,path));te_assert(h_equal(digest,h_sha(path)),"deterministic compact locals");
    let before=0;if tc_baseline {let old=h_join(te_work,"old");h_save(old,"preserve baseline destination");let old_digest=h_sha(old);let p=h_run(tc_args(tc_baseline,source,target,language,old));
        if baseline_mode==1 {h_check(p,1,0);te_assert(h_has(h_err(p),"function frame exceeds 16 KiB"),h_err(p));te_assert(h_equal(old_digest,h_sha(old)),"oversized baseline frame preserves output");}
        else {h_check(p,0,0);before=tc_native_size(old,elf);if baseline_mode==2 {te_assert(size<before,"unused stores reduce actual native code size");}else {te_assert(h_equal(digest,h_sha(old)),"all-read local layout remains byte-identical");}}
    }
    if elf {let a=h_args(tc_link,"--firmware",path,"--output",h_join(te_work,"linked.elf"),"--ld");h_add(a,tc_ld);h_add(a,"--rom");h_add(a,h_join(te_work,"empty.ld"));if te_xip {h_add(a,"--xip");}if tc_object {h_add(a,"--object");h_add(a,tc_object);}h_add(a,"--image");h_add(a,te_binary);h_ok(a);}te_run(te_binary,tc_trapped,0);
    let row=j_object();j_set(row,"target",j_string(target));j_set(row,"case",j_string(name));j_set(row,"native_bytes",j_int(size));j_set(row,"baseline_native_bytes",j_int(before));j_set(row,"sha256",j_string(digest));j_push(tc_results,row);h_print(1,h_cat3(h_cat3(target," ",name),": passed\n",""));return 0;
}
fn tc_source(target,name,text,mode) {tc_flags(target);if te_xip {let module="lib/platform/esp32-xip.flex";if te_s3_xip {module="lib/platform/esp32s3-xip.flex";}text=h_cat(h_cat3("import \"",h_absolute(module),"\";"),text);}let path=h_join(te_work,"locals.flex");h_save(path,text);return tc_run(target,name,path,0,mode);}
fn tc_fir(slots,instructions) {
    let size=132+instructions*16;let p=h_take(size);store64(p,0x31524946);store64(p+8,size);store64(p+16,1);store64(p+24,128);store64(p+32,instructions*16);store64(p+40,size-4);store64(p+48,4);store64(p+72,4);store64(p+96,slots);h_copy(p+size-4,"main",4);store64(p+128,18);store64(p+136,slots);store64(p+144,1);return p;
}
// Reuse one stack frame after writing a nonzero word, so ROM-zeroed RAM
// cannot hide missing local initialization in the second callee.
fn tc_zero() {
    let p=h_take(510);store64(p,0x31524946);store64(p+8,510);store64(p+16,3);store64(p+24,256);store64(p+32,240);store64(p+40,496);store64(p+48,14);h_copy(p+496,"mainpoisonzero",14);
    store64(p+72,4);store64(p+128,4);store64(p+136,6);store64(p+144,80);store64(p+160,3000);store64(p+192,10);store64(p+200,4);store64(p+208,176);store64(p+224,3000);
    let c=p+256;store64(c,18);store64(c+16,1);store64(c+32,8);store64(c+40,1);store64(c+48,8);store64(c+56,2);store64(c+64,9);
    store64(c+80,18);store64(c+88,3000);store64(c+96,1);store64(c+112,1);store64(c+120,0xfedcba9876543210);store64(c+128,4);store64(c+136,2999);store64(c+144,3);store64(c+152,2999);store64(c+160,9);
    store64(c+176,18);store64(c+184,3000);store64(c+192,1);store64(c+208,3);store64(c+216,2999);store64(c+224,9);return p;
}
fn tc_ir(target,name,p,mode) {let path=h_join(te_work,"locals.fir");h_save_bytes(path,p,load64(p+8),420);return tc_run(target,name,path,"ir",mode);}
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"requires --compiler PATH [--qemu PATH] [--ld PATH] [--baseline PATH] [--report PATH]");te_init(compiler);te_qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));tc_ld=b_option(argc,argv,"--ld","xtensa-esp32-elf-ld");tc_baseline=b_option(argc,argv,"--baseline",0);if tc_baseline {tc_baseline=h_real(tc_baseline);}tc_results=j_array();tc_link=h_join(te_work,"link");h_compile(te_compiler,"scripts/esp32-link.flex",tc_link);h_save(h_join(te_work,"empty.ld"),"/* No vendor imports. */\n");
    let c=h_join(te_work,"sparse-callback.c");let oracle=h_join(te_work,"sparse-callback.o");h_save(c,"typedef unsigned int u32;typedef unsigned long long u64;typedef u64(*callback)(u32,u32,u32,u32,u32,u32,u32,u32);u64 compact_call(callback fn){return fn(3,0x81234567,5,0xfedcba98,7,0xffffffff,9,0x88776655);}");let gcc=b_option(argc,argv,"--gcc",h_cat(h_slice(tc_ld,h_len(tc_ld)-2),"gcc"));let ca=h_args(gcc,"-Os","-fno-optimize-sibling-calls","-mlongcalls","-mtext-section-literals","-c");h_add(ca,c);h_add(ca,"-o");h_add(ca,oracle);h_ok(ca);
    let dead=h_buffer();let i=0;while i<3000 {h_text(dead,h_cat3(h_cat3("let dead",h_int(i),"="),h_int(i),";"));i=i+1;}
    let sparse=h_cat3("fn main(){",h_data(dead),"return dead2999-2999;}");let effects=h_cat3("global count=0;fn touch(n){count=count+1;return n;}fn main(){let discarded=touch(19);discarded=touch(29);",h_data(dead),"if count!=2{return 1;}let p=alloc(8);discarded=store64(p,touch(0x1234567887654321));if count!=3||load64(p)!=0x1234567887654321{return 2;}return 0;}");
    let parameters=h_cat3("fn pick(a,b,c,d,e,f,g,h){",h_data(dead),"return b+(d<<32)^(f<<16)^h;}fn main(){return pick(3,0x81234567,5,0xfedcba98,7,0xffffffff,9,0x88776655)^(0x81234567+(0xfedcba98<<32)^(0xffffffff<<16)^0x88776655);}");
    let zero=tc_zero();
    let value=tc_fir(3000,9);let code=value+128;store64(code+32,1);store64(code+40,0xfedcba9876543210);store64(code+48,4);store64(code+56,2999);store64(code+64,2);store64(code+80,1);store64(code+88,0xfedcba9876543210);store64(code+96,7);store64(code+104,45);store64(code+112,9);store64(code+128,9);
    let callback=h_cat3("fn compact_cb(a,b,c,d,e,f,g,h){",h_data(dead),"return b+(d<<32)^(f<<16)^h;}fn main(){return esp32_call64(esp32_external(\"compact_call\"),esp32_callback32(compact_cb),0,0,0,0,0,0,0)^(0x81234567+(0xfedcba98<<32)^(0xffffffff<<16)^0x88776655);}");
    let limit=tc_fir(2048,2052);code=limit+128;i=0;while i<2048 {store64(code+32+i*16,3);store64(code+40+i*16,i);i=i+1;}store64(code+2050*16,1);store64(code+2051*16,9);
    let over=tc_fir(3000,2053);code=over+128;i=0;while i<2049 {store64(code+32+i*16,3);store64(code+40+i*16,i);i=i+1;}store64(code+2051*16,1);store64(code+2052*16,9);
    let small=h_buffer();i=0;while i<30 {h_text(small,h_cat3("let discarded",h_int(i),"=0;"));i=i+1;}
    let targets=h_args("esp32","esp32s3","esp32-elf","esp32s3-elf","esp32-radio-elf","esp32-btdm-elf");h_add(targets,"esp32-xip-elf");h_add(targets,"esp32s3-sdk-elf");h_add(targets,"esp32s3-xip-elf");i=0;
    while i<h_count(targets) {let target=h_at(targets,i);
        tc_source(target,"all-read-parity","fn add(a,b){let x=a+b;return x;}fn main(){let x=0;while x<12{x=add(x,1);}return x-12;}",0);
        tc_source(target,"sparse-last-slot",sparse,1);tc_source(target,"effects",effects,1);tc_source(target,"source-parameters",parameters,1);
        tc_source(target,"code-reduction",h_cat3("fn main(){",h_data(small),"return 0;}"),2);
        tc_ir(target,"zero-initialized",zero,1);tc_ir(target,"store-value",value,1);tc_ir(target,"live-frame-limit",limit,0);
        if h_has(target,"-elf") {tc_object=oracle;tc_source(target,"C-sparse-parameters",callback,1);tc_object=0;}
        let path=h_join(te_work,"over.fir");h_save_bytes(path,over,load64(over+8),420);h_save(te_binary,"preserve oversized live frame output");let saved=h_sha(te_binary);let result=h_run(tc_args(te_compiler,path,target,"ir",te_binary));h_check(result,1,0);te_assert(h_has(h_err(result),"function frame exceeds 16 KiB"),h_err(result));te_assert(h_equal(saved,h_sha(te_binary)),"live frame rejection preserves output");
        tc_trapped=1;tc_source(target,"discarded-load-traps","fn main(){let ignored=load8(0);return 0;}",2);tc_trapped=0;i=i+1;
    }
    let report=b_option(argc,argv,"--report",0);if report {let r=j_object();j_set(r,"pass",j_bool(1));j_set(r,"checks",j_int(te_checks));j_set(r,"ROM_boots",j_int(te_runs));j_set(r,"cases",tc_results);j_set(r,"physical_hardware",j_bool(0));j_set(r,"emulator_implementation_changes",j_bool(0));j_save(report,r);}h_print(1,"PASS: compact ESP32 locals, source parameters, zero initialization and RHS effects\n");te_done();return 0;
}
