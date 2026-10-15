import "lib/esp32-test.flex";
global tf_link=0;
global tf_ld=0;
global tf_rom=0;
fn tf_build(source,object,output) {
    h_ok(h_args(te_compiler,"--target","esp32-xip-elf",source,"-o",te_fixture));let a=h_args(tf_link,"--firmware",te_fixture,"--output",h_cat(output,".elf"),"--xip");h_add(a,"--ld");h_add(a,tf_ld);h_add(a,"--rom");h_add(a,h_join(tf_rom,"esp32.rom.ld"));if object {h_add(a,"--object");h_add(a,object);}h_add(a,"--image");h_add(a,output);h_ok(a);return 0;
}
fn tf_protected(image) {
    let bytes=h_read(image);let size=h_file_size;let expected=h_take(4194304);let i=0;while i<4194304 {store8(expected+i,255);i=i+1;}h_copy(expected+4096,bytes,size);let disk=h_read(h_join(te_work,"flash.bin"));
    te_assert(h_file_size==4194304 && h_equal(h_sha_bytes(expected,0x3e0000),h_sha_bytes(disk,0x3e0000)) && h_equal(h_sha_bytes(expected+0x3e2000,0x1e000),h_sha_bytes(disk+0x3e2000,0x1e000)),"every flash byte outside application storage preserved, including full linked image");return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"requires --compiler PATH --gcc PATH --ld PATH --rom DIRECTORY [--qemu PATH] [--report PATH]");te_init(compiler);te_qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));te_legacy=1;
    tf_ld=b_option(argc,argv,"--ld","xtensa-esp32-elf-ld");tf_rom=b_option(argc,argv,"--rom",".");tf_link=h_join(te_work,"link");h_compile(te_compiler,"scripts/esp32-link.flex",tf_link);
    let driver=h_read("lib/platform/esp32-flash.flex");te_assert(h_has(driver,"esp32_iram_callback(ef_critical);"),"production driver includes its SRAM placement annotation");driver=h_replace(driver,"esp32_iram_callback(ef_critical);","");driver=h_replace(driver,"import \"esp32-xip.flex\";",h_cat3("import \"",h_absolute("lib/platform/esp32-xip.flex"),"\";"));h_save(h_join(te_work,"flash-model-driver.flex"),driver);
    h_save(h_join(te_work,"flash-register-fixture.flex"),h_read("tests/esp32/flash-register-fixture.flex"));
    let source=h_join(te_work,"model.flex");h_save(source,h_read("tests/esp32/flash-register-model.flex"));let model=h_join(te_work,"model");h_compile(te_compiler,source,model);h_check(h_run(h_args(model,0,0,0,0,0)),0,"");te_checks=te_checks+1;h_check(h_run(h_args(model,"1",0,0,0,0)),81,"");te_checks=te_checks+1;h_check(h_run(h_args(model,"2",0,0,0,0)),82,"");te_checks=te_checks+1;
    h_check(h_run(h_args(model,"3",0,0,0,0)),83,"");te_checks=te_checks+1;
    let backend=h_read("lib/platform/esp32-settings.flex");backend=h_replace(backend,"import \"esp32-flash.flex\";","import \"flash-model-driver.flex\";");backend=h_replace(backend,"import \"../storage/settings.flex\";",h_cat3("import \"",h_absolute("lib/storage/settings.flex"),"\";"));h_save(h_join(te_work,"flash-model-settings.flex"),backend);h_save(source,h_read("tests/esp32/settings-backend-model.flex"));h_compile(te_compiler,source,model);h_check(h_run(h_args(model,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    let gcc=b_option(argc,argv,"--gcc","xtensa-esp32-elf-gcc");let object=h_join(te_work,"flash.o");let a=h_args(gcc,"-Os","-c","tests/esp32/abi-oracle/flash-fixture.c","-o",object);h_ok(a);tf_build("tests/esp32/flash-original.flex",object,te_binary);te_xip=1;te_run(te_binary,0,"PASS: cached original ESP32 flash");tf_protected(te_binary);
    a=h_args(gcc,"-Os","-DFLASH_LARGE_IMAGE","-c","tests/esp32/abi-oracle/flash-fixture.c","-o");h_add(a,object);h_ok(a);tf_build("tests/esp32/flash-original.flex",object,te_binary);let large=h_read(te_binary);te_assert(h_file_size>1048576,"oversized-image fixture really exceeds one MiB");te_run(te_binary,0,"PASS: cached original ESP32 flash");tf_protected(te_binary);
    let settings=h_join(te_work,"settings.bin");tf_build("tests/esp32/settings-flash.flex",0,settings);a=h_args("python3","tests/esp32/settings-reboot-peer.py","--qemu",te_qemu,"--image",settings);h_add(a,"--report");h_add(a,b_option(argc,argv,"--report",h_join(te_work,"settings-reboot.json")));h_print(1,h_out(h_ok(a)));te_checks=te_checks+1;
    let combined=h_join(te_work,"combined.bin");tf_build("tests/esp32/settings-flash-probe.flex",object,combined);a=h_args("python3","tests/esp32/settings-reboot-peer.py","--qemu",te_qemu,"--image",combined);h_add(a,"--serial-gate");h_add(a,"--report");h_add(a,b_option(argc,argv,"--probe-report",h_join(te_work,"combined-reboot.json")));h_print(1,h_out(h_ok(a)));te_checks=te_checks+1;
    h_print(1,"Original ESP32 flash protection, independent register/NOR model, real cached-DROM input and settings reboot recovery passed\n");te_done();return 0;
}
