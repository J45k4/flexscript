// ESP32-S3 compiler/ROM regression. Requires Espressif's qemu-system-xtensa.
// Run this tooling natively on Linux; the tested firmware is pure Xtensa.
import "build.flex";
global te_checks=0;
global te_compiler=0;
global te_work=0;
global te_fixture=0;
global te_binary=0;
global te_qemu=0;
global te_runs=0;
global te_sd=0;
global te_psram=0;
global te_legacy=0;
global te_btdm=0;
global te_xip=0;
fn te_assert(ok,message) {h_assert(ok,message);te_checks=te_checks+1;return 0;}
fn te_program(text) {return h_save(te_fixture,text);}
fn te_init(compiler) {te_compiler=h_real(compiler);te_work=h_temp();te_fixture=h_join(te_work,"test.flex");te_binary=h_join(te_work,"firmware.bin");return 0;}
fn te_done() {h_print(1,h_cat3("ESP32 checks: ",h_int(te_checks)," passed\n"));h_remove(te_work);return 0;}
fn te_u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn te_compile(source,image) {
    let target="esp32s3";if te_legacy {target="esp32";}let args=h_args(te_compiler,"--target",target,source,"-o",image);h_ok(args);return 0;
}
fn te_image(image) {
    let bytes=h_read(image);let size=h_file_size;
    te_assert(size>=80 && size%16==0,"firmware image size");
    te_assert(load8(bytes)==233 && load8(bytes+1)==2 && load8(bytes+2)==2,"ROM magic, segments, DIO flash mode");
    let chip=9;let code_base=0x40380000;let data_base=0x3fcb0000;if te_legacy {chip=0;code_base=0x40080000;data_base=0x3ffb0000;}
    if te_btdm {data_base=0x3ffc0000;}
    te_assert(load8(bytes+12)==chip && load8(bytes+13)==0 && load8(bytes+23)==1,"ESP32-S3 chip ID and hash flag");
    let at=24;let sum=239;let i=0;
    while i<2 {
        let base=te_u32(bytes+at);let n=te_u32(bytes+at+4);at=at+8;
        te_assert(n>0 && n<=131072 && n%4==0 && at+n<size-32,"bounded aligned RAM segment");
        if !i {te_assert(n<=131072,"code SRAM bound");if !te_legacy {te_assert(0x3fc90000+n<=data_base,"code physical alias ends before DRAM");}te_assert(base==code_base && te_u32(bytes+4)>=base+1024 && te_u32(bytes+4)<base+n,"IRAM load and entry addresses");}
        else {te_assert(base==data_base && n<=65536,"DRAM load address and bound");}
        let j=0;while j<n {sum=sum^load8(bytes+at+j);j=j+1;}at=at+n;i=i+1;
    }
    while at%16!=15 {te_assert(load8(bytes+at)==0,"zero image padding");at=at+1;}
    te_assert((te_xip || at==size-33) && load8(bytes+at)==sum,"ROM XOR checksum and exact file length");
    te_assert(h_equal(h_sha_bytes(bytes,at+1),h_hex(bytes+at+1,32)),"independent OpenSSL SHA-256 validation");return 0;
}
fn te_run(image,trapped,expected) {
    te_image(image);let flash=h_join(te_work,"flash.bin");let uart=h_join(te_work,"uart.log");
    let bytes=h_read(image);let size=h_file_size;let data=h_take(4194304);let i=0;
    while i<4194304 {store8(data+i,255);i=i+1;}let offset=0;if te_legacy {offset=4096;}h_copy(data+offset,bytes,size);h_save_bytes(flash,data,4194304,420);
    let machine="esp32s3";if te_legacy {machine="esp32";}let args=h_args(te_qemu,"-M",machine,"-display","none","-monitor");h_add(args,"none");
    h_add(args,"-qmp");h_add(args,"stdio");h_add(args,"-serial");h_add(args,h_cat("file:",uart));
    h_add(args,"-drive");h_add(args,h_cat3("file=",flash,",if=mtd,format=raw"));h_add(args,"-nic");h_add(args,"none");h_add(args,"-no-reboot");
    if te_sd {h_add(args,"-drive");h_add(args,h_cat3("file=",te_sd,",if=sd,format=raw"));}
    if te_psram {h_add(args,"-m");h_add(args,"8M");}
    let process=h_spawn(args,0,0);h_until(process,"\"QMP\"",5000);
    h_trigger(process,"{\"execute\":\"qmp_capabilities\"}\n");h_until(process,"\"return\"",5000);
    let marker="0x444f4e45";if trapped>0 {marker="0x54524150";}
    let status_query="{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"xp /1wx 0x3fcb0004\"}}\n";if te_legacy {status_query="{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"xp /1wx 0x3ffb0004\"}}\n";}
    if te_btdm {status_query="{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"xp /1wx 0x3ffc0004\"}}\n";}
    let end=net_now()+10000;if trapped<0 {end=net_now()+1000;}let terminal=0;
    while !terminal && !h_has(h_out(process),marker) && net_now()<end && h_status(process)== -999 {
        h_trigger(process,status_query);h_pump(process,10);
        if h_has(h_out(process),"0x54524150") || h_has(h_out(process),"0x444f4e45") {terminal=1;}
    }
    if !trapped && h_has(h_out(process),marker) {
        let query="{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"xp /2wx 0x3fcb0008\"}}\n";let address="3fcb0008";if te_legacy {query="{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"xp /2wx 0x3ffb0008\"}}\n";address="3ffb0008";}if te_btdm {query="{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"xp /2wx 0x3ffc0008\"}}\n";address="3ffc0008";}h_trigger(process,query);h_until(process,address,3000);
        te_assert(h_has(h_out(process),"0x00000000 0x00000000"),"main returned zero");
    }
    let reached=h_has(h_out(process),marker);if trapped<0 {reached=1;}
    if !reached {h_trigger(process,"{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"info registers\"}}\n");h_pump(process,30);}
    // QMP quit closes and flushes the serial file; SIGTERM may discard it.
    if h_status(process)== -999 {h_trigger(process,"{\"execute\":\"quit\"}\n");}
    end=net_now()+3000;while h_status(process)== -999 && net_now()<end {h_pump(process,5);}
    if h_status(process)== -999 {h_stop(process);}
    let serial=h_read(uart);
    let persisted=h_read(flash);te_assert(h_equal(h_sha_bytes(data,1048576),h_sha_bytes(persisted,1048576)),"protected first MiB of flash preserved");
    if !reached {h_print(2,serial);h_print(2,h_out(process));h_print(2,h_err(process));}
    te_assert(reached,"guest completion/trap status");h_check(process,0,0);
    let entry_text="entry 0x4038";let boot_text="SPI_FLASH_BOOT";if te_legacy {entry_text="entry 0x4008";boot_text="SPI_FAST_FLASH_BOOT";}te_assert(h_has(serial,boot_text) && h_has(serial,entry_text),"booted through the chip ROM from flash");
    te_assert(!h_has(serial,"SHA-256 comparison failed") && !h_has(serial,"invalid header"),"ROM accepted image integrity");
    if expected {te_assert(h_has(serial,expected),serial);}
    te_runs=te_runs+1;return serial;
}
fn te_fault(text) {
    te_program(text);te_compile(te_fixture,te_binary);te_run(te_binary,1,0);return 0;
}
fn te_reject(text,message) {
    te_program(text);h_save(te_binary,"preserve existing output");let before=h_sha(te_binary);
    let result=h_run(h_args(te_compiler,"--target","esp32s3",te_fixture,"-o",te_binary));h_check(result,1,0);
    te_assert(h_has(h_err(result),message),h_err(result));te_assert(h_equal(h_sha(te_binary),before),"rejected firmware overwrote destination");return 0;
}
