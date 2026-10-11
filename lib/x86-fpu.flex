// Per-vCPU x87 state and checked execution on the host's x87 arithmetic unit.
// CPU allocation is 8192 bytes: FX image 1024, host FX image 1568, operand
// scratch 2080, physical byte map 2816 and private helper cache pointer 6936.
// Only explicitly accepted x87 opcode/ModR/M pairs are emitted. Guest memory
// operands always refer to scratch; no guest address enters native code.
global xf_mxcsr_supported=0;
fn xf_u16(p) {return load8(p)|(load8(p+1)<<8);}
fn xf_put16(p,v) {store8(p,v);store8(p+1,v>>8);return 0;}
// SIMD helpers execute on the host arithmetic unit, so expose exactly its
// writable MXCSR bits. In particular, DAZ (bit 6) is optional and Mesa enables
// it on modern SSE2 CPUs. A zero FXSAVE mask has the architectural fallback.
fn xf_mxcsr_mask() {
    if xf_mxcsr_supported {return xf_mxcsr_supported;}
    let code=alloc(4096);if code<0 {return 0xffbf;}let state=alloc(512);
    if state<0 {syscall(11,code,4096,0,0,0,0);return 0xffbf;}
    xf_hex(code,"480fae07c3");let mask=0;
    if syscall(10,code,4096,5,0,0,0)==0 {ffi_call(code,state,0,0,0,0,0);mask=(load64(state+24)>>32)&0xffff;}
    syscall(11,state,512,0,0,0,0);syscall(11,code,4096,0,0,0,0);
    if !mask {mask=0xffbf;}xf_mxcsr_supported=mask;return mask;
}
fn xf_reset(c) {let i=0;while i<512 {store8(c+1024+i,0);i=i+1;}xf_put16(c+1024,0x37f);store64(c+1048,(xf_mxcsr_mask()<<32)|0x1f80);return 0;}
fn xf_close(c) {let cache=load64(c+6936);if cache {syscall(11,load64(cache),524288,0,0,0,0);syscall(11,cache,3104,0,0,0,0);store64(c+6936,0);}return 0;}
// 128 direct-mapped entries, one separately protected page per trusted helper.
// Hits never change page protection. Collisions rebuild only that slot; no
// helper is executing while this single-vCPU cache is changed.
fn xf_helper(c,key) {
    let cache=load64(c+6936);if !cache {
        cache=alloc(3104);if cache<0 {x86_fault(c,"Cannot allocate FP helper cache.");return 0;}
        let arena=alloc(524288);if arena<0 {syscall(11,cache,3104,0,0,0,0);x86_fault(c,"Cannot allocate FP helper arena.");return 0;}
        store64(cache,arena);store64(c+6936,cache);
    }
    let slot=((key*0x9e3779b185ebca87)>>57)&127;let entry=cache+32+slot*24;
    if load64(entry+16) && load64(entry)==key {return entry;}
    let p=load64(cache)+slot*4096;
    if syscall(10,p,4096,3,0,0,0)<0 {x86_fault(c,"Cannot make FP helper writable.");return 0;}
    store64(entry,key);store64(entry+8,p);store64(entry+16,0);return entry;
}
fn xf_seal(c,entry) {if syscall(10,load64(entry+8),4096,5,0,0,0)<0 {return x86_fault(c,"Cannot make FP helper executable.");}store64(entry+16,1);let cache=load64(c+6936);store64(cache+8,load64(cache+8)+1);return 1;}
fn xf_digit(v) {if v>=97 {return v-87;}return v-48;}
fn xf_hex(p,text) {let i=0;while load8(text+i*2) {store8(p+i,xf_digit(load8(text+i*2))*16+xf_digit(load8(text+i*2+1)));i=i+1;}return i;}
fn xf_pending(c) {return (xf_u16(c+1026)&~xf_u16(c+1024)&63)!=0;}
fn xf_wait(c) {
    if (load64(c+152)&10)==10 {return x86_trap(c,7,"Guest FWAIT raised device-not-available.");}
    if xf_pending(c) {return x86_trap(c,16,"Guest FWAIT raised pending x87 exception.");}return 1;
}
// Prevalidate the whole operand and retain physical pointers before any write.
fn xf_memory(c,address,n,write) {
    let i=0;while i<n {let phys=x86_translate(c,address+i,write);if phys<0 {return 0;}let p=x86_phys(c,phys,1);if !p {return 0;}store64(c+2816+i*8,p);if !write {store8(c+2080+i,load8(p));}i=i+1;}return 1;
}
fn xf_commit(c,n) {let i=0;while i<n {let p=load64(c+2816+i*8);x86_invalidate_write(c,p-load64(c+296));store8(p,load8(c+2080+i));i=i+1;}return 0;}
fn xf_native(c,op,m,small,flags_result) {
    let key=op|(m<<8)|(small<<16)|(flags_result<<17);let entry=xf_helper(c,key);if !entry {return 0;}let p=load64(entry+8);
    if !load64(entry+16) {
        // FXSAVE64 host; FXRSTOR64 guest; operand scratch into RAX; guest flags.
        let n=xf_hex(p,"480fae06480fae0f4889d0519d");
        if small {store8(p+n,0x66);n=n+1;}store8(p+n,op);store8(p+n+1,m);n=n+2;
        n=n+xf_hex(p+n,"9c59480fae07480fae0e"); // flags; save guest; restore host
        if flags_result {n=n+xf_hex(p+n,"4889c8");}else {n=n+xf_hex(p+n,"0fb7c0");}
        store8(p+n,0xc3);
        if !xf_seal(c,entry) {return 0;}
    }
    return ffi_call(p,c+1024,c+1568,c+2080,(load64(c+136)&0x8d5)|0x202,0,0);
}
fn xf_valid_register(op,m) {
    if op==0xd8 {return 1;}
    if op==0xd9 {return m<=0xcf || m==0xd0 || m==0xe0 || m==0xe1 || m==0xe4 || m==0xe5 || (m>=0xe8 && m<=0xee) || m>=0xf0;}
    if op==0xda {return m<=0xdf || m==0xe9;}
    if op==0xdb {return m<=0xdf || m==0xe2 || m==0xe3 || (m>=0xe8 && m<=0xf7);}
    if op==0xdc {return m<=0xcf || m>=0xe0;}
    if op==0xdd {return m<=0xc7 || (m>=0xd0 && m<=0xef);}
    if op==0xde {return m<=0xcf || m==0xd9 || m>=0xe0;}
    return m==0xe0 || (m>=0xe8 && m<=0xf7);
}
fn xf_step(c,op) {
    if load64(c+152)&12 {return x86_trap(c,7,"Guest x87 raised device-not-available.");}
    let m=x86_modrm(c);if load64(c+288) {return 0;}
    let group=(m>>3)&7;let reg=m>=192;let bytes=0;let write=0;let small=load64(c+216)==2;let control=0;let nowait=0;
    if reg {
        if !xf_valid_register(op,m) {return x86_fault(c,"Unsupported or reserved x87 register instruction.");}
        if op==0xdb && (m==0xe2 || m==0xe3) {nowait=1;}if op==0xdf && m==0xe0 {nowait=1;}
    }else {
        if op==0xd8 || op==0xda {bytes=4;}else if op==0xdc {bytes=8;}else if op==0xde {bytes=2;}
        else if op==0xd9 {
            if group==0 {bytes=4;}else if group==2 || group==3 {bytes=4;write=1;}
            else if group==4 || group==6 {bytes=28;if small {bytes=14;}control=1;if group==6 {write=1;nowait=1;}}
            else if group==5 || group==7 {bytes=2;control=1;if group==7 {write=1;nowait=1;}}
        }else if op==0xdb {
            if group==0 {bytes=4;}else if group==2 || group==3 {bytes=4;write=1;}else if group==5 {bytes=10;}else if group==7 {bytes=10;write=1;}
        }else if op==0xdd {
            if group==0 {bytes=8;}else if group==2 || group==3 {bytes=8;write=1;}
            else if group==4 || group==6 {bytes=108;if small {bytes=94;}control=1;if group==6 {write=1;nowait=1;}}
            else if group==7 {bytes=2;write=1;nowait=1;}
        }else if op==0xdf {
            if group==0 {bytes=2;}else if group==2 || group==3 {bytes=2;write=1;}else if group==4 || group==5 {bytes=10;if group==5 {bytes=8;}}else if group==6 || group==7 {bytes=10;if group==7 {bytes=8;}write=1;}
        }
        if !bytes {return x86_fault(c,"Unsupported or reserved x87 memory instruction.");}
    }
    let cw=xf_u16(c+1024);let sw=xf_u16(c+1026);let saved_ip=load64(c+1032);let saved_dp=load64(c+1040);let saved_op=xf_u16(c+1030);
    if !nowait && xf_pending(c) {return x86_trap(c,16,"Guest x87 raised pending floating-point exception.");}
    // Masked arithmetic is supported. Unmasked arithmetic requires precise
    // exception-dependent commit/rollback and is rejected before executing.
    if !control && !nowait && (cw&63)!=63 {return x86_fault(c,"Unmasked x87 arithmetic is not implemented.");}
    let address=0;let loaded_cw=cw;
    if !reg {address=x86_linear(c);if !xf_memory(c,address,bytes,write) {return 0;}
        if control && !write {loaded_cw=xf_u16(c+2080);xf_put16(c+2080,loaded_cw|63);}
    }
    // Host arithmetic never runs with guest traps enabled. The complete host
    // x87/XMM/MXCSR state is saved/restored around the trusted instruction.
    xf_put16(c+1024,cw|63);xf_put16(c+1026,sw&~0x8080);
    let host_m=m;if !reg {host_m=group<<3;}
    let flags_result=reg && ((op==0xdb || op==0xdf) && m>=0xe8);
    let result=xf_native(c,op,host_m,small && !reg && control,flags_result);
    if load64(c+288) {xf_put16(c+1024,cw);xf_put16(c+1026,sw);return 0;}
    store64(c+1048,(load64(c+1048)&0xffffffff)|(xf_mxcsr_mask()<<32));
    let next_cw=cw;
    if control && !write {next_cw=loaded_cw;}
    if (op==0xdb && reg && m==0xe3) || (op==0xdd && !reg && group==6) {next_cw=0x37f;}
    else if op==0xd9 && !reg && group==6 {next_cw=cw|63;}
    xf_put16(c+1024,next_cw);let status=xf_u16(c+1026);if xf_pending(c) {status=status|0x8080;}else {status=status&~0x8080;}xf_put16(c+1026,status);
    if flags_result {store64(c+136,(load64(c+136)&~0x8d5)|(result&0x8d5));}
    if op==0xdf && reg && m==0xe0 {x86_setreg(c,0,2,sw);}
    if !reg && write {
        if control {xf_put16(c+2080,cw);}
        if (op==0xd9 || op==0xdd) && group==6 {
            let at=4;if small {at=2;}xf_put16(c+2080+at,sw);
            if small {xf_put16(c+2086,saved_ip);xf_put16(c+2088,load64(c+376));xf_put16(c+2090,saved_dp);xf_put16(c+2092,load64(c+672));}
            else {let j=0;while j<4 {store8(c+2092+j,saved_ip>>(j*8));store8(c+2100+j,saved_dp>>(j*8));j=j+1;}xf_put16(c+2096,load64(c+376));xf_put16(c+2098,saved_op);xf_put16(c+2104,load64(c+672));}
        }
        if op==0xdd && group==7 {xf_put16(c+2080,sw);}
        xf_commit(c,bytes);
    }
    // No native helper address is exposed as an x87 instruction/data pointer.
    if !control && !nowait {
        store64(c+1032,load64(c+200));if !reg {store64(c+1040,address);}
        xf_put16(c+1030,((op&7)<<8)|m);
    }
    return 1;
}
fn xf_fx(c,m) {
    let group=(m>>3)&7;let address=x86_linear(c);
    if load64(c+240) || group>3 {return x86_fault(c,"Unsupported floating-point state instruction.");}
    if load64(c+152)&8 {return x86_trap(c,7,"Guest FP state operation raised device-not-available.");}
    if group<2 && (address&15) {return x86_gp(c,"Guest FXSAVE/FXRSTOR address is not 16-byte aligned.");}
    let n=512;if group>=2 {n=4;}let write=group==0 || group==3;
    if !xf_memory(c,address,n,write) {return 0;}
    if group==0 {
        let i=0;while i<464 {store8(c+2080+i,load8(c+1024+i));i=i+1;}
        // FXSAVE leaves the software-owned tail of its 512-byte image intact.
        i=464;while i<512 {store8(c+2080+i,load8(load64(c+2816+i*8)));i=i+1;}
        if !(load64(c+208)&8) {store64(c+2088,load64(c+1032)&0xffffffff);store64(c+2096,load64(c+1040)&0xffffffff);}
        xf_commit(c,512);
    }else if group==1 {
        let mx=load64(c+2104)&0xffffffff;if mx&~xf_mxcsr_mask() {return x86_gp(c,"Guest FXRSTOR contains reserved MXCSR bits.");}
        let i=0;while i<416 {store8(c+1024+i,load8(c+2080+i));i=i+1;}
        if !(load64(c+208)&8) {store64(c+1032,load64(c+1032)&0xffffffff);store64(c+1040,load64(c+1040)&0xffffffff);}
        store64(c+1048,mx|(xf_mxcsr_mask()<<32));
    }else if group==2 {
        let mx=load64(c+2080)&0xffffffff;if mx&~xf_mxcsr_mask() {return x86_gp(c,"Guest LDMXCSR contains reserved bits.");}store64(c+1048,mx|(xf_mxcsr_mask()<<32));
    }else {let mx=load64(c+1048)&0xffffffff;store64(c+2080,mx);xf_commit(c,4);}
    return 1;
}
fn xf_mmx_opcode(op) {
    return (op>=0x60 && op<=0x6b) || op==0x6e || op==0x6f || (op>=0x71 && op<=0x77) || op==0x7e || op==0x7f || (op>=0xd1 && op<=0xd5) || op==0xd8 || op==0xd9 || op==0xdb || op==0xdc || op==0xdd || op==0xdf || op==0xe1 || op==0xe2 || op==0xe5 || op==0xe8 || op==0xe9 || op==0xeb || op==0xec || op==0xed || op==0xef || (op>=0xf1 && op<=0xf5) || (op>=0xf8 && op<=0xfe);
}
fn xf_mmx(c,op) {
    if load64(c+152)&4 {return x86_trap(c,6,"Guest MMX with CR0.EM raised invalid opcode.");}
    if load64(c+152)&8 {return x86_trap(c,7,"Guest MMX raised device-not-available.");}
    if xf_pending(c) {return x86_trap(c,16,"Guest MMX raised pending x87 exception.");}
    let m=0;let memory=0;let immediate=-1;let width=8;let write=op==0x7e || op==0x7f;let integer=op==0x6e || op==0x7e;
    if op!=0x77 {m=x86_modrm(c);memory=!load64(c+240);}
    if integer {width=4;if load64(c+208)&8 {width=8;}}
    let shifts=op>=0x71 && op<=0x73;
    if shifts {let group=(m>>3)&7;if memory || (group!=2 && group!=6 && (group!=4 || op==0x73)) {return x86_trap(c,6,"Invalid MMX immediate shift.");}immediate=x86_fetch(c,1);}
    if load64(c+288) {return 0;}
    if memory {if !xf_memory(c,x86_linear(c),width,write) {return 0;}}
    else if integer && !write {store64(c+2080,x86_rm(c,width));}
    let native_m=m;if memory || integer {native_m=m&0x38;}
    let rex=0;if integer && width==8 {rex=0x48;}
    let key=0x200000000|op|(native_m<<8)|(rex<<16)|((immediate+1)<<40);let entry=xf_helper(c,key);if !entry {return 0;}let p=load64(entry+8);
    if !load64(entry+16) {
        let at=xf_hex(p,"480fae06480fae0f4889d0");if rex {store8(p+at,rex);at=at+1;}
        store8(p+at,0x0f);store8(p+at+1,op);at=at+2;if op!=0x77 {store8(p+at,native_m);at=at+1;}
        if immediate>=0 {store8(p+at,immediate);at=at+1;}
        xf_hex(p+at,"480fae07480fae0e31c0c3");if !xf_seal(c,entry) {return 0;}
    }
    let ip=load64(c+1032);let dp=load64(c+1040);let saved_op=xf_u16(c+1030);
    ffi_call(p,c+1024,c+1568,c+2080,0,0,0);store64(c+1032,ip);store64(c+1040,dp);xf_put16(c+1030,saved_op);
    if memory && write {xf_commit(c,width);}else if integer && write {x86_setrm(c,width,load64(c+2080));}
    return !load64(c+288);
}
fn xf_vector_opcode(op,prefix) {
    if op==0xc4 || op==0xc5 {return prefix==0x66;}
    if op==0x2a || op==0x2c || op==0x2d {return prefix==0xf2 || prefix==0xf3;}
    if op>=0x12 && op<=0x17 {return !prefix || prefix==0x66;}
    if op==0x5a {return 1;}
    if op==0x5b {return !prefix || prefix==0x66 || prefix==0xf3;}
    if op==0xe6 {return prefix==0x66 || prefix==0xf2 || prefix==0xf3;}
    if op==0x50 || op==0x2e || op==0x2f {return !prefix || prefix==0x66;}
    if op==0x6e || op==0xd6 || op==0xd7 {return prefix==0x66;}
    if op==0x7e {return prefix==0x66 || prefix==0xf3;}
    if op==0x10 || op==0x11 || op==0x51 || (op>=0x58 && op<=0x59) || (op>=0x5c && op<=0x5f) || op==0xc2 {return 1;}
    if op==0x28 || op==0x29 || (op>=0x54 && op<=0x57) || op==0xc6 {return !prefix || prefix==0x66;}
    if op==0x6f || op==0x7f {return prefix==0x66 || prefix==0xf3;}
    if op==0x70 {return prefix==0x66 || prefix==0xf2 || prefix==0xf3;}
    if prefix!=0x66 {return 0;}
    return (op>=0x60 && op<=0x6d) || (op>=0x71 && op<=0x76) || (op>=0xd1 && op<=0xd5) || (op>=0xd8 && op<=0xe5) || (op>=0xe8 && op<=0xef) || (op>=0xf1 && op<=0xf6) || (op>=0xf8 && op<=0xfe);
}
fn xf_vector(c,op,prefix) {
    if load64(c+152)&4 {return x86_trap(c,6,"Guest SSE with CR0.EM raised invalid opcode.");}
    if load64(c+152)&8 {return x86_trap(c,7,"Guest SSE raised device-not-available.");}
    if !(load64(c+168)&512) {return x86_trap(c,6,"Guest SSE requires CR4.OSFXSR.");}
    let m=x86_modrm(c);let reg=load64(c+232);let rm=load64(c+248);let memory=!load64(c+240);
    if op==0xc4 || op==0xc5 {
        if op==0xc5 && memory {return x86_trap(c,6,"PEXTRW requires an XMM register source.");}
        let index=x86_fetch(c,1)&7;if load64(c+288) {return 0;}
        if op==0xc5 {x86_setreg(c,reg,4,xf_u16(c+1184+rm*16+index*2));}
        else {let value=x86_rm(c,2);if load64(c+288) {return 0;}xf_put16(c+1184+reg*16+index*2,value);}
        return 1;
    }
    if op==0x12 || op==0x13 || op==0x16 || op==0x17 {
        let vector=c+1184+reg*16;let half=0;if op&4 {half=8;}
        if op&1 {
            if !memory {return x86_trap(c,6,"Packed half-vector store requires memory.");}
            x86_write(c,x86_linear(c),8,load64(vector+half));
        }else {
            if !memory && prefix==0x66 {return x86_trap(c,6,"Packed double half-vector load requires memory.");}
            let value=0;if memory {value=x86_read(c,x86_linear(c),8);}else {value=load64(c+1184+rm*16+8-half);}
            if !load64(c+288) {store64(vector+half,value);}
        }return !load64(c+288);
    }
    // These instructions cross the integer/vector register files, unlike the
    // native vector helper whose operands both name XMM registers.
    if op==0x6e || op==0x7e || op==0xd6 {
        let width=4;if (load64(c+208)&8) || prefix==0xf3 || op==0xd6 {width=8;}
        let vector=c+1184+reg*16;
        if op==0x6e || prefix==0xf3 {
            let value=0;if prefix==0xf3 && !memory {value=load64(c+1184+rm*16);}else {value=x86_rm(c,width);}
            if load64(c+288) {return 0;}store64(vector,value);store64(vector+8,0);
        }else if op==0xd6 && !memory {store64(c+1184+rm*16,load64(vector));store64(c+1192+rm*16,0);}
        else {x86_setrm(c,width,load64(vector));if load64(c+288) {return 0;}}
        return 1;
    }
    if op==0xd7 || op==0x50 {
        if memory {return x86_trap(c,6,"Vector mask extraction requires an XMM register.");}
        let vector=c+1184+rm*16;let mask=0;let i=0;
        if op==0xd7 {while i<16 {mask=mask|((load8(vector+i)>>7)<<i);i=i+1;}}
        else {let width=4;if prefix==0x66 {width=8;}while i<16/width {mask=mask|((load8(vector+i*width+width-1)>>7)<<i);i=i+1;}}
        x86_setreg(c,reg,4,mask);return 1;
    }
    // Integer sources are staged in scratch memory so the trusted template
    // cannot interpret a guest GPR number as a host register.
    let integer_input=op==0x2a;let integer_output=op==0x2c || op==0x2d;let integer_width=4;
    if integer_output && (load64(c+208)&8) {integer_width=8;}
    if integer_input {
        if load64(c+208)&8 {integer_width=8;}
        let value=x86_rm(c,integer_width);if load64(c+288) {return 0;}store64(c+2080,value);
        memory=1;
    }
    let immediate=-1;let shifts=op>=0x71 && op<=0x73;
    if shifts || op==0x70 || op==0xc2 || op==0xc6 {immediate=x86_fetch(c,1);}
    if load64(c+288) {return 0;}
    if shifts {let group=(m>>3)&7;let valid=group==2 || group==6 || (group==4 && op!=0x73) || (op==0x73 && (group==3 || group==7));if memory || !valid || reg>=8 {return x86_fault(c,"Invalid packed immediate shift.");}}
    let compare=op==0x2e || op==0x2f;
    let n=16;if compare {n=4;if prefix==0x66 {n=8;}}if prefix==0xf3 && (integer_output || op==0x10 || op==0x11 || op==0x51 || (op>=0x58 && op<=0x5f) || op==0xc2) {n=4;}
    if prefix==0xf2 && op!=0x70 {n=8;}
    if op==0x5a {n=16;if !prefix || prefix==0xf2 {n=8;}if prefix==0xf3 {n=4;}}
    if op==0x5b {n=16;}if op==0xe6 {n=16;if prefix==0xf3 {n=8;}}
    let write=op==0x11 || op==0x29 || op==0x7f;let address=0;
    if memory && !integer_input {
        address=x86_linear(c);
        if (op==0x28 || op==0x29 || ((op==0x6f || op==0x7f) && prefix==0x66)) && (address&15) {return x86_gp(c,"Aligned SSE memory operand is not 16-byte aligned.");}
        if !xf_memory(c,address,n,write) {return 0;}
    }
    let arithmetic=op==0x5a || op==0x5b || op==0xe6 || compare || integer_input || integer_output || op==0x51 || (op>=0x58 && op<=0x5f) || op==0xc2;
    let mx=load64(c+1048)&0xffffffff;
    if arithmetic && (mx&0x1f80)!=0x1f80 {return x86_fault(c,"Unmasked SIMD arithmetic exceptions are not implemented.");}
    let native_m=(reg&7)<<3;let rex=0;if reg>=8 {rex=4;}
    if !memory {native_m=native_m|192|(rm&7);if rm>=8 {rex=rex|1;}}
    if integer_output {native_m=native_m&~56;rex=rex&~4;}
    if (integer_input || integer_output) && integer_width==8 {rex=rex|8;}
    let key=0x100000000|op|(native_m<<8)|(prefix<<16)|(rex<<24)|((immediate+1)<<40);let entry=xf_helper(c,key);if !entry {return 0;}let p=load64(entry+8);
    if !load64(entry+16) {
        let at=xf_hex(p,"480fae06480fae0f4889d0");
        if prefix {store8(p+at,prefix);at=at+1;}if rex {store8(p+at,0x40|rex);at=at+1;}
        store8(p+at,0x0f);store8(p+at+1,op);store8(p+at+2,native_m);at=at+3;if immediate>=0 {store8(p+at,immediate);at=at+1;}
        if compare {at=at+xf_hex(p+at,"9c8f00");}
        if integer_output {at=at+xf_hex(p+at,"488902");}
        at=at+xf_hex(p+at,"480fae07480fae0e31c0c3");
        if !xf_seal(c,entry) {return 0;}
    }
    let cw=xf_u16(c+1024);let sw=xf_u16(c+1026);xf_put16(c+1024,cw|63);xf_put16(c+1026,sw&~0x8080);
    ffi_call(p,c+1024,c+1568,c+2080,0,0,0);xf_put16(c+1024,cw);xf_put16(c+1026,sw);store64(c+1048,(load64(c+1048)&0xffffffff)|(xf_mxcsr_mask()<<32));
    if integer_output {x86_setreg(c,reg,integer_width,load64(c+2080));}
    if compare {store64(c+136,(load64(c+136)&~0x8d5)|(load64(c+2080)&0x45));}
    if memory && write {xf_commit(c,n);}return 1;
}
