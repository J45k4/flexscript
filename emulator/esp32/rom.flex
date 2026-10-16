import "../xtensa/cpu.flex";
// Explicit original ESP32 ECO3 ROM-service profile. The caller supplies its
// ROM image; this module ships no ROM bytes and provides no service stubs.
// The host harness pins the image hash. Structural validation here bounds
// mapping and execution, rather than establishing an arbitrary ROM's identity.
fn er_rom_v3_valid(bytes,size){return bytes && size==455722 && em_u32(bytes+0x424)==0x4000d4f8 && em_u32(bytes+0x428)==0x4000d5c8 && em_u32(bytes+0xd558)==0x3ffae0c0 && em_u32(bytes+0xd560)==0x4000d6c0;}
fn er_available(c,address,size){let i=0;while i<load64(c+144){let p=load64(c+136)+i*32;if address<load64(p)+load64(p+8) && load64(p)<address+size{return 0;}i=i+1;}return 1;}
fn er_rom_v3_map(c,bytes,size){
 if !c || !er_rom_v3_valid(bytes,size) || load64(c+144)>28{return -22;}
 if !er_available(c,0x40000000,0x70000) || !er_available(c,0x3ff90000,0x10000) || !er_available(c,0x3ffae000,0x2000) || !er_available(c,0x3ffe0000,0x20000){return -22;}
 let code=xt_map(c,0x40000000,0x70000,5);if code<0{return code;}em_copy(code,bytes,size);
 // QEMU's original-chip DROM is the last64KiB of the IROM image. Both
 // mappings are immutable, so the independent host copies cannot diverge.
 let data=xt_map(c,0x3ff90000,0x10000,1);if data<0{return data;}em_copy(data,code+0x60000,0x10000);
 let low=xt_map(c,0x3ffae000,0x2000,3);if low<0{return low;}
 let high=xt_map(c,0x3ffe0000,0x20000,3);if high<0{return high;}return 0;
}
// Execute the ROM reset fragment that copies its own initialized data table.
// CPU0 PRID selects the shared/pro-CPU entries. This is an explicit pre-entry
// profile, not a full ROM boot or downloader. Restore the caller's pristine
// architectural state afterwards; mapped RAM retains the actual ROM writes.
// Return the number of real ROM instructions; failures retain CPU diagnostics.
fn er_rom_v3_data(c){
 if !c || (xt_sr(c,235) && xt_sr(c,235)!=0xcdcd) || load64(c+160) || load64(c+176) || load64(c+192) || !xt_load_region(c,0x40000000,0x70000) || !xt_load_region(c,0x3ffae000,0x2000) || !xt_load_region(c,0x3ffe0000,0x20000){return -22;}
 let saved=alloc(4096);let run=alloc(4096);if saved<0 || run<0{if saved>0{syscall(11,saved,4096,0,0,0,0);}if run>0{syscall(11,run,4096,0,0,0,0);}return -12;}
 em_copy(saved,c,4096);em_zero(run,4096);store64(c+224,run);xt_wsr(c,72,0);xt_wsr(c,73,1);xt_wsr(c,230,31);xt_wsr(c,235,0xcdcd);store64(c+128,0x400004fb);let count=0;let error=0;
 while load64(c+128)!=0x40000526 && count<100000{let reason=xt_step(c);if reason || load64(c+272){error= -95;if load64(c+160){error=load64(c+160);}count=100000;}else{count=count+1;}}
 if !error && load64(c+128)!=0x40000526{error= -110;}if !error{em_copy(c,saved,4096);}else{store64(c+224,load64(saved+224));}
 syscall(11,saved,4096,0,0,0,0);syscall(11,run,4096,0,0,0,0);if error{return error;}return count;
}
