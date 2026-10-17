import "jit.flex";
import "fpu.flex";
// Bounded x86 interpreter and native block JIT. CPU state is owned per VM.
// Registers follow architectural encoding: AX,CX,DX,BX,SP,BP,SI,DI,R8..R15.
// State: regs[16], IP, flags, mode, CR0/3/4, EFER, GDTR, decode scratch,
// pending IN width, fault, RAM pointer/size, retired count.
global x86_message=0;
global x86_error=0;
fn x86_mask(n) {if n==8 {return -1;}return (1<<(n*8))-1;}
fn x86_signed(v,n) {let shift=(8-n)*8;return (v<<shift)>>shift;}
fn x86_unsigned_lt(a,b) {return (a^0x8000000000000000)<(b^0x8000000000000000);}
fn x86_shr(value,count) {if !count {return value;}return ((value>>1)&0x7fffffffffffffff)>>(count-1);}
fn x86_fault(c,message) {store64(c+288,1);x86_message=message;x86_error=-95;return 0;}
fn x86_gp(c,message) {store64(c+392,2);store64(c+360,0);return x86_fault(c,message);}
fn x86_trap(c,vector,message) {store64(c+392,256+vector);store64(c+360,0);return x86_fault(c,message);}
fn x86_phys(c,address,n) {
    let bytes=load64(c+304);
    if address<0 || address>bytes || n>bytes-address {return x86_fault(c,"Guest physical memory access is outside RAM.");}
    return load64(c+296)+address;
}
fn x86_phys64(c,address) {let p=x86_phys(c,address,8);if !p {return 0;}return load64(p);}
// A physical-page bitmap watches page tables and translated code. Ordinary
// data/stack writes cannot change cached mappings or compiled instructions.
// Watching physical pages also covers aliases and page-table self-mappings.
fn x86_watch(c,physical) {let p=load64(c+432)+(physical>>15);store8(p,load8(p)|(1<<((physical>>12)&7)));return 0;}
fn x86_invalidate_write(c,physical) {
    if load8(load64(c+432)+(physical>>15))&(1<<((physical>>12)&7)) {store64(c+400,load64(c+400)+1);}return 0;
}
fn x86_translate(c,address,write) {
    if !(load64(c+152)&0x80000000) {return address;}
    if !(load64(c+168)&32) || !(load64(c+176)&256) {x86_fault(c,"Only four-level long-mode paging is supported.");return -1;}
    if (address>>47)!=0 && (address>>47)!=-1 {x86_fault(c,"Noncanonical guest address.");return -1;}
    let table=load64(c+160)&0x000ffffffffff000;let level=39;let user=(load64(c+376)&3)==3 && !load64(c+6928);
    while level>=12 {
        let at=table+((address>>level)&511)*8;let entry=x86_phys64(c,at);
        if load64(c+288) {return -1;}x86_watch(c,at);
        if !(entry&1) || (user && !(entry&4)) || (write && !(entry&2) && (user || (load64(c+152)&0x10000))) {store64(c+352,address);store64(c+360,write*2+(entry&1)+user*4);store64(c+392,1);x86_fault(c,"Guest page is absent or disallows this access.");return -1;}
        if (entry&128) && (level==30 || level==21) {let mask=(1<<level)-1;return (entry&0x000ffffffffff000&~mask)|(address&mask);}
        if level==12 {return (entry&0x000ffffffffff000)|(address&4095);}
        table=entry&0x000ffffffffff000;level=level-9;
    }return -1;
}
fn x86_read(c,address,n) {
    if n>0 && n<=8 && (address&4095)+n<=4096 {
        let page=address&~4095;let physical=0;
        // Four-entry read translation cache. Watched writes/control changes
        // and each RUN invalidate it; direct calls outside execution never use it.
        let cache=c+800+((page>>12)&3)*24;let generation=load64(c+400);
        if load64(c+424) && load64(cache+16)==generation && load64(cache)==page {physical=load64(cache+8)|(address&4095);}
        else {physical=x86_translate(c,address,0);if physical<0 {return 0;}if load64(c+424) {store64(cache,page);store64(cache+8,physical&~4095);store64(cache+16,generation);}}
        let p=x86_phys(c,physical,n);if !p {return 0;}
        if n==8 {return load64(p);}if n==1 {return load8(p);}if physical<=load64(c+304)-8 {return load64(p)&x86_mask(n);}let value=0;let j=0;while j<n {value=value|(load8(p+j)<<(j*8));j=j+1;}return value;
    }
    let result=0;let i=0;
    while i<n {let physical=x86_translate(c,address+i,0);if physical<0 {return 0;}let p=x86_phys(c,physical,1);if !p {return 0;}result=result|(load8(p)<<(i*8));i=i+1;}return result;
}
// Descriptor/IDT/TSS reads are implicit supervisor accesses even from CPL3.
// Bypass the data TLB so these reads cannot populate a user-access cache entry.
fn x86_system_read(c,address,n) {let active=load64(c+424);store64(c+424,0);store64(c+6928,1);let value=x86_read(c,address,n);store64(c+6928,0);store64(c+424,active);return value;}
fn x86_canonical(v) {return (v>>47)==0 || (v>>47)==-1;}
fn x86_iret(c) {
    let sp=load64(c+32);let target=x86_read(c,sp,8);let cs=x86_read(c,sp+8,8);let flags=x86_read(c,sp+16,8);let rsp=x86_read(c,sp+24,8);let ss=x86_read(c,sp+32,8);
    if load64(c+288) {return 0;}let old=load64(c+376)&3;let level=cs&3;
    if (level!=0 && level!=3) || level<old || !x86_canonical(target) || !x86_canonical(rsp) || (flags&0x24000) {return x86_gp(c,"Unsupported IRETQ privilege, address or flags.");}
    if level==0 {if ss&3 {return x86_gp(c,"Invalid ring-0 IRETQ stack selector.");}if !x86_far(c,target,cs) {return 0;}}
    else {
        let off=cs&~7;let soff=ss&~7;
        if (cs&4) || (ss&7)!=3 || !off || !soff || off+7>load64(c+192) || soff+7>load64(c+192) {return x86_gp(c,"Invalid user IRETQ GDT selectors.");}
        let code=x86_system_read(c,load64(c+184)+off,8);let data=x86_system_read(c,load64(c+184)+soff,8);if load64(c+288) {return 0;}
        if ((code>>40)&0xfe)!=0xfa || !(code&(1<<53)) || (code&(1<<54)) || ((data>>40)&0xfe)!=0xf2 {return x86_gp(c,"IRETQ requires present 64-bit user code and writable user data.");}
        if ((code>>16)&0xffffff) || ((code>>32)&0xff000000) || ((data>>16)&0xffffff) || ((data>>32)&0xff000000) {return x86_fault(c,"Nonflat user descriptors are not implemented.");}
        store64(c+376,cs&65535);store64(c+128,target);
    }
    if old {let mask=0x3000;if old>((load64(c+136)>>12)&3) {mask=mask|512;}flags=(flags&~mask)|(load64(c+136)&mask);}
    store64(c+136,(flags&0x3f7fd7)|2);store64(c+32,rsp);store64(c+384,ss&65535);store64(c+400,load64(c+400)+1);return 1;
}
fn x86_write(c,address,n,value) {
    if n>0 && n<=8 && (address&4095)+n<=4096 {
        let physical=x86_translate(c,address,1);if physical<0 {return 0;}let p=x86_phys(c,physical,n);if !p {return 0;}x86_invalidate_write(c,physical);
        if n==8 {store64(p,value);}else {let j=0;while j<n {store8(p+j,value>>(j*8));j=j+1;}}return 1;
    }
    // Validate the whole transfer before changing memory.
    let i=0;while i<n {let physical=x86_translate(c,address+i,1);if physical<0 || !x86_phys(c,physical,1) {return 0;}i=i+1;}
    i=0;while i<n {let physical=x86_translate(c,address+i,1);let p=x86_phys(c,physical,1);x86_invalidate_write(c,physical);store8(p,value>>(i*8));i=i+1;}return 1;
}
// Dedicated instruction window avoids general data-TLB lookup for every byte.
// Any guest write or control change invalidates it through the same generation.
fn x86_fetch(c,n) {
    let ip=load64(c+128);if ip-load64(c+200)+n>15 {return x86_fault(c,"Instruction exceeds 15 bytes.");}
    let generation=load64(c+400);let offset=ip-load64(c+968);let p=0;
    if load64(c+424) && load64(c+976)==generation && offset>=0 && offset+n<=load64(c+984) {p=load64(c+960)+offset;}
    else if (ip&4095)+n<=4096 {
        let physical=x86_translate(c,ip,0);if physical<0 {return 0;}p=x86_phys(c,physical,n);if !p {return 0;}
        if load64(c+424) {let available=4096-(ip&4095);let remaining=load64(c+304)-physical;if available>remaining {available=remaining;}store64(c+960,p);store64(c+968,ip);store64(c+976,generation);store64(c+984,available);}
    }
    let value=0;
    if p {if n==1 {value=load8(p);}else if p<=load64(c+296)+load64(c+304)-8 {value=load64(p)&x86_mask(n);}else {let i=0;while i<n {value=value|(load8(p+i)<<(i*8));i=i+1;}}}
    else {value=x86_read(c,ip,n);}
    store64(c+128,ip+n);return value;
}
fn x86_reg(c,r,n) {
    if n==1 && !load64(c+208) && r>=4 && r<8 {return (load64(c+(r-4)*8)>>8)&255;}
    return load64(c+r*8)&x86_mask(n);
}
fn x86_setreg(c,r,n,value) {
    value=value&x86_mask(n);
    if n==1 && !load64(c+208) && r>=4 && r<8 {let p=c+(r-4)*8;store64(p,(load64(p)&~0xff00)|(value<<8));}
    else {let p=c+r*8;if n==4 || n==8 {store64(p,value);}else {store64(p,(load64(p)&~x86_mask(n))|value);}}return 0;
}
fn x86_modrm(c) {
    let m=x86_fetch(c,1);let mod=m>>6;let raw=m&7;let rex=load64(c+208);let width=load64(c+224);
    store64(c+232,((m>>3)&7)+((rex&4)*2));store64(c+256,0);
    if mod==3 {store64(c+240,1);store64(c+248,raw+((rex&1)*8));return m;}
    store64(c+240,0);let address=0;let displacement=0;
    if width==2 {
        if raw==0 || raw==1 || raw==7 {address=load64(c+24);}
        else if raw==2 || raw==3 || (raw==6 && mod!=0) {address=load64(c+40);}
        if raw==0 || raw==2 || raw==4 {address=address+load64(c+48);}
        if raw==1 || raw==3 || raw==5 {address=address+load64(c+56);}
        if raw==6 && mod==0 {displacement=x86_fetch(c,2);}
        else if mod==1 {displacement=x86_signed(x86_fetch(c,1),1);}
        else if mod==2 {displacement=x86_signed(x86_fetch(c,2),2);}
    } else {
        if raw==4 {
            let sib=x86_fetch(c,1);let base=sib&7;let index=(sib>>3)&7;
            if index!=4 || (rex&2) {address=load64(c+(index+((rex&2)*4))*8)<<(sib>>6);}
            if base==5 && mod==0 {displacement=x86_signed(x86_fetch(c,4),4);}
            else {address=address+load64(c+(base+((rex&1)*8))*8);}
        } else if raw==5 && mod==0 {
            displacement=x86_signed(x86_fetch(c,4),4);if width==8 {store64(c+256,1);}
        } else {address=load64(c+(raw+((rex&1)*8))*8);}
        if mod==1 {displacement=x86_signed(x86_fetch(c,1),1);}
        else if mod==2 {displacement=x86_signed(x86_fetch(c,4),4);}
    }
    store64(c+248,(address+displacement)&x86_mask(width));return m;
}
fn x86_address(c) {let address=load64(c+248);if load64(c+256) {address=address+load64(c+128);}return address&x86_mask(load64(c+224));}
fn x86_linear(c) {return x86_address(c)+load64(c+456);}
fn x86_rm(c,n) {if load64(c+240) {return x86_reg(c,load64(c+248),n);}return x86_read(c,x86_linear(c),n);}
fn x86_setrm(c,n,value) {if load64(c+240) {return x86_setreg(c,load64(c+248),n,value);}return x86_write(c,x86_linear(c),n,value);}
fn x86_flags(c,result,n,cf,of,af) {
    result=result&x86_mask(n);let parity=result&255;parity=parity^(parity>>4);parity=parity^(parity>>2);parity=parity^(parity>>1);
    let flags=load64(c+136)&~0x8d5;
    if cf {flags=flags|1;}if !(parity&1) {flags=flags|4;}if af {flags=flags|16;}if result==0 {flags=flags|64;}if result&(1<<(n*8-1)) {flags=flags|128;}if of {flags=flags|2048;}store64(c+136,flags);return result;
}
// ALU encoding groups: add,or,adc,sbb,and,sub,xor,cmp.
fn x86_alu(c,op,a,b,n) {
    let mask=x86_mask(n);a=a&mask;b=b&mask;let sign=1<<(n*8-1);let result=0;let cf=0;let of=0;let af=0;
    if op==0 || op==2 || op==3 || op==5 || op==7 {
        let carry=0;if op==2 || op==3 {carry=load64(c+136)&1;}
        if op==0 || op==2 {let partial=(a+b)&mask;result=(partial+carry)&mask;cf=x86_unsigned_lt(partial,a) || x86_unsigned_lt(result,partial);of=(~(a^b)&(a^result)&sign)!=0;}
        else {result=(a-b-carry)&mask;cf=x86_unsigned_lt(a,b) || (a==b && carry);of=((a^b)&(a^result)&sign)!=0;}
        af=((a^b^result)&16)!=0;
    } else if op==1 {result=a|b;}else if op==4 {result=a&b;}else if op==6 {result=a^b;}
    else {return x86_fault(c,"Unsupported ALU operation.");}
    return x86_flags(c,result,n,cf,of,af);
}
fn x86_condition(c,condition) {
    let f=load64(c+136);let cf=(f&1)!=0;let zf=(f&64)!=0;let sf=(f&128)!=0;let of=(f&2048)!=0;let value=0;
    let base=condition/2;
    if base==0 {value=of;}else if base==1 {value=cf;}else if base==2 {value=zf;}else if base==3 {value=cf || zf;}
    else if base==4 {value=sf;}else if base==5 {value=(f&4)!=0;}else if base==6 {value=sf!=of;}else {value=zf || sf!=of;}
    if condition&1 {value=!value;}return value;
}
fn x86_stackwidth(c) {if load64(c+144)==64 {if load64(c+216)==2 {return 2;}return 8;}return load64(c+216);}
fn x86_push(c,value,n) {let sp=(load64(c+32)-n)&x86_mask(load64(c+144)/8);if !x86_write(c,sp,n,value) {return 0;}store64(c+32,sp);return 1;}
fn x86_pop(c,n) {let sp=load64(c+32);let value=x86_read(c,sp,n);store64(c+32,(sp+n)&x86_mask(load64(c+144)/8));return value;}
fn x86_far(c,target,selector) {
    if load64(c+376)&3 {return x86_gp(c,"User far transfers are not implemented.");}
    let offset=selector&~7;
    if (selector&7) || !offset || offset+7>load64(c+192) {return x86_fault(c,"Invalid flat code GDT selector.");}
    let descriptor=x86_read(c,load64(c+184)+offset,8);
    let base=((descriptor>>16)&0xffffff)|((descriptor>>32)&0xff000000);
    if base || !(descriptor&(1<<47)) || !(descriptor&(1<<44)) || !(descriptor&(1<<43)) || (descriptor&(3<<45)) {return x86_fault(c,"Unsupported code descriptor.");}
    let mode=32;
    if descriptor&(1<<53) {
        if !(load64(c+176)&256) || !(load64(c+152)&0x80000000) || (descriptor&(1<<54)) {return x86_fault(c,"Invalid long-mode code handoff.");}
        mode=64;store64(c+176,load64(c+176)|1024);
    }else if !(descriptor&(1<<54)) {return x86_fault(c,"16-bit protected code segments are not implemented.");}
    store64(c+376,selector);store64(c+144,mode);store64(c+128,target);return 1;
}
fn x86_create(ram,bytes) {
    let c=alloc(8192);if c<0 {x86_message="Cannot allocate software CPU.";x86_error=c;return 0;}
    let watch_bytes=((bytes+262143)/262144)*8;let watch=alloc(watch_bytes);if watch<0 {syscall(11,c,8192,0,0,0,0);x86_message="Cannot allocate physical-page watch bitmap.";x86_error=watch;return 0;}
    store64(c+432,watch);store64(c+440,watch_bytes);store64(c+296,ram);store64(c+304,bytes);store64(c+136,2);store64(c+144,16);xf_reset(c);return c;
}
fn x86_close(c) {if c {xj_close(c);xf_close(c);syscall(11,load64(c+432),load64(c+440),0,0,0,0);syscall(11,c,8192,0,0,0,0);}return 0;}
fn x86_start(c,entry,bits,a,b) {
    if (bits!=16 && bits!=32) || entry<0 || entry>=load64(c+304) || (bits==16 && entry>=65536) {return x86_fault(c,"Invalid software CPU entry or mode.");}
    xj_reset(c);xf_reset(c);let watch=load64(c+432);let watch_bytes=load64(c+440);let clear=0;while clear<watch_bytes {store8(watch+clear,0);clear=clear+1;}let i=0;while i<296 {store8(c+i,0);i=i+1;}i=312;while i<992 {store8(c+i,0);i=i+1;}store64(c,a);store64(c+24,b);store64(c+32,0x8000);store64(c+128,entry);store64(c+136,2);store64(c+944,0xffff0ff0);store64(c+952,0x400);store64(c+144,bits);store64(c+432,watch);store64(c+440,watch_bytes);if bits==32 {store64(c+152,1);}return 1;
}
fn x86_io(c,run,out,port,n) {
    store8(run+32,out);store8(run+33,n);store8(run+34,port);store8(run+35,port>>8);
    store64(run+36,1);store64(run+40,128); // count's high bytes overwritten by offset
    if out {store64(run+128,x86_reg(c,0,n));}else {store64(c+280,n);}return 2;
}
fn x86_cpuid(c) {
    let leaf=load64(c)&0xffffffff;let a=0;let b=0;let d=0;let e=0;
    // libc's baseline ISA discovery requires a recognized architectural vendor.
    // Keep our own identity in the hypervisor leaf and advertise only supported bits.
    if leaf==0 {a=7;b=0x756e6547;d=0x49656e69;e=0x6c65746e;} // "GenuineIntel"
    else if leaf==1 {a=0x600;e=1<<31;d=1|(1<<5)|(1<<6)|(1<<8)|(1<<15)|(1<<23)|(1<<24)|(1<<25)|(1<<26);}
    else if leaf==0x40000000 {a=0x40000000;b=0x78656c46;e=0x74666f53;d=0x74726956;} // "FlexSoftVirt"
    else if leaf==0x80000000 {a=0x80000008;}
    else if leaf==0x80000001 {d=(1<<29)|(1<<11);}
    else if leaf==0x80000008 {a=0x3024;}
    x86_setreg(c,0,4,a);x86_setreg(c,3,4,b);x86_setreg(c,1,4,e);x86_setreg(c,2,4,d);return 0;
}
fn x86_multiply(c,a,b,n,signed) {
    let mask=x86_mask(n);a=a&mask;b=b&mask;let low=0;let high=0;
    if n<8 {if signed {a=x86_signed(a,n);b=x86_signed(b,n);}let product=a*b;low=product&mask;high=(product>>(n*8))&mask;}
    else {
        let a0=a&0xffffffff;let a1=(a>>32)&0xffffffff;let b0=b&0xffffffff;let b1=(b>>32)&0xffffffff;
        let p=a0*b0;let middle=a1*b0+((p>>32)&0xffffffff);let upper=(middle>>32)&0xffffffff;
        let middle2=a0*b1+(middle&0xffffffff);high=a1*b1+upper+((middle2>>32)&0xffffffff);low=(middle2<<32)|(p&0xffffffff);
        if signed {if a<0 {high=high-b;}if b<0 {high=high-a;}}
    }
    store64(c+344,high);let expected=0;if signed && (low&(1<<(n*8-1))) {expected=mask;}
    let flags=load64(c+136)&~0x801;if high!=expected {flags=flags|0x801;}store64(c+136,flags);return low;
}
fn x86_udiv(c,high,low,divisor,n) {
    let mask=x86_mask(n);high=high&mask;low=low&mask;divisor=divisor&mask;
    if !divisor {return x86_fault(c,"Guest division by zero.");}
    if !x86_unsigned_lt(high,divisor) {return x86_fault(c,"Guest division overflow.");}
    let quotient=0;let remainder=high;let bit=n*8-1;
    while bit>=0 {let overflow=(remainder>>(n*8-1))&1;remainder=((remainder<<1)|((low>>bit)&1))&mask;
        if overflow || !x86_unsigned_lt(remainder,divisor) {remainder=(remainder-divisor)&mask;quotient=quotient|(1<<bit);}bit=bit-1;
    }store64(c+344,remainder);return quotient;
}
fn x86_step(c,run) {
    store64(c+200,load64(c+128));store64(c+208,0);store64(c+456,0);let mode=load64(c+144);let n=4;if mode==16 {n=2;}let addr=mode/8;
    let locked=0;let repeat=0;let op=x86_fetch(c,1);let prefixes=0;let operand_override=0;let address_override=0;let mandatory=0;
    while op==0x66 || op==0x67 || op==0xf0 || op==0xf2 || op==0xf3 || op==0x64 || op==0x65 || op==0x26 || op==0x2e || op==0x36 || op==0x3e || (mode==64 && op>=0x40 && op<=0x4f) {
        prefixes=prefixes+1;if prefixes>=15 {return x86_fault(c,"Too many instruction prefixes.");}
        if op==0x66 {operand_override=1;mandatory=op;store64(c+208,0);}else if op==0x67 {address_override=1;store64(c+208,0);}
        else if op==0xf0 {locked=1;store64(c+208,0);}
        else if op==0xf3 || op==0xf2 {repeat=1;if op==0xf2 {repeat=2;}mandatory=op;store64(c+208,0);}
        else if op==0x64 || op==0x65 {if mode!=64 {return x86_fault(c,"Legacy FS/GS segments are not implemented.");}let slot=464;if op==0x65 {slot=472;}store64(c+456,load64(c+slot));store64(c+208,0);}else if op==0x26 || op==0x2e || op==0x36 || op==0x3e {store64(c+456,0);store64(c+208,0);}else {store64(c+208,op);}op=x86_fetch(c,1);
    }
    if operand_override {if mode==16 {n=4;}else {n=2;}}
    if mode==64 && (load64(c+208)&8) {n=8;}
    if address_override {if mode==16 {addr=4;}else if mode==32 {addr=2;}else {addr=4;}}
    store64(c+216,n);store64(c+224,addr);let rex=load64(c+208);let stack=x86_stackwidth(c);
    if load64(c+288) {return -1;}
    let cpl=load64(c+376)&3;
    if cpl && op==0xf4 {return x86_gp(c,"User HLT raised general protection.");}
    if (op==0xfa || op==0xfb) && cpl>((load64(c+136)>>12)&3) {return x86_gp(c,"Guest interrupt flag change exceeds IOPL.");}
    if locked {
        let m=x86_read(c,load64(c+128),1);let valid=0;
        if op==0x0f {let second=m;m=x86_read(c,load64(c+128)+1,1);valid=second==0xb0 || second==0xb1 || second==0xc0 || second==0xc1 || second==0xab || second==0xb3 || second==0xbb || (second==0xc7 && ((m>>3)&7)==1) || (second==0xba && ((m>>3)&7)>=5);}
        else {let group=(m>>3)&7;valid=(op<=0x31 && (op&7)<=1) || op==0x86 || op==0x87 || ((op==0x80 || op==0x81 || op==0x83) && group!=7) || ((op==0xff || op==0xfe) && group<2) || ((op==0xf6 || op==0xf7) && (group==2 || group==3));}
        if !valid || m>=192 || repeat || load64(c+288) {return x86_fault(c,"Invalid or unsupported LOCK instruction.");}
    }
    if repeat && op!=0xab && op!=0xaa && op!=0xa4 && op!=0xa5 && op!=0x90 && op!=0xc3 && op!=0x0f {return x86_fault(c,"Unsupported repeated instruction.");}
    if mode!=64 && op>=0x40 && op<=0x4f {let r=op&7;let carry=load64(c+136)&1;let operation=0;if op&8 {operation=5;}x86_setreg(c,r,n,x86_alu(c,operation,x86_reg(c,r,n),1,n));store64(c+136,(load64(c+136)&~1)|carry);}
    else if op>=0xb0 && op<=0xb7 {let value=x86_fetch(c,1);x86_setreg(c,op-0xb0+(rex&1)*8,1,value);}
    else if op>=0xb8 && op<=0xbf {let value=x86_fetch(c,n);x86_setreg(c,op-0xb8+(rex&1)*8,n,value);}
    else if op>=0x50 && op<=0x57 {x86_push(c,x86_reg(c,op-0x50+(rex&1)*8,stack),stack);}
    else if op>=0x58 && op<=0x5f {let value=x86_pop(c,stack);x86_setreg(c,op-0x58+(rex&1)*8,stack,value);}
    else if op==0x68 || op==0x6a {let size=n;if size==8 {size=4;}if op==0x6a {size=1;}let value=x86_signed(x86_fetch(c,size),size);x86_push(c,value,stack);}
    else if op>=0x90 && op<=0x97 {let r=op-0x90+(rex&1)*8;if r {let a=x86_reg(c,0,n);let b=x86_reg(c,r,n);x86_setreg(c,0,n,b);x86_setreg(c,r,n,a);}}
    else if op==0xf8 {store64(c+136,load64(c+136)&~1);}
    else if op==0xf9 {store64(c+136,load64(c+136)|1);}
    else if op==0xf5 {store64(c+136,load64(c+136)^1);}
    else if op==0xfa {store64(c+136,load64(c+136)&~512);}
    else if op==0xfb {store64(c+136,load64(c+136)|512);store64(c+496,load64(c+312)+2);}
    else if op==0xfc {store64(c+136,load64(c+136)&~1024);}
    else if op==0xfd {store64(c+136,load64(c+136)|1024);}
    else if op==0xf4 {return 5;}
    else if op==0xcc {store64(c+640,load64(c+128));return x86_trap(c,3,"Guest INT3 breakpoint trap.");}
    else if op==0xc3 {store64(c+128,x86_pop(c,stack));}
    else if op==0xcb {let target=x86_pop(c,n);let selector=x86_pop(c,n);x86_far(c,target,selector);}
    else if op==0xcf {
        if mode!=64 || n!=8 {return x86_fault(c,"Only 64-bit IRETQ is implemented.");}if !x86_iret(c) {return -1;}
    }
    else if op==0x9c {x86_push(c,load64(c+136),stack);}
    else if op==0x9d {let flags=x86_pop(c,stack);let mask=0x10000;if cpl {mask=mask|0x3000;}if cpl>((load64(c+136)>>12)&3) {mask=mask|512;}store64(c+136,(flags&~mask)|(load64(c+136)&mask)|2);}
    else if op==0xc9 {store64(c+32,load64(c+40));let value=x86_pop(c,stack);x86_setreg(c,5,stack,value);}
    else if op==0xe8 || op==0xe9 || op==0xeb {
        let width=n;if mode==64 {width=4;}if op==0xeb {width=1;}let displacement=x86_signed(x86_fetch(c,width),width);let next=load64(c+128);
        if op==0xe8 {x86_push(c,next,stack);}store64(c+128,(next+displacement)&x86_mask(mode/8));
    }
    else if op>=0x70 && op<=0x7f {let displacement=x86_signed(x86_fetch(c,1),1);if x86_condition(c,op&15) {store64(c+128,(load64(c+128)+displacement)&x86_mask(mode/8));}}
    else if op==0xe2 {let displacement=x86_signed(x86_fetch(c,1),1);let count=(load64(c+8)-1)&x86_mask(addr);x86_setreg(c,1,addr,count);if count {store64(c+128,(load64(c+128)+displacement)&x86_mask(mode/8));}}
    else if op==0xa1 || op==0xa3 {let address=x86_fetch(c,addr)+load64(c+456);if op==0xa1 {x86_setreg(c,0,n,x86_read(c,address,n));}else {x86_write(c,address,n,x86_reg(c,0,n));}}
    else if op==0xa8 || op==0xa9 {if op==0xa8 {n=1;}let size=n;if size==8 {size=4;}let value=x86_signed(x86_fetch(c,size),size);x86_alu(c,4,x86_reg(c,0,n),value,n);}
    else if op==0x63 {if mode!=64 {return x86_fault(c,"ARPL is not implemented.");}x86_modrm(c);x86_setreg(c,load64(c+232),n,x86_signed(x86_rm(c,4),4));}
    else if op==0x69 || op==0x6b {
        x86_modrm(c);let r=load64(c+232);let width=n;if width==8 {width=4;}if op==0x6b {width=1;}let value=x86_signed(x86_fetch(c,width),width);x86_setreg(c,r,n,x86_multiply(c,x86_rm(c,n),value,n,1));
    }
    else if op==0xab || op==0xaa || op==0xa4 || op==0xa5 {
        // Batch REP iterations without changing per-iteration fuel or fault state.
        if op==0xaa || op==0xa4 {n=1;}
        let count=1;if repeat {count=x86_reg(c,1,addr);}let batch=1;
        if repeat && load64(c+768)>load64(c+312) {batch=count;if batch>256 {batch=256;}let left=load64(c+768)-load64(c+312);if batch>left {batch=left;}}
        let completed=0;
        while count && completed<batch {
            let fast=0;if x86_jit_enabled && repeat && batch-completed>=8 {fast=xj_rep_batch(c,n,addr,op,batch-completed);}
            if fast {count=count-fast;completed=completed+fast;}else {
            let destination=x86_reg(c,7,addr);let value=x86_reg(c,0,n);let source=x86_reg(c,6,addr);if op==0xa4 || op==0xa5 {value=x86_read(c,source+load64(c+456),n);}
            if load64(c+288) || !x86_write(c,destination,n,value) {
                store64(c+312,load64(c+312)+completed);
                // Completed iterations remain committed when #PF retries this REP.
                if load64(c+328)>=239 {
                store64(c+512,load64(c+0));store64(c+520,load64(c+8));store64(c+528,load64(c+16));
                store64(c+536,load64(c+24));store64(c+544,load64(c+32));store64(c+552,load64(c+40));
                store64(c+560,load64(c+48));store64(c+568,load64(c+56));store64(c+576,load64(c+64));
                store64(c+584,load64(c+72));store64(c+592,load64(c+80));store64(c+600,load64(c+88));
                store64(c+608,load64(c+96));store64(c+616,load64(c+104));store64(c+624,load64(c+112));
                store64(c+632,load64(c+120));store64(c+640,load64(c+128));store64(c+648,load64(c+136));store64(c+640,load64(c+200));}
                return -1;
            }
            let delta=n;if load64(c+136)&1024 {delta=-n;}x86_setreg(c,7,addr,destination+delta);
            if op==0xa4 || op==0xa5 {x86_setreg(c,6,addr,source+delta);}
            count=count-1;completed=completed+1;if repeat {x86_setreg(c,1,addr,count);}
            }
        }
        if repeat && count {store64(c+128,load64(c+200));}
        if completed {store64(c+312,load64(c+312)+completed-1);}
    }
    else if op==0xec || op==0xed || op==0xee || op==0xef || op==0xe4 || op==0xe5 || op==0xe6 || op==0xe7 {
        if cpl>((load64(c+136)>>12)&3) {return x86_gp(c,"Guest port access requires IOPL; TSS I/O bitmap is not implemented.");}
        let port=load64(c+16)&65535;if op>=0xe4 && op<=0xe7 {port=x86_fetch(c,1);}let size=1;if op&1 {size=n;if size==8 {size=4;}}
        return x86_io(c,run,(op&2)!=0,port,size);
    }
    else if op==0x99 {let high=0;if x86_signed(x86_reg(c,0,n),n)<0 {high=-1;}x86_setreg(c,2,n,high);}
    else if op==0x98 {let from=n/2;if n==8 {from=4;}x86_setreg(c,0,n,x86_signed(x86_reg(c,0,from),from));}
    else if op==0xea {
        if mode!=32 {return x86_fault(c,"Only 32-bit far jumps are supported.");}
        let target=x86_fetch(c,4);let selector=x86_fetch(c,2);x86_far(c,target,selector);
    }
    else if op==0x0f {
        let second=x86_fetch(c,1);
        if cpl && (second==0x20 || second==0x22 || second==0x21 || second==0x23 || second==0x30 || second==0x32 || second==0x06 || second==0x08 || second==0x09) {return x86_gp(c,"Guest privileged instruction requires CPL0.");}
        if second==0xa2 {x86_cpuid(c);}
        else if second==0x31 {
            if cpl && (load64(c+168)&4) {return x86_gp(c,"RDTSC is disabled for user mode by CR4.TSD.");}
            // Deterministic instruction count, including idle time. The monitor
            // may separately scale PIT/RTC time to allow longer CPU slices.
            let ticks=load64(c+312)+load64(c+504);x86_setreg(c,0,4,ticks);x86_setreg(c,2,4,ticks>>32);
        }
        else if second==0x05 {
            if mode!=64 || !(load64(c+176)&1) {return x86_trap(c,6,"SYSCALL requires 64-bit mode and EFER.SCE.");}
            let target=load64(c+744);if !x86_canonical(target) {return x86_gp(c,"Noncanonical SYSCALL entry.");}
            store64(c+8,load64(c+128));store64(c+88,load64(c+136)&~0x10000);store64(c+136,(load64(c+136)&~(load64(c+760)|0x10000))|2);
            let selector=(load64(c+736)>>32)&0xfffc;store64(c+376,selector);store64(c+384,(selector+8)&65535);store64(c+128,target);store64(c+400,load64(c+400)+1);
        }
        else if second==0x07 {
            if mode!=64 || !(load64(c+176)&1) {return x86_trap(c,6,"SYSRET requires EFER.SCE.");}
            if cpl {return x86_gp(c,"SYSRET requires CPL0.");}if n!=8 {return x86_fault(c,"Compatibility-mode SYSRET is not implemented.");}
            let target=load64(c+8);if !x86_canonical(target) {return x86_gp(c,"Noncanonical SYSRET target.");}
            let selector=(load64(c+736)>>48)&65535;store64(c+376,((selector+16)&65535)|3);store64(c+384,((selector+8)&65535)|3);store64(c+128,target);store64(c+136,(load64(c+88)&0x3c7fd7)|2);store64(c+400,load64(c+400)+1);
        }
        else if !mandatory && xf_mmx_opcode(second) {xf_mmx(c,second);}
        else if xf_vector_opcode(second,mandatory) {xf_vector(c,second,mandatory);}
        else if second>=0x40 && second<=0x4f {x86_modrm(c);let value=x86_rm(c,n);let r=load64(c+232);if x86_condition(c,second&15) {x86_setreg(c,r,n,value);}else if n==4 && mode==64 {x86_setreg(c,r,4,x86_reg(c,r,4));}}
        else if second>=0x80 && second<=0x8f {let width=n;if mode==64 {width=4;}let displacement=x86_signed(x86_fetch(c,width),width);if x86_condition(c,second&15) {store64(c+128,(load64(c+128)+displacement)&x86_mask(mode/8));}}
        else if second>=0x90 && second<=0x9f {x86_modrm(c);x86_setrm(c,1,x86_condition(c,second&15));}
        else if second==0xa4 || second==0xa5 || second==0xac || second==0xad {
            x86_modrm(c);let source=x86_reg(c,load64(c+232),n);let count=load64(c+8)&255;
            if !(second&1) {count=x86_fetch(c,1);}let mask=31;if n==8 {mask=63;}count=count&mask;
            if count>n*8 {return x86_fault(c,"Undefined double-shift count exceeds operand width.");}
            let old=x86_rm(c,n);let result=old;
            if count {
                let carry=0;let overflow=(load64(c+136)>>11)&1;
                if second&8 {result=x86_shr(old,count)|(source<<(n*8-count));carry=(old>>(count-1))&1;if count==1 {overflow=((old^result)>>(n*8-1))&1;}}
                else {result=(old<<count)|x86_shr(source,n*8-count);carry=(old>>(n*8-count))&1;if count==1 {overflow=((result>>(n*8-1))&1)^carry;}}
                result=x86_flags(c,result,n,carry,overflow,(load64(c+136)>>4)&1);
            }
            x86_setrm(c,n,result);
        }
        else if second==0xba || second==0xa3 || second==0xab || second==0xb3 || second==0xbb {
            let m=x86_modrm(c);let operation=4;let index=0;
            if second==0xba {operation=(m>>3)&7;index=x86_fetch(c,1);if operation<4 {return x86_fault(c,"Invalid immediate bit operation.");}}
            else {index=x86_signed(x86_reg(c,load64(c+232),n),n);if second==0xab {operation=5;}else if second==0xb3 {operation=6;}else if second==0xbb {operation=7;}}
            let bits=n*8;
            if !load64(c+240) && second!=0xba {let shift=4;if n==4 {shift=5;}if n==8 {shift=6;}store64(c+248,load64(c+248)+(index>>shift)*n);}
            let bit=1<<(index&(bits-1));let value=x86_rm(c,n);let carry=(value&bit)!=0;store64(c+136,(load64(c+136)&~1)|carry);
            if operation==5 {x86_setrm(c,n,value|bit);}else if operation==6 {x86_setrm(c,n,value&~bit);}else if operation==7 {x86_setrm(c,n,value^bit);}
        }
        else if second==0xbc || second==0xbd {
            x86_modrm(c);let value=x86_rm(c,n);let flags=load64(c+136)&~64;
            if !value {flags=flags|64;}else {let bit=0;if second==0xbc {while !((value>>bit)&1) {bit=bit+1;}}else {bit=n*8-1;while !((value>>bit)&1) {bit=bit-1;}}x86_setreg(c,load64(c+232),n,bit);}store64(c+136,flags);
        }
        else if second>=0xc8 && second<=0xcf {
            if n==2 {return x86_fault(c,"16-bit BSWAP is undefined.");}let r=second-0xc8+(rex&1)*8;let value=x86_reg(c,r,n);let result=0;let i=0;while i<n {result=(result<<8)|((value>>(i*8))&255);i=i+1;}x86_setreg(c,r,n,result);
        }
        else if second==0xc7 {
            let m=x86_modrm(c);if ((m>>3)&7)!=1 || load64(c+240) {return x86_trap(c,6,"Invalid CMPXCHG8B operand.");}
            if rex&8 {return x86_fault(c,"CMPXCHG16B is not implemented.");}
            let address=x86_linear(c);let old=x86_read(c,address,8);if load64(c+288) {return -1;}
            let expected=(load64(c)&0xffffffff)|((load64(c+16)&0xffffffff)<<32);let replacement=old;
            if old==expected {replacement=(load64(c+24)&0xffffffff)|((load64(c+8)&0xffffffff)<<32);}
            if !x86_write(c,address,8,replacement) {return -1;}
            store64(c+136,(load64(c+136)&~64)|((old==expected)*64));if old!=expected {x86_setreg(c,0,4,old);x86_setreg(c,2,4,old>>32);}
        }
        else if second==0xb0 || second==0xb1 || second==0xc0 || second==0xc1 {
            if second==0xb0 || second==0xc0 {n=1;}x86_modrm(c);let r=load64(c+232);let old=x86_rm(c,n);let source=x86_reg(c,r,n);
            if second==0xb0 || second==0xb1 {let acc=x86_reg(c,0,n);x86_alu(c,7,acc,old,n);if acc==old {x86_setrm(c,n,source);}else {if !load64(c+240) {x86_setrm(c,n,old);}x86_setreg(c,0,n,old);}}
            else {let result=x86_alu(c,0,old,source,n);x86_setrm(c,n,result);if !load64(c+240) || load64(c+248)!=r {x86_setreg(c,r,n,old);}}
        }
        else if second==0xb6 || second==0xb7 || second==0xbe || second==0xbf || second==0xaf {
            x86_modrm(c);let r=load64(c+232);
            if second==0xaf {x86_setreg(c,r,n,x86_multiply(c,x86_reg(c,r,n),x86_rm(c,n),n,1));}
            else {let width=1;if second==0xb7 || second==0xbf {width=2;}let value=x86_rm(c,width);if second==0xbe || second==0xbf {value=x86_signed(value,width);}x86_setreg(c,r,n,value);}
        }
        else if second==0x20 || second==0x22 {
            let m=x86_modrm(c);let control=load64(c+232);let slot=0;if control==0 {slot=152;}else if control==2 {slot=368;}else if control==3 {slot=160;}else if control==4 {slot=168;}
            if m<192 || !slot {return x86_fault(c,"Unsupported control-register access.");}
            let width=4;if mode==64 {width=8;}if second==0x20 {x86_setrm(c,width,load64(c+slot));}else {store64(c+slot,x86_rm(c,width));store64(c+400,load64(c+400)+1);}
        }
        else if second==0x21 || second==0x23 {
            let m=x86_modrm(c);let reg=load64(c+232);
            if m<192 || reg>7 {return x86_fault(c,"Invalid debug-register access.");}
            if reg==4 || reg==5 {if load64(c+168)&8 {return x86_fault(c,"DR4/DR5 aliases disabled by CR4.DE.");}reg=reg+2;}
            let width=4;if mode==64 {width=8;}let slot=c+896+reg*8;
            if second==0x21 {x86_setrm(c,width,load64(slot));}
            else {let value=x86_rm(c,width);if reg==7 && (value&0x20ff) {return x86_fault(c,"Hardware breakpoints and debug traps are not implemented.");}store64(slot,value);}
        }
        else if second==0x32 || second==0x30 {
            let msr=load64(c+8)&0xffffffff;let slot=0;if msr==0xc0000080 {slot=176;}else if msr==0xc0000100 {slot=464;}else if msr==0xc0000101 {slot=472;}else if msr==0xc0000102 {slot=480;}else if msr==0xc0000081 {slot=736;}else if msr==0xc0000082 {slot=744;}else if msr==0xc0000083 {slot=752;}else if msr==0xc0000084 {slot=760;}else if msr==0x174 {slot=776;}else if msr==0x175 {slot=784;}else if msr==0x176 {slot=792;}
            if !slot {return x86_gp(c,"Unimplemented MSR raised guest general protection.");}
            if second==0x32 {let value=load64(c+slot);x86_setreg(c,0,4,value);x86_setreg(c,2,4,value>>32);}
            else {let value=(load64(c)&0xffffffff)|((load64(c+16)&0xffffffff)<<32);if slot==176 && (value&~0xd01) {return x86_fault(c,"Unsupported EFER bits.");}if (slot==464 || slot==472 || slot==480 || slot==744 || slot==752 || slot==784 || slot==792) && (value>>47)!=0 && (value>>47)!=-1 {return x86_fault(c,"Noncanonical guest MSR address.");}store64(c+slot,value);store64(c+400,load64(c+400)+1);}
        }
        else if second==0x00 {
            let m=x86_modrm(c);let group=(m>>3)&7;
            if cpl && (group==2 || group==3) {return x86_gp(c,"Loading system segments requires CPL0.");}
            if group==0 || group==1 {let slot=728;if group==1 {slot=704;}let width=n;if !load64(c+240) {width=2;}x86_setrm(c,width,load64(c+slot));}
            else if group==4 || group==5 {
                if mode==16 {return x86_trap(c,6,"VERR/VERW requires protected mode.");}
                let selector=x86_rm(c,2);if load64(c+288) {return -1;}
                let offset=selector&~7;let valid=0;
                // A null/unavailable LDT selector or GDT limit failure clears
                // ZF, rather than raising #GP. Presence is not checked by VERR/W.
                if !(selector&4) && offset && offset+7<=load64(c+192) {
                    let d=x86_system_read(c,load64(c+184)+offset,8);if load64(c+288) {return -1;}
                    let type=(d>>40)&15;let dpl=(d>>45)&3;let cpl=load64(c+376)&3;let rpl=selector&3;
                    let accessible=dpl>=cpl && dpl>=rpl;
                    if group==4 && (type&12)==12 {accessible=1;}
                    if d&(1<<44) {if group==5 {valid=accessible && !(type&8) && (type&2);}else {valid=accessible && (!(type&8) || (type&2));}}
                }
                store64(c+136,(load64(c+136)&~64)|(valid!=0)*64);
            }
            else if group==2 {if x86_rm(c,2) {return x86_fault(c,"Only a null LDTR is implemented.");}store64(c+728,0);}
            else if group==3 {
                if mode!=64 {return x86_fault(c,"Only a 64-bit task register is implemented.");}
                let selector=x86_rm(c,2);let offset=selector&~7;
                if (selector&4) || !offset || offset+15>load64(c+192) {return x86_fault(c,"Invalid TSS GDT selector.");}
                let address=load64(c+184)+offset;let desc=x86_read(c,address,8);let upper=x86_read(c,address+8,8);
                let limit=(desc&65535)|((desc>>32)&0xf0000);if desc&(1<<55) {limit=(limit<<12)|4095;}
                if load64(c+288) {return -1;}
                if ((desc>>40)&31)!=9 || !(desc&(1<<47)) || (upper>>32) || limit<103 {return x86_fault(c,"Invalid available 64-bit TSS descriptor.");}
                let base=((desc>>16)&0xffffff)|((desc>>32)&0xff000000)|(upper<<32);
                if (base>>47)!=0 && (base>>47)!=-1 {return x86_fault(c,"Noncanonical TSS base.");}
                if !x86_write(c,address,8,desc|(1<<41)) {return -1;}store64(c+704,selector);store64(c+712,base);store64(c+720,limit);
            }else {return x86_fault(c,"Unsupported system-segment instruction.");}
        }
        else if second==0x01 {
            let m=x86_modrm(c);let group=(m>>3)&7;
            if cpl && (m==0xf8 || group>=2) {return x86_gp(c,"Guest system operation requires CPL0.");}
            if m==0xf8 && mode==64 {let base=load64(c+472);store64(c+472,load64(c+480));store64(c+480,base);return 0;}
            if group==7 && !load64(c+240) {store64(c+400,load64(c+400)+1);return 0;} // INVLPG
            if group>3 || load64(c+240) {return x86_fault(c,"Unsupported descriptor-table instruction.");}
            let address=x86_linear(c);let limit=192;let base=184;if group&1 {limit=328;base=320;}let width=4;if mode==64 {width=8;}
            if group<2 {let i=0;while i<width+2 {let phys=x86_translate(c,address+i,1);if phys<0 || !x86_phys(c,phys,1) {return -1;}i=i+1;}x86_write(c,address,2,load64(c+limit));x86_write(c,address+2,width,load64(c+base));}
            else {let value=x86_read(c,address,2);let pointer=x86_read(c,address+2,width);if load64(c+288) {return -1;}store64(c+limit,value);store64(c+base,pointer);}
        }
        else if second==0xae {let m=x86_modrm(c);if m!=0xe8 && m!=0xf0 && m!=0xf8 {xf_fx(c,m);}}
        else if second==0x18 {let m=x86_modrm(c);if load64(c+240) || (m&0x38)>24 {return x86_fault(c,"Unsupported prefetch hint.");}}
        else if second==0x1f {let m=x86_modrm(c);if (m&0x38)!=0 {return x86_fault(c,"Invalid multi-byte NOP.");}}
        else if second==0x1e && mandatory==0xf3 {
            let form=x86_fetch(c,1);
            if form==0xfa || form==0xfb {} // ENDBR64/ENDBR32, with CET unadvertised.
            else if (form&0xf8)==0xc8 {if load64(c+168)&(1<<23) {return x86_fault(c,"CET shadow stacks are not implemented.");}} // RDSSP is a NOP without CET.
            else {return x86_fault(c,"Unsupported CET instruction form.");}
        }
        else {return x86_fault(c,"Unsupported two-byte x86 opcode.");}
    }
    else if op>=0xd8 && op<=0xdf {xf_step(c,op);}
    else if op==0x9b {xf_wait(c);}
    else if op==0x8c {
        x86_modrm(c);let segment=load64(c+232)&7;let slot=0;if segment==0 {slot=680;}else if segment==1 {slot=376;}else if segment==2 {slot=384;}else if segment==3 {slot=672;}else if segment==4 {slot=688;}else if segment==5 {slot=696;}else {return x86_fault(c,"Invalid segment-register move.");}
        if !load64(c+240) {n=2;}x86_setrm(c,n,load64(c+slot));
    }
    else if op==0x8e {
        let m=x86_modrm(c);let segment=(m>>3)&7;let selector=x86_rm(c,2);let offset=selector&~7;
        if segment==1 || segment>5 || (selector&4) {return x86_fault(c,"Unsupported data-segment selector.");}
        if offset {
            if offset+7>load64(c+192) {return x86_fault(c,"Data-segment selector exceeds GDT.");}
            let descriptor=x86_system_read(c,load64(c+184)+offset,8);let base=((descriptor>>16)&0xffffff)|((descriptor>>32)&0xff000000);let dpl=(descriptor>>45)&3;
            if base || !(descriptor&(1<<47)) || !(descriptor&(1<<44)) || (descriptor&(1<<43)) {return x86_fault(c,"Only present flat data segments are implemented.");}
            if dpl<cpl || dpl<(selector&3) || (segment==2 && (dpl!=cpl || (selector&3)!=cpl || !(descriptor&(1<<41)))) {return x86_gp(c,"Guest data-segment privilege check failed.");}
        }else if mode!=64 {return x86_fault(c,"Null protected-mode data segments are not implemented.");}
        let slot=672;if segment==0 {slot=680;}else if segment==2 {slot=384;}else if segment==4 {slot=688;}else if segment==5 {slot=696;}store64(c+slot,selector);
        if segment==2 {store64(c+496,load64(c+312)+2);} // MOV SS interrupt shadow
    }
    else if op==0xff || op==0xfe {
        if op==0xfe {n=1;}
        let m=x86_modrm(c);let group=(m>>3)&7;
        if group==0 || group==1 {let carry=load64(c+136)&1;let operation=0;if group {operation=5;}x86_setrm(c,n,x86_alu(c,operation,x86_rm(c,n),1,n));store64(c+136,(load64(c+136)&~1)|carry);}
        else if op==0xff && (group==2 || group==4 || group==6) {let width=n;if mode==64 {width=stack;}let value=x86_rm(c,width);if group==2 {x86_push(c,load64(c+128),stack);}if group==6 {x86_push(c,value,stack);}else {store64(c+128,value);}}
        else {return x86_fault(c,"Unsupported FF instruction group.");}
    }
    else if op==0x88 || op==0x89 || op==0x8a || op==0x8b || op==0x8d || op==0x86 || op==0x87 || op==0xc6 || op==0xc7 || op==0x80 || op==0x81 || op==0x83 || op==0x84 || op==0x85 || op==0xf6 || op==0xf7 || op==0xd0 || op==0xd1 || op==0xd2 || op==0xd3 || op==0xc0 || op==0xc1 || (op<=0x3b && (op&7)<=3) {
        if op==0x86 || op==0x88 || op==0x8a || op==0xc6 || op==0x80 || op==0x84 || op==0xf6 || op==0xd0 || op==0xd2 || op==0xc0 || (op<=0x3b && !(op&1)) {n=1;}
        let m=x86_modrm(c);let r=load64(c+232);let group=(m>>3)&7;
        if op==0x88 || op==0x89 {x86_setrm(c,n,x86_reg(c,r,n));}
        else if op==0x8a || op==0x8b {x86_setreg(c,r,n,x86_rm(c,n));}
        else if op==0x8d {if load64(c+240) {return x86_fault(c,"LEA requires memory addressing.");}x86_setreg(c,r,n,x86_address(c));}
        else if op==0x86 || op==0x87 {let a=x86_rm(c,n);let b=x86_reg(c,r,n);x86_setrm(c,n,b);x86_setreg(c,r,n,a);}
        else if op==0xc6 || op==0xc7 {if group {return x86_fault(c,"Invalid MOV immediate group.");}let size=n;if size==8 {size=4;}let value=x86_fetch(c,size);if n==8 {value=x86_signed(value,4);}x86_setrm(c,n,value);}
        else if op==0x80 || op==0x81 || op==0x83 {let size=n;if size==8 {size=4;}if op==0x83 {size=1;}let value=x86_signed(x86_fetch(c,size),size);let result=x86_alu(c,group,x86_rm(c,n),value,n);if group!=7 {x86_setrm(c,n,result);}}
        else if op==0x84 || op==0x85 {x86_alu(c,4,x86_rm(c,n),x86_reg(c,r,n),n);}
        else if op==0xf6 || op==0xf7 {
            if group==0 {let size=n;if size==8 {size=4;}let value=x86_signed(x86_fetch(c,size),size);x86_alu(c,4,x86_rm(c,n),value,n);}
            else if group==2 {x86_setrm(c,n,~x86_rm(c,n));}
            else if group==3 {x86_setrm(c,n,x86_alu(c,5,0,x86_rm(c,n),n));}
            else if group==4 || group==5 {
                let low=x86_multiply(c,x86_reg(c,0,n),x86_rm(c,n),n,group==5);let high=load64(c+344);
                if n==1 {x86_setreg(c,0,2,low|(high<<8));}else {x86_setreg(c,0,n,low);x86_setreg(c,2,n,high);}
            }
            else if group==6 || group==7 {
                let divisor=x86_rm(c,n);let low=x86_reg(c,0,n);let high=x86_reg(c,2,n);if n==1 {high=(load64(c)>>8)&255;}
                let negative=0;let divisor_negative=0;let mask=x86_mask(n);
                if group==7 {
                    negative=x86_signed(high,n)<0;divisor_negative=x86_signed(divisor,n)<0;
                    if negative {low=(-low)&mask;let carry=0;if !low {carry=1;}high=(~high+carry)&mask;}
                    if divisor_negative {divisor=(-divisor)&mask;}
                }
                let quotient=x86_udiv(c,high,low,divisor,n);if load64(c+288) {return -1;}let remainder=load64(c+344);
                if group==7 {let limit=1<<(n*8-1);let qnegative=negative!=divisor_negative;
                    if x86_unsigned_lt(limit,quotient) || (quotient==limit && !qnegative) {return x86_fault(c,"Guest division overflow.");}
                    if qnegative {quotient=-quotient;}if negative {remainder=-remainder;}
                }
                if n==1 {x86_setreg(c,0,2,(quotient&255)|((remainder&255)<<8));}else {x86_setreg(c,0,n,quotient);x86_setreg(c,2,n,remainder);}
            } else {return x86_fault(c,"Unsupported unary arithmetic group.");}
        }
        else if op==0xd0 || op==0xd1 || op==0xd2 || op==0xd3 || op==0xc0 || op==0xc1 {
            let count=1;if op==0xd2 || op==0xd3 {count=load64(c+8)&255;}if op==0xc0 || op==0xc1 {count=x86_fetch(c,1);}let countmask=31;if n==8 {countmask=63;}count=count&countmask;
            if group==6 {return x86_fault(c,"Unsupported shift operation.");}
            if group==2 || group==3 {
                // RCL/RCR memory operands require write permission even for
                // a zero effective count. Validate the whole RMW first.
                if !load64(c+240) {
                    let address=x86_linear(c);let i=0;
                    while i<n {let physical=x86_translate(c,address+i,1);if physical<0 || !x86_phys(c,physical,1) {return -1;}i=i+1;}
                }
                let value=x86_rm(c,n);if load64(c+288) {return -1;}
                let rotate=count;if n<4 {rotate=count%(n*8+1);}
                let flags=load64(c+136);let carry=flags&1;let i=0;
                while i<rotate {
                    let next=value&1;if group==2 {next=(value>>(n*8-1))&1;value=((value<<1)|carry)&x86_mask(n);}
                    else {value=(x86_shr(value,1)|(carry<<(n*8-1)))&x86_mask(n);}
                    carry=next;i=i+1;
                }
                flags=(flags&~1)|carry;
                if count==1 {let overflow=((value>>(n*8-1))&1)!=carry;if group==3 {overflow=((value>>(n*8-1))^(value>>(n*8-2)))&1;}flags=(flags&~2048)|(overflow*2048);}
                // Even a zero-count r32 operation zero-extends its result.
                x86_setrm(c,n,value);if !load64(c+288) {store64(c+136,flags);}
            }
            else if (group==0 || group==1) && count {
                let value=x86_rm(c,n);let rotate=count%(n*8);let result=value;
                if rotate {let right=(value>>1)&0x7fffffffffffffff;
                    if group==0 {result=(value<<rotate)|(right>>(n*8-rotate-1));}
                    else {result=(right>>(rotate-1))|(value<<(n*8-rotate));}
                }result=result&x86_mask(n);let carry=result&1;if group==1 {carry=(result>>(n*8-1))&1;}
                let flags=(load64(c+136)&~1)|carry;
                if count==1 {flags=flags&~2048;let overflow=((result>>(n*8-1))&1)!=carry;if group==1 {overflow=((result>>(n*8-1))^(result>>(n*8-2)))&1;}if overflow {flags=flags|2048;}}
                x86_setrm(c,n,result);store64(c+136,flags);
            }
            else if count {let value=x86_rm(c,n);let result=0;let carry=0;let overflow=0;
                if group==4 {result=value<<count;if count<=n*8 {carry=(value>>(n*8-count))&1;}if count==1 {overflow=((result>>(n*8-1))&1)!=carry;}}
                else if group==5 {result=(value>>1)&0x7fffffffffffffff;if count>1 {result=result>>(count-1);}carry=(value>>(count-1))&1;if count==1 {overflow=(value>>(n*8-1))&1;}}
                else {result=x86_signed(value,n)>>count;carry=(x86_signed(value,n)>>(count-1))&1;}
                x86_setrm(c,n,x86_flags(c,result,n,carry,overflow,0));
            }
        }
        else {let operation=(op>>3)&7;let a=x86_rm(c,n);let b=x86_reg(c,r,n);if op&2 {let tmp=a;a=b;b=tmp;}let result=x86_alu(c,operation,a,b,n);if operation!=7 {if op&2 {x86_setreg(c,r,n,result);}else {x86_setrm(c,n,result);}}}
    }
    else if op<=0x3d && ((op&7)==4 || (op&7)==5) {let size=n;if !(op&1) {n=1;size=1;}if size==8 {size=4;}let value=x86_signed(x86_fetch(c,size),size);let operation=(op>>3)&7;let result=x86_alu(c,operation,x86_reg(c,0,n),value,n);if operation!=7 {x86_setreg(c,0,n,result);}}
    else {return x86_fault(c,"Unsupported x86 opcode.");}
    if load64(c+288) {return -1;}return 0;
}
// Enter a ring-0 interrupt/exception gate. CPL3 switches through the loaded
// 64-bit TSS RSP0; the guest still controls SWAPGS and its syscall stack switch.
fn x86_event_stack(c,target,selector) {
    if (load64(c+376)&3)==3 {
        if !load64(c+704) || load64(c+720)<103 {return x86_fault(c,"User event requires a loaded 64-bit TSS.");}
        let rsp=x86_system_read(c,load64(c+712)+4,8);if load64(c+288) {return 0;}
        if !x86_canonical(rsp) {return x86_fault(c,"Noncanonical TSS RSP0.");}
        // Validate the gate's code descriptor with supervisor access first.
        let old=load64(c+376);store64(c+376,0);if !x86_far(c,target,selector) {store64(c+376,old);return 0;}
        store64(c+384,0);store64(c+32,rsp&~15);store64(c+400,load64(c+400)+1);return 1;
    }
    if load64(c+376)&3 {return x86_fault(c,"Only CPL0/CPL3 event delivery is implemented.");}
    if !x86_far(c,target,selector) {return 0;}store64(c+32,load64(c+32)&~15);return 1;
}
// Deliver a non-IST long-mode fault/trap. Unsupported/double faults stop.
fn x86_exception(c,vector) {
    if load64(c+144)!=64 || load64(c+328)<vector*16+15 {return 0;}
    let address=load64(c+352);let error=load64(c+360);store64(c+288,0);store64(c+392,0);
    let gate=load64(c+320)+vector*16;let low=x86_system_read(c,gate,8);let high=x86_system_read(c,gate+8,8);
    if load64(c+288) {return 0;}
    let type=(low>>40)&15;let selector=(low>>16)&65535;
    if !(low&(1<<47)) || (type!=14 && type!=15) || (low&(7<<32)) || (selector&3) || (high>>32) {return x86_fault(c,"Unsupported exception IDT gate.");}
    let target=(low&65535)|((low>>32)&0xffff0000)|(high<<32);
    let i=0;while i<144 {store64(c+i,load64(c+512+i));i=i+8;}
    if vector==14 {store64(c+368,address);}let rsp=load64(c+32);let flags=load64(c+136);let cs=load64(c+376);let ss=load64(c+384);let ip=load64(c+128);
    if !x86_event_stack(c,target,selector) {return 0;}
    if !x86_push(c,ss,8) || !x86_push(c,rsp,8) || !x86_push(c,flags,8) || !x86_push(c,cs,8) || !x86_push(c,ip,8) {return 0;}
    if (vector==13 || vector==14) && !x86_push(c,error,8) {return 0;}
    let clear=0x10100;if type==14 {clear=clear|512;}store64(c+136,flags&~clear);x86_message=0;x86_error=0;return 1;
}
fn x86_page_fault(c) {return x86_exception(c,14);}
// Queue a maskable interrupt; delivery follows completion of any pending IN.
// The monitor acknowledges its PIC only when this accepts an eligible vector.
fn x86_irq(c,vector) {
    if vector<0 || vector>255 || load64(c+488) || !(load64(c+136)&512) || load64(c+312)<load64(c+496) {return 0;}
    store64(c+488,vector+1);return 1;
}
fn x86_interrupt(c,vector) {
    if load64(c+144)!=64 || vector*16+15>load64(c+328) {return x86_fault(c,"Maskable interrupt requires a long-mode IDT gate.");}
    let gate=load64(c+320)+vector*16;let low=x86_system_read(c,gate,8);let high=x86_system_read(c,gate+8,8);
    if load64(c+288) {return 0;}
    let type=(low>>40)&15;let selector=(low>>16)&65535;
    if !(low&(1<<47)) || (type!=14 && type!=15) || (low&(7<<32)) || (selector&3) || (high>>32) {return x86_fault(c,"Unsupported interrupt IDT gate or IST stack.");}
    let target=(low&65535)|((low>>32)&0xffff0000)|(high<<32);
    let rsp=load64(c+32);let flags=load64(c+136);let cs=load64(c+376);let ss=load64(c+384);let ip=load64(c+128);
    if !x86_event_stack(c,target,selector) {return 0;}
    if !x86_push(c,ss,8) || !x86_push(c,rsp,8) || !x86_push(c,flags,8) || !x86_push(c,cs,8) || !x86_push(c,ip,8) {return 0;}
    let clear=0x34100;if type==14 {clear=clear|512;}store64(c+136,flags&~clear);store64(c+336,load64(c+336)+1);store64(c+488,0);return 1;
}
// IO/HLT exits and nonfaulting KVM_EXIT_INTR timeslices. Total fuel is cumulative.
// The slice limits REP and native chaining as well as interpreter instructions.
fn x86_run_slice(c,run,fuel,limit) {
    if limit>fuel {limit=fuel;}x86_message=0;x86_error=0;store64(c+768,limit);store64(c+400,load64(c+400)+1);
    if load64(c+288) {x86_message="Software CPU is faulted.";x86_error=-95;return -1;}
    if load64(c+280) {store64(c+208,0x40);x86_setreg(c,0,load64(c+280),load64(run+128));store64(c+280,0);}
    while load64(c+312)<limit {
        if load64(c+488) && (load64(c+136)&512) && load64(c+312)>=load64(c+496) {if !x86_interrupt(c,load64(c+488)-1) {return -1;}}
        let compiled=0;if x86_jit_enabled && fuel>=x86_jit_min_fuel && load64(c+312)>=load64(c+496) {compiled=xj_run(c,limit);}
        if !compiled {
            store64(c+392,0);if load64(c+328)>=63 {
                store64(c+512,load64(c+0));store64(c+520,load64(c+8));store64(c+528,load64(c+16));
                store64(c+536,load64(c+24));store64(c+544,load64(c+32));store64(c+552,load64(c+40));
                store64(c+560,load64(c+48));store64(c+568,load64(c+56));store64(c+576,load64(c+64));
                store64(c+584,load64(c+72));store64(c+592,load64(c+80));store64(c+600,load64(c+88));
                store64(c+608,load64(c+96));store64(c+616,load64(c+104));store64(c+624,load64(c+112));
                store64(c+632,load64(c+120));store64(c+640,load64(c+128));store64(c+648,load64(c+136));}
            store64(c+424,1);let reason=x86_step(c,run);store64(c+424,0);store64(c+312,load64(c+312)+1);
            if load64(c+288) {let fault=load64(c+392);let vector=14;if fault==2 {vector=13;}if fault>=256 {vector=fault-256;}if !fault || !x86_exception(c,vector) {return -1;}reason=0;}
            if reason {store64(run+8,reason);return reason;}
        }
    }
    if load64(c+312)>=fuel {x86_fault(c,"Software CPU instruction budget exhausted.");x86_error=-110;return -1;}
    store64(run+8,10);return 10;
}
fn x86_run(c,run,fuel) {return x86_run_slice(c,run,fuel,fuel);}
