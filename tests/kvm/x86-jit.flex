import "../../lib/softvm.flex";
global tj_seed=0x145624734;
global tj_p=0;
fn tj_expect(ok) {if !ok {syscall(1,2,"x86 JIT differential assertion failed\n",38,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn tj_random() {tj_seed=tj_seed^(tj_seed<<13);tj_seed=tj_seed^(tj_seed>>7);tj_seed=tj_seed^(tj_seed<<17);return tj_seed&0x7fffffffffffffff;}
fn tj_byte(v) {store8(tj_p,v);tj_p=tj_p+1;return 0;}
fn tj_word(v,n) {let i=0;while i<n {tj_byte(v>>(i*8));i=i+1;}return 0;}
fn tj_hex(p,text) {let i=0;while load8(text+i*2) {let a=load8(text+i*2);let b=load8(text+i*2+1);if a>=97 {a=a-87;}else {a=a-48;}if b>=97 {b=b-87;}else {b=b-48;}store8(p+i,a*16+b);i=i+1;}return i;}
fn tj_compare(a,b,ram_a,ram_b,run_a,run_b,fuel) {
    x86_jit_enabled=0;let reason=x86_run(a,run_a,fuel);let error=x86_error;
    x86_jit_enabled=1;x86_jit_min_fuel=0;x86_jit_threshold=1;let translated=x86_run(b,run_b,fuel);
    tj_expect(reason==translated && error==x86_error);
    let i=0;while i<208 {tj_expect(load64(a+i)==load64(b+i));i=i+8;}
    tj_expect(load64(a+288)==load64(b+288) && load64(a+312)==load64(b+312));
    tj_expect(load64(a+352)==load64(b+352) && load64(a+360)==load64(b+360) && load64(a+368)==load64(b+368));
    i=0x1000;while i<0x6000 {tj_expect(load64(ram_a+i)==load64(ram_b+i));i=i+8;}return reason;
}
fn tj_reset(a,b,ra,rb,text,mode) {
    x86_start(a,0x1000,32,0,0);x86_start(b,0x1000,32,0,0);store64(a+144,mode);store64(b+144,mode);
    let i=0x1000;while i<0x6000 {store64(ra+i,0);store64(rb+i,0);i=i+8;}
    tj_hex(ra+0x1000,text);tj_hex(rb+0x1000,text);return 0;
}
fn main(argc,argv) {
    tj_expect(argc==2);let va=softvm_create(1048576);let vb=softvm_create(1048576);tj_expect(va && vb);
    let a=load64(va+64);let b=load64(vb+64);let ra=load64(va+24);let rb=load64(vb+24);let ua=load64(va+40);let ub=load64(vb+40);
    // The embedded RX helper must exactly match its auditable assembly source.
    let s=xj_state(b);tj_expect(s);let fd=syscall(2,load64(argv+8),0,0,0,0,0);tj_expect(fd>=0);let buf=alloc(4096);let size=syscall(0,fd,buf,4096,0,0,0);tj_expect(size>512 && size<4096);let i=0;
    while i<size {tj_expect(load8(buf+i)==load8(xj_helper(s)+i));i=i+1;}syscall(3,fd,0,0,0,0,0);syscall(11,buf,4096,0,0,0,0);
    // Chain through a slot outside the original 8192-entry cache. Once both
    // blocks are warm, one FFI entry must execute many complete iterations.
    tj_reset(a,b,ra,rb,"",64);let target=0x3000;let firstkey=0x1000^(0x1000>>17);let firstslot=((firstkey*0x9e3779b97f4a7c15)>>32)&32767;let slot=0;
    while slot<=8191 || slot==firstslot {let key=target^(target>>17);slot=((key*0x9e3779b97f4a7c15)>>32)&32767;if slot<=8191 || slot==firstslot {target=target+16;}}
    store8(rb+0x1000,0xe9);kvm_put32(rb+0x1001,target-0x1005);store8(rb+target,0xb8);kvm_put32(rb+target+1,42);store8(rb+target+5,0xe9);kvm_put32(rb+target+6,0x1000-target-10);
    x86_jit_enabled=1;x86_jit_min_fuel=0;x86_jit_threshold=1;tj_expect(xj_run(b,300));tj_expect(xj_run(b,300));
    store64(b+128,0x1000);store64(b+312,0);tj_expect(xj_run(b,300));tj_expect(load64(b+312)==300 && load64(b)==42);
    // All conditional branches, both outcomes, and exact fuel boundaries.
    let cond=0;while cond<16 {let flags=0;while flags<32 {
        tj_reset(a,b,ra,rb,"7005b801000000f4",64);store8(ra+0x1000,0x70+cond);store8(rb+0x1000,0x70+cond);
        let f=2|((flags&1))|((flags&2)*2)|((flags&4)*16)|((flags&8)*16)|((flags&16)*128);store64(a+136,f);store64(b+136,f);
        tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)>0);flags=flags+1;
    }cond=cond+1;}
    // Conditional moves: all conditions/flag combinations, both outcomes,
    // register and memory sources, extended registers and r32 zero extension.
    cond=0;while cond<16 {let flags=0;while flags<32 {let variant=0;while variant<4 {
        tj_reset(a,b,ra,rb,"",64);let f=2|(flags&1)|((flags&2)*2)|((flags&4)*16)|((flags&8)*16)|((flags&16)*128);
        store64(a+136,f);store64(b+136,f);store64(a+80,0xfedcba9876543210);store64(b+80,0xfedcba9876543210);
        store64(a+88,0x123456789abcdef0);store64(b+88,0x123456789abcdef0);store64(ra+0x4000,0x123456789abcdef0);store64(rb+0x4000,0x123456789abcdef0);
        tj_p=ra+0x1000;let rex=0x45;if variant&1 {rex=rex|8;}if variant&2 {rex=rex&~1;}tj_byte(rex);tj_byte(0x0f);tj_byte(0x40+cond);
        if variant&2 {tj_byte(0x14);tj_byte(0x25);tj_word(0x4000,4);}else {tj_byte(0xd3);}tj_byte(0xf4);
        let j=0;while j<tj_p-ra-0x1000 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}
        tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)>0);variant=variant+1;
    }flags=flags+1;}cond=cond+1;}
    // BSF/BSR retain undefined flags and the full destination on zero input.
    // Nonzero r32 results zero-extend; memory sources still use checked reads.
    let scan=0;while scan<1024 {tj_reset(a,b,ra,rb,"",64);let destination=scan&15;let source=(scan>>4)&15;let value=tj_random()^(tj_random()<<32);
        if scan&64 {value=0;}if scan&128 {value=0x1234567800000000;}
        let old=0xfeedface87654321;store64(a+source*8,value);store64(b+source*8,value);if source!=destination || (scan&32) {store64(a+destination*8,old);store64(b+destination*8,old);}
        store64(ra+0x4000,value);store64(rb+0x4000,value);store64(a+136,0xad7);store64(b+136,0xad7);
        tj_p=ra+0x1000;let rex=0x40;if destination>=8 {rex=rex|4;}if (source>=8) && !(scan&32) {rex=rex|1;}if scan&512 {rex=rex|8;}tj_byte(rex);tj_byte(0x0f);let op=0xbc;if scan&256 {op=0xbd;}tj_byte(op);
        if scan&32 {tj_byte((destination&7)*8+4);tj_byte(0x25);tj_word(0x4000,4);}else {tj_byte(0xc0+(destination&7)*8+(source&7));}tj_byte(0xf4);
        let j=0;while j<tj_p-ra-0x1000 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)==1);scan=scan+1;
    }
    tj_reset(a,b,ra,rb,"b9010000004c0fbd1425ffff0f00f4",64);tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==-1 && load64(b+200)==0x1005);
    // A false CMOVE still faults on an inaccessible memory operand. Earlier
    // native instructions retire, while the CMOV destination stays unchanged.
    tj_reset(a,b,ra,rb,"b901000000480f440425ffff0f00f4",64);store64(a,0xfeedface12345678);store64(b,0xfeedface12345678);
    tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==-1 && load64(b+200)==0x1005 && load64(b)==0xfeedface12345678);
    let fuel=1;while fuel<40 {tj_reset(a,b,ra,rb,"b91400000031c04883c0014883e90175f6f4",64);tj_compare(a,b,ra,rb,ua,ub,fuel);fuel=fuel+1;}
    // Byte comparisons include AH versus SPL/extended-byte encodings, both
    // operand directions, immediate values and checked memory reads.
    let bytecase=0;while bytecase<1024 {tj_reset(a,b,ra,rb,"",64);let r=0;
        while r<16 {let value=tj_random()^(tj_random()<<32);store64(a+r*8,value);store64(b+r*8,value);r=r+1;}
        store64(a+136,0xad7);store64(b+136,0xad7);let value=tj_random();store64(ra+0x4000,value);store64(rb+0x4000,value);
        tj_p=ra+0x1000;let rex=0;if bytecase&1 {rex=0x40|((bytecase&2)*2)|((bytecase&4)/4);tj_byte(rex);}
        let kind=(bytecase>>3)%5;let op=0x38;if kind==1 {op=0x3a;}else if kind==2 {op=0x84;}else if kind==3 {op=0x80;}else if kind==4 {op=0x3c;}tj_byte(op);
        if op==0x3c {tj_byte(bytecase&255);}else {let reg=(bytecase>>5)&7;let rm=(bytecase>>8)&7;if op==0x80 {reg=7;}
            if bytecase&16 {tj_byte(reg*8+4);tj_byte(0x25);tj_word(0x4000,4);}else {tj_byte(0xc0+reg*8+rm);}if op==0x80 {tj_byte(bytecase&255);}}
        tj_byte(0xf4);let j=0;while j<tj_p-ra-0x1000 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}
        tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)>0);bytecase=bytecase+1;
    }
    tj_reset(a,b,ra,rb,"803d000010007ff4",64);tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==-1 && load64(b+200)==0x1000);
    // Byte MOVs preserve all other bits, including legacy high-byte registers
    // and REX SPL/R8B forms. Exercise checked loads/stores in both directions.
    let movbyte=0;while movbyte<1024 {tj_reset(a,b,ra,rb,"",64);let r=0;
        while r<16 {let value=tj_random()^(tj_random()<<32);store64(a+r*8,value);store64(b+r*8,value);r=r+1;}
        store64(a+136,0xad7);store64(b+136,0xad7);store64(ra+0x4000,0xfeedface12345678);store64(rb+0x4000,0xfeedface12345678);
        tj_p=ra+0x1000;let rex=0;if movbyte&1 {rex=0x40|((movbyte&2)*2)|((movbyte&4)/4);tj_byte(rex);}
        let op=0x88;if movbyte&8 {op=0x8a;}tj_byte(op);let reg=(movbyte>>5)&7;let rm=(movbyte>>8)&7;
        if movbyte&16 {tj_byte(reg*8+4);tj_byte(0x25);tj_word(0x4000,4);}else {tj_byte(0xc0+reg*8+rm);}tj_byte(0xf4);
        let j=0;while j<tj_p-ra-0x1000 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}
        tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)==1);movbyte=movbyte+1;
    }
    tj_reset(a,b,ra,rb,"4488042500001000f4",64);tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==-1 && load64(b+200)==0x1000);
    tj_reset(a,b,ra,rb,"448a042500001000f4",64);tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==-1 && load64(b+200)==0x1000);
    tj_reset(a,b,ra,rb,"b8070000008804250d100000b801000000f4",64);tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b)==7);
    let signcase=0;while signcase<128 {tj_reset(a,b,ra,rb,"98f4",64);if signcase&1 {tj_reset(a,b,ra,rb,"4898f4",64);}
        let value=tj_random()^(tj_random()<<32);store64(a,value);store64(b,value);store64(a+136,0xad7);store64(b+136,0xad7);
        tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)==1);signcase=signcase+1;
    }
    // Operand-size MOVs preserve the destination's upper 48 bits and touch
    // exactly two bytes in RAM. Include extended registers and both modes.
    let wordcase=0;while wordcase<256 {let mode=64;if wordcase&128 {mode=32;}tj_reset(a,b,ra,rb,"",mode);
        let r=0;while r<16 {let value=tj_random()^(tj_random()<<32);store64(a+r*8,value);store64(b+r*8,value);r=r+1;}
        store64(a+136,0xad7);store64(b+136,0xad7);store64(ra+0x4000,0xfedcba9876543210);store64(rb+0x4000,0xfedcba9876543210);
        tj_p=ra+0x1000;tj_byte(0x66);let rex=0;if mode==64 {rex=0x40|((wordcase&1)*4)|((wordcase&2)/2);tj_byte(rex);}
        let op=0x89;if wordcase&4 {op=0x8b;}tj_byte(op);let dest=(wordcase>>3)&7;let source=(wordcase>>6)&7;
        if wordcase&32 {tj_byte(dest*8+4);tj_byte(0x25);tj_word(0x4000,4);}else {tj_byte(0xc0+dest*8+source);}tj_byte(0xf4);
        let j=0;while j<tj_p-ra-0x1000 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)>0);wordcase=wordcase+1;
    }
    tj_reset(a,b,ra,rb,"6644891425ffff0f00f4",64);tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==-1 && load64(b+200)==0x1000);
    tj_reset(a,b,ra,rb,"66448b1425ffff0f00f4",64);tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==-1 && load64(b+200)==0x1000);
    tj_reset(a,b,ra,rb,"66448b1425feff0f00f4",64);store64(a+80,0xfeedface87654321);store64(b+80,0xfeedface87654321);store8(ra+1048574,0x34);store8(rb+1048574,0x34);store8(ra+1048575,0x12);store8(rb+1048575,0x12);
    tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+80)==0xfeedface87651234 && load64(b+1008)>0);
    // A 16-bit store into translated code must exit after committing the
    // store, before executing a cached immediate from the previous bytes.
    tj_reset(a,b,ra,rb,"b807000000668904250e100000b801000000f4",64);tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b)==7);
    // BSWAP and INC/DEC: all registers, both widths and CF states. Include
    // overflow/borrow/zero boundaries and verify each instruction runs native.
    let swapcase=0;while swapcase<768 {tj_reset(a,b,ra,rb,"",64);
        let destination=swapcase&15;let kind=(swapcase>>5)%3;let value=tj_random()^(tj_random()<<32);
        if swapcase&64 {value=0;}if swapcase&128 {value=-1;}if swapcase&256 {value=0x8000000080000000;}if swapcase&512 {value=0x7fffffff7fffffff;}
        store64(a+destination*8,value);store64(b+destination*8,value);let flags=0xad6|(swapcase&1);store64(a+136,flags);store64(b+136,flags);
        tj_p=ra+0x1000;let rex=0x40;if destination>=8 {rex=rex|1;}if swapcase&16 {rex=rex|8;}tj_byte(rex);
        if !kind {tj_byte(0x0f);tj_byte(0xc8+(destination&7));}else {tj_byte(0xff);let group=kind-1;tj_byte(0xc0+group*8+(destination&7));}tj_byte(0xf4);
        let j=0;while j<tj_p-ra-0x1000 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}
        tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)==1);swapcase=swapcase+1;
    }
    // The real kernel's byte-swapping copy loop must chain across BSWAP and
    // preserve exact retirement/fault boundaries, including partial fuel.
    let copyfuel=1;while copyfuel<140 {tj_reset(a,b,ra,rb,"be00300000bf00400000b9100000008b060fc8c1c80889074883c6044883c704ffc975ebf4",64);
        let j=0;while j<64 {store8(ra+0x3000+j,j*17+3);store8(rb+0x3000+j,j*17+3);j=j+1;}
        tj_compare(a,b,ra,rb,ua,ub,copyfuel);copyfuel=copyfuel+1;
    }
    // NEG/NOT register forms, including zero and signed overflow boundaries.
    let unary=0;while unary<256 {tj_reset(a,b,ra,rb,"",64);let destination=unary&15;let value=tj_random();
        if unary&16 {value=0;}if unary&32 {value=0x8000000080000000;}if unary&64 {value=-1;}
        store64(a+destination*8,value);store64(b+destination*8,value);store64(a+136,0xad7);store64(b+136,0xad7);
        tj_p=ra+0x1000;let rex=0x40;if destination>=8 {rex=rex|1;}if unary&16 {rex=rex|8;}tj_byte(rex);tj_byte(0xf7);let group=2;if unary&128 {group=3;}tj_byte(0xc0+group*8+(destination&7));tj_byte(0xf4);
        let j=0;while j<tj_p-ra-0x1000 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)>0);unary=unary+1;
    }
    // Register shifts/rotates: every masked and unmasked CL count, both
    // widths, extended registers, zero-count preservation and defined flags.
    let shift=0;while shift<5 {let group=shift;if shift>=2 {group=shift+2;}if shift==4 {group=7;}let count=0;
        while count<256 {let wide=0;while wide<2 {tj_reset(a,b,ra,rb,"",64);let value=tj_random()^(tj_random()<<32);store64(a+8,count);store64(b+8,count);store64(a+80,value);store64(b+80,value);store64(a+136,0xad7);store64(b+136,0xad7);
            tj_p=ra+0x1000;let rex=0x41;if wide {rex=0x49;}tj_byte(rex);tj_byte(0xd3);tj_byte(0xc2+group*8);tj_byte(0xf4);let j=0;while j<4 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)>0);wide=wide+1;}count=count+1;
        }shift=shift+1;
    }
    tj_reset(a,b,ra,rb,"48c1e00348d1e849c1c902f4",64);store64(a,0x8123456789abcdef);store64(b,0x8123456789abcdef);store64(a+72,-1);store64(b+72,-1);tj_compare(a,b,ra,rb,ua,ub,100);
    // RDTSC inside a native block includes earlier retired instructions,
    // preserves guest flags and zero-extends its two integer destinations.
    tj_reset(a,b,ra,rb,"b9010000004883c1010f314889c348c1e2204809d34983c0010f31f4",64);store64(a+504,0x123456789);store64(b+504,0x123456789);store64(a+136,0xad7);store64(b+136,0xad7);tj_compare(a,b,ra,rb,ua,ub,100);
    // Reusing a kernel-compiled RDTSC block at CPL3 with TSD set must
    // retry as a guest #GP, including after native code was already cached.
    tj_reset(a,b,ra,rb,"0f31ebfc",64);tj_compare(a,b,ra,rb,ua,ub,100);store64(a+288,0);store64(b+288,0);store64(a+128,0x1000);store64(b+128,0x1000);store64(a+376,0x33);store64(b+376,0x33);store64(a+168,4);store64(b+168,4);tj_expect(tj_compare(a,b,ra,rb,ua,ub,200)==-1 && load64(b+392)==2);
    // Deterministic mixed ALU/move/LEA/load/store programs, full and partial runs.
    let test=0;while test<256 {
        let mode=64;if test&1 {mode=32;}tj_reset(a,b,ra,rb,"",mode);let r=0;
        while r<16 {let value=tj_random()^(tj_random()<<32);store64(a+r*8,value);store64(b+r*8,value);r=r+1;}
        tj_p=ra+0x1000;let instruction=0;while instruction<48 {
            let kind=tj_random()%8;let rex=0x40;let width=4;if mode==64 && (tj_random()&1) {rex=rex|8;width=8;}
            let dest=tj_random()%8;let src=tj_random()%8;
            if mode==64 {rex=rex|((tj_random()&1)*4)|(tj_random()&1);tj_byte(rex);}
            if kind==0 {tj_byte(0xb8+dest);tj_word(tj_random(),width);}
            else if kind==1 {tj_byte(0x89);tj_byte(0xc0+src*8+dest);}
            else if kind==2 {tj_byte((tj_random()%8)*8+1+(tj_random()&1)*2);tj_byte(0xc0+src*8+dest);}
            else if kind==3 {tj_byte(0x83);tj_byte(0xc0+(tj_random()%8)*8+dest);tj_byte(tj_random());}
            else if kind==4 {tj_byte(0x8d);tj_byte(0x84+dest*8);tj_byte(src*8+5);tj_word(tj_random(),4);}
            else {let opcode=0x8b;if kind==6 {opcode=0x89;}else if kind==7 {opcode=(tj_random()%8)*8+3;}tj_byte(opcode);tj_byte(0x04+dest*8);tj_byte(0x25);tj_word(0x3000+(tj_random()%512)*8,4);}
            instruction=instruction+1;
        }
        tj_byte(0xf4);i=0;while i<tj_p-ra-0x1000 {store8(rb+0x1000+i,load8(ra+0x1000+i));i=i+1;}
        i=0x3000;while i<0x5000 {let value=tj_random();store64(ra+i,value);store64(rb+i,value);i=i+8;}
        let limit=100;if test&2 {limit=1+tj_random()%48;}tj_compare(a,b,ra,rb,ua,ub,limit);test=test+1;
    }
    // Extending loads preserve flags, high byte registers and 32-bit destination
    // zero extension. Exercise all source/destination registers and both widths.
    test=0;while test<512 {
        let mode=64;if test&1 {mode=32;}tj_reset(a,b,ra,rb,"",mode);let r=0;
        while r<16 {let value=tj_random()^(tj_random()<<32);store64(a+r*8,value);store64(b+r*8,value);r=r+1;}
        store64(a+136,0xcd7);store64(b+136,0xcd7);tj_p=ra+0x1000;
        let rex=0;if mode==64 && (test&2) {rex=0x40;if test&4 {rex=rex|8;}if test&8 {rex=rex|4;}if test&16 {rex=rex|1;}tj_byte(rex);}
        let opcode=0xb6;if test&32 {opcode=opcode|1;}if test&64 {opcode=opcode|8;}
        tj_byte(0x0f);tj_byte(opcode);let dest=(test>>3)&7;let source=(test>>6)&7;
        if test&128 {let address=0x3ffc;if test&256 {address=0x3fff;}tj_byte(dest*8+4);tj_byte(0x25);tj_word(address,4);store64(ra+address,0xfedcba98765480ff);store64(rb+address,0xfedcba98765480ff);}
        else {tj_byte(0xc0+dest*8+source);}
        tj_byte(0xf4);i=0;while i<tj_p-ra-0x1000 {store8(rb+0x1000+i,load8(ra+0x1000+i));i=i+1;}
        tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==5);if !(test&256) {tj_expect(load64(b+1008)>0);}test=test+1;
    }
    tj_reset(a,b,ra,rb,"4863c1f4",64);store64(a+8,0xabcdef0080000001);store64(b+8,0xabcdef0080000001);tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b)==0xffffffff80000001 && load64(b+1008)>0);
    tj_reset(a,b,ra,rb,"4c63042500400000f4",64);store64(ra+0x4000,0xabcdef0080000001);store64(rb+0x4000,0xabcdef0080000001);tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+64)==0xffffffff80000001 && load64(b+1008)>0);
    // Failed native extending loads retry at the original instruction boundary.
    tj_reset(a,b,ra,rb,"b901000000480fbf0425ffff0f00f4",64);tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==-1 && load64(b+200)==0x1005);
    // Stack operations, direct/indirect calls, return adjustments, and POP RSP.
    tj_reset(a,b,ra,rb,"b878563412505b6aff5968000100005a545ce801000000f44883c001c3",64);tj_compare(a,b,ra,rb,ua,ub,100);
    tj_reset(a,b,ra,rb,"b80d100000ffd0f4b8010000004883c001c3",64);tj_compare(a,b,ra,rb,ua,ub,100);
    tj_reset(a,b,ra,rb,"b80c100000ffe0b8010000004883c001f4",64);tj_compare(a,b,ra,rb,ua,ub,100);
    tj_reset(a,b,ra,rb,"50f4",64);store64(a+32,3);store64(b+32,3);tj_compare(a,b,ra,rb,ua,ub,100);
    // ADC/SBB carry dependency survives native loop budget checks.
    fuel=1;while fuel<80 {tj_reset(a,b,ra,rb,"b914000000b8ffffffff4883d0004883e90175f6f4",64);tj_compare(a,b,ra,rb,ua,ub,fuel);fuel=fuel+1;}
    // Self-loop register mapping also handles SP/BP/SI/DI as ordinary operands.
    tj_reset(a,b,ra,rb,"b9140000004883c4014883c5014883c6014883c7014883e90175eaf4",64);tj_compare(a,b,ra,rb,ua,ub,1000);tj_expect(load64(b+1008)>0);
    // Register-resident loops with mixed flag producers, carries and widths.
    test=0;while test<256 {
        let mode=64;if test&1 {mode=32;}tj_reset(a,b,ra,rb,"",mode);let r=0;
        while r<8 {let value=tj_random()^(tj_random()<<32);store64(a+r*8,value);store64(b+r*8,value);r=r+1;}store64(a+8,37);store64(b+8,37);
        tj_p=ra+0x1000;let instruction=0;while instruction<6 {let dest=tj_random()%8;if dest==1 {dest=0;}let src=tj_random()%8;let width=4;if mode==64 && (tj_random()&1) {width=8;tj_byte(0x48);}
            let kind=tj_random()%3;if kind==0 {tj_byte((tj_random()%8)*8+1);tj_byte(0xc0+src*8+dest);}else if kind==1 {tj_byte(0x83);tj_byte(0xc0+(tj_random()%8)*8+dest);tj_byte(tj_random());}else {tj_byte(0x89);tj_byte(0xc0+src*8+dest);}instruction=instruction+1;
        }
        if mode==64 {tj_byte(0x48);}tj_byte(0x83);tj_byte(0xe9);tj_byte(1);tj_byte(0x75);tj_byte(-(tj_p-ra-0x1000+1));tj_byte(0xf4);
        i=0;while i<tj_p-ra-0x1000 {store8(rb+0x1000+i,load8(ra+0x1000+i));i=i+1;}
        tj_compare(a,b,ra,rb,ua,ub,1+tj_random()%1000);test=test+1;
    }
    // REP moves/stores: both directions, all widths, overlap, page boundaries,
    // and budgets that stop inside a native chunk or interpreter remainder.
    test=0;while test<128 {
        let mode=64;if test&1 {mode=32;}tj_reset(a,b,ra,rb,"",mode);tj_p=ra+0x1000;
        let width=1<<(test%4);if mode==32 && width==8 {width=4;}tj_byte(0xf3);if width==2 {tj_byte(0x66);}if width==8 {tj_byte(0x48);}
        let copy=(test&4)!=0;let opcode=0xaa;if copy {opcode=0xa4;}if width!=1 {opcode=opcode+1;}tj_byte(opcode);tj_byte(0xf4);
        i=0;while i<tj_p-ra-0x1000 {store8(rb+0x1000+i,load8(ra+0x1000+i));i=i+1;}
        i=0x2000;while i<0x5000 {let value=tj_random();store64(ra+i,value);store64(rb+i,value);i=i+8;}
        let count=8+tj_random()%600;let dest=0x3000+(test%8)*width;let source=dest+16;let f=2;if test&8 {f=f|1024;dest=0x4000+(test%8)*width;source=dest-16;}
        store64(a,0xa5a5a5a5);store64(b,0xa5a5a5a5);store64(a+8,count);store64(b+8,count);store64(a+48,source);store64(b+48,source);store64(a+56,dest);store64(b+56,dest);store64(a+136,f);store64(b+136,f);
        let limit=count+2;if test&16 {limit=1+tj_random()%count;}tj_compare(a,b,ra,rb,ua,ub,limit);test=test+1;
    }
    // Expanding one-byte PUSH templates must leave room for the final
    // native dispatch tail, including when emission rolls back at its limit.
    let limit=1;while limit<=70 {tj_reset(a,b,ra,rb,"",64);store64(a,0x123456789abcdef0);store64(b,0x123456789abcdef0);tj_p=ra+0x1000;i=0;while i<32 {tj_byte(0x50);i=i+1;}i=0;while i<32 {tj_byte(0x5b);i=i+1;}tj_byte(0xf4);i=0;while i<65 {store8(rb+0x1000+i,load8(ra+0x1000+i));i=i+1;}tj_compare(a,b,ra,rb,ua,ub,limit);limit=limit+1;}
    // Guest self-modification ends a block before translated stale code runs.
    tj_reset(a,b,ra,rb,"c704250b100000b878563412b801000000f4",64);tj_compare(a,b,ra,rb,ua,ub,100);
    // RAM boundary and canonical-address failures retry through the interpreter.
    tj_reset(a,b,ra,rb,"488b00f4",64);store64(a,1048573);store64(b,1048573);tj_compare(a,b,ra,rb,ua,ub,100);
    tj_reset(a,b,ra,rb,"488b00f4",64);store64(a,0x800000000000);store64(b,0x800000000000);tj_compare(a,b,ra,rb,ua,ub,100);
    // A block cannot speculate instructions across a guest instruction page.
    tj_reset(a,b,ra,rb,"",64);tj_hex(ra+0x1fff,"48b87856341200000000f4");tj_hex(rb+0x1fff,"48b87856341200000000f4");store64(a+128,0x1fff);store64(b+128,0x1fff);tj_compare(a,b,ra,rb,ua,ub,100);
    // Host changes between RUN calls invalidate cached code even without writes.
    tj_reset(a,b,ra,rb,"b807000000e900000000f4",64);tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+1008)>0);
    store64(a+288,0);store64(b+288,0);store64(a+128,0x1000);store64(b+128,0x1000);store8(ra+0x1001,9);store8(rb+0x1001,9);tj_compare(a,b,ra,rb,ua,ub,200);tj_expect(load64(b)==9);
    // Data writes preserve the cache; writes through aliases to code invalidate.
    tj_reset(a,b,ra,rb,"c704250030000078563412f4",64);tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(b+400)==1);
    let before=load64(b+400);tj_expect(x86_write(b,0x1001,1,0x90));tj_expect(load64(b+400)==before+1);
    // Live paging permissions and frame remapping are re-read by native accesses.
    tj_reset(a,b,ra,rb,"488b0425004000004889042500500000f4",64);let n=0;
    while n<2 {let c=a;let ram=ra;if n {c=b;ram=rb;}store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,32);store64(c+176,256);
        store64(ram+0x10000,0x11003);store64(ram+0x11000,0x12003);store64(ram+0x12000,0x13003);i=0;while i<6 {store64(ram+0x13000+i*8,i*4096+3);i=i+1;}store64(ram+0x4000,0x11223344);n=n+1;}
    tj_compare(a,b,ra,rb,ua,ub,100);tj_expect(load64(rb+0x5000)==0x11223344);
    store64(ra+0x13028,0x5001);store64(rb+0x13028,0x5001);store64(a+128,0x1000);store64(b+128,0x1000);tj_compare(a,b,ra,rb,ua,ub,200);
    // A guest PTE write remaps the very next instruction. Continuing the
    // current native block would execute the old mapping's MOV EAX,1.
    tj_reset(a,b,ra,rb,"48c704250830010003200000b801000000f4",64);n=0;
    while n<2 {let c=a;let ram=ra;if n {c=b;ram=rb;}store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,32);store64(c+176,256);
        store64(ram+0x10000,0x11003);store64(ram+0x11000,0x12003);store64(ram+0x12000,0x13003);i=0;while i<21 {store64(ram+0x13000+i*8,i*4096+3);i=i+1;}tj_hex(ram+0x200c,"b807000000f4");n=n+1;}
    tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==5 && load64(b)==7);
    // Large-page native walks and supervisor write-protection match the model.
    let large=0;while large<3 {
        tj_reset(a,b,ra,rb,"488b0425004000004889042500500000f4",64);n=0;
        while n<2 {let c=a;let ram=ra;if n {c=b;ram=rb;}store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,32);store64(c+176,256);
            store64(ram+0x10000,0x11003);if large==0 {store64(ram+0x11000,0x83);}else {store64(ram+0x11000,0x12003);let leaf=0x83;if large==2 {leaf=0x81;}store64(ram+0x12000,leaf);}store64(ram+0x4000,0x12345678);n=n+1;}
        let reason=tj_compare(a,b,ra,rb,ua,ub,100);if large<2 {tj_expect(reason==5 && load64(rb+0x5000)==0x12345678);}else {tj_expect(reason==-1);}large=large+1;
    }
    // Precompile a target, then modify it through another virtual mapping of
    // its physical code page. Native chaining must reject the stale target.
    tj_reset(a,b,ra,rb,"c704250b500000b8785634b801000000f4",64);n=0;
    while n<2 {let c=a;let ram=ra;if n {c=b;ram=rb;}store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,32);store64(c+176,256);
        store64(ram+0x10000,0x11003);store64(ram+0x11000,0x12003);store64(ram+0x12000,0x13003);store64(ram+0x13008,0x1003);store64(ram+0x13028,0x1003);store64(c+128,0x100b);n=n+1;}
    tj_expect(tj_compare(a,b,ra,rb,ua,ub,100)==5 && load64(b)==1);store64(a+128,0x1000);store64(b+128,0x1000);
    tj_expect(tj_compare(a,b,ra,rb,ua,ub,200)==5 && load64(b)==0x345678);
    softvm_close(va);softvm_close(vb);syscall(1,1,"PASS: native JIT chaining, differential programs, fuel, code changes and memory bounds\n",87,0,0,0);return 0;
}
