// Exact C objects for the pinned ESP-IDF5.5.1/newlib4.3 ILP32 stdio profile.
// No C implementation/toolchain is needed to construct this ET_REL data object.
fn ee_newlib_stdio_object() {
    let names=h_args("_impure_data","__lock___sinit_recursive_mutex","__lock___malloc_recursive_mutex","__lock___env_recursive_mutex","__lock___sfp_recursive_mutex","__lock___atexit_recursive_mutex");
    h_add(names,"__lock___at_quick_exit_mutex");h_add(names,"__lock___tz_mutex");h_add(names,"__lock___dd_hash_mutex");h_add(names,"__lock___arc4random_mutex");
    let count=h_count(names);let pool_size=1;let i=0;while i<count {pool_size=pool_size+h_len(h_at(names,i))+1;i=i+1;}
    let symoff=52;let stroff=symoff+(count+1)*16;let shnames=".bss,.symtab,.strtab,.shstrtab,";let noff=stroff+pool_size;let shoff=0;
    shoff=(noff+h_len(shnames)+2+3)&~3;let size=shoff+5*40;let out=h_take(size);
    ee_w32(out,0x464c457f);store8(out+4,1);store8(out+5,1);store8(out+6,1);ee_w16(out+16,1);ee_w16(out+18,243);ee_w32(out+20,1);ee_w32(out+32,shoff);ee_w16(out+40,52);ee_w16(out+46,40);ee_w16(out+48,5);ee_w16(out+50,4);
    let offset=0;let nameoff=1;i=0;while i<count {let n=h_at(names,i);let length=h_len(n);h_copy(out+stroff+nameoff,n,length);let s=out+symoff+(i+1)*16;let bytes=84;if !i {bytes=240;}
        ee_w32(s,nameoff);ee_w32(s+4,offset);ee_w32(s+8,bytes);store8(s+12,17);ee_w16(s+14,1);offset=offset+bytes;nameoff=nameoff+length+1;i=i+1;
    }
    let b=out+shoff+40;ee_w32(b,1);ee_w32(b+4,8);ee_w32(b+8,3);ee_w32(b+16,52);ee_w32(b+20,offset);ee_w32(b+32,4);
    b=out+shoff+80;ee_w32(b,6);ee_w32(b+4,2);ee_w32(b+16,symoff);ee_w32(b+20,(count+1)*16);ee_w32(b+24,3);ee_w32(b+28,1);ee_w32(b+32,4);ee_w32(b+36,16);
    b=out+shoff+120;ee_w32(b,14);ee_w32(b+4,3);ee_w32(b+16,stroff);ee_w32(b+20,pool_size);ee_w32(b+32,1);
    b=out+shoff+160;ee_w32(b,22);ee_w32(b+4,3);ee_w32(b+16,noff);ee_w32(b+20,h_len(shnames)+2);ee_w32(b+32,1);
    i=0;while i<h_len(shnames) {let c=load8(shnames+i);if c==44 {c=0;}store8(out+noff+1+i,c);i=i+1;}
    h_file_size=size;return out;
}
