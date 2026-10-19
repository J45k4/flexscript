import "lib/esp32-elf.flex";
import "lib/esp32s3-ftm.flex";
import "lib/esp32-riscv-radio-build.flex";
// Explicit local vendor archives and compiler; never downloads or bootstraps.
global er_s3=0;
fn er_alias(a,b) {
    if h_equal(h_absolute(a),h_absolute(b)) {return 1;}let x=h_take(144);let y=h_take(144);
    if syscall(4,a,x,0,0,0,0)==0 && syscall(4,b,y,0,0,0,0)==0 {return load64(x)==load64(y) && load64(x+8)==load64(y+8);}return 0;
}
fn er_preserve(output,input) {h_assert(!er_alias(output,input) && !er_alias(h_cat(output,".map"),input) && !er_alias(h_cat(output,".elf"),input),h_cat("radio output aliases input: ",input));return 0;}
fn er_pin_path(inventory_path,path,name) {
    let inventory=h_read(inventory_path);let at=0;
    while load8(inventory+at) {let begin=at;while load8(inventory+at) && load8(inventory+at)!=10 {at=at+1;}
        let size=at-begin;if size>66 && load8(inventory+begin)!=35 && h_equal(h_slice(inventory+begin+66,size-66),name) {let message="vendor archive checksum mismatch: ";if h_equal(inventory_path,"docs/esp32s3-rom-sha256.txt") {message="S3 ROM checksum mismatch: ";}h_assert(h_equal(h_slice(inventory+begin,64),h_sha(path)),h_cat(message,name));return 0;}
        if load8(inventory+at) {at=at+1;}
    }h_assert(0,h_cat("input missing from pinned inventory: ",name));return 0;
}
fn er_pin(vendor,name) {let inventory="docs/esp32-vendor-sha256.txt";if er_s3 {inventory="docs/esp32s3-vendor-sha256.txt";}return er_pin_path(inventory,h_join(vendor,name),name);}

fn er_tls_text(object,key) {let value=j_get(object,key);h_assert(j_kind(value)==2,"invalid TLS vendor manifest");return j_value(value);}
fn er_tls(args,tls,output) {
    tls=h_absolute(tls);let manifest=h_join(tls,"flexscript-tls.json");er_preserve(output,manifest);let report=j_parse(h_read(manifest));
    h_assert(h_equal(er_tls_text(report,"version"),"3.6.7") && h_equal(er_tls_text(report,"target"),"xtensa-esp32") && h_equal(er_tls_text(report,"source_sha256"),"a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6"),"TLS vendor source/target mismatch");
    h_assert(h_equal(er_tls_text(report,"profile_sha256"),h_sha("lib/platform/esp32-mbedtls-config.h")),"TLS vendor profile mismatch");let archives=j_get(report,"archives");h_assert(j_kind(archives)==4,"invalid TLS archive manifest");let names=h_args("libmbedtls.a","libmbedx509.a","libmbedcrypto.a",0,0,0);let i=0;
    while i<h_count(names) {let name=h_at(names,i);let file=h_join(tls,name);er_preserve(output,file);h_assert(h_equal(h_sha(file),er_tls_text(archives,name)),h_cat("TLS archive checksum mismatch: ",name));h_add(args,"--archive");h_add(args,file);i=i+1;}return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",h_getenv("FLEX"));if !compiler {compiler="flexscript";}
    compiler=h_real(h_executable(compiler));let vendor=b_option(argc,argv,"--vendor",0);let rom=b_option(argc,argv,"--rom",0);let output=b_option(argc,argv,"--output",0);let kind=b_option(argc,argv,"--kind","wifi");
    h_assert(vendor && rom && output && (h_equal(kind,"wifi") || h_equal(kind,"bluetooth")),"requires --vendor ESP32_ARCHIVES --rom ROM_SCRIPTS --output firmware.bin [--chip esp32|esp32s3|esp32c3|esp32c6] [--kind wifi|bluetooth] [--compiler PATH] [--ld PATH] [--source app.flex]");
    let chip=b_option(argc,argv,"--chip","esp32");let rv=0;if h_equal(chip,"esp32c3"){rv=3;}if h_equal(chip,"esp32c6"){rv=6;}if rv{return er_rv_build(argc,argv,compiler,vendor,rom,output,kind,rv);}let s3=h_equal(chip,"esp32s3");h_assert(s3 || h_equal(chip,"esp32"),"--chip must be esp32, esp32s3, esp32c3 or esp32c6");
    h_assert(!s3 || h_equal(kind,"wifi"),"S3 Bluetooth vendor startup is not yet integrated");er_s3=s3;
    let bluetooth=h_equal(kind,"bluetooth");let tls=b_option(argc,argv,"--tls",0);h_assert(!tls || !bluetooth,"TLS vendor profile currently requires the Wi-Fi target");let source="examples/esp32-wifi-scan.flex";let target="esp32-xip-elf";let archives="core pp net80211 phy coexist wpa_supplicant espnow regulatory printf rtc";
    if bluetooth {source="examples/esp32-bluetooth-hci.flex";target="esp32-btdm-elf";archives="btdm_app phy coexist printf rtc";}if s3 {source="examples/esp32s3-vendor-probe.flex";target="esp32s3-xip-elf";archives="core pp net80211 phy coexist wpa_supplicant espnow regulatory printf smartconfig wapi mesh";h_assert(!tls,"the TLS vendor manifest must match this chip;S3 TLS archives are not yet integrated");}source=b_option(argc,argv,"--source",source);
    output=h_absolute(output);let pin_inventory="docs/esp32-vendor-sha256.txt";if s3 {pin_inventory="docs/esp32s3-vendor-sha256.txt";er_preserve(output,"docs/esp32s3-rom-sha256.txt");}er_preserve(output,pin_inventory);er_preserve(output,source);er_preserve(output,compiler);h_assert(!er_alias(output,h_cat(output,".map")) && !er_alias(output,h_cat(output,".elf")) && !er_alias(h_cat(output,".map"),h_cat(output,".elf")),"radio output paths alias");vendor=h_absolute(vendor);rom=h_absolute(rom);let work=h_temp();let link=h_join(work,"link");let objtool=h_join(work,"data-object");let firmware=h_join(work,"native.elf");let linked=h_join(work,"linked.elf");
    h_compile(compiler,"scripts/esp32-link.flex",link);h_compile(compiler,"scripts/esp32-data-object.flex",objtool);h_ok(h_args(compiler,"--target",target,source,"-o",firmware));
    let default_ld="xtensa-esp32-elf-ld";let default_gcc="xtensa-esp32-elf-gcc";if s3 {default_ld="xtensa-esp32s3-elf-ld";default_gcc="xtensa-esp32s3-elf-gcc";}let ld=h_real(h_executable(b_option(argc,argv,"--ld",default_ld)));let gcc=b_option(argc,argv,"--gcc",default_gcc);let libgcc=b_option(argc,argv,"--libgcc",0);if !libgcc {libgcc=h_trim(h_out(h_ok(h_args(h_executable(gcc),"-mabi=windowed","-print-libgcc-file-name",0,0,0))));}
    let args=h_args(link,"--firmware",firmware,"--output",linked,"--xip");h_add(args,"--ld");h_add(args,ld);h_add(args,"--image");h_add(args,output);h_add(args,"--map");h_add(args,h_cat(output,".map"));
    let at=0;while load8(archives+at) {let begin=at;while load8(archives+at) && load8(archives+at)!=32 {at=at+1;}let name=h_slice(archives+begin,at-begin);let file=h_cat3("lib",name,".a");er_preserve(output,h_join(vendor,file));er_pin(vendor,file);let archive=h_join(vendor,file);
        // Pinned WPA intentionally retains its static lifecycle mutex. Expose
        // that one object for quiescent teardown; code/data bytes stay intact.
        if h_equal(file,"libwpa_supplicant.a") {let objcopy=b_option(argc,argv,"--objcopy",0);if !objcopy {h_assert(h_len(ld)>2 && h_equal(h_slice(ld+h_len(ld)-2,2),"ld"),"nonstandard linker name requires --objcopy PATH");objcopy=h_cat(h_slice(ld,h_len(ld)-2),"objcopy");}let visible=h_join(work,"wpa-lifecycle.a");h_ok(h_args(h_executable(objcopy),"--globalize-symbol=eloop_data_lock",archive,visible,0,0));archive=visible;}
        h_add(args,"--archive");h_add(args,archive);if load8(archives+at) {at=at+1;}}
    if tls {er_tls(args,tls,output);}er_preserve(output,libgcc);h_add(args,"--archive");h_add(args,libgcc);let names=h_args("esp32.rom.ld","esp32.rom.libgcc.ld","esp32.rom.libc-funcs.ld","esp32.rom.newlib-data.ld",0,0);if s3 {names=h_args("esp32s3.rom.ld","esp32s3.rom.libgcc.ld","esp32s3.rom.libc.ld","esp32s3.rom.newlib.ld",0,0);}let i=0;while i<h_count(names) {let name=h_at(names,i);let file=h_join(rom,name);er_preserve(output,file);if s3 {er_pin_path("docs/esp32s3-rom-sha256.txt",file,name);}h_add(args,"--rom");h_add(args,file);i=i+1;}
    if bluetooth {er_preserve(output,"lib/platform/esp32-btdm-rom.ld");h_add(args,"--rom");h_add(args,h_absolute("lib/platform/esp32-btdm-rom.ld"));}
    else {let data=h_join(work,"wifi-event.o");let osi=h_join(work,"wifi-osi.o");h_ok(h_args(objtool,"--symbol","WIFI_EVENT","--output",data,0));let bytes="484";if s3 {bytes="480";}let a=h_args(objtool,"--symbol","g_wifi_osi_funcs","--size",bytes,"--output");h_add(a,osi);h_ok(a);h_add(args,"--object");h_add(args,data);h_add(args,"--object");h_add(args,osi);}
    if s3 {er_s3_ftm(args,objtool,work);}
    h_print(1,h_out(h_ok(args)));let result=h_read(linked);h_save_bytes(h_cat(output,".elf"),result,h_file_size,420);h_remove(work);return 0;
}
