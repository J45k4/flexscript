import "jit-memory.flex";
// Native x86-64 block compiler, written in Flexscript. Only explicitly decoded
// integer instructions and selected SSE primitives enter generated code.
// Memory accesses retain bounds and
// paging checks; faults, privileged instructions and devices use the interpreter.
// No guest bytes execute as host code. Each bounded code page transitions RW -> RX before execution.
global x86_jit_enabled=1;
global x86_jit_min_fuel=1024;
global x86_jit_threshold=4;
// Transient compiler prefix state; generated accesses load the live guest base.
global xj_segment=0;
fn xj_reset(c) {
    let state=load64(c+992);if state {let i=0;while i<32768 {store64(state+64+i*256+56,0);i=i+1;}}
    store64(c+1008,0);store64(c+1016,0);return 0;
}
fn xj_close(c) {
    let state=load64(c+992);if state {syscall(11,load64(state),134221824,0,0,0,0);syscall(11,state,8388672,0,0,0,0);store64(c+992,0);}return 0;
}
fn xj_state(c) {
    let state=load64(c+992);if state {return state;}if load64(c+1000) {return 0;}
    state=alloc(8388672);if state<0 {store64(c+1000,1);return 0;}let code=alloc(134221824);
    if code<0 {syscall(11,state,8388672,0,0,0,0);store64(c+1000,1);return 0;}
    store64(state,code);if !xj_memory_init(state) {syscall(11,code,134221824,0,0,0,0);syscall(11,state,8388672,0,0,0,0);store64(c+1000,1);return 0;}store64(c+992,state);return state;
}
// Cache layout: 64-byte header + 32768 records of 256 bytes. Each slot owns
// one 4 KiB code page; the helper page follows the 128 MiB code arena. The slot
// mask is mirrored in the audited dispatcher; tests verify its embedded bytes.
// Record: IP, mode, generation, source length, instruction count, native size,
// visit count, status (0 empty, 1 warming, 2 interpreted, 3 compiled), source[128].
// Emitter state lives in the state header: output, cursor, source, limit, pos.
fn xj_byte(s,value) {let at=load64(s+16);if at>=4000 {store64(s+48,1);return 0;}store8(load64(s+8)+at,value);store64(s+16,at+1);return 0;}
fn xj_word(s,value,n) {let i=0;while i<n {xj_byte(s,value>>(i*8));i=i+1;}return 0;}
fn xj_source(s,n) {
    let at=load64(s+40);if n<1 || at+n>load64(s+32) {store64(s+48,1);return 0;}
    let result=0;let i=0;while i<n {result=result|(load8(load64(s+24)+at+i)<<(i*8));i=i+1;}
    store64(s+40,at+n);return result;
}
// Look ahead without changing the decoder on failure. NOP operands describe
// encoding length only: never calculate or access their apparent address.
fn xj_nop_byte(s,at) {if at>=load64(s+32) {return -1;}return load8(load64(s+24)+at);}
fn xj_nop(s,mode) {
    let start=load64(s+40);let at=start;let rex=0;let op=xj_nop_byte(s,at);
    while op==0x66 || op==0x2e || (mode==64 && op>=0x40 && op<=0x4f) {
        rex=0;if op>=0x40 && op<=0x4f {rex=op;}
        at=at+1;if at-start>=15 {return 0;}op=xj_nop_byte(s,at);
    }
    if op==0x90 && !(rex&1) {store64(s+40,at+1);return 1;}
    if op!=0x0f || xj_nop_byte(s,at+1)!=0x1f {return 0;}
    let m=xj_nop_byte(s,at+2);if m<0 || (m&0x38) {return 0;}at=at+3;
    let mod=m>>6;let rm=m&7;let displacement=0;
    if mod<3 {
        if rm==4 {let sib=xj_nop_byte(s,at);if sib<0 {return 0;}at=at+1;if mod==0 && (sib&7)==5 {displacement=4;}}
        else if mod==0 && rm==5 {displacement=4;}
        if mod==1 {displacement=1;}else if mod==2 {displacement=4;}
    }
    at=at+displacement;if at>load64(s+32) || at-start>15 {return 0;}
    store64(s+40,at);return 1;
}
fn xj_load(s,host,guest) {let rex=0x48;if host>=8 {rex=0x4c;}xj_byte(s,rex);xj_byte(s,0x8b);xj_byte(s,0x87+(host&7)*8);xj_word(s,guest*8,4);return 0;}
fn xj_store(s,host,offset) {let rex=0x48;if host>=8 {rex=0x4c;}xj_byte(s,rex);xj_byte(s,0x89);xj_byte(s,0x87+(host&7)*8);xj_word(s,offset,4);return 0;}
fn xj_immediate(s,host,value) {xj_byte(s,0x48);xj_byte(s,0xb8+host);xj_word(s,value,8);return 0;}
fn xj_flags_mask(s,mask) {
    // pushfq; pop rdx. Merge only arithmetic status bits into guest RFLAGS.
    xj_byte(s,0x9c);xj_byte(s,0x5a);
    xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0xe2);xj_word(s,mask,4);
    xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0xa7);xj_word(s,136,4);xj_word(s,~mask,4);
    xj_byte(s,0x48);xj_byte(s,0x09);xj_byte(s,0x97);xj_word(s,136,4);return 0;
}
fn xj_flags(s) {return xj_flags_mask(s,0x8d5);}
fn xj_arithmetic(s,operation,width,is_test) {
    if operation==2 || operation==3 {
        xj_load(s,2,17); // guest FLAGS at 136
        xj_byte(s,0x48);xj_byte(s,0x0f);xj_byte(s,0xba);xj_byte(s,0xe2);xj_byte(s,0);
    }
    if width==8 {xj_byte(s,0x48);}
    let opcode=operation*8+1;if is_test {opcode=0x85;}
    xj_byte(s,opcode);xj_byte(s,0xc8);xj_flags(s);
    return 0;
}
fn xj_alu(s,operation,width,destination,source,immediate,is_test) {
    xj_load(s,0,destination);if immediate {xj_immediate(s,1,source);}else {xj_load(s,1,source);}
    xj_arithmetic(s,operation,width,is_test);
    if operation!=7 && !is_test {xj_store(s,0,destination*8);}return 0;
}
// LEA is safe to translate: it calculates an address without accessing RAM.
fn xj_address(s,m,rex,ip,trailing) {
    let mod=m>>6;let raw=m&7;let base=raw+(rex&1)*8;let index=-1;let shift=0;let rip=0;
    if raw==4 {let sib=xj_source(s,1);base=(sib&7)+(rex&1)*8;let r=(sib>>3)&7;shift=sib>>6;if r!=4 || (rex&2) {index=r+(rex&2)*4;}if (sib&7)==5 && mod==0 {base=-1;}}
    else if raw==5 && mod==0 {base=-1;rip=load64(s+56)==64;}
    let displacement=0;if mod==1 {displacement=x86_signed(xj_source(s,1),1);}else if mod==2 || (mod==0 && base<0) {displacement=x86_signed(xj_source(s,4),4);}
    if load64(s+48) {return 0;}
    if base>=0 {xj_load(s,0,base);}else {let value=0;if rip {value=ip+load64(s+40)+trailing;}xj_immediate(s,0,value);}
    if index>=0 {xj_load(s,1,index);if shift {xj_byte(s,0x48);xj_byte(s,0xc1);xj_byte(s,0xe1);xj_byte(s,shift);}xj_byte(s,0x48);xj_byte(s,0x01);xj_byte(s,0xc8);}
    if displacement {xj_byte(s,0x48);xj_byte(s,0x05);xj_word(s,displacement,4);}
    if load64(s+56)==32 {xj_byte(s,0x89);xj_byte(s,0xc0);}
    if xj_segment {xj_byte(s,0x48);xj_byte(s,0x03);xj_byte(s,0x87);xj_word(s,xj_segment,4);}return 1;
}
fn xj_shift(s,op,width,group,destination) {
    if op==0xd3 {xj_load(s,1,1);}else {let count=1;if op==0xc1 {count=xj_source(s,1);}xj_immediate(s,1,count);}
    xj_byte(s,0x83);xj_byte(s,0xe1);let mask=31;if width==8 {mask=63;}xj_byte(s,mask);
    xj_byte(s,0x0f);xj_byte(s,0x84);let zero=load64(s+16);xj_word(s,0,4);
    xj_load(s,0,destination);
    if group==2 || group==3 {xj_load(s,2,17);xj_byte(s,0x48);xj_byte(s,0x0f);xj_byte(s,0xba);xj_byte(s,0xe2);xj_byte(s,0);}
    if width==8 {xj_byte(s,0x48);}xj_byte(s,0xd3);xj_byte(s,0xc0+group*8);
    xj_byte(s,0x9c);xj_byte(s,0x5a); // capture shift flags before testing CL
    xj_byte(s,0x83);xj_byte(s,0xf9);xj_byte(s,1);
    xj_byte(s,0x0f);xj_byte(s,0x84);let one=load64(s+16);xj_word(s,0,4);
    let changed=0x8d5;let many=0xc5;let single=0x8c5;
    if group<4 {changed=1;many=1;single=0x801;}
    xj_byte(s,0x81);xj_byte(s,0xe2);xj_word(s,many,4);
    // Rotates preserve OF except for count=1. Shifts deterministically clear
    // undefined AF and multi-bit OF, matching the interpreter's contract.
    xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0xa7);xj_word(s,136,4);xj_word(s,~changed,4);
    xj_byte(s,0xe9);let merge=load64(s+16);xj_word(s,0,4);
    xj_patch(s,one,load64(s+16));if group<4 {changed=0x801;}
    xj_byte(s,0x81);xj_byte(s,0xe2);xj_word(s,single,4);
    xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0xa7);xj_word(s,136,4);xj_word(s,~changed,4);
    xj_patch(s,merge,load64(s+16));xj_byte(s,0x48);xj_byte(s,0x09);xj_byte(s,0x97);xj_word(s,136,4);
    xj_store(s,0,destination*8);
    if (group==2 || group==3) && width==4 {
        xj_byte(s,0xe9);let done=load64(s+16);xj_word(s,0,4);xj_patch(s,zero,load64(s+16));
        xj_load(s,0,destination);xj_byte(s,0x89);xj_byte(s,0xc0);xj_store(s,0,destination*8);xj_patch(s,done,load64(s+16));
    }else {xj_patch(s,zero,load64(s+16));}return 1;
}
fn xj_rdtsc(s,ip,last,count) {
    // Preserve CR4.TSD privilege checks when a cached block is reused after
    // a control change. Retry the denied instruction in the interpreter.
    xj_byte(s,0xf6);xj_byte(s,0x87);xj_word(s,376,4);xj_byte(s,3);
    xj_byte(s,0x0f);xj_byte(s,0x84);let kernel=load64(s+16);xj_word(s,0,4);
    xj_byte(s,0xf6);xj_byte(s,0x87);xj_word(s,168,4);xj_byte(s,4);
    xj_byte(s,0x0f);xj_byte(s,0x84);let allowed=load64(s+16);xj_word(s,0,4);
    xj_finish(s,ip,last,count);xj_patch(s,kernel,load64(s+16));xj_patch(s,allowed,load64(s+16));
    // Native blocks retire together, so include preceding instructions in
    // this block when constructing the same deterministic TSC as x86_step.
    xj_load(s,0,39);xj_load(s,2,63);xj_byte(s,0x48);xj_byte(s,0x01);xj_byte(s,0xd0);
    if count {xj_byte(s,0x48);xj_byte(s,0x05);xj_word(s,count,4);}
    xj_byte(s,0x48);xj_byte(s,0x89);xj_byte(s,0xc2);xj_byte(s,0x48);xj_byte(s,0xc1);xj_byte(s,0xea);xj_byte(s,32);xj_byte(s,0x89);xj_byte(s,0xc0);xj_store(s,0,0);xj_store(s,2,16);return 1;
}
fn xj_cmov(s,rex,ip,instruction,width,condition,last,count) {
    let m=xj_source(s,1);let destination=((m>>3)&7)+(rex&4)*2;let source=(m&7)+(rex&1)*8;
    // A memory source is read even when the condition is false. Retain the
    // normal walker and precise retry boundary before changing any register.
    if m<192 {
        if !xj_address(s,m,rex,ip,0) {return 0;}
        xj_memory_call(s,width,0,instruction,last,count);
        if width==8 {xj_byte(s,0x48);}xj_byte(s,0x8b);xj_byte(s,0x08);
    }else {xj_load(s,1,source);}
    xj_load(s,0,destination);xj_load(s,2,17);
    xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0xe2);xj_word(s,0x8d5,4);
    xj_byte(s,0x48);xj_byte(s,0x83);xj_byte(s,0xca);xj_byte(s,2);xj_byte(s,0x52);xj_byte(s,0x9d);
    if width==8 {xj_byte(s,0x48);}xj_byte(s,0x0f);xj_byte(s,0x40+condition);xj_byte(s,0xc1);
    // CMOV r32 zero-extends the destination on both outcomes.
    xj_store(s,0,destination*8);return 1;
}
fn xj_bitscan(s,rex,ip,instruction,width,opcode,last,count) {
    let m=xj_source(s,1);let destination=((m>>3)&7)+(rex&4)*2;let source=(m&7)+(rex&1)*8;
    if m<192 {if !xj_address(s,m,rex,ip,0) {return 0;}xj_memory_call(s,width,0,instruction,last,count);
        if width==8 {xj_byte(s,0x48);}xj_byte(s,0x8b);xj_byte(s,0x08);
    }else {xj_load(s,1,source);}
    if width==8 {xj_byte(s,0x48);}xj_byte(s,0x0f);xj_byte(s,opcode);xj_byte(s,0xc1);
    xj_byte(s,0x0f);xj_byte(s,0x84);let zero=load64(s+16);xj_word(s,0,4);
    // Only ZF is defined. Retain the interpreter's other flags and preserve
    // the entire old destination for zero input, including its upper bits.
    xj_store(s,0,destination*8);xj_flags_mask(s,64);xj_byte(s,0xe9);let end=load64(s+16);xj_word(s,0,4);
    xj_patch(s,zero,load64(s+16));xj_flags_mask(s,64);xj_patch(s,end,load64(s+16));return 1;
}
fn xj_store16(s,destination) {
    xj_byte(s,0x25);xj_word(s,65535,4);xj_load(s,2,destination);
    xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0xe2);xj_word(s,~65535,4);
    xj_byte(s,0x48);xj_byte(s,0x09);xj_byte(s,0xd0);xj_store(s,0,destination*8);return 0;
}
fn xj_move16(s,rex,ip,instruction,op,last,count) {
    let m=xj_source(s,1);let r=((m>>3)&7)+(rex&4)*2;let rm=(m&7)+(rex&1)*8;
    if m<192 {
        if !xj_address(s,m,rex,ip,0) {return 0;}
        xj_memory_call(s,2,op==0x89,instruction,last,count);
        if op==0x89 {xj_load(s,1,r);xj_byte(s,0x66);xj_byte(s,0x89);xj_byte(s,0x08);
            let after=ip+load64(s+40);if load64(s+56)==32 {after=after&0xffffffff;}xj_after_store(s,after,instruction,count+1);
        }else {xj_byte(s,0x0f);xj_byte(s,0xb7);xj_byte(s,0x00);xj_store16(s,r);}
    }else {let source=r;let destination=rm;if op==0x8b {source=rm;destination=r;}xj_load(s,0,source);xj_store16(s,destination);}
    return 1;
}
fn xj_reg8_load(s,host,guest,rex) {
    if !rex && guest>=4 && guest<8 {xj_load(s,host,guest-4);xj_byte(s,0x48);xj_byte(s,0xc1);xj_byte(s,0xe8+host);xj_byte(s,8);}
    else {xj_load(s,host,guest);}return 0;
}
fn xj_store8(s,guest,rex) {
    let shift=0;if !rex && guest>=4 && guest<8 {guest=guest-4;shift=8;}
    xj_byte(s,0x25);xj_word(s,255,4);
    if shift {xj_byte(s,0x48);xj_byte(s,0xc1);xj_byte(s,0xe0);xj_byte(s,shift);}
    xj_load(s,2,guest);xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0xe2);xj_word(s,~(255<<shift),4);
    xj_byte(s,0x48);xj_byte(s,0x09);xj_byte(s,0xd0);xj_store(s,0,guest*8);return 0;
}
fn xj_move8(s,rex,ip,instruction,op,last,count) {
    let m=xj_source(s,1);let r=((m>>3)&7)+(rex&4)*2;let rm=(m&7)+(rex&1)*8;
    if m<192 {
        if !xj_address(s,m,rex,ip,0) {return 0;}xj_memory_call(s,1,op==0x88,instruction,last,count);
        if op==0x88 {xj_reg8_load(s,1,r,rex);xj_byte(s,0x88);xj_byte(s,0x08);
            let after=ip+load64(s+40);if load64(s+56)==32 {after=after&0xffffffff;}xj_after_store(s,after,instruction,count+1);
        }else {xj_byte(s,0x0f);xj_byte(s,0xb6);xj_byte(s,0x00);xj_store8(s,r,rex);}
    }else {let source=r;let destination=rm;if op==0x8a {source=rm;destination=r;}xj_reg8_load(s,0,source,rex);xj_store8(s,destination,rex);}
    return 1;
}
fn xj_compare8(s,rex,ip,instruction,op,last,count) {
    if op==0x3c || op==0xa8 {xj_load(s,0,0);xj_immediate(s,1,xj_source(s,1));}
    else {
        let m=xj_source(s,1);let r=((m>>3)&7)+(rex&4)*2;let rm=(m&7)+(rex&1)*8;
        if op==0x80 && ((m>>3)&7)!=7 {return 0;}
        if m<192 {
            let trailing=0;if op==0x80 {trailing=1;}
            if !xj_address(s,m,rex,ip,trailing) {return 0;}let immediate=0;if trailing {immediate=xj_source(s,1);}
            xj_memory_call(s,1,0,instruction,last,count);xj_byte(s,0x0f);xj_byte(s,0xb6);xj_byte(s,0x00);
            if op==0x3a {xj_byte(s,0x48);xj_byte(s,0x89);xj_byte(s,0xc1);xj_reg8_load(s,0,r,rex);}
            else if trailing {xj_immediate(s,1,immediate);}else {xj_reg8_load(s,1,r,rex);}
        }else {
            let destination=rm;let source=r;if op==0x3a {destination=r;source=rm;}
            xj_reg8_load(s,0,destination,rex);if op==0x80 {xj_immediate(s,1,xj_source(s,1));}else {xj_reg8_load(s,1,source,rex);}
        }
    }
    let native=0x38;if op==0x84 || op==0xa8 {native=0x84;}xj_byte(s,native);xj_byte(s,0xc8);xj_flags(s);return 1;
}
// TEST never writes its operand. Fetch the immediate before the checked read
// so RIP-relative addressing includes its complete encoded length.
fn xj_test_immediate(s,rex,ip,instruction,width,m,last,count) {
    let size=4;if width==1 {size=1;}
    if m>=0 && m<192 {if !xj_address(s,m,rex,ip,size) {return 0;}}
    let value=x86_signed(xj_source(s,size),size);
    if m>=0 && m<192 {
        xj_memory_call(s,width,0,instruction,last,count);
        if width==1 {xj_byte(s,0x0f);xj_byte(s,0xb6);}else if width==8 {xj_byte(s,0x48);}
        if width!=1 {xj_byte(s,0x8b);}xj_byte(s,0x00);
    }else {
        let r=0;if m>=192 {r=(m&7)+(rex&1)*8;}
        if width==1 {xj_reg8_load(s,0,r,rex);}else {xj_load(s,0,r);}
    }
    xj_immediate(s,1,value);
    if width==1 {xj_byte(s,0x84);xj_byte(s,0xc8);xj_flags(s);}
    else {xj_arithmetic(s,4,width,1);}return 1;
}
fn xj_setcc(s,rex,ip,instruction,condition,last,count) {
    let m=xj_source(s,1);let r=(m&7)+(rex&1)*8;
    if m<192 {
        if !xj_address(s,m,rex,ip,0) {return 0;}xj_memory_call(s,1,1,instruction,last,count);
        xj_byte(s,0x49);xj_byte(s,0x89);xj_byte(s,0xc1); // R9 = checked pointer
    }
    // Restore arithmetic flags only. SETcc preserves all guest flags.
    xj_load(s,2,17);xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0xe2);xj_word(s,0x8d5,4);
    xj_byte(s,0x48);xj_byte(s,0x83);xj_byte(s,0xca);xj_byte(s,2);xj_byte(s,0x52);xj_byte(s,0x9d);
    xj_byte(s,0x0f);xj_byte(s,0x90+condition);xj_byte(s,0xc0);
    if m<192 {
        xj_byte(s,0x41);xj_byte(s,0x88);xj_byte(s,0x01);
        let after=ip+load64(s+40);if load64(s+56)==32 {after=after&0xffffffff;}xj_after_store(s,after,instruction,count+1);
    }else {xj_store8(s,r,rex);}return 1;
}
fn xj_count(s,count) {
    xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0x87);xj_word(s,312,4);xj_word(s,count,4);
    if count {
        xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0x87);xj_word(s,1008,4);xj_word(s,count,4);
        xj_byte(s,0x48);xj_byte(s,0xff);xj_byte(s,0x87);xj_word(s,1016,4);
    }return 0;
}
fn xj_finish(s,ip,last,count) {
    xj_immediate(s,0,ip);xj_store(s,0,128);xj_immediate(s,0,last);xj_store(s,0,200);xj_count(s,count);
    xj_byte(s,0xb8);xj_word(s,count,4);xj_byte(s,0xc3);return 0;
}
fn xj_memory_call(s,width,write,ip,last,count) {
    xj_byte(s,0xb9);xj_word(s,width,4);xj_byte(s,0x41);xj_byte(s,0xb8);xj_word(s,write,4);
    xj_byte(s,0xe8);xj_word(s,xj_helper(s)-(load64(s+8)+load64(s+16)+4),4);
    xj_byte(s,0x48);xj_byte(s,0x85);xj_byte(s,0xc0); // test returned host pointer
    xj_byte(s,0x0f);xj_byte(s,0x85);let patch=load64(s+16);xj_word(s,0,4);
    xj_finish(s,ip,last,count);let offset=load64(s+16)-patch-4;let i=0;while i<4 {store8(load64(s+8)+patch+i,offset>>(i*8));i=i+1;}return 0;
}
// A normal data store can stay in its block. The helper leaves R8=1
// only for a watched code/page-table write, which must return immediately
// after committing the store and before any stale translated instruction.
fn xj_after_store(s,ip,last,count) {
    xj_byte(s,0x45);xj_byte(s,0x85);xj_byte(s,0xc0);
    xj_byte(s,0x0f);xj_byte(s,0x84);let patch=load64(s+16);xj_word(s,0,4);
    xj_finish(s,ip,last,count);xj_patch(s,patch,load64(s+16));return 0;
}
fn xj_sse_guard(s,instruction,last,count) {
    // Recheck on every execution, including reuse after a control change.
    // Denied SSE retries in the interpreter to deliver the precise #UD/#NM.
    xj_byte(s,0xf6);xj_byte(s,0x87);xj_word(s,152,4);xj_byte(s,12);
    xj_byte(s,0x0f);xj_byte(s,0x84);let enabled=load64(s+16);xj_word(s,0,4);
    xj_finish(s,instruction,last,count);xj_patch(s,enabled,load64(s+16));
    xj_byte(s,0xf7);xj_byte(s,0x87);xj_word(s,168,4);xj_word(s,512,4);
    xj_byte(s,0x0f);xj_byte(s,0x85);enabled=load64(s+16);xj_word(s,0,4);
    xj_finish(s,instruction,last,count);xj_patch(s,enabled,load64(s+16));
    return 0;
}
// Trusted MOVDQU between host XMM0/1 and a fixed CPU-state displacement.
fn xj_xmm(s,reg,offset,write) {
    xj_byte(s,0xf3);xj_byte(s,0x0f);let op=0x6f;if write {op=0x7f;}
    xj_byte(s,op);xj_byte(s,0x87+reg*8);xj_word(s,offset,4);return 0;
}
// Register-only SSE2 string primitives. These cannot raise arithmetic SIMD
// exceptions or change MXCSR. Preserve the two temporary host XMM registers.
// Memory forms remain interpreted, including their operand/fault handling.
fn xj_vector_register(s,rex,instruction,op,prefix,last,count) {
    if prefix!=0x66 || (op!=0xef && op!=0x74 && op!=0xd7 && op!=0x70 && op!=0xd4 && op!=0x73) {return 0;}
    let m=xj_source(s,1);if m<192 {return 0;}
    let reg=((m>>3)&7)+(rex&4)*2;let rm=(m&7)+(rex&1)*8;let immediate=0;if op==0x70 || op==0x73 {immediate=xj_source(s,1);}
    if op==0x73 {if reg!=3 {return 0;}reg=rm;}
    xj_sse_guard(s,instruction,last,count);
    xj_xmm(s,0,1728,1);xj_xmm(s,1,1744,1);
    xj_xmm(s,0,1184+reg*16,0);xj_xmm(s,1,1184+rm*16,0);
    xj_byte(s,0x66);xj_byte(s,0x0f);xj_byte(s,op);let host_modrm=0xc1;if op==0x73 {host_modrm=0xd8;}xj_byte(s,host_modrm);if op==0x70 || op==0x73 {xj_byte(s,immediate);}
    if op==0xd7 {xj_store(s,0,reg*8);}else {xj_xmm(s,0,1184+reg*16,1);}
    xj_xmm(s,0,1728,0);xj_xmm(s,1,1744,0);return 1;
}
// Bit-preserving 128-bit SSE copies use integer host registers. No host FP
// state or MXCSR changes, and no untrusted guest instruction bytes execute.
fn xj_vector_move(s,rex,ip,instruction,op,prefix,last,count) {
    let valid=((op==0x10 || op==0x11 || op==0x28 || op==0x29) && (!prefix || prefix==0x66)) || ((op==0x6f || op==0x7f) && (prefix==0x66 || prefix==0xf3));
    if !valid {return 0;}
    let m=xj_source(s,1);let reg=((m>>3)&7)+(rex&4)*2;let rm=(m&7)+(rex&1)*8;let write=op==0x11 || op==0x29 || op==0x7f;
    xj_sse_guard(s,instruction,last,count);
    if m>=192 {
        let source=rm;let destination=reg;if write {source=reg;destination=rm;}
        xj_load(s,0,148+source*2);xj_load(s,1,149+source*2);
        xj_store(s,0,1184+destination*16);xj_store(s,1,1192+destination*16);return 1;
    }
    if !xj_address(s,m,rex,ip,0) {return 0;}
    if op==0x28 || op==0x29 || prefix==0x66 && (op==0x6f || op==0x7f) {
        xj_byte(s,0xa8);xj_byte(s,15); // test al,15, before any RAM access
        xj_byte(s,0x0f);xj_byte(s,0x84);let aligned=load64(s+16);xj_word(s,0,4);
        xj_finish(s,instruction,last,count);xj_patch(s,aligned,load64(s+16));
    }
    xj_memory_call(s,16,write,instruction,last,count);
    if write {
        xj_load(s,1,148+reg*2);xj_load(s,2,149+reg*2);
        xj_byte(s,0x48);xj_byte(s,0x89);xj_byte(s,0x08);
        xj_byte(s,0x48);xj_byte(s,0x89);xj_byte(s,0x50);xj_byte(s,8);
        xj_after_store(s,ip+load64(s+40),instruction,count+1);
    }else {
        xj_byte(s,0x48);xj_byte(s,0x8b);xj_byte(s,0x08);
        xj_byte(s,0x48);xj_byte(s,0x8b);xj_byte(s,0x50);xj_byte(s,8);
        xj_store(s,1,1184+reg*16);xj_store(s,2,1192+reg*16);
    }return 1;
}
fn xj_stack_address(s,mode,delta) {
    xj_load(s,0,4);if delta {xj_byte(s,0x48);xj_byte(s,0x05);xj_word(s,delta,4);}if mode==32 {xj_byte(s,0x89);xj_byte(s,0xc0);}return 0;
}
fn xj_stack_store(s,mode,delta) {xj_stack_address(s,mode,delta);xj_store(s,0,32);return 0;}
// MOVZX/MOVSX/MOVSXD use the same checked memory helper as ordinary loads.
// Guest arithmetic flags are untouched by these instructions.
fn xj_extend(s,rex,ip,instruction,width,source_width,signed,last,count) {
    let m=xj_source(s,1);let destination=((m>>3)&7)+(rex&4)*2;let rm=(m&7)+(rex&1)*8;let memory=m<192;
    if memory {
        if !xj_address(s,m,rex,ip,0) {return 0;}
        xj_memory_call(s,source_width,0,instruction,last,count);
    }else {
        // Legacy AH/CH/DH/BH require extraction before adding a host REX.W.
        if source_width==1 && !rex && rm>=4 && rm<8 {
            xj_load(s,0,rm-4);xj_byte(s,0x48);xj_byte(s,0xc1);xj_byte(s,0xe8);xj_byte(s,8);
        }else {xj_load(s,0,rm);}
    }
    if source_width==4 {
        if width==8 && signed {xj_byte(s,0x48);xj_byte(s,0x63);}else {xj_byte(s,0x8b);}
    }else {
        if width==8 && signed {xj_byte(s,0x48);}xj_byte(s,0x0f);
        let opcode=0xb6;if source_width==2 {opcode=0xb7;}if signed {opcode=opcode+8;}xj_byte(s,opcode);
    }
    let modrm=0xc0;if memory {modrm=0;}xj_byte(s,modrm);xj_store(s,0,destination*8);return 1;
}
fn xj_patch(s,at,target) {let value=target-at-4;let i=0;while i<4 {store8(load64(s+8)+at+i,value>>(i*8));i=i+1;}return 0;}
fn xj_host_register(guest) {if guest<3 {return guest;}if guest==3 {return 6;}return guest+4;}
fn xj_native_prefix(s,width,r,b) {let rex=0x40;if width==8 {rex=rex|8;}if r>=8 {rex=rex|4;}if b>=8 {rex=rex|1;}if rex!=0x40 {xj_byte(s,rex);}return 0;}
// A register-only self-loop keeps guest registers and arithmetic flags on the
// host CPU across iterations. Its native counter bounds execution by fuel.
// No guest memory, faults, I/O, mode changes or interrupts occur inside it.
fn xj_loop(s,record,ip,mode) {
    store64(s+16,0);store64(s+40,0);store64(s+48,0);
    // Preserve SysV callee-saved loop counter, iteration count and next IP.
    xj_byte(s,0x41);xj_byte(s,0x54);xj_byte(s,0x41);xj_byte(s,0x55);xj_byte(s,0x41);xj_byte(s,0x56);
    xj_load(s,0,96);xj_byte(s,0x48);xj_byte(s,0x2b);xj_byte(s,0x87);xj_word(s,312,4);
    xj_byte(s,0x31);xj_byte(s,0xd2);xj_byte(s,0xb9);let divisor=load64(s+16);xj_word(s,1,4);
    xj_byte(s,0x48);xj_byte(s,0xf7);xj_byte(s,0xf1);xj_byte(s,0x49);xj_byte(s,0x89);xj_byte(s,0xc4);
    xj_byte(s,0x45);xj_byte(s,0x31);xj_byte(s,0xed);
    xj_load(s,0,17);xj_byte(s,0x48);xj_byte(s,0x25);xj_word(s,0x8d5,4);xj_byte(s,0x48);xj_byte(s,0x83);xj_byte(s,0xc8);xj_byte(s,2);xj_byte(s,0x50);xj_byte(s,0x9d);
    let reg=0;while reg<8 {xj_load(s,xj_host_register(reg),reg);reg=reg+1;}
    let body=load64(s+16);let count=0;let condition=-2;let last=ip;let after=ip;let saw_flags=0;let clobber_flags=0;
    while count<32 && condition==-2 && !load64(s+48) {
        let start=load64(s+40);let op=xj_source(s,1);let rex=0;let width=4;
        if mode==64 && op>=0x40 && op<=0x4f {rex=op;op=xj_source(s,1);if rex&8 {width=8;}}
        let supported=1;
        if op==0x90 && !(rex&1) {}
        else if op>=0xb8 && op<=0xbf && !(rex&1) {let host=xj_host_register(op-0xb8);let value=xj_source(s,width);xj_native_prefix(s,width,0,host);xj_byte(s,0xb8+(host&7));xj_word(s,value,width);}
        else if op==0x89 || op==0x8b || op==0x85 || op==0x81 || op==0x83 || op==0xc7 || (op<=0x3b && ((op&7)==1 || (op&7)==3)) {
            let m=xj_source(s,1);if m<192 || (rex&5) {supported=0;}
            else {let rm=xj_host_register(m&7);let group=(m>>3)&7;let r=xj_host_register(group);
                let arithmetic=op!=0x89 && op!=0x8b && op!=0xc7;
                if arithmetic && !saw_flags {let operation=(op>>3)&7;if op==0x81 || op==0x83 {operation=group;}clobber_flags=operation!=2 && operation!=3;saw_flags=1;}
                if op==0x81 || op==0x83 || op==0xc7 {if op==0xc7 && group!=0 {supported=0;}xj_native_prefix(s,width,0,rm);xj_byte(s,op);xj_byte(s,0xc0+group*8+(rm&7));let size=4;if op==0x83 {size=1;}xj_word(s,xj_source(s,size),size);}
                else {xj_native_prefix(s,width,r,rm);xj_byte(s,op);xj_byte(s,0xc0+(r&7)*8+(rm&7));}
            }
        }
        else if (op>=0x70 && op<=0x7f) || op==0x0f || op==0xeb || op==0xe9 {
            let size=4;let cc=-1;if op>=0x70 && op<=0x7f {size=1;cc=op&15;}else if op==0xeb {size=1;}else if op==0x0f {let second=xj_source(s,1);if second>=0x80 && second<=0x8f {cc=second&15;}else {supported=0;}}
            if supported {let relative=x86_signed(xj_source(s,size),size);after=ip+load64(s+40);let target=after+relative;if mode==32 {target=target&0xffffffff;}if target!=ip {supported=0;}else {condition=cc;}}
        }
        else {supported=0;}
        if !supported || load64(s+40)>128 {return 0;}last=ip+start;count=count+1;
    }
    if condition==-2 || load64(s+48) || !count {return 0;}
    let i=0;while i<4 {store8(load64(s+8)+divisor+i,count>>(i*8));i=i+1;}
    // LEA increments the iteration count without changing guest arithmetic flags.
    xj_byte(s,0x4d);xj_byte(s,0x8d);xj_byte(s,0x6d);xj_byte(s,1);
    let untaken=0;if condition>=0 {xj_byte(s,0x0f);xj_byte(s,0x80+(condition^1));untaken=load64(s+16);xj_word(s,0,4);}
    xj_byte(s,0x9c);xj_byte(s,0x49);xj_byte(s,0xff);xj_byte(s,0xcc); // pushfq; dec r12
    xj_byte(s,0x0f);xj_byte(s,0x84);let exhausted=load64(s+16);xj_word(s,0,4);
    if clobber_flags {xj_byte(s,0x48);xj_byte(s,0x8d);xj_byte(s,0x64);xj_byte(s,0x24);xj_byte(s,8);}else {xj_byte(s,0x9d);}
    xj_byte(s,0xe9);let back=load64(s+16);xj_word(s,body-back-4,4);
    xj_patch(s,exhausted,load64(s+16));xj_byte(s,0x9d);
    xj_byte(s,0x49);xj_byte(s,0xbe);xj_word(s,ip,8);
    xj_byte(s,0xe9);let finish=load64(s+16);xj_word(s,0,4);
    if untaken {xj_patch(s,untaken,load64(s+16));}
    xj_byte(s,0x49);xj_byte(s,0xbe);xj_word(s,after,8);xj_patch(s,finish,load64(s+16));
    reg=0;while reg<8 {xj_store(s,xj_host_register(reg),reg*8);reg=reg+1;}
    xj_store(s,14,128);xj_flags(s);xj_immediate(s,0,last);xj_store(s,0,200);
    xj_byte(s,0x49);xj_byte(s,0x69);xj_byte(s,0xc5);xj_word(s,count,4); // rax=r13*count
    xj_byte(s,0x48);xj_byte(s,0x01);xj_byte(s,0x87);xj_word(s,312,4);
    xj_byte(s,0x48);xj_byte(s,0x01);xj_byte(s,0x87);xj_word(s,1008,4);
    xj_byte(s,0x4c);xj_byte(s,0x01);xj_byte(s,0xaf);xj_word(s,1016,4);
    xj_byte(s,0x41);xj_byte(s,0x5e);xj_byte(s,0x41);xj_byte(s,0x5d);xj_byte(s,0x41);xj_byte(s,0x5c);xj_byte(s,0xb8);xj_word(s,1,4);xj_byte(s,0xc3);
    if syscall(10,load64(s+8),4096,5,0,0,0)!=0 {return 0;}
    store64(record+24,load64(s+40));store64(record+32,count);store64(record+40,load64(s+16));i=0;while i<load64(s+40) {store8(record+64+i,load8(load64(s+24)+i));i=i+1;}return 1;
}
fn xj_compile(s,record,ip,mode) {
    let output=load64(s+8);if syscall(10,output,4096,3,0,0,0)!=0 {return 0;}
    if xj_loop(s,record,ip,mode) {return 1;}
    store64(s+16,0);store64(s+40,0);store64(s+48,0);store64(s+56,mode);
    let count=0;let last=ip;let next=ip;let end=0;let dynamic=0;
    while count<32 && load64(s+40)<128 && !end {
        let start=load64(s+40);let emitted=load64(s+16);let op=0x90;if !xj_nop(s,mode) {op=xj_source(s,1);}let rex=0;let repeat=0;let width=4;let operand=0;
        xj_segment=0;if mode==64 && (op==0x64 || op==0x65) {xj_segment=464;if op==0x65 {xj_segment=472;}op=xj_source(s,1);}
        if op==0x66 {operand=1;width=2;op=xj_source(s,1);}
        if mode==64 && op>=0x40 && op<=0x4f {rex=op;op=xj_source(s,1);if rex&8 {width=8;}}
        if op==0xf3 {repeat=1;rex=0;width=4;if operand {width=2;}op=xj_source(s,1);if mode==64 && op>=0x40 && op<=0x4f {rex=op;op=xj_source(s,1);if rex&8 {width=8;}}}
        let supported=1;
        if op==0x0f && (operand || repeat) {
            let second=xj_source(s,1);let prefix=0x66;if repeat {prefix=0xf3;}
            if operand && repeat {supported=0;}
            else if repeat && second==0x1e {supported=xj_source(s,1)==0xfa;}
            else if prefix==0x66 && (second==0xef || second==0x74 || second==0xd7 || second==0x70 || second==0xd4 || second==0x73) {supported=xj_vector_register(s,rex,ip+start,second,prefix,last,count);}
            else {supported=xj_vector_move(s,rex,ip,ip+start,second,prefix,last,count);}
        }
        else if operand && op!=0x89 && op!=0x8b {supported=0;}
        else if operand && width==2 {supported=xj_move16(s,rex,ip,ip+start,op,last,count);}
        else if op==0x88 || op==0x8a {supported=xj_move8(s,rex,ip,ip+start,op,last,count);}
        else if op==0x38 || op==0x3a || op==0x3c || op==0x80 || op==0x84 || op==0xa8 {supported=xj_compare8(s,rex,ip,ip+start,op,last,count);}
        else if repeat {if op!=0x0f || xj_source(s,1)!=0x1e || xj_source(s,1)!=0xfa {supported=0;}}
        else if op==0x90 && !(rex&1) {}
        else if op==0xf8 || op==0xf9 || op==0xf5 {
            // Modify only the guest carry bit; never import host flag state.
            xj_load(s,0,17);xj_byte(s,0x48);xj_byte(s,0x83);
            let operation=0xe0;let value=254;if op==0xf9 {operation=0xc8;value=1;}if op==0xf5 {operation=0xf0;value=1;}
            xj_byte(s,operation);xj_byte(s,value);xj_store(s,0,136);
        }
        else if op==0x98 {xj_load(s,0,0);if width==8 {xj_byte(s,0x48);}xj_byte(s,0x98);xj_store(s,0,0);}
        else if op>=0xb8 && op<=0xbf {
            let value=xj_source(s,width);xj_immediate(s,0,value);xj_store(s,0,(op-0xb8+(rex&1)*8)*8);
        }
        else if (op>=0x50 && op<=0x5f) || op==0x68 || op==0x6a || op==0xe8 || op==0xc3 || op==0xc2 {
            let size=mode/8;let push=(op>=0x50 && op<=0x57) || op==0x68 || op==0x6a || op==0xe8;
            let value=0;let extra=0;
            if op==0x68 {value=x86_signed(xj_source(s,4),4);}else if op==0x6a {value=x86_signed(xj_source(s,1),1);}
            else if op==0xe8 {let relative=x86_signed(xj_source(s,4),4);value=ip+load64(s+40);next=value+relative;if mode==32 {next=next&0xffffffff;}end=1;}
            else if op==0xc2 {extra=xj_source(s,2);}
            let delta=0;if push {delta=-size;}
            xj_stack_address(s,mode,delta);xj_memory_call(s,size,push,ip+start,last,count);
            if push {
                if op>=0x50 && op<=0x57 {xj_load(s,1,op-0x50+(rex&1)*8);}else {xj_immediate(s,1,value);}
                if size==8 {xj_byte(s,0x48);}xj_byte(s,0x89);xj_byte(s,0x08);
                xj_stack_store(s,mode,-size);
                if !end {let after=ip+load64(s+40);if mode==32 {after=after&0xffffffff;}xj_after_store(s,after,ip+start,count+1);}
            }else {
                if size==8 {xj_byte(s,0x48);}xj_byte(s,0x8b);xj_byte(s,0x08); // RCX=value
                xj_stack_store(s,mode,size+extra);
                if op==0xc3 || op==0xc2 {xj_store(s,1,128);dynamic=1;end=1;}
                else {xj_store(s,1,(op-0x58+(rex&1)*8)*8);}
            }
        }
        else if op==0xff {
            let m=xj_source(s,1);let group=(m>>3)&7;
            if m<192 {supported=0;}
            else if group<2 {
                let destination=(m&7)+(rex&1)*8;xj_load(s,0,destination);
                if width==8 {xj_byte(s,0x48);}xj_byte(s,0xff);xj_byte(s,0xc0+group*8);
                // INC/DEC change arithmetic flags except CF.
                xj_flags_mask(s,0x8d4);xj_store(s,0,destination*8);
            }
            else if group!=2 && group!=4 {supported=0;}
            else {
                let size=mode/8;let target=(m&7)+(rex&1)*8;
                if group==2 {
                    xj_stack_address(s,mode,-size);xj_memory_call(s,size,1,ip+start,last,count);
                    xj_immediate(s,1,ip+load64(s+40));if size==8 {xj_byte(s,0x48);}xj_byte(s,0x89);xj_byte(s,0x08);
                    // A CALL through RSP uses its original value as the target.
                    xj_load(s,1,target);if size==4 {xj_byte(s,0x89);xj_byte(s,0xc9);}xj_store(s,1,128);
                    xj_stack_store(s,mode,-size);
                }else {xj_load(s,0,target);if size==4 {xj_byte(s,0x89);xj_byte(s,0xc0);}xj_store(s,0,128);}
                dynamic=1;end=1;
            }
        }
        else if op==0x89 || op==0x8b || op==0xc7 || op==0x8d || op==0x85 || op==0x81 || op==0x83 || (op<=0x3b && ((op&7)==1 || (op&7)==3)) {
            let m=xj_source(s,1);let r=((m>>3)&7)+(rex&4)*2;let rm=(m&7)+(rex&1)*8;
            if m<192 {
                let trailing=0;if op==0xc7 || op==0x81 {trailing=4;}else if op==0x83 {trailing=1;}
                if op==0x8d {xj_segment=0;} // LEA calculates an offset, not a linear address.
                supported=xj_address(s,m,rex,ip,trailing);
                if op==0x8d {if width==4 {xj_byte(s,0x89);xj_byte(s,0xc0);}xj_store(s,0,r*8);}
                else {
                    let immediate=0;if trailing {immediate=x86_signed(xj_source(s,trailing),trailing);}
                    let operation=(op>>3)&7;let destination_memory=!(op&2);
                    if op==0x81 || op==0x83 {operation=(m>>3)&7;destination_memory=1;}
                    let write=destination_memory && operation!=7 && op!=0x85 && op!=0x8b;
                    if op==0x89 || op==0xc7 {write=1;}
                    if op==0xc7 && ((m>>3)&7)!=0 {supported=0;}
                    xj_memory_call(s,width,write,ip+start,last,count);
                    if op==0x89 || op==0xc7 {
                        if op==0x89 {xj_load(s,1,r);}else {xj_immediate(s,1,immediate);}
                        if width==8 {xj_byte(s,0x48);}xj_byte(s,0x89);xj_byte(s,0x08);
                    }
                    else if op==0x8b {if width==8 {xj_byte(s,0x48);}xj_byte(s,0x8b);xj_byte(s,0x00);xj_store(s,0,r*8);}
                    else {
                        // R9 preserves the validated host pointer across ALU/flags.
                        xj_byte(s,0x49);xj_byte(s,0x89);xj_byte(s,0xc1);
                        if width==8 {xj_byte(s,0x48);}xj_byte(s,0x8b);xj_byte(s,0x00);
                        if destination_memory || op==0x85 {if trailing {xj_immediate(s,1,immediate);}else {xj_load(s,1,r);}}
                        else {xj_byte(s,0x48);xj_byte(s,0x89);xj_byte(s,0xc1);xj_load(s,0,r);}
                        xj_arithmetic(s,operation,width,op==0x85);
                        if write {if width==8 {xj_byte(s,0x49);}else {xj_byte(s,0x41);}xj_byte(s,0x89);xj_byte(s,0x01);}
                        else if !destination_memory && operation!=7 && op!=0x85 {xj_store(s,0,r*8);}
                    }
                    if write {let after=ip+load64(s+40);if mode==32 {after=after&0xffffffff;}xj_after_store(s,after,ip+start,count+1);}
                }
            }
            else if op==0x8d {supported=0;}
            else if op==0x89 || op==0x8b {let dest=rm;let src=r;if op==0x8b {dest=r;src=rm;}xj_load(s,0,src);if width==4 {xj_byte(s,0x89);xj_byte(s,0xc0);}xj_store(s,0,dest*8);}
            else if op==0xc7 {if ((m>>3)&7)!=0 {supported=0;}else {let value=xj_source(s,4);if width==8 {value=x86_signed(value,4);}xj_immediate(s,0,value);xj_store(s,0,rm*8);}}
            else if op==0x81 || op==0x83 {let size=4;if op==0x83 {size=1;}let value=x86_signed(xj_source(s,size),size);xj_alu(s,(m>>3)&7,width,rm,value,1,0);}
            else if op==0x85 {xj_alu(s,4,width,rm,r,0,1);}
            else {let dest=rm;let src=r;if op&2 {dest=r;src=rm;}xj_alu(s,(op>>3)&7,width,dest,src,0,0);}
        }
        else if op<=0x3d && (op&7)==5 {
            // Accumulator immediates use imm32 even with REX.W. Reuse the
            // checked register ALU path, including carry and CMP preservation.
            let immediate=x86_signed(xj_source(s,4),4);
            xj_alu(s,(op>>3)&7,width,0,immediate,1,0);
        }
        else if op==0xa9 {supported=xj_test_immediate(s,rex,ip,ip+start,width,-1,last,count);}
        else if op==0xf6 {
            let m=xj_source(s,1);if ((m>>3)&7)!=0 {supported=0;}
            else {supported=xj_test_immediate(s,rex,ip,ip+start,1,m,last,count);}
        }
        else if op==0xf7 {
            let m=xj_source(s,1);let group=(m>>3)&7;
            if group==0 {supported=xj_test_immediate(s,rex,ip,ip+start,width,m,last,count);}
            else if m>=192 && (group==4 || group==5) {
                // Load both inputs before replacing RAX/RDX, including aliases.
                // MUL defines only CF/OF; preserve all other guest flag bits.
                xj_load(s,0,0);xj_load(s,1,(m&7)+(rex&1)*8);
                if width==8 {xj_byte(s,0x48);}xj_byte(s,0xf7);xj_byte(s,0xc1+group*8);
                // Flag merging uses host RDX, so save the product high half first.
                xj_store(s,2,16);xj_store(s,2,344);xj_store(s,0,0);xj_flags_mask(s,0x801);
            }
            else if m<192 || (group!=2 && group!=3) {supported=0;}
            else {let destination=(m&7)+(rex&1)*8;xj_load(s,0,destination);
                if width==8 {xj_byte(s,0x48);}xj_byte(s,0xf7);xj_byte(s,0xc0+group*8);
                if group==3 {xj_flags(s);}xj_store(s,0,destination*8);
            }
        }
        else if op==0xc1 || op==0xd1 || op==0xd3 {
            let m=xj_source(s,1);let group=(m>>3)&7;
            if m<192 || group==6 {supported=0;}
            else {supported=xj_shift(s,op,width,group,(m&7)+(rex&1)*8);}
        }
        else if op==0x63 && mode==64 {
            supported=xj_extend(s,rex,ip,ip+start,width,4,1,last,count);
        }
        else if op==0xe9 || op==0xeb || (op>=0x70 && op<=0x7f) || op==0x0f {
            let condition=-1;let size=4;let extension=0;
            if op==0xeb {size=1;}else if op>=0x70 && op<=0x7f {condition=op&15;size=1;}
            else if op==0x0f {let second=xj_source(s,1);if second>=0x80 && second<=0x8f {condition=second&15;}
                else if second==0x10 || second==0x11 || second==0x28 || second==0x29 {extension=1;supported=xj_vector_move(s,rex,ip,ip+start,second,0,last,count);}
                else if second==0x31 {extension=1;supported=xj_rdtsc(s,ip+start,last,count);}
                else if second>=0x90 && second<=0x9f {extension=1;supported=xj_setcc(s,rex,ip,ip+start,second&15,last,count);}
                else if second>=0xc8 && second<=0xcf {
                    extension=1;let destination=second-0xc8+(rex&1)*8;
                    xj_load(s,0,destination);if width==8 {xj_byte(s,0x48);}
                    xj_byte(s,0x0f);xj_byte(s,0xc8);xj_store(s,0,destination*8);
                }
                else if second>=0x40 && second<=0x4f {extension=1;supported=xj_cmov(s,rex,ip,ip+start,width,second&15,last,count);}
                else if second==0xbc || second==0xbd {extension=1;supported=xj_bitscan(s,rex,ip,ip+start,width,second,last,count);}
                else if second==0xb6 || second==0xb7 || second==0xbe || second==0xbf {
                    extension=1;let source_width=1;if second&1 {source_width=2;}supported=xj_extend(s,rex,ip,ip+start,width,source_width,(second&8)!=0,last,count);
                }else {supported=0;}}
            if supported && !extension {
                let displacement=x86_signed(xj_source(s,size),size);let after=ip+load64(s+40);next=after+displacement;
                if mode==32 {next=next&0xffffffff;}
                if condition>=0 {
                    // Restore only arithmetic host flags for CMOVcc; never guest
                    // DF, TF, AC, IOPL or other host process control flags.
                    xj_load(s,2,17);xj_byte(s,0x48);xj_byte(s,0x81);xj_byte(s,0xe2);xj_word(s,0x8d5,4);xj_byte(s,0x48);xj_byte(s,0x83);xj_byte(s,0xca);xj_byte(s,2);
                    xj_immediate(s,0,after);xj_immediate(s,1,next);xj_byte(s,0x52);xj_byte(s,0x9d);
                    xj_byte(s,0x48);xj_byte(s,0x0f);xj_byte(s,0x40+condition);xj_byte(s,0xc1);xj_store(s,0,128);dynamic=1;
                }end=1;
            }
        }
        else {supported=0;}
        if !supported || load64(s+48) || load64(s+16)>3800 || load64(s+40)-start>15 || load64(s+40)>128 {store64(s+40,start);store64(s+16,emitted);next=ip+start;if mode==32 {next=next&0xffffffff;}dynamic=0;end=1;}
        else {last=ip+start;count=count+1;if !end {next=ip+load64(s+40);if mode==32 {next=next&0xffffffff;}}}
    }
    if !count {return 0;}
    // Rollback may have hit the emitter limit. Reserve space for a complete
    // final state/count/dispatch tail; never seal a truncated native block.
    store64(s+48,0);
    if !dynamic {xj_immediate(s,0,next);xj_store(s,0,128);}
    xj_immediate(s,0,last);xj_store(s,0,200);
    xj_count(s,count);
    xj_byte(s,0xe9);xj_word(s,xj_helper(s)+768-(load64(s+8)+load64(s+16)+4),4);
    let size=load64(s+16);if load64(s+48) || size>4096 {return 0;}
    if syscall(10,output,4096,5,0,0,0)!=0 {return 0;}
    store64(record+24,load64(s+40));store64(record+32,count);store64(record+40,size);
    let i=0;while i<load64(s+40) {store8(record+64+i,load8(load64(s+24)+i));i=i+1;}
    return 1;
}
fn xj_run(c,fuel) {
    // Native memory walks enforce CPL3 U/S and write permissions at every
    // level. Privilege transitions invalidate the chained-code generation.
    let cpl=load64(c+376)&3;if cpl!=0 && cpl!=3 {return 0;}
    let mode=load64(c+144);if (mode!=32 && mode!=64) || fuel-load64(c+312)<1 {return 0;}
    store64(c+768,fuel);
    let s=xj_state(c);if !s {return 0;}let ip=load64(c+128);let key=ip^((ip>>17)&0x00007fffffffffff);let slot=((key*0x9e3779b97f4a7c15)>>32)&32767;let record=s+64+slot*256;
    let generation=load64(c+400);let status=load64(record+56);let same=load64(record)==ip && load64(record+8)==mode;
    if !same {status=0;}
    if !status || load64(record+16)!=generation {
        // Speculative decode must never deliver a guest fault. If current code
        // cannot be read, let the interpreter fetch it with its checkpoint.
        let address=load64(c+352);let error=load64(c+360);let physical=x86_translate(c,ip,0);
        if physical<0 || !x86_phys(c,physical,1) {store64(c+288,0);store64(c+392,0);store64(c+352,address);store64(c+360,error);x86_message=0;x86_error=0;return 0;}
        x86_watch(c,physical);let source=load64(c+296)+physical;let available=4096-(ip&4095);let remaining=load64(c+304)-physical;if available>remaining {available=remaining;}if available>128 {available=128;}
        if status {
            let length=load64(record+24);let i=0;if available<length {status=0;}else {if length>=8 {
                while i+8<=length && status {if load64(source+i)!=load64(record+64+i) {status=0;}i=i+8;}
                if status && i<length && load64(source+length-8)!=load64(record+64+length-8) {status=0;}
            }else {while i<length && status {if load8(source+i)!=load8(record+64+i) {status=0;}i=i+1;}}}
        }
        if !status {
            store64(record,ip);store64(record+8,mode);store64(record+48,0);let length=available;if length>15 {length=15;}store64(record+24,length);let i=0;while i<length {store8(record+64+i,load8(source+i));i=i+1;}status=1;
        }
        store64(record+16,generation);store64(record+56,status);
        store64(s+24,source);store64(s+32,available);
    }
    if status==2 {return 0;}
    if status==1 {
        let visits=load64(record+48)+1;store64(record+48,visits);if visits<x86_jit_threshold {return 0;}
        // Re-read the mapping even when generation matched: the emitter's
        // source window is shared scratch, not a persistent record pointer.
        let physical=x86_translate(c,ip,0);if physical<0 {return 0;}
        let available=4096-(ip&4095);let remaining=load64(c+304)-physical;if available>remaining {available=remaining;}if available>128 {available=128;}
        store64(s+24,load64(c+296)+physical);store64(s+32,available);store64(s+8,load64(s)+slot*4096);
        store64(c+448,load64(c+448)+1);if !xj_compile(s,record,ip,mode) {store64(record+56,2);return 0;}store64(record+56,3);
    }
    let count=load64(record+32);if count>fuel-load64(c+312) {return 0;}
    store64(c+424,1);let result=ffi_call(load64(s)+slot*4096,c,0,0,0,0,0);store64(c+424,0);
    return result;
}

// Execute only a present, writable, single-page chunk. Faults and the final
// cross-page element use the interpreter, preserving precise REP progress.
fn xj_rep_batch(c,n,addr,op,batch) {
    if addr!=load64(c+144)/8 {return 0;}let state=xj_state(c);if !state {return 0;}
    let backward=(load64(c+136)&1024)!=0;let destination=x86_reg(c,7,addr);let source=x86_reg(c,6,addr)+load64(c+456);let copy=op==0xa4 || op==0xa5;
    if (destination&4095)+n>4096 || (copy && (source&4095)+n>4096) {return 0;}
    let room=(4096-(destination&4095))/n;if backward {room=(destination&4095)/n+1;}if batch>room {batch=room;}
    if copy {room=(4096-(source&4095))/n;if backward {room=(source&4095)/n+1;}if batch>room {batch=room;}}
    if batch<8 {return 0;}let from=0;let physical=0;let low=0;
    if copy {physical=x86_translate(c,source,0);if physical<0 {return 0;}low=physical;if backward {low=low-(batch-1)*n;}if !x86_phys(c,low,batch*n) {return 0;}from=load64(c+296)+physical;}
    physical=x86_translate(c,destination,1);if physical<0 {return 0;}low=physical;if backward {low=low-(batch-1)*n;}if !x86_phys(c,low,batch*n) {return 0;}
    let to=load64(c+296)+physical;let delta=n;if backward {delta=-n;}
    ffi_call(xj_helper(state)+1536,to,from,batch,n,x86_reg(c,0,n),delta);
    x86_invalidate_write(c,physical);x86_setreg(c,7,addr,destination+delta*batch);if copy {x86_setreg(c,6,addr,x86_reg(c,6,addr)+delta*batch);}x86_setreg(c,1,addr,x86_reg(c,1,addr)-batch);
    store64(c+1008,load64(c+1008)+batch);store64(c+1016,load64(c+1016)+1);return batch;
}
