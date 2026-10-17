// Explicit supplied original ECO3 ROM; no automatic download or service stubs.
import "lib/esp32-test.flex";
global tr_runner=0;
global tr_rom=0;
fn tr_firmware(fixture,name,object,link,ld,symbols,marker){
 let unlinked=h_join(te_work,h_cat(name,"-unlinked.elf"));
 h_ok(h_args(te_compiler,"--target","esp32-elf",fixture,"-o",unlinked));
 let linked=h_join(te_work,h_cat(name,".elf"));let image=h_join(te_work,h_cat(name,".bin"));
 let args=h_args(link,"--firmware",unlinked,"--output",linked,"--rom");h_add(args,symbols);
 if object{h_add(args,"--object");h_add(args,object);}
 h_add(args,"--ld");h_add(args,ld);h_add(args,"--image");h_add(args,image);h_ok(args);
 let serial=h_join(te_work,h_cat(name,".uart"));args=h_args(tr_runner,linked,serial,"--rom",tr_rom,"--fuel");h_add(args,"100000000");
 let result=h_run(args);h_check(result,0,0);let native_output=h_out(result);h_print(1,native_output);
 te_assert(h_has(native_output,"ROM data init: instructions=2155"),"real ROM startup sequence executed");
 let text=h_read(serial);te_assert(h_has(text,marker),"native ROM/GNU firmware completed");
 let qemu_text=te_run(image,0,marker);h_save(h_join(te_work,h_cat(name,".qemu.uart")),qemu_text);
 te_assert(h_has(qemu_text,text),"same ROM-linked firmware UART matches QEMU");
 let row=j_object();j_set(row,"fixture",j_string(fixture));j_set(row,"native_result",j_string(native_output));
 j_set(row,"elf_sha256",j_string(h_sha(linked)));j_set(row,"image_sha256",j_string(h_sha(image)));j_set(row,"uart_sha256",j_string(h_sha(serial)));j_set(row,"uart_matches_QEMU",j_bool(1));return row;
}
fn main(argc,argv){
 h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);let work=b_option(argc,argv,"--work",0);
 let rom=b_option(argc,argv,"--rom-image",0);let symbols=b_option(argc,argv,"--rom-symbols",0);
 h_assert(compiler && work && rom && symbols,"requires --compiler PATH --rom-image FILE --rom-symbols FILE --work DIR");
 te_init(compiler);h_remove(te_work);h_mkdir(work);te_work=h_real(work);tr_rom=h_real(rom);symbols=h_real(symbols);
 h_assert(h_equal(h_sha(tr_rom),"9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b"),"original ECO3 ROM image hash mismatch");
 te_qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));te_legacy=1;
 let ld=h_real(h_executable(b_option(argc,argv,"--ld","xtensa-esp32-elf-ld")));
 let assembler=h_real(h_executable(b_option(argc,argv,"--as","xtensa-esp32-elf-as")));
 let units=h_join(te_work,"rom-test");h_compile(te_compiler,"tests/xtensa/rom.flex",units);let prefix=h_join(te_work,"native-startup");h_ok(h_args(units,tr_rom,prefix,0,0,0));
 let startup=h_join(te_work,"qemu-startup");let startup_report=h_join(te_work,"qemu-startup.json");
 let args=h_args("python3","tests/xtensa/rom-startup-qemu.py","--qemu",te_qemu,"--rom",tr_rom);
 h_add(args,"--native-prefix");h_add(args,prefix);h_add(args,"--work");h_add(args,startup);h_add(args,"--report");h_add(args,startup_report);h_ok(args);
 let result=h_run(h_args(units,tr_rom,prefix,startup,0,0));h_check(result,0,0);let unit_output=h_out(result);h_print(1,unit_output);
 let link=h_join(te_work,"link");h_compile(te_compiler,"scripts/esp32-link.flex",link);tr_runner=h_join(te_work,"board-run");h_compile(te_compiler,"tests/xtensa/board-run.flex",tr_runner);
 te_bios=h_join(startup,"bios");let cases=j_array();
 j_push(cases,tr_firmware("tests/esp32/emulator-rom.flex","services",0,link,ld,symbols,"PASS: actual ROM data and16 frequency/delay cases"));
 let object=h_join(te_work,"branches.o");h_ok(h_args(assembler,"tests/esp32/rom-oracle/branches.S","-o",object,0,0));
 j_push(cases,tr_firmware("tests/esp32/emulator-rom-branches.flex","branches",object,link,ld,symbols,"PASS:1984 GNU ROM branch cases"));
 let report=b_option(argc,argv,"--report",0);
 if report{let row=j_object();j_set(row,"pass",j_bool(1));j_set(row,"scope_complete",j_bool(0));j_set(row,"physical_hardware",j_bool(0));j_set(row,"ROM_sha256",j_string(h_sha(tr_rom)));j_set(row,"ROM_symbols_sha256",j_string(h_sha(symbols)));j_set(row,"compiler_sha256",j_string(h_sha(te_compiler)));j_set(row,"startup_sequence_instructions",j_int(2155));j_set(row,"startup_RAM_matches_QEMU",j_bool(1));j_set(row,"startup_report",j_string(startup_report));j_set(row,"unit_result",j_string(unit_output));j_set(row,"service_frequency_delay_cases",j_int(16));j_set(row,"GNU_branch_cases",j_int(1984));j_set(row,"QEMU_firmware_boots",j_int(te_runs));j_set(row,"QEMU_firmware_checks",j_int(te_checks));j_set(row,"cases",cases);j_set(row,"limitations",j_string("Original ECO3 ROM data profile and real frequency/delay calls only; not full boot/downloader, analog-I2C/PLL switching, complete ROM/FPU/ISA or unchanged physical I2S image replay."));j_save(report,row);}
 h_print(1,"PASS: actual ROM startup,service calls and1984 GNU branch cases match QEMU\n");return 0;
}
