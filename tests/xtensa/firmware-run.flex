// Test harness only: acknowledges the exact watchdog-disable writes in startup.
// Unknown MMIO fails; these acknowledgments are not peripheral models.
import "../../emulator/xtensa/cpu.flex";
import "../../scripts/lib/esp32-elf.flex";
fn main(argc,argv){if argc!=2{return 99;}let bytes=h_read(load64(argv+8));let size=h_file_size;let elf=ee_open(bytes,size);let info=ee_profile(elf);let code=ee_u32(info+8);let data=ee_u32(info+12);let c=xt_create();let rom=xt_map(c,code,131072,5);let ram=xt_map(c,data,196608,3);if rom<=0 || ram<=0{return 98;}
 if xt_load_elf(c,bytes,size){return 97;}let run=alloc(4096);em_zero(run,4096);let exits=0;let slices=0;while load64(c+176)<100000000{let reason=xt_run_slice(c,run,100000000,load64(c+176)+10000);if reason<0{h_print(2,"CPU fault ");h_print(2,h_int(load64(c+160)));h_print(2," PC ");h_print(2,h_int(load64(c+168)));h_print(2," OP ");h_print(2,h_int(load64(c+216)));h_print(2,"\n");return 1;}
 if reason==6{let address=load64(run+32);let allowed=0;if ee_u32(info+4)==0{allowed=address==0x3ff480a4 || address==0x3ff4808c || address==0x3ff5f064 || address==0x3ff5f048 || address==0x3ff60064 || address==0x3ff60048;}else{allowed=address==0x600080b0 || address==0x60008098 || address==0x600080b8 || address==0x600080b4 || address==0x6001f064 || address==0x6001f048 || address==0x60020064 || address==0x60020048;}
 if !allowed || !load8(run+52) || em_u32(run+48)!=4{return 2;}exits=exits+1;}else if reason!=10{return 3;}
 let state=em_u32(ram+4);if state==0x54524150{return 4;}if state==0x444f4e45{if load64(ram+8){h_print(2,"Guest return ");h_print(2,h_int(load64(ram+8)));return 5;}h_print(1,"PASS emitted firmware, machine instructions=");h_print(1,h_int(load64(c+176)));h_print(1," MMIO exits=");h_print(1,h_int(exits));h_print(1,"\n");xt_close(c);return 0;}slices=slices+1;
 }return 6;}
