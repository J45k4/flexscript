import "kvm.flex";
// Linux x86 boot protocol >=2.12, relocatable 64-bit bzImage, up to 3 GiB RAM.
// Boot payloads remain below 1 GiB, covered by the trampoline's identity map.
// The loader supplies the documented 64-bit entry contract via a native stub.
fn lnx_u16(p) {return load8(p)|(load8(p+1)<<8);}
fn lnx_digit(c) {if c>=65 && c<=70 {return c-55;}if c>=97 {return c-87;}return c-48;}
fn lnx_hex(p,text) {let i=0;while load8(text+i*2) {store8(p+i,lnx_digit(load8(text+i*2))*16+lnx_digit(load8(text+i*2+1)));i=i+1;}return i;}
fn lnx_load_target(ram,bytes,image,size,initrd,initrd_size,cmdline,target) {
    if size<0x26c || lnx_u16(image+0x1fe)!=0xaa55 || kvm_u32(image+0x202)!=0x53726448 || lnx_u16(image+0x206)<0x20c {
        return kvm_fail("Expected a modern Linux bzImage with boot protocol >=2.12.",-22);
    }
    if !(load8(image+0x211)&1) || !(lnx_u16(image+0x236)&1) || !load8(image+0x234) {return kvm_fail("Linux loader requires a relocatable, high-loaded x86-64 kernel.",-95);}
    let sectors=load8(image+0x1f1);if !sectors {sectors=4;}let offset=(sectors+1)*512;
    let payload=kvm_u32(image+0x1f4)*16;let base=0x1000000;let workspace=kvm_u32(image+0x260);let alignment=kvm_u32(image+0x230);
    if alignment<4096 || alignment>base || (alignment&(alignment-1)) || base%alignment {return kvm_fail("Unsupported Linux kernel alignment.",-22);}
    if bytes<67108864 || bytes>3221225472 || offset>size || payload<512 || payload>size-offset || workspace<payload || workspace>1073741824-base || workspace>bytes-base {return kvm_fail("Linux kernel payload or decompression workspace does not fit RAM.",-22);}
    if target && (target<base || target-base>=workspace) {return kvm_fail("Linux entry exceeds kernel workspace.",-22);}
    let header_end=0x202+load8(image+0x201);if header_end<0x264 || header_end>offset || header_end>size {return kvm_fail("Invalid Linux setup header length.",-22);}
    let length=0;while length<4096 && load8(cmdline+length) {length=length+1;}
    if length>=4096 || length>kvm_u32(image+0x238) {return kvm_fail("Linux command line is too long.",-22);}
    let rd=0;
    if initrd_size {
        if initrd_size<0 || initrd_size>bytes-base || !initrd {return kvm_fail("Invalid Linux initramfs.",-22);}
        let ceiling=bytes;if ceiling>1073741824 {ceiling=1073741824;}let maximum=kvm_u32(image+0x22c)+1;if ceiling>maximum {ceiling=maximum;}
        if initrd_size>ceiling-4096 {return kvm_fail("Linux initramfs exceeds its low-memory placement limit.",-22);}
        rd=(ceiling-initrd_size-4096)&~4095;
        if rd<base+workspace || rd+initrd_size-1>kvm_u32(image+0x22c) {return kvm_fail("Linux initramfs overlaps kernel workspace or exceeds address limit.",-22);}
    }
    if !ram {return 0x7000;}
    kvm_copy(ram+base,image+offset,payload);
    let bp=ram+0x90000;kvm_zero(bp,4096);kvm_copy(bp+0x1f1,image+0x1f1,header_end-0x1f1);
    store8(bp+0x210,0xff);store8(bp+0x211,load8(bp+0x211)&~0x60);store8(bp+0x1ef,0);
    kvm_put32(bp+0x214,base);kvm_put32(bp+0x228,0x91000);kvm_put32(bp+0x218,rd);kvm_put32(bp+0x21c,initrd_size);
    kvm_copy(ram+0x91000,cmdline,length+1);if rd {kvm_copy(ram+rd,initrd,initrd_size);}
    store8(bp+0x1e8,3);kvm_put32(bp+0x1e0,(bytes-1048576)/1024);
    let map=bp+0x2d0;
    store64(map,0);store64(map+8,0x9f000);kvm_put32(map+16,1);
    store64(map+20,0x9f000);store64(map+28,0x61000);kvm_put32(map+36,2);
    store64(map+40,1048576);store64(map+48,bytes-1048576);kvm_put32(map+56,1);
    kvm_zero(ram+0x8000,32);store64(ram+0x8010,0x00af9a000000ffff);store64(ram+0x8018,0x00cf92000000ffff);
    kvm_zero(ram+0x8100,10);store8(ram+0x8100,31);store64(ram+0x8102,0x8000);
    let p=ram+0x7000;let n=0;
    n=n+lnx_hex(p+n,"fafcbc00f00800bf0000010031c0b9000c0000f3ab");
    n=n+lnx_hex(p+n,"c7050000010003100100c7050010010003200100");
    n=n+lnx_hex(p+n,"bf00200100b883000000b900020000");
    let loop=n;n=n+lnx_hex(p+n,"8907050000200083c708e2");store8(p+n,loop-n-1);n=n+1;
    n=n+lnx_hex(p+n,"0f20e00d200600000f22e00f20c083e0f383c8020f22c0dbe3");
    n=n+lnx_hex(p+n,"b8000001000f22d8b9800000c00f320d000100000f300f011500810000");
    n=n+lnx_hex(p+n,"0f20c00d000000800f22c0ea");let jump=n;n=n+6;
    kvm_put32(p+jump,0x7000+n);store8(p+jump+4,16);store8(p+jump+5,0);
    if !target {target=base+0x200;}
    n=n+lnx_hex(p+n,"66b818008ed88ec08ed048bc00f008000000000048be000009000000000048b8");store64(p+n,target);n=n+8;
    lnx_hex(p+n,"ffe0");return 0x7000;
}
fn lnx_load(ram,bytes,image,size,initrd,initrd_size,cmdline) {
    return lnx_load_target(ram,bytes,image,size,initrd,initrd_size,cmdline,0);
}
// Optional already-decompressed Linux ELF. Validate all segments before writing.
// The bzImage still supplies setup parameters and the workspace/relocation bound.
fn lnx_elf(ram,limit,image,size) {
    if size<64 || load64(image)!=0x00010102464c457f || lnx_u16(image+16)!=2 || lnx_u16(image+18)!=62 || kvm_u32(image+20)!=1 || lnx_u16(image+52)!=64 || lnx_u16(image+54)!=56 {
        return kvm_fail("Expected an uncompressed Linux ELF64 x86-64 executable.",-22);
    }
    let offset=load64(image+32);let count=lnx_u16(image+56);let entry=load64(image+24);let target=0;
    if offset<64 || offset>size || !count || count>128 || count*56>size-offset {return kvm_fail("Invalid Linux ELF program header bounds.",-22);}
    let i=0;while i<count {
        let ph=image+offset+i*56;
        if kvm_u32(ph)==1 {
            let file=load64(ph+8);let virt=load64(ph+16);let phys=load64(ph+24);let disk=load64(ph+32);let mem=load64(ph+40);
            if file<0 || file>size || disk<0 || disk>size-file || mem<disk || phys<0x1000000 || phys>limit || mem>limit-phys || (phys&4095)!=(virt&4095) {return kvm_fail("Linux ELF segment exceeds file or kernel workspace.",-22);}
            let j=0;while j<i {
                let prev=image+offset+j*56;let start=load64(prev+24);let end=start+load64(prev+40);
                if kvm_u32(prev)==1 && mem && end>start && phys<end && start<phys+mem {return kvm_fail("Overlapping Linux ELF segments.",-22);}j=j+1;
            }
            if mem {
                if entry>=phys && entry-phys<mem {target=entry;}
                else if (entry^0x8000000000000000)>=(virt^0x8000000000000000) && entry-virt>=0 && entry-virt<mem {target=phys+(entry-virt);}
            }
        }i=i+1;
    }
    if !target {return kvm_fail("Linux ELF entry is outside loadable segments.",-22);}
    if ram {i=0;while i<count {let ph=image+offset+i*56;if kvm_u32(ph)==1 {let start=ram+load64(ph+24);kvm_zero(start,load64(ph+40));kvm_copy(start,image+load64(ph+8),load64(ph+32));}i=i+1;}}
    return target;
}
