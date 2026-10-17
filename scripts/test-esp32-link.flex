// GNU-generated C/assembly are independent test oracles only. Production
// firmware/runtime code remains Flexscript; GNU ld relocates vendor objects.
import "lib/esp32-test.flex";
import "lib/esp32-elf.flex";
global tl_linker=0;
global tl_prefix=0;
global tl_cases=0;
global tl_case_count=0;
global tl_keep=0;
fn tl_tool_sha(path) {let result=h_out(h_ok(h_args("sha256sum","--",path,0,0,0)));h_assert(h_len(result)>=66,"invalid streaming tool checksum");return h_slice(result,64);}
fn tl_compile(source,target) {h_ok(h_args(te_compiler,"--target",target,source,"-o",te_fixture));return 0;}
fn tl_args(output,object,xip) {
    let a=h_args(tl_linker,"--firmware",te_fixture,"--output",output,"--ld");h_add(a,h_cat(tl_prefix,"ld"));if xip {h_add(a,"--xip");}
    if object {h_add(a,"--object");h_add(a,object);}return a;
}
fn tl_run(source,object,xip,expected) {
    h_print(1,h_cat3("Link test: ",source,"\n"));
    let target="esp32-elf";if xip {target="esp32-xip-elf";}if !xip && (h_has(source,"sdk-radio-resources") || h_has(source,"sdk-task-reap") || h_has(source,"sdk-runtime") || h_has(source,"sdk-heap") || h_has(source,"sdk-timers") || h_has(source,"sdk-priorities") || h_has(source,"sdk-preempt") || h_has(source,"sdk-queue") || h_has(source,"bluetooth-transport") || h_has(source,"wifi-runtime")) {target="esp32-radio-elf";}
    if h_has(source,"s3-sdk-") || h_has(source,"s3-radio-ownership") || h_has(source,"s3-adc-guards") {target="esp32s3-sdk-elf";te_legacy=0;te_s3_sdk=1;if h_has(source,"s3-sdk-preempt-ram") {target="esp32s3-elf";te_s3_sdk=0;}}
    if h_has(source,"s3-adc-api") {target="esp32s3-elf";te_legacy=0;te_s3_sdk=0;}
    if h_has(source,"btdm-memory") {target="esp32-btdm-elf";te_btdm=1;}tl_compile(source,target);let linked=h_join(te_work,"linked.elf");let args=tl_args(linked,object,xip);
    if h_has(source,"c-abi.flex") {h_add(args,"--object");h_add(args,h_join(te_work,"windows.o"));}
    if h_has(source,"sdk-masked-waits.flex") {h_add(args,"--object");h_add(args,h_join(te_work,"masked-waits.o"));}
    if h_has(source,"radio-event-preempt.flex") {h_add(args,"--object");h_add(args,h_join(te_work,"radio-event.o"));}
    if h_has(source,"wifi-control-preempt.flex") {h_add(args,"--object");h_add(args,h_join(te_work,"wifi-control.o"));}
    if h_has(source,"wifi-ownership-preempt.flex") {h_add(args,"--object");h_add(args,h_join(te_work,"wifi-ownership.o"));}
    if h_has(source,"phy-preempt.flex") {h_add(args,"--object");h_add(args,h_join(te_work,"phy-preempt.o"));}
    if h_has(source,"bt-transport-preempt") {h_add(args,"--object");h_add(args,h_join(te_work,"bt-concurrent.o"));}
    if h_has(source,"bluetooth-transport") {h_add(args,"--object");h_add(args,h_join(te_work,"bluetooth.o"));}
    if h_has(source,"radio-irq-publication.flex") {h_add(args,"--object");h_add(args,h_join(te_work,"irq-publication.o"));}
    if h_has(source,"sdk-wake-abi.flex") {h_add(args,"--object");h_add(args,h_join(te_work,"wake.o"));}
    if h_has(source,"sdk-preempt.flex") {let object_name="preempt.o";let state_name="preempt-state.o";if h_has(source,"s3-sdk-") {object_name="s3-preempt.o";state_name="s3-preempt-state.o";}h_add(args,"--object");h_add(args,h_join(te_work,object_name));h_add(args,"--object");h_add(args,h_join(te_work,state_name));}
    if h_has(source,"ble-adapter") {h_add(args,"--object");h_add(args,h_join(te_work,"ble-controller.o"));}
    h_add(args,"--image");h_add(args,te_binary);h_ok(args);te_xip=xip;let serial=te_run(te_binary,0,expected);
    if tl_keep {let directory=h_join(te_work,"cases");h_mkdir(directory);let stem=h_join(directory,h_int(tl_case_count));let elf_path=h_cat(stem,".elf");let image_path=h_cat(stem,".bin");let uart_path=h_cat(stem,".uart");let bytes=h_read(linked);h_save_bytes(elf_path,bytes,h_file_size,420);bytes=h_read(te_binary);h_save_bytes(image_path,bytes,h_file_size,420);h_save(uart_path,serial);
        let row=j_object();j_set(row,"source",j_string(source));j_set(row,"target",j_string(target));j_set(row,"cached_flash",j_bool(xip));j_set(row,"elf",j_string(elf_path));j_set(row,"image",j_string(image_path));j_set(row,"uart",j_string(uart_path));j_set(row,"elf_sha256",j_string(h_sha(elf_path)));j_set(row,"image_sha256",j_string(h_sha(image_path)));j_set(row,"uart_sha256",j_string(h_sha(uart_path)));j_push(tl_cases,row);tl_case_count=tl_case_count+1;
    }te_xip=0;te_btdm=0;te_s3_sdk=0;te_legacy=1;return 0;
}
fn tl_reject(args,message,output) {h_save(output,"preserve existing output");let before=h_sha(output);let r=h_run(args);h_check(r,1,0);te_assert(h_has(h_cat(h_out(r),h_err(r)),message),h_err(r));te_assert(h_equal(h_sha(output),before),"link rejection preserves destination");return 0;}
fn tl_radio_tooling(vendor,rom) {
    let original=h_join(vendor,"libwpa_supplicant.a");let visible=h_join(te_work,"wpa-visible.a");h_ok(h_args(h_cat(tl_prefix,"objcopy"),"--globalize-symbol=eloop_data_lock",original,visible,0,0));h_ok(h_args("python3","tests/esp32/vendor-lifecycle-visibility.py",original,visible,0,0));te_checks=te_checks+1;
    let objtool=h_join(te_work,"data-object");h_compile(te_compiler,"scripts/esp32-data-object.flex",objtool);let object=h_join(te_work,"radio-data.o");
    let a=h_args(objtool,"--symbol","g_wifi_osi_funcs","--size","484","--output");h_add(a,object);h_ok(a);let bytes=h_read(object);let elf=ee_open(bytes,h_file_size);let data=ee_section(elf,".data");
    te_assert(ee_u16(bytes+16)==1 && ee_u32(data+20)==484 && ee_u32(data+32)==4,"radio data is aligned ET_REL storage");te_assert(ee_find_symbol(elf,"g_wifi_osi_funcs")==1,"radio data exports its object symbol");let i=0;while i<484 {te_assert(!load8(ee_payload(elf,data)+i),"radio data starts zeroed");i=i+1;}
    a=h_args(objtool,"--symbol","bad-symbol","--output",object,0);tl_reject(a,"requires --symbol identifier",object);
    a=h_args(objtool,"--symbol","valid","--size","32769","--output");h_add(a,object);tl_reject(a,"requires --symbol identifier",object);
    let builder=h_join(te_work,"radio-build");h_compile(te_compiler,"scripts/build-esp32-radio.flex",builder);let image=h_join(te_work,"radio.bin");
    let base=h_args(builder,"--compiler",te_compiler,"--vendor",h_absolute(vendor),"--rom");h_add(base,h_absolute(rom));h_add(base,"--ld");h_add(base,h_cat(tl_prefix,"ld"));h_add(base,"--gcc");h_add(base,h_cat(tl_prefix,"gcc"));
    i=0;while i<2 {a=h_args(0,0,0,0,0,0);let j=0;while j<h_count(base) {h_add(a,h_at(base,j));j=j+1;}h_add(a,"--output");h_add(a,image);h_add(a,"--kind");let kind="wifi";if i {kind="bluetooth";}h_add(a,kind);h_ok(a);te_xip=1;te_btdm=i;te_image(image);te_xip=0;te_btdm=0;let linked=h_read(h_cat(image,".elf"));let profile=ee_profile(ee_open(linked,h_file_size));let expected=0x3ffb0000;if i {expected=0x3ffc0000;}te_assert(ee_u32(profile+12)==expected,"radio build selects controller-safe memory");i=i+1;}
    let source=h_join(te_work,"protected.flex");h_save(source,"fn main(){return 0;}");a=h_args(0,0,0,0,0,0);i=0;while i<h_count(base) {h_add(a,h_at(base,i));i=i+1;}h_add(a,"--source");h_add(a,source);h_add(a,"--output");h_add(a,source);tl_reject(a,"radio output aliases input",source);
    let wrong=h_join(te_work,"wrong-vendor");h_mkdir(wrong);h_save(h_join(wrong,"libcore.a"),"untrusted archive bytes");a=h_args(builder,"--compiler",te_compiler,"--vendor",wrong,"--rom");h_add(a,h_absolute(rom));h_add(a,"--output");h_add(a,image);h_add(a,"--ld");h_add(a,h_cat(tl_prefix,"ld"));h_add(a,"--gcc");h_add(a,h_cat(tl_prefix,"gcc"));tl_reject(a,"vendor archive checksum mismatch",image);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"requires --compiler PATH [--prefix xtensa-esp32-elf-]");te_init(compiler);te_legacy=1;tl_cases=j_array();let work=b_option(argc,argv,"--work",0);let report=b_option(argc,argv,"--report",0);
    if work {h_remove(te_work);h_mkdir(work);te_work=h_real(work);te_fixture=h_join(te_work,"test.flex");te_binary=h_join(te_work,"firmware.bin");tl_keep=1;}
    h_assert(!report || work,"--report requires --work to retain its executed firmware artifacts");
    te_qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));tl_prefix=b_option(argc,argv,"--prefix","xtensa-esp32-elf-");tl_linker=h_join(te_work,"link");h_compile(te_compiler,"scripts/esp32-link.flex",tl_linker);
    let policy=h_join(te_work,"priority-policy");let policy_args=h_args("python3","tests/esp32/sdk-priority-reference.py","--compiler",te_compiler,"--work",policy);h_add(policy_args,"--report");h_add(policy_args,h_join(te_work,"priority-policy.json"));h_ok(policy_args);te_checks=te_checks+1;
    let wake_policy=h_join(te_work,"wake-policy");let wake_args=h_args("python3","tests/esp32/sdk-wake-reference.py","--compiler",te_compiler,"--work",wake_policy);h_add(wake_args,"--report");h_add(wake_args,h_join(te_work,"wake-policy.json"));h_ok(wake_args);te_checks=te_checks+1;
    let model=h_join(te_work,"xip-model");h_compile(te_compiler,"tests/esp32/xip-register-model.flex",model);h_check(h_run(h_args(model,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    h_compile(te_compiler,"tests/esp32/uart-register-model.flex",model);h_check(h_run(h_args(model,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    let oracle=h_join(te_work,"oracle.o");let windows=h_join(te_work,"windows.o");let xip=h_join(te_work,"xip.o");
    let a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-optimize-sibling-calls","-fno-inline","-fno-builtin","-mlongcalls");h_add(a,"-mtext-section-literals");h_add(a,"-c");h_add(a,"tests/esp32/abi-oracle/abi-fixture.c");h_add(a,"-o");h_add(a,oracle);h_ok(a);
    h_ok(h_args(h_cat(tl_prefix,"as"),"tests/esp32/abi-oracle/abi-windows.S","-o",windows,0,0));
    a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-mlongcalls","-mtext-section-literals","-c","tests/esp32/abi-oracle/xip-fixture.c");h_add(a,"-o");h_add(a,xip);h_ok(a);
    let bluetooth=h_join(te_work,"bluetooth.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/bluetooth-fixture.c");h_add(a,"-o");h_add(a,bluetooth);h_ok(a);
    let masked_waits=h_join(te_work,"masked-waits.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/masked-waits-fixture.c");h_add(a,"-o");h_add(a,masked_waits);h_ok(a);
    let radio_event=h_join(te_work,"radio-event.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/radio-event-fixture.c");h_add(a,"-o");h_add(a,radio_event);h_ok(a);
    let wifi_control=h_join(te_work,"wifi-control.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/wifi-control-fixture.c");h_add(a,"-o");h_add(a,wifi_control);h_ok(a);
    let wifi_ownership=h_join(te_work,"wifi-ownership.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/wifi-ownership-fixture.c");h_add(a,"-o");h_add(a,wifi_ownership);h_ok(a);
    let phy_preempt=h_join(te_work,"phy-preempt.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/phy-preempt-fixture.c");h_add(a,"-o");h_add(a,phy_preempt);h_ok(a);
    let bt_concurrent=h_join(te_work,"bt-concurrent.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/bt-concurrent-fixture.c");h_add(a,"-o");h_add(a,bt_concurrent);h_ok(a);
    let ble=h_join(te_work,"ble-controller.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/ble-controller-fixture.c");h_add(a,"-o");h_add(a,ble);h_ok(a);
    let preempt=h_join(te_work,"preempt.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-optimize-sibling-calls","-fno-inline","-fno-builtin","-mlongcalls");h_add(a,"-mtext-section-literals");h_add(a,"-c");h_add(a,"tests/esp32/abi-oracle/preempt-fixture.c");h_add(a,"-o");h_add(a,preempt);h_ok(a);h_ok(h_args(h_cat(tl_prefix,"as"),"tests/esp32/abi-oracle/preempt-state.S","-o",h_join(te_work,"preempt-state.o"),0,0));
    let wake=h_join(te_work,"wake.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/wake-fixture.c");h_add(a,"-o");h_add(a,wake);h_ok(a);
    let irq_publication=h_join(te_work,"irq-publication.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/irq-publication-fixture.c");h_add(a,"-o");h_add(a,irq_publication);h_ok(a);
    tl_run("tests/esp32/iram-callback.flex",oracle,1,"PASS:");tl_run("tests/esp32/c-irq-state.flex",oracle,0,"PASS:");tl_run("tests/esp32/c-reentrant.flex",oracle,0,"PASS:");tl_run("tests/esp32/c-abi-rom.flex",oracle,0,"PASS:");tl_run("tests/esp32/c-abi.flex",oracle,0,"PASS:");tl_run("tests/esp32/context.flex",oracle,0,"PASS:");tl_run("tests/esp32/sdk-runtime.flex",oracle,0,"PASS:");tl_run("tests/esp32/sdk-priorities.flex",oracle,1,"PASS: SDK priority");tl_run("tests/esp32/sdk-preempt-ram.flex",oracle,0,"PASS: CPU-bound RAM");tl_run("tests/esp32/sdk-preempt.flex",oracle,1,"PASS: forced C");tl_run("tests/esp32/sdk-preempt-resources.flex",oracle,1,"PASS: radio/timer lifecycle");tl_run("tests/esp32/sdk-wake-abi.flex",oracle,1,"PASS:448 guarded C bool ABI");tl_run("tests/esp32/radio-irq-publication.flex",oracle,1,"PASS: IRQ callback pairs");tl_run("tests/esp32/irq-capacity.flex",oracle,1,"PASS: IRQ native allocation");tl_run("tests/esp32/sdk-task-reap.flex",oracle,0,"PASS:");tl_run("tests/esp32/sdk-radio-resources-xip.flex",oracle,1,"PASS:");tl_run("tests/esp32/radio-ownership.flex",oracle,1,"PASS:");tl_run("tests/esp32/xip.flex",xip,1,"PASS:");tl_run("tests/esp32/vendor-sections.flex",xip,1,"PASS:");tl_run("tests/esp32/sdk-timers.flex",oracle,0,"PASS:");tl_run("tests/esp32/sdk-queue-wrap.flex",oracle,0,"PASS:");tl_run("tests/esp32/bluetooth-transport.flex",oracle,1,"PASS:");tl_run("tests/esp32/bt-transport-preempt.flex",oracle,1,"PASS: preemptive VHCI");tl_run("tests/esp32/phy-preempt.flex",oracle,1,"PASS: PHY masked");tl_run("tests/esp32/wifi-ownership-preempt.flex",oracle,1,"PASS: Wi-Fi concurrent C TX/free");tl_run("tests/esp32/wifi-control-preempt.flex",oracle,1,"PASS: Wi-Fi control lease");tl_run("tests/esp32/radio-event-preempt.flex",oracle,1,"PASS: radio event count/scan");tl_run("tests/esp32/sdk-masked-waits.flex",oracle,1,"PASS: masked/ISR switch");tl_run("tests/esp32/ble-adapter.flex",oracle,1,"PASS:");tl_run("tests/esp32/ble-adapter-shared.flex",oracle,1,"PASS:");tl_run("tests/esp32/ble-adapter-gatt.flex",oracle,1,"PASS:");tl_run("tests/esp32/btdm-memory.flex",oracle,1,"PASS:");
    let heap_probes=h_join(te_work,"heap-probes");h_ok(h_args("python3","tests/esp32/sdk-heap-probes.py",heap_probes,0,0,0));tl_run(h_join(heap_probes,"sdk-heap-probes.flex"),oracle,0,"PASS:");tl_run(h_join(heap_probes,"sdk-heap-probes-xip.flex"),oracle,1,"PASS:");
    let lifecycle=h_join(te_work,"radio-lifecycle.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/radio-lifecycle-fixture.c");h_add(a,"-o");h_add(a,lifecycle);h_ok(a);tl_run("tests/esp32/wifi-lifecycle-failures.flex",lifecycle,1,"PASS:");tl_run("tests/esp32/ble-adapter-lifecycle.flex",lifecycle,1,"PASS:");
    let wifi=h_join(te_work,"wifi.o");a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-fno-builtin","-mlongcalls","-mtext-section-literals","-c");h_add(a,"tests/esp32/abi-oracle/wifi-fixture.c");h_add(a,"-o");h_add(a,wifi);h_ok(a);tl_run("tests/esp32/wifi-runtime.flex",wifi,1,"PASS:");
    // Native + vendor code runs from flash across a real timer ISR and deep windows.
    let text=h_read("tests/esp32/c-abi.flex");let fixture=h_join(te_work,"flash-abi.flex");
    text=h_cat3(h_cat3("import \"",h_absolute("lib/platform/esp32-irq.flex"),"\";import \""),h_cat3(h_absolute("lib/platform/esp32-timer.flex"),"\";import \"",h_absolute("lib/platform/esp32-xip.flex")),h_cat("\";",text+h_len("import \"../../lib/platform/esp32-irq.flex\";\nimport \"../../lib/platform/esp32-timer.flex\";\n")));
    h_save(fixture,text);tl_compile(fixture,"esp32-xip-elf");let linked=h_join(te_work,"linked.elf");a=tl_args(linked,oracle,1);h_add(a,"--object");h_add(a,windows);h_add(a,"--image");h_add(a,te_binary);h_ok(a);te_xip=1;te_run(te_binary,0,"PASS:");te_xip=0;
    tl_compile("tests/esp32/c-abi-irq-alloc.flex","esp32-elf");a=tl_args(linked,oracle,0);h_add(a,"--image");h_add(a,te_binary);h_ok(a);te_run(te_binary,1,0);
    // An unknown read-only orphan must fail before image/output replacement,
    // including an image that has no ordinary .drom section.
    let orphan_source=h_join(te_work,"orphan.c");let orphan_object=h_join(te_work,"orphan.o");h_save(orphan_source,"__attribute__((section(\".unmapped_cached_fixture\"),used)) const unsigned char omitted[3]={7,8,9};");
    a=h_args(h_cat(tl_prefix,"gcc"),"-Os","-c",orphan_source,"-o",orphan_object);h_ok(a);
    h_save(fixture,h_cat3("import \"",h_absolute("lib/platform/esp32-xip.flex"),"\";fn main(){return load8(esp32_external(\"omitted\"));}"));tl_compile(fixture,"esp32-xip-elf");a=tl_args(linked,orphan_object,1);h_add(a,"--image");h_add(a,te_binary);h_save(te_binary,"preserve image");let orphan_before=h_sha(te_binary);tl_reject(a,"cached allocated section",linked);te_assert(h_equal(h_sha(te_binary),orphan_before),"unmapped cached section preserves image output");
    // A failed mapper must trap in SRAM before calling a cached main().
    h_save(fixture,"fn esp_xip_enable(){return 1;}fn main(){return 0;}");tl_compile(fixture,"esp32-xip-elf");a=tl_args(linked,oracle,1);h_add(a,"--image");h_add(a,te_binary);h_ok(a);te_xip=1;te_run(te_binary,1,0);te_xip=0;
    te_reject("fn bad(a){return a;}fn main(){return esp32_callback32(bad);}","wrong function argument count");
    te_reject("fn bad(a){return a;}fn main(){return esp32_iram_callback32(bad);}","wrong function argument count");
    te_reject("fn main(){return esp32_external(\"not-a-C-symbol\");}","invalid ESP32 external symbol");
    // Output aliases must be rejected before any file is written.
    h_save(fixture,"fn main(){return 0;}");tl_compile(fixture,"esp32-elf");let alias_args=tl_args(linked,oracle,0);h_add(alias_args,"--map");h_add(alias_args,oracle);let oracle_sha=h_sha(oracle);tl_reject(alias_args,"link output aliases an object",linked);te_assert(h_equal(h_sha(oracle),oracle_sha),"alias rejection preserved oracle input");
    // Rejection paths cannot clobber a previously good output.
    h_save(te_fixture,"not an ELF");tl_reject(tl_args(linked,oracle,0),"requires ELF32",linked);
    h_save(fixture,"fn main(){return esp32_external(\"missing_vendor_function\");}");tl_compile(fixture,"esp32-elf");tl_reject(tl_args(linked,oracle,0),"undefined reference",linked);
    h_save(fixture,"fn main(){return 0;}");tl_compile(fixture,"esp32-elf");let bytes=h_read(te_fixture);let size=h_file_size;store8(bytes+32,255);store8(bytes+33,255);store8(bytes+34,255);store8(bytes+35,127);h_save_bytes(te_fixture,bytes,size,420);tl_reject(tl_args(linked,oracle,0),"invalid ELF section table",linked);
    let s3prefix=b_option(argc,argv,"--s3-prefix",0);if s3prefix {
        let s3oracle=h_join(te_work,"s3-oracle.o");let s3windows=h_join(te_work,"s3-windows.o");let s3preempt=h_join(te_work,"s3-preempt.o");
        a=h_args(h_cat(s3prefix,"gcc"),"-Os","-fno-optimize-sibling-calls","-fno-inline","-fno-builtin","-mlongcalls");h_add(a,"-mtext-section-literals");h_add(a,"-c");h_add(a,"tests/esp32/abi-oracle/abi-fixture.c");h_add(a,"-o");h_add(a,s3oracle);h_ok(a);
        h_ok(h_args(h_cat(s3prefix,"as"),"tests/esp32/abi-oracle/abi-windows.S","-o",s3windows,0,0));tl_compile("tests/esp32/s3-c-abi.flex","esp32s3-elf");a=tl_args(linked,s3oracle,0);h_add(a,"--object");h_add(a,s3windows);h_add(a,"--image");h_add(a,te_binary);h_ok(a);te_legacy=0;te_run(te_binary,0,"PASS: S3 C ABI");te_legacy=1;
        let saved_prefix=tl_prefix;tl_prefix=s3prefix;
        a=h_args(h_cat(s3prefix,"gcc"),"-Os","-fno-optimize-sibling-calls","-fno-inline","-fno-builtin","-mlongcalls");h_add(a,"-mtext-section-literals");h_add(a,"-c");h_add(a,"tests/esp32/abi-oracle/preempt-fixture.c");h_add(a,"-o");h_add(a,s3preempt);h_ok(a);h_ok(h_args(h_cat(s3prefix,"as"),"tests/esp32/abi-oracle/preempt-state.S","-o",h_join(te_work,"s3-preempt-state.o"),0,0));
        tl_run("tests/esp32/s3-sdk-preempt-ram.flex",s3oracle,0,"PASS:");tl_run("tests/esp32/s3-sdk-runtime.flex",s3oracle,0,"PASS:");tl_run("tests/esp32/s3-sdk-timers.flex",s3oracle,0,"PASS:");tl_run("tests/esp32/s3-sdk-preempt.flex",s3oracle,0,"PASS:");tl_run("tests/esp32/s3-radio-ownership.flex",s3oracle,0,"PASS:");tl_run("tests/esp32/s3-adc-guards.flex",s3oracle,0,"PASS:");tl_run("tests/esp32/s3-adc-api.flex",s3oracle,0,"PASS:");tl_prefix=saved_prefix;

    }
    // Vendor bytes are explicit optional inputs; never auto-download archives.
    let vendor=b_option(argc,argv,"--vendor",0);if vendor {tl_compile("tests/esp32/vendor-library.flex","esp32-elf");a=tl_args(linked,0,0);h_add(a,"--archive");h_add(a,h_join(vendor,"libwpa_supplicant.a"));let rom=b_option(argc,argv,"--rom",0);h_assert(rom,"vendor test requires --rom ESP-IDF rom directory");h_add(a,"--rom");h_add(a,h_join(rom,"esp32.rom.ld"));h_add(a,"--rom");h_add(a,h_join(rom,"esp32.rom.libc-funcs.ld"));h_add(a,"--rom");h_add(a,h_join(rom,"esp32.rom.libgcc.ld"));h_add(a,"--image");h_add(a,te_binary);h_ok(a);te_run(te_binary,0,"PASS:");tl_radio_tooling(vendor,rom);}
    h_print(1,"Vendor linking: ABI/windows/ISR-FPU, context/tasks/heap/synchronization, cached flash and rejection checks passed\n");
    if report {let result=j_object();j_set(result,"pass",j_bool(1));j_set(result,"checks",j_int(te_checks));j_set(result,"qemu_boots",j_int(te_runs));j_set(result,"cases",tl_cases);j_set(result,"compiler",j_string(te_compiler));j_set(result,"compiler_sha256",j_string(h_sha(te_compiler)));j_set(result,"qemu",j_string(te_qemu));j_set(result,"qemu_sha256",j_string(tl_tool_sha(te_qemu)));j_set(result,"priority_policy",j_string(h_join(te_work,"priority-policy.json")));j_set(result,"physical_hardware",j_bool(0));j_set(result,"preemptive_scheduler",j_bool(1));j_set(result,"wake_policy",j_string(h_join(te_work,"wake-policy.json")));j_save(report,result);}
    if work {h_print(1,h_cat3("ESP32 checks: ",h_int(te_checks)," passed\n"));}else {te_done();}return 0;
}
