// ESP-IDF5.5.1 ROM ABI, emitted as initialized C data and R_RISCV_32 relocations.
fn ee_newlib_rom_object(profile) {
    let fields=h_args("__getreent","_malloc_r","_free_r","_realloc_r","_calloc_r","abort");let i=6;
    while i<14 {let name="esp_libc_rom_nosys";if i==10 {name="abort";}h_add(fields,name);i=i+1;}
    h_add(fields,"esp_libc_rom_fstat");h_add(fields,"_sbrk_r");h_add(fields,"esp_libc_rom_nosys");h_add(fields,"esp_libc_rom_nosys");h_add(fields,"abort");h_add(fields,"_close_r");h_add(fields,"_open_r");h_add(fields,"_write_r");h_add(fields,"_lseek_r");h_add(fields,"_read_r");
    h_add(fields,"__retarget_lock_init");h_add(fields,"__retarget_lock_init_recursive");h_add(fields,"__retarget_lock_close");h_add(fields,"__retarget_lock_close_recursive");h_add(fields,"__retarget_lock_acquire");h_add(fields,"__retarget_lock_acquire_recursive");h_add(fields,"__retarget_lock_try_acquire");h_add(fields,"__retarget_lock_try_acquire_recursive");h_add(fields,"__retarget_lock_release");h_add(fields,"__retarget_lock_release_recursive");h_add(fields,0);h_add(fields,0);h_add(fields,"__assert_func");h_add(fields,"abort");h_add(fields,"esp_libc_stdio_cleanup");h_assert(h_count(fields)==39,"invalid ROM callback table");
    let names=h_args("flex_rom_syscalls",0,0,0,0,0);let indices=h_take(39*8);let relcount=0;i=0;
    while i<39 {let name=h_at(fields,i);if name {let j=1;while j<h_count(names) && !h_equal(h_at(names,j),name) {j=j+1;}if j==h_count(names) {h_add(names,name);}store64(indices+i*8,j+1);relcount=relcount+1;}i=i+1;}
    let callbacks=h_count(names);h_add(names,"syscall_table_ptr");h_add(names,"esp_rom_newlib_init_common_mutexes");
    let n=h_count(names);let pool_size=1;i=0;while i<n {pool_size=pool_size+h_len(h_at(names,i))+1;i=i+1;}
    let dataoff=52;let reloff=dataoff+160;let symoff=reloff+relcount*12;let stroff=symoff+(n+1)*16;let noff=stroff+pool_size;let shnames=".data,.rela.data,.symtab,.strtab,.shstrtab,";let shoff=(noff+h_len(shnames)+2+3)&~3;let size=shoff+6*40;let out=h_take(size);
    ee_w32(out,0x464c457f);store8(out+4,1);store8(out+5,1);store8(out+6,1);ee_w16(out+16,1);ee_w16(out+18,243);ee_w32(out+20,1);ee_w32(out+32,shoff);ee_w16(out+40,52);ee_w16(out+46,40);ee_w16(out+48,6);ee_w16(out+50,5);ee_w32(out+dataoff+156,0xbb10c433);
    let nameoff=1;i=0;while i<n {let name=h_at(names,i);let length=h_len(name);h_copy(out+stroff+nameoff,name,length);let s=out+symoff+(i+1)*16;ee_w32(s,nameoff);store8(s+12,18);if !i {ee_w32(s+8,160);store8(s+12,17);ee_w16(s+14,1);}if i==callbacks {let address=0x3fcdffe0;if ee_u32(profile+4)==13 {address=0x4087ffd4;}ee_w32(s+4,address);ee_w32(s+8,4);store8(s+12,17);ee_w16(s+14,65521);}else if i==callbacks+1 {let address=0x40000350;if ee_u32(profile+4)==13 {address=0x400004a4;}ee_w32(s+4,address);ee_w16(s+14,65521);}nameoff=nameoff+length+1;i=i+1;}
    i=0;let r=0;while i<39 {let symbol=load64(indices+i*8);if symbol {ee_w32(out+reloff+r*12,i*4);ee_w32(out+reloff+r*12+4,(symbol<<8)|1);r=r+1;}i=i+1;}
    let b=out+shoff+40;ee_w32(b,1);ee_w32(b+4,1);ee_w32(b+8,3);ee_w32(b+16,dataoff);ee_w32(b+20,160);ee_w32(b+32,4);
    b=out+shoff+80;ee_w32(b,7);ee_w32(b+4,4);ee_w32(b+16,reloff);ee_w32(b+20,relcount*12);ee_w32(b+24,3);ee_w32(b+28,1);ee_w32(b+32,4);ee_w32(b+36,12);
    b=out+shoff+120;ee_w32(b,18);ee_w32(b+4,2);ee_w32(b+16,symoff);ee_w32(b+20,(n+1)*16);ee_w32(b+24,4);ee_w32(b+28,1);ee_w32(b+32,4);ee_w32(b+36,16);
    b=out+shoff+160;ee_w32(b,26);ee_w32(b+4,3);ee_w32(b+16,stroff);ee_w32(b+20,pool_size);ee_w32(b+32,1);
    b=out+shoff+200;ee_w32(b,34);ee_w32(b+4,3);ee_w32(b+16,noff);ee_w32(b+20,h_len(shnames)+2);ee_w32(b+32,1);
    i=0;while i<h_len(shnames) {let c=load8(shnames+i);if c==44 {c=0;}store8(out+noff+1+i,c);i=i+1;}h_file_size=size;return out;
}
