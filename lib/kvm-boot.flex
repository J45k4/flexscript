import "kvm.flex";
// Multiboot 1 flat address-field images, such as Flexscript's bare-metal target.
// Returns the protected-mode entry address. ram=0 validates without loading.
// Does not modify RAM on validation failure.
fn kvm_multiboot(ram,bytes,image,size) {
    let header=-1;let i=0;
    while i+32<=size && i<8192 && header<0 {
        if kvm_u32(image+i)==0x1badb002 {header=i;}i=i+4;
    }
    if header<0 {return kvm_fail("Missing flat Multiboot header.",-22);}
    let h=image+header;let flags=kvm_u32(h+4);
    if ((kvm_u32(h)+flags+kvm_u32(h+8))&0xffffffff)!=0 || !(flags&0x10000) || (flags&0xfffc)!=0 {
        return kvm_fail("Unsupported Multiboot flags or invalid checksum.",-22);
    }
    let address=kvm_u32(h+12);let base=kvm_u32(h+16);let end=kvm_u32(h+20);let bss=kvm_u32(h+24);let entry=kvm_u32(h+28);
    if address<base || address-base>header {return kvm_fail("Invalid Multiboot load offset.",-22);}
    let offset=header-(address-base);let length=size-offset;
    if end {if end<base || end-base>length {return kvm_fail("Truncated Multiboot load region.",-22);}length=end-base;}
    if !bss {bss=base+length;}
    // Reserve low memory for boot info, and report conventional RAM above 1 MiB.
    if base<1048576 || bytes<67108864 || base>bytes || length>bytes-base || bss<base+length || bss>bytes || entry<base || entry>=base+length {
        return kvm_fail("Multiboot image does not fit guest RAM or has invalid entry/BSS.",-22);
    }
    if !ram {return entry;}
    kvm_copy(ram+base,image+offset,length);kvm_zero(ram+base+length,bss-base-length);
    let info=ram+0x8000;kvm_zero(info,116);kvm_put32(info,0x41);kvm_put32(info+4,640);kvm_put32(info+8,(bytes-1048576)/1024);
    kvm_put32(info+44,48);kvm_put32(info+48,0x9000);
    let map=ram+0x9000;kvm_zero(map,48);
    kvm_put32(map,20);store64(map+4,0);store64(map+12,0xa0000);kvm_put32(map+20,1);
    kvm_put32(map+24,20);store64(map+28,1048576);store64(map+36,bytes-1048576);kvm_put32(map+44,1);
    return entry;
}
