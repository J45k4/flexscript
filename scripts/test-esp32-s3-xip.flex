// Existing stock Espressif QEMU executes actual emitted S3 cached firmware.
import "lib/esp32-test.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);let work=b_option(argc,argv,"--work",0);h_assert(compiler && work,"requires --compiler --work --prefix --qemu");h_mkdir(work);work=h_real(work);let prefix=b_option(argc,argv,"--prefix","xtensa-esp32s3-elf-");let qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));compiler=h_real(compiler);
    let driver=h_join(work,"driver");h_compile(compiler,"scripts/test-esp32-preempt.flex",driver);
    let files=h_args("preempt-fixture.c","s3-cache-fixture.c",0,0,0,0);let outputs=h_args("preempt.o","cache.o",0,0,0,0);let i=0;
    while i<2 {let a=h_args(h_cat(prefix,"gcc"),"-Os","-fno-inline","-fno-optimize-sibling-calls","-fno-builtin","-mlongcalls");h_add(a,"-mtext-section-literals");h_add(a,"-c");h_add(a,h_cat("tests/esp32/abi-oracle/",h_at(files,i)));h_add(a,"-o");h_add(a,h_join(work,h_at(outputs,i)));h_ok(a);i=i+1;}
    h_ok(h_args(h_cat(prefix,"as"),"tests/esp32/abi-oracle/preempt-state.S","-o",h_join(work,"preempt-state.o"),0,0));h_ok(h_args(h_cat(prefix,"as"),"tests/esp32/abi-oracle/abi-windows.S","-o",h_join(work,"windows.o"),0,0));
    let data=h_take(131329);i=0;while i<131329 {store8(data+i,(i*37+(i>>8)*11+(i>>16)*83+19)^((i*3)>>5));i=i+1;}let data_path=h_join(work,"cache-data.bin");h_save_bytes(data_path,data,131329,420);
    let assembly=h_join(work,"cache-data.S");h_save(assembly,h_cat3(".section .rodata.s3_cache_data,\"a\"\n.balign 16\n.global s3_cache_bytes\ns3_cache_bytes:\n.incbin ",j_dump(j_string(data_path)),"\n.global s3_cache_bytes_end\ns3_cache_bytes_end:\n"));h_ok(h_args(h_cat(prefix,"as"),assembly,"-o",h_join(work,"cache-data.o"),0,0));
    let cases=h_args("s3-xip.flex","s3-xip-data.flex","s3-xip-c-abi.flex","s3-xip-preempt.flex","s3-xip-runtime.flex","s3-xip-timers.flex");h_add(cases,"s3-xip-heap-bounds.flex");h_add(cases,"s3-xip-buffer.flex");h_add(cases,"s3-xip-adc.flex");h_add(cases,"s3-buffer-native.flex");h_add(cases,"s3-buffer-native.flex");let results=j_array();i=0;
    while i<h_count(cases) {
        let name=h_at(cases,i);let casework=h_join(work,h_int(i));let report=h_cat(casework,".json");let a=h_args(driver,"--compiler",compiler,"--work",casework,"--qemu");h_add(a,qemu);h_add(a,"--prefix");h_add(a,prefix);h_add(a,"--source");h_add(a,h_cat("tests/esp32/",name));h_add(a,"--chip");h_add(a,"esp32s3");
        if i<9 {h_add(a,"--xip");h_add(a,"yes");}else {h_add(a,"--profile");let profile="esp32s3-elf";if i==10 {profile="esp32s3-sdk-elf";}h_add(a,profile);}
        if i==1 {h_add(a,"--extra");h_add(a,h_join(work,"cache.o"));h_add(a,"--assembly");h_add(a,h_join(work,"cache-data.o"));}
        if i==2 {h_add(a,"--assembly");h_add(a,h_join(work,"windows.o"));}
        if i==3 {h_add(a,"--extra");h_add(a,h_join(work,"preempt.o"));h_add(a,"--assembly");h_add(a,h_join(work,"preempt-state.o"));}
        h_add(a,"--report");h_add(a,report);h_print(1,h_cat3("S3 cache case: ",name,"\n"));h_print(1,h_out(h_ok(a)));let row=j_parse(h_read(report));j_set(row,"target",j_string("esp32s3-xip-elf"));if i==9 {j_set(row,"target",j_string("esp32s3-elf"));}if i==10 {j_set(row,"target",j_string("esp32s3-sdk-elf"));}j_push(results,row);i=i+1;
    }
    let report=b_option(argc,argv,"--report",h_join(work,"report.json"));let out=j_object();j_set(out,"pass",j_bool(1));j_set(out,"cases",results);j_set(out,"ROM_boots",j_int(h_count(cases)));j_set(out,"compiler_sha256",j_string(h_sha(compiler)));j_set(out,"data_sha256",j_string(h_sha(data_path)));j_set(out,"physical_hardware",j_bool(0));j_set(out,"emulator_implementation_changes",j_bool(0));j_save(report,out);h_print(1,"PASS: S3 cached code/data, C/windows/FPU preemption, runtime/timers, heap and buffers\n");return 0;
}
