// ELF/static TLS checks and descriptor patching for the RV32 SRAM profiles.
// RISC-V Variant-I: tp points at the first byte of a per-thread TLS copy.
fn ee_tls_descriptor(elf,required) {
    let index=ee_find_symbol(elf,"flex_tls_descriptor");if index<0 {h_assert(!required,"RISC-V TLS requires a compiler TLS descriptor");return 0;}
    let table=ee_section(elf,".symtab");let symbol=ee_payload(elf,table)+index*16;let data=ee_section(elf,".data");let profile=ee_profile(elf);let base=ee_u32(profile+12);
    h_assert(data && ee_u32(data+4)==1 && ee_u32(data+12)==base && ee_u32(data+20)>=56 && ee_u32(symbol+4)==base+24 && ee_u32(symbol+8)==32 && load8(symbol+12)==17 && ee_u16(symbol+14)==(data-load64(elf)-load64(elf+16))/40,"invalid RISC-V TLS descriptor symbol");
    return ee_payload(elf,data)+24;
}
fn ee_tls_patch(elf) {
    let bytes=load64(elf);let profile=ee_profile(elf);let base=ee_u32(profile+12);let tls=0;let i=0;
    while i<load64(elf+56) {let ph=bytes+load64(elf+48)+i*32;if ee_u32(ph)==7 && ee_u32(ph+20) {h_assert(!tls,"multiple RISC-V TLS segments");tls=ph;}i=i+1;}
    let descriptor=ee_tls_descriptor(elf,tls!=0);if descriptor {i=0;while i<32 {h_assert(!load8(descriptor+i),"RISC-V TLS descriptor must start zeroed");i=i+1;}}
    if !tls {i=0;while i<load64(elf+24) {let sh=bytes+load64(elf+16)+i*40;h_assert(!(ee_u32(sh+8)&1024) || !ee_u32(sh+20),"TLS section has no TLS segment");i=i+1;}return 0;}let address=ee_u32(tls+8);let initialized=ee_u32(tls+16);let total=ee_u32(tls+20);let align=ee_u32(tls+28);if align<16 {align=16;}
    h_assert(initialized<=total && total<=ee_data_capacity(profile) && align<=65536 && !(align&(align-1)) && !(address&(align-1)) && address>=base+56 && address<=base+ee_data_capacity(profile)-total && ee_range(load64(elf+8),ee_u32(tls+4),initialized),"invalid RISC-V TLS template");
    let main=ee_section(elf,".flex.tls.main");h_assert(main && ee_u32(main+4)==8 && (ee_u32(main+8)&3)==3 && ee_u32(main+20)>=total,"missing RISC-V main TLS instance");let main_address=ee_u32(main+12);
    h_assert(!(main_address&(align-1)) && main_address>=address+total && main_address<=base+ee_data_capacity(profile)-total && ee_u32(main+20)<=base+ee_data_capacity(profile)-main_address,"invalid RISC-V main TLS bounds");
    let mapped=0;i=0;while i<load64(elf+56) {let ph=bytes+load64(elf+48)+i*32;if ee_u32(ph)==1 {let low=ee_u32(ph+8);let memory=ee_u32(ph+20);let offset=address-low;
        if offset>=0 && offset<=memory && total<=memory-offset && main_address>=low && main_address-low<=memory && total<=memory-(main_address-low) {
            h_assert(!initialized || (offset<=ee_u32(ph+16) && initialized<=ee_u32(ph+16)-offset && ee_u32(tls+4)==ee_u32(ph+4)+offset),"TLS template is not mapped file data");mapped=1;
        }}i=i+1;}h_assert(mapped,"TLS instances are outside load memory");
    i=0;while i<load64(elf+24) {let sh=bytes+load64(elf+16)+i*40;if (ee_u32(sh+8)&1024) && ee_u32(sh+20) {let offset=ee_u32(sh+12)-address;let n=ee_u32(sh+20);h_assert((ee_u32(sh+8)&2) && offset>=0 && offset<=total && n<=total-offset,"TLS section outside template");if ee_u32(sh+4)==1 {h_assert(offset<=initialized && n<=initialized-offset,"initialized TLS outside file template");}else {h_assert(ee_u32(sh+4)==8,"unsupported TLS section type");}}i=i+1;}
    ee_w32(descriptor,0x31534c54);ee_w32(descriptor+4,address);ee_w32(descriptor+8,initialized);ee_w32(descriptor+12,total);ee_w32(descriptor+16,align);ee_w32(descriptor+20,main_address);return 0;
}
// TLS symbols are offsets from tp, never process-wide function/data pointers.
fn ee_tls_imports(input,final) {
    let imports=ee_section(input,".flex.imports");let strings=ee_section(input,".strtab");let symbols=ee_section(final,".symtab");let i=0;
    while i<ee_u32(imports+20)/8 {let name=ee_string(ee_payload(input,strings),ee_u32(strings+20),ee_u32(ee_payload(input,imports)+i*8));let index=ee_find_symbol(final,name);if index>=0 {h_assert((load8(ee_payload(final,symbols)+index*16+12)&15)!=6,"RISC-V TLS variable imports require C accessors");}i=i+1;}return 0;
}
