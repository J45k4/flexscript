// Direct word IR -> RV32IMC instructions -> ESP32-C3/C6 ROM image or ELF32.
// Private stack ABI: a0:a1 value, s0 frame, ra return, eight-byte word args.
// No assembler/linker, interpreter, libc, ESP-IDF runtime or RTOS in firmware.
global rv_target=0;
global rv_elf=0;
global rv_flash=0;
global rv_radio=0;
global rv_compressed=0;
global rv_iram_size=0;
global rv_iram_functions=0;
global rv_flash_init=-1;
global rv_code_base=0x40380000;
global rv_data_base=0x3fca0000;
global rv_stack_floor=0x3fcc0000;
global rv_stack_top=0x3fcc8000;
global rv_ir=0;
global rv_ir_size=0;
global rv_seen=0;
global rv_entries=0;
global rv_map=0;
global rv_jumps=0;
global rv_fixups=0;
global rv_fixup_count=0;
global rv_locals=0;
global rv_platform_entry=-1;
global rv_c_thunks=0;
global rv_helpers=0;
global rv_irq_dispatch=-1;
global rv_irq_tail=-1;
global rv_vector_ref=-1;
fn rv_code_capacity() {if rv_radio {return 65536;}return 131072;}
fn rv_data_capacity() {if rv_radio {return 32768;}return 65536;}
fn rv_heap_begin() {return rv_data_base+rv_data_capacity();}
fn rv_heap_end() {if rv_radio {return rv_heap_begin()+16384;}return rv_heap_begin()+32768;}
fn rv_address(offset) {if rv_flash && offset>=0x50000 {return 0x42000000+offset-0x50000;}return rv_code_base+offset;}
fn rv_ins(word) {let bound=rv_code_capacity();if rv_flash && output_size>=0x50000 {bound=0x350000;}if output_size+4>bound {if bound<=131072 {if rv_radio {fail("RISC-V radio machine code exceeds 64 KiB SRAM region");}fail("RISC-V machine code exceeds 128 KiB SRAM region");}fail("RISC-V flash code exceeds 3 MiB");}emit32(word);return 0;}
fn rv_ins16(word) {let bound=rv_code_capacity();if rv_flash && output_size>=0x50000 {bound=0x350000;}if output_size+2>bound {if bound<=131072 {if rv_radio {fail("RISC-V radio machine code exceeds 64 KiB SRAM region");}fail("RISC-V machine code exceeds 128 KiB SRAM region");}fail("RISC-V flash code exceeds 3 MiB");}emit(word&255);emit((word>>8)&255);rv_compressed=1;return 0;}
fn rv_r(f3,f7,d,s,t) {return rv_ins(0x33|(d<<7)|(f3<<12)|(s<<15)|(t<<20)|(f7<<25));}
fn rv_add(d,s,t) {if d==s && d && t {return rv_ins16(0x9002|(d<<7)|(t<<2));}return rv_r(0,0,d,s,t);}
fn rv_i(op,f3,d,s,n) {if n< -2048 || n>2047 {fail("RISC-V immediate out of range");}return rv_ins(op|(d<<7)|(f3<<12)|(s<<15)|((n&4095)<<20));}
fn rv_addi(d,s,n) {if d==s && d && n && n>= -32 && n<=31 {return rv_ins16(1|(d<<7)|((n&32)<<7)|((n&31)<<2));}return rv_i(0x13,0,d,s,n);}
fn rv_mov(d,s) {if d && s {return rv_ins16(0x8002|(d<<7)|(s<<2));}return rv_addi(d,s,0);}
fn rv_const(d,n) {n=(n<<32)>>32;let lo=((n+2048)&4095)-2048;rv_ins(0x37|(d<<7)|(((n-lo)>>12&1048575)<<12));rv_i(0x13,0,d,d,lo);return 0;}
fn rv_imm(d,n) {n=(n<<32)>>32;if d && n>= -32 && n<=31 {return rv_ins16(0x4001|(d<<7)|((n&32)<<7)|((n&31)<<2));}if n>= -2048 && n<=2047 {return rv_addi(d,0,n);}return rv_const(d,n);}
fn rv_lw(d,s,n) {
 if n>=0 && n%4==0 {if s==2 && d && n<=252 {return rv_ins16(0x4002|(d<<7)|((n&32)<<7)|((n&28)<<2)|((n&192)>>4));}if d>=8 && d<=15 && s>=8 && s<=15 && n<=124 {return rv_ins16(0x4000|((n&56)<<7)|((s-8)<<7)|((n&4)<<4)|((n&64)>>1)|((d-8)<<2));}}
 return rv_i(3,2,d,s,n);
}
fn rv_lbu(d,s,n) {return rv_i(3,4,d,s,n);}
fn rv_store(f3,t,s,n) {if n< -2048 || n>2047 {fail("RISC-V store offset out of range");}return rv_ins(0x23|((n&31)<<7)|(f3<<12)|(s<<15)|(t<<20)|(((n>>5)&127)<<25));}
fn rv_sw(t,s,n) {
 if n>=0 && n%4==0 {if s==2 && n<=252 {return rv_ins16(0xc002|((n&60)<<7)|((n&192)<<1)|(t<<2));}if t>=8 && t<=15 && s>=8 && s<=15 && n<=124 {return rv_ins16(0xc000|((n&56)<<7)|((s-8)<<7)|((n&4)<<4)|((n&64)>>1)|((t-8)<<2));}}
 return rv_store(2,t,s,n);
}
fn rv_shift_i(f3,d,s,n) {if n<0 || n>31 {fail("RISC-V shift out of range");}return rv_i(0x13,f3,d,s,n);}
fn rv_slli(d,s,n) {return rv_shift_i(1,d,s,n);}
fn rv_srli(d,s,n) {return rv_shift_i(5,d,s,n);}
fn rv_srai(d,s,n) {return rv_i(0x13,5,d,s,1024+n);}
fn rv_csr(f3,d,csr,s) {return rv_ins(0x73|(d<<7)|(f3<<12)|(s<<15)|(csr<<20));}
fn rv_branch(f3,s,t) {let at=output_size;rv_ins(0x63|(f3<<12)|(s<<15)|(t<<20));return at;}
fn rv_patch_branch(at,to) {
    let n=to-at;if n%2 || n< -4096 || n>4094 {fail("RISC-V conditional branch out of range");}
    let old=output_size;let word=load8(output+at)|(load8(output+at+1)<<8)|(load8(output+at+2)<<16)|(load8(output+at+3)<<24);
    output_size=at;rv_ins((word&0x01fff07f)|(((n>>12)&1)<<31)|(((n>>5)&63)<<25)|(((n>>1)&15)<<8)|(((n>>11)&1)<<7));output_size=old;return 0;
}
fn rv_jump() {let at=output_size;rv_ins(0x17|(31<<7));rv_i(0x67,0,0,31,0);return at;}
fn rv_patch_transfer(at,to,link) {
    let n=rv_address(to)-rv_address(at);let lo=((n+2048)&4095)-2048;let old=output_size;output_size=at;
    rv_ins(0x17|(31<<7)|((((n-lo)>>12)&1048575)<<12));rv_i(0x67,0,link,31,lo);output_size=old;return 0;
}
fn rv_j(to) {let at=rv_jump();return rv_patch_transfer(at,to,0);}
fn rv_guard(f3,s,t) {let okay=rv_branch(f3,s,t);rv_j(0);rv_patch_branch(okay,output_size);return 0;}
fn rv_stack_check() {rv_imm(5,rv_data_base+20);rv_lw(6,5,0);rv_guard(7,2,6);return 0;}
fn rv_push() {rv_addi(2,2,-8);rv_stack_check();rv_sw(10,2,0);rv_sw(11,2,4);return 0;}
fn rv_pop(lo,hi) {rv_lw(lo,2,0);rv_lw(hi,2,4);rv_addi(2,2,8);return 0;}
// Fold frame addressing into the two word accesses when both offsets fit.
// Larger frames/parameter lists retain the full-width address calculation.
fn rv_frame_pair(offset,storing) {
 let base=8;if offset< -2048 || offset>2043 {rv_imm(5,offset);rv_add(5,8,5);base=5;offset=0;}
 if storing {rv_sw(10,base,offset);rv_sw(11,base,offset+4);}else {rv_lw(10,base,offset);rv_lw(11,base,offset+4);}return 0;
}
fn rv_epilogue(frame) {if frame {if frame<=2047 {rv_addi(2,8,frame);}else {rv_imm(5,frame);rv_add(2,8,5);}}else {rv_mov(2,8);}rv_lw(1,2,0);rv_lw(8,2,4);rv_addi(2,2,16);rv_ins16(0x8082);return 0;}
fn rv_neg(lo,hi) {rv_r(0,32,5,0,lo);rv_r(3,0,6,0,lo);rv_r(0,32,hi,0,hi);rv_r(0,32,hi,hi,6);rv_mov(lo,5);return 0;}
fn rv_bool(invert) {rv_r(6,0,5,10,11);rv_r(3,0,10,0,5);if invert {rv_i(0x13,4,10,10,1);}rv_imm(11,0);return 0;}
fn rv_compare(op) {
    if op==259 || op==260 {rv_r(4,0,5,12,10);rv_r(4,0,6,13,11);rv_r(6,0,5,5,6);rv_r(3,0,10,0,5);if op==259 {rv_i(0x13,4,10,10,1);}rv_imm(11,0);return 0;}
    if op==62 || op==261 {rv_mov(5,12);rv_mov(12,10);rv_mov(10,5);rv_mov(5,13);rv_mov(13,11);rv_mov(11,5);}
    rv_r(2,0,5,13,11);let different=rv_branch(1,13,11);rv_r(3,0,5,12,10);rv_patch_branch(different,output_size);
    rv_mov(10,5);if op==261 || op==262 {rv_i(0x13,4,10,10,1);}rv_imm(11,0);return 0;
}
fn rv_shift(op) {
    rv_i(0x13,7,6,10,63);rv_imm(7,32);let large=rv_branch(7,6,7);let zero=rv_branch(0,6,0);
    rv_r(0,32,7,7,6);
    if op==265 {rv_r(1,0,10,12,6);rv_r(1,0,11,13,6);rv_r(5,0,5,12,7);rv_r(6,0,11,11,5);}
    else {rv_r(5,0,10,12,6);rv_r(5,32,11,13,6);rv_r(1,0,5,13,7);rv_r(6,0,10,10,5);}
    let done=rv_jump();rv_patch_branch(zero,output_size);rv_mov(10,12);rv_mov(11,13);let done2=rv_jump();
    rv_patch_branch(large,output_size);rv_addi(6,6,-32);
    if op==265 {rv_r(1,0,11,12,6);rv_imm(10,0);}else {rv_r(5,32,10,13,6);rv_srai(11,13,31);}
    rv_patch_transfer(done,output_size,0);rv_patch_transfer(done2,output_size,0);return 0;
}
fn rv_divide(remainder) {
    rv_r(6,0,5,10,11);rv_guard(1,5,0);
    rv_imm(5,0x80000000);let safe1=rv_branch(1,13,5);let safe2=rv_branch(1,12,0);rv_imm(5,-1);let safe3=rv_branch(1,10,5);rv_guard(1,11,5);
    rv_patch_branch(safe1,output_size);rv_patch_branch(safe2,output_size);rv_patch_branch(safe3,output_size);
    rv_srli(28,13,31);rv_r(4,0,29,13,11);rv_srli(29,29,31);
    let positive=rv_branch(0,28,0);rv_neg(12,13);rv_patch_branch(positive,output_size);
    let den_positive=rv_branch(5,11,0);rv_neg(10,11);rv_patch_branch(den_positive,output_size);
    rv_imm(14,0);rv_imm(15,0);rv_imm(16,0);rv_imm(17,0);rv_imm(30,64);let loop=output_size;
    rv_srli(5,16,31);rv_slli(17,17,1);rv_r(6,0,17,17,5);rv_srli(5,13,31);rv_slli(16,16,1);rv_r(6,0,16,16,5);
    rv_srli(5,12,31);rv_slli(13,13,1);rv_r(6,0,13,13,5);rv_slli(12,12,1);
    rv_srli(5,14,31);rv_slli(15,15,1);rv_r(6,0,15,15,5);rv_slli(14,14,1);
    let skip=rv_branch(6,17,11);let take=rv_branch(6,11,17);let skip2=rv_branch(6,16,10);rv_patch_branch(take,output_size);
    rv_r(3,0,5,16,10);rv_r(0,32,16,16,10);rv_r(0,32,17,17,11);rv_r(0,32,17,17,5);rv_addi(14,14,1);
    rv_patch_branch(skip,output_size);rv_patch_branch(skip2,output_size);rv_addi(30,30,-1);let again=rv_branch(1,30,0);rv_patch_branch(again,loop);
    if remainder {rv_mov(10,16);rv_mov(11,17);}else {rv_mov(10,14);rv_mov(11,15);}
    let sign=29;if remainder {sign=28;}let finish=rv_branch(0,sign,0);rv_neg(10,11);rv_patch_branch(finish,output_size);return 0;
}
fn rv_binary(op) {
    rv_pop(12,13);
    if op==43 {rv_add(5,12,10);rv_r(3,0,6,5,12);rv_add(11,13,11);rv_add(11,11,6);rv_mov(10,5);}
    else if op==45 {rv_r(3,0,5,12,10);rv_r(0,32,10,12,10);rv_r(0,32,11,13,11);rv_r(0,32,11,11,5);}
    else if op==42 {rv_r(0,1,5,12,10);rv_r(3,1,6,12,10);rv_r(0,1,7,13,10);rv_add(6,6,7);rv_r(0,1,7,12,11);rv_add(11,6,7);rv_mov(10,5);}
    else if op==47 || op==37 {rv_divide(op==37);}
    else if op==38 || op==124 || op==94 {let f=7;if op==124 {f=6;}else if op==94 {f=4;}rv_r(f,0,10,12,10);rv_r(f,0,11,13,11);}
    else if op==265 || op==266 {rv_shift(op);}else {rv_compare(op);}return 0;
}
fn rv_c_call(wide) {
    // C a0..a7 carry the low words of eight private 64-bit arguments. The
    // expression stack may be only eight-byte aligned; restore its exact SP.
    rv_mov(7,2);rv_addi(2,2,-16);rv_i(0x13,7,2,2,-16);rv_stack_check();
    rv_sw(7,2,0);rv_sw(1,2,4);rv_lw(5,7,64);rv_lw(6,7,68);rv_guard(0,6,0);rv_guard(1,5,0);
    let i=0;while i<8 {rv_lw(10+i,7,56-i*8);i=i+1;}rv_i(0x67,0,1,5,0);
    if !wide {rv_imm(11,0);}rv_lw(7,2,0);rv_lw(1,2,4);rv_addi(2,7,72);return 0;
}
fn rv_c_callback(index) {
    // C preserves s0..s11, gp and tp. Private code preserves s0 and never
    // touches the other saved registers, gp or tp. Both ABIs return a0:a1.
    store64(rv_c_thunks+index*8,output_size);rv_addi(2,2,-80);rv_stack_check();rv_sw(1,2,64);
    let i=0;while i<8 {rv_sw(10+i,2,(7-i)*8);rv_sw(0,2,(7-i)*8+4);i=i+1;}
    rv_fix(index,0);rv_lw(1,2,64);rv_addi(2,2,80);rv_ins16(0x8082);return 0;
}
fn rv_context_pointer(reg,hi) {
    rv_guard(0,hi,0);rv_i(0x13,7,28,reg,15);rv_guard(0,28,0);
    rv_imm(28,rv_data_base+56);rv_guard(7,reg,28);rv_imm(28,rv_stack_floor-512);rv_guard(7,28,reg);return 0;
}
fn rv_context_switch() {
    // Cooperative 512-byte context: x1..x31 at register*4, PC256,
    // mstatus272, stack floor304. t0/t1/t2 and a0:a1 are call-clobbered.
    // Saved C registers, gp/tp, private frames and C ancestors survive a yield.
    rv_lw(5,2,8);rv_lw(10,2,12);rv_context_pointer(5,10);
    rv_lw(6,2,0);rv_lw(11,2,4);rv_context_pointer(6,11);
    rv_imm(28,rv_data_base+16);rv_lw(28,28,0);rv_guard(0,28,0);let same=rv_branch(0,5,6);
    let before=rv_branch(6,5,6);rv_addi(28,6,512);rv_guard(7,5,28);let separate=rv_jump();rv_patch_branch(before,output_size);rv_addi(28,5,512);rv_guard(7,6,28);rv_patch_transfer(separate,output_size,0);
    rv_csr(7,7,0x300,8);
    // Validate target state before publishing the old context or changing SP.
    rv_lw(29,6,304);rv_i(0x13,7,28,29,15);rv_guard(0,28,0);rv_imm(28,rv_data_base+56);rv_guard(7,29,28);
    rv_lw(30,6,8);rv_i(0x13,7,28,30,7);rv_guard(0,28,0);rv_guard(6,29,30);rv_imm(28,rv_stack_top);rv_guard(7,28,30);
    rv_lw(30,6,256);rv_i(0x13,7,28,30,1);rv_guard(0,28,0);let cached= -1;if rv_flash {rv_imm(28,0x42000000);cached=rv_branch(7,30,28);}rv_imm(28,rv_code_base+128);rv_guard(7,30,28);rv_imm(28,rv_code_base+rv_code_capacity());rv_guard(6,30,28);if rv_flash {let ram=rv_jump();rv_patch_branch(cached,output_size);rv_imm(28,0x42300000);rv_guard(6,30,28);rv_patch_transfer(ram,output_size,0);}
    rv_addi(2,2,16);let i=1;while i<32 {rv_sw(i,5,i*4);i=i+1;}rv_sw(7,5,272);
    let resume=output_size;rv_const(28,0);rv_sw(28,5,256);rv_imm(28,rv_data_base+20);rv_lw(29,28,0);rv_sw(29,5,304);
    rv_lw(29,6,304);rv_sw(29,28,0);rv_mov(5,6);rv_lw(6,5,256);rv_lw(7,5,272);
    i=1;while i<32 {if i!=5 && i!=6 && i!=7 {rv_lw(i,5,i*4);}i=i+1;}
    rv_csr(1,0,0x300,7);rv_i(0x67,0,0,6,0);
    let end=output_size;output_size=resume;rv_const(28,rv_code_base+end);output_size=end;
    // A same-context yield still consumes its two private argument words.
    let resumed=rv_jump();rv_patch_branch(same,output_size);rv_addi(2,2,16);rv_patch_transfer(resumed,output_size,0);rv_imm(10,0);rv_imm(11,0);return 0;
}
fn rv_irq_enable_reg() {if rv_target==2 {return 0x20001000;}return 0x600c2104;}
fn rv_irq_pending_reg() {if rv_target==2 {return 0x2000100c;}return 0x600c2110;}
fn rv_irq_soft_reg() {if rv_target==2 {return 0x600c5090;}return 0x600c0028;}
fn rv_jal(to) {let n=to-output_size;if n%2 || n< -1048576 || n>1048574 {fail("RISC-V vector jump out of range");}return rv_ins(0x6f|(((n>>20)&1)<<31)|(((n>>1)&1023)<<21)|(((n>>11)&1)<<20)|(((n>>12)&255)<<12));}
fn rv_irq_boot() {
    rv_imm(5,0xffffffff);rv_csr(1,0,0x304,5);rv_register(rv_irq_enable_reg(),0);let matrix=0x600c2000;let count=62;let type=0x600c2108;let clear=0x600c210c;let threshold=0x600c2194;
    if rv_target==2 {matrix=0x60010000;count=77;type=0x20001004;clear=0x20001008;threshold=0x20001090;}
    rv_register(type,0);rv_register(clear,0xffffffff);rv_register(clear,0);rv_register(threshold,1);rv_register(rv_irq_soft_reg(),0);
    rv_imm(5,matrix);rv_imm(6,count);let loop=output_size;rv_sw(0,5,0);rv_addi(5,5,4);rv_addi(6,6,-1);let again=rv_branch(1,6,0);rv_patch_branch(again,loop);
    rv_imm(5,rv_stack_top+16384);rv_csr(1,0,0x340,5);rv_vector_ref=output_size;rv_const(5,0);rv_csr(1,0,0x305,5);return 0;
}
fn rv_interrupt_entry() {
    while output_size%256 {emit(0);}let vector=output_size;let entry=vector+128;let i=0;while i<32 {let to=entry;if !i {to=0;}rv_jal(to);i=i+1;}
    // mscratch is zero while callbacks run. Nested entry fails before any store.
    rv_csr(1,2,0x340,2);let ready=rv_branch(1,2,0);rv_j(0);rv_patch_branch(ready,output_size);rv_addi(2,2,-208);
    i=1;while i<32 {if i!=2 {rv_sw(i,2,i*4);}i=i+1;}
    rv_csr(2,5,0x340,0);rv_sw(5,2,8);rv_csr(1,0,0x340,0);
    let csr=0;i=0;while i<6 {csr=0x341;if i==1 {csr=0x300;}else if i==2 {csr=0x342;}else if i==3 {csr=0x343;}else if i==4 {csr=0x305;}else if i==5 {csr=0x304;}rv_csr(2,5,csr,0);rv_sw(5,2,128+i*4);i=i+1;}
    rv_imm(5,rv_data_base+16);rv_lw(6,5,0);rv_guard(0,6,0);rv_lw(6,5,4);rv_sw(6,2,152);rv_imm(6,1);rv_sw(6,5,0);rv_imm(6,rv_stack_top);rv_sw(6,5,4);
    rv_lw(5,2,136);rv_imm(6,0x80000000);rv_r(7,0,7,5,6);rv_guard(1,7,0);rv_i(0x13,7,5,5,31);rv_guard(1,5,0);rv_imm(10,1);rv_r(1,0,10,10,5);rv_imm(11,0);
    rv_push();rv_fix(rv_irq_dispatch,0);rv_addi(2,2,8);rv_csr(7,0,0x300,8);
    rv_imm(5,rv_data_base+16);rv_lw(6,5,0);rv_imm(7,1);rv_guard(0,6,7);rv_lw(6,2,152);rv_sw(6,5,4);rv_sw(0,5,0);
    if rv_irq_tail>=0 {
        // Park the return frame on its task stack before any scheduler switch.
        // Each suspended task then owns its mepc/mstatus and saved registers.
        rv_lw(7,2,8);rv_i(0x13,7,28,7,7);rv_guard(0,28,0);rv_imm(28,rv_stack_top);rv_guard(7,28,7);rv_guard(7,7,6);rv_addi(7,7,-208);rv_guard(7,7,6);
        rv_imm(28,rv_data_base+56);rv_guard(7,6,28);rv_i(0x13,7,28,6,15);rv_guard(0,28,0);
        i=0;while i<208 {rv_lw(5,2,i);rv_sw(5,7,i);i=i+4;}rv_mov(2,7);
        rv_imm(5,rv_stack_top+16384);rv_csr(1,0,0x340,5);rv_lw(10,2,132);rv_srli(5,10,4);rv_i(0x13,7,5,5,8);rv_r(6,0,10,10,5);rv_imm(11,0);rv_push();rv_fix(rv_irq_tail,0);rv_addi(2,2,8);rv_csr(7,0,0x300,8);
    }
    i=0;while i<6 {csr=0x341;if i==1 {csr=0x300;}else if i==2 {csr=0x342;}else if i==3 {csr=0x343;}else if i==4 {csr=0x305;}else if i==5 {csr=0x304;}rv_lw(5,2,128+i*4);if i==1 {rv_i(0x13,7,5,5,-9);}rv_csr(1,0,csr,5);i=i+1;}
    rv_imm(5,rv_stack_top+16384);rv_csr(1,0,0x340,5);i=1;while i<32 {if i!=2 {rv_lw(i,2,i*4);}i=i+1;}rv_lw(2,2,8);rv_ins(0x30200073);
    let end=output_size;output_size=rv_vector_ref;rv_const(5,(rv_code_base+vector)|1);output_size=end;return 0;
}
fn rv_builtin(kind) {
    if kind==38 || kind==43 {let address=rv_irq_pending_reg();if kind==43 {address=rv_irq_enable_reg();}rv_imm(5,address);rv_ins(0x0ff0000f);rv_lw(10,5,0);rv_imm(11,0);return 0;}
    if kind==39 || kind==41 || kind==42 {
        rv_pop(10,11);rv_guard(0,11,0);let address=rv_irq_enable_reg();let empty= -1;
        if kind==39 {rv_i(0x13,7,5,10,1);rv_guard(0,5,0);}
        else {rv_imm(5,~128);rv_r(7,0,5,10,5);rv_guard(0,5,0);empty=rv_branch(0,10,0);address=rv_irq_soft_reg();if kind==41 {rv_srli(10,10,7);}else {rv_imm(10,0);}}
        rv_imm(5,address);rv_ins(0x0ff0000f);rv_sw(10,5,0);rv_ins(0x0ff0000f);if empty>=0 {rv_patch_branch(empty,output_size);}rv_imm(10,0);rv_imm(11,0);return 0;
    }
    if kind==46 {return rv_context_switch();}
    if kind==49 {rv_imm(10,rv_irq_dispatch>=0 && rv_irq_tail>=0);rv_imm(11,0);return 0;}
    if kind==44 || kind==45 {return rv_c_call(kind==45);}
    if kind==47 {rv_imm(10,rv_data_base);rv_imm(11,0);return 0;}
    if kind==32 || kind==48 {let csr=0xc00;if kind==48 {csr=0x341;}rv_csr(2,10,csr,0);rv_imm(11,0);return 0;}
    if kind==33 {rv_csr(7,0,0x300,8);rv_j(output_size);return 0;}
    if kind==36 {rv_csr(7,10,0x300,8);rv_imm(11,0);return 0;}
    if kind==37 {rv_pop(10,11);rv_csr(1,0,0x300,10);rv_imm(10,0);rv_imm(11,0);return 0;}
    if kind==40 {rv_ins(0x10500073);rv_imm(10,0);rv_imm(11,0);return 0;}
    if kind==35 {rv_lw(12,2,8);rv_lw(13,2,12);rv_guard(0,13,0);rv_i(0x67,0,1,12,0);rv_addi(2,2,16);return 0;}
    if kind==5 {
        rv_imm(5,rv_data_base+16);rv_lw(6,5,0);rv_guard(0,6,0);rv_pop(10,11);
        let badhi=rv_branch(1,11,0);let zero=rv_branch(0,10,0);let maximum=32768;if rv_radio {maximum=16384;}rv_imm(5,maximum);let large=rv_branch(6,5,10);
        rv_addi(5,10,7);rv_i(0x13,7,5,5,-8);rv_imm(7,rv_data_base);rv_lw(6,7,0);rv_add(5,6,5);rv_imm(12,rv_heap_end());let full=rv_branch(6,12,5);
        rv_sw(5,7,0);rv_mov(10,6);rv_imm(11,0);let loop=output_size;let done=rv_branch(7,6,5);rv_store(0,0,6,0);rv_addi(6,6,1);rv_j(loop);rv_patch_branch(done,output_size);let end=rv_jump();
        rv_patch_branch(badhi,output_size);rv_patch_branch(large,output_size);rv_patch_branch(full,output_size);rv_imm(10,-12);rv_imm(11,-1);let end2=rv_jump();rv_patch_branch(zero,output_size);rv_imm(10,-22);rv_imm(11,-1);rv_patch_transfer(end,output_size,0);rv_patch_transfer(end2,output_size,0);return 0;
    }
    if kind!=1 && kind!=2 && kind!=3 && kind!=4 && kind!=30 && kind!=31 {fail("RISC-V builtin requires a supported C3/C6 platform adapter");}
    if kind==3 || kind==4 || kind==31 {rv_pop(10,11);}rv_pop(12,13);rv_guard(0,13,0);
    if kind==30 || kind==31 {rv_i(0x13,7,5,12,3);rv_guard(0,5,0);rv_ins(0x0ff0000f);if kind==30 {rv_lw(10,12,0);rv_imm(11,0);}else {rv_sw(10,12,0);rv_imm(10,0);rv_imm(11,0);}rv_ins(0x0ff0000f);return 0;}
    if kind==1 {rv_lbu(10,12,0);rv_imm(11,0);}else if kind==2 {rv_imm(10,0);rv_imm(11,0);let i=0;while i<8 {rv_lbu(6,12,i);if i%4 {rv_slli(6,6,(i%4)*8);}rv_r(6,0,10+i/4,10+i/4,6);i=i+1;}}
    else if kind==3 {rv_store(0,10,12,0);}else {let i=0;while i<8 {rv_srli(6,10+i/4,(i%4)*8);rv_store(0,6,12,i);i=i+1;}}return 0;
}
fn rv_end(i) {if i+1<function_count {return load64(functions+(i+1)*32+16);}return rv_ir_size;}
fn rv_reachable(index) {
    store64(rv_seen+index*8,1);let changed=1;while changed {changed=0;let i=0;while i<function_count {
        if load64(rv_seen+i*8)==1 {store64(rv_seen+i*8,2);changed=1;let pc=load64(functions+i*32+16)+16;let end=rv_end(i);
            while pc<end {let op=load64(rv_ir+pc);let arg=load64(rv_ir+pc+8);
                if op==8 || op==23 || op==24 || op==26 || op==27 {if op==24 || op==26 {store64(rv_c_thunks+arg*8,1);}if op==26 || op==27 {store64(rv_iram_functions+arg*8,1);}if !load64(rv_seen+arg*8) {store64(rv_seen+arg*8,1);}}
                else if op==25 {store64(esp_import_used+arg*8,1);}
                else if op==17 {if arg!=1 && arg!=2 && arg!=3 && arg!=4 && arg!=5 && arg!=30 && arg!=31 && arg!=32 && arg!=33 && arg!=35 && arg!=36 && arg!=37 && arg!=38 && arg!=39 && arg!=40 && arg!=41 && arg!=42 && arg!=43 && arg!=44 && arg!=45 && arg!=46 && arg!=47 && arg!=48 && arg!=49 {fail("C3/C6 has no Linux syscalls, dynamic FFI or Xtensa SDK ABI");}}
                else if (op<1 || op>16) && (op<19 || op>22) {fail("unsupported RISC-V IR instruction");}pc=pc+16;
            }
        }i=i+1;
    }}return 0;
}
// Keep cache initialization, IRQ dispatch/tails and named IRAM callback closures
// in SRAM. Dynamic external pointers retain their linked object's contract.
fn rv_flash_prepare() {
    rv_flash_init=find(functions,function_count,"esp_xip_enable",14);
    if rv_flash_init<0 || load64(functions+rv_flash_init*32+24) {fail("RISC-V cached target requires esp_xip_enable() from the chip XIP adapter");}
    rv_reachable(rv_flash_init);store64(rv_iram_functions+rv_flash_init*8,1);
    if rv_irq_dispatch>=0 {store64(rv_iram_functions+rv_irq_dispatch*8,1);}
    if rv_irq_tail>=0 {store64(rv_iram_functions+rv_irq_tail*8,1);}
    let changed=1;while changed {changed=0;let i=0;while i<function_count {
        if load64(rv_iram_functions+i*8)==1 {store64(rv_iram_functions+i*8,2);changed=1;let pc=load64(functions+i*32+16)+16;let end=rv_end(i);
            while pc<end {let op=load64(rv_ir+pc);let arg=load64(rv_ir+pc+8);if op==8 || op==23 || op==24 || op==26 || op==27 {if !load64(rv_iram_functions+arg*8) {store64(rv_iram_functions+arg*8,1);}}pc=pc+16;}
        }i=i+1;
    }}
    // Every compact shared helper stays in RAM, including helpers used only by
    // flash functions; discover them before emission instead of backpatching
    // cache-disabled callers to a flash tail.
    let i=0;while i<function_count {if load64(rv_seen+i*8) {let pc=load64(functions+i*32+16)+16;let end=rv_end(i);while pc<end {let op=load64(rv_ir+pc);let arg=load64(rv_ir+pc+8);let key=0;if op==2 {key=1;}else if op==7 {key=512+arg;}else if op==17 && arg!=35 {key=128+arg;}if key {store64(rv_helpers+key*8,1);}pc=pc+16;}}i=i+1;}return 0;
}
fn rv_fix(index,reference) {
    if rv_fixup_count>=65536 {fail("too many RISC-V function relocations");}let p=rv_fixups+rv_fixup_count*24;store64(p,output_size);store64(p+8,index);store64(p+16,reference);rv_fixup_count=rv_fixup_count+1;
    if reference>0 {rv_const(10,0);rv_imm(11,0);}else {rv_ins(0x17|(31<<7));rv_i(0x67,0,1,31,0);}return 0;
}
fn rv_helper(key) {if !load64(rv_helpers+key*8) {store64(rv_helpers+key*8,1);}return rv_fix(key,-1);}
fn rv_emit_helpers() {
    let key=0;while key<1024 {if load64(rv_helpers+key*8) {store64(rv_helpers+key*8,output_size);if key==1 {rv_push();}else if key<512 {rv_builtin(key-128);}else {rv_binary(key-512);}rv_ins16(0x8082);}key=key+1;}return 0;
}
fn rv_state(arg,storing) {
    if storing {rv_pop(12,13);}else {rv_mov(12,10);rv_mov(13,11);}rv_guard(0,13,0);rv_imm(5,arg>>32);rv_guard(6,12,5);rv_slli(6,12,3);rv_imm(5,rv_data_base+(arg&4294967295));rv_add(5,5,6);
    if storing {rv_sw(10,5,0);rv_sw(11,5,4);}else {rv_lw(10,5,0);rv_lw(11,5,4);}return 0;
}
fn rv_word_io(reading) {
    let mask=1023;if rv_target==2 {mask=255;}rv_imm(12,0x60000000);if reading {rv_imm(10,0);rv_imm(11,0);}let i=0;while i<8 {
        let loop=output_size;rv_lw(6,12,28);let f=6;rv_imm(7,126);
        if reading {rv_i(0x13,7,6,6,mask);rv_imm(7,0);f=1;}else {rv_srli(6,6,16);rv_i(0x13,7,6,6,mask);}
        let ready=rv_branch(f,6,7);rv_j(loop);rv_patch_branch(ready,output_size);let word=10+i/4;
        if reading {rv_lw(6,12,0);rv_i(0x13,7,6,6,255);if i%4 {rv_slli(6,6,(i%4)*8);}rv_r(6,0,word,word,6);}
        else {rv_srli(6,word,(i%4)*8);rv_i(0x13,7,6,6,255);rv_sw(6,12,0);}i=i+1;
    }
    if !reading {let loop=output_size;rv_lw(6,12,28);rv_srli(6,6,16);rv_i(0x13,7,6,6,mask);let done=rv_branch(0,6,0);rv_j(loop);rv_patch_branch(done,output_size);}return 0;
}
// Definite assignment for one local. Stop a path at its first store/return;
// retain zero initialization if any reachable path reads the local first.
fn rv_flow_add(pc,start,end,seen,queue,stamp,top) {
 if pc==end {return top;}if pc<start || pc>=end || pc%16 {return -1;}
 let at=(pc-start)/2;if load64(seen+at)==stamp {return top;}
 store64(seen+at,stamp);store64(queue+top*8,pc);return top+1;
}
fn rv_local_needs_initial(slot,start,end,seen,queue) {
 let stamp=slot+1;let top=rv_flow_add(start,start,end,seen,queue,stamp,0);
 while top>0 {
  top=top-1;let pc=load64(queue+top*8);let op=load64(rv_ir+pc);let arg=load64(rv_ir+pc+8);
  if op==3 && arg==slot {return 1;}
  if op!=9 && !(op==4 && arg==slot) {
   if op>=10 && op<=12 {top=rv_flow_add(arg,start,end,seen,queue,stamp,top);if top<0 {return 1;}}
   if op!=10 {top=rv_flow_add(pc+16,start,end,seen,queue,stamp,top);if top<0 {return 1;}}
  }
 }return 0;
}
fn rv_function(index) {
    store64(rv_entries+index*8,output_size);let entry=functions+index*32;let pc=load64(entry+16);let slots=load64(rv_ir+pc+8);let arity=load64(entry+24);let end=rv_end(index);
    rv_locals=alloc(slots*8+8);if rv_locals<0 {fail("cannot allocate RISC-V local map");}let scan=pc+16;while scan<end {if load64(rv_ir+scan)==3 {store64(rv_locals+load64(rv_ir+scan+8)*8,1);}scan=scan+16;}
    let i=0;let used=0;while i<slots {if load64(rv_locals+i*8) {store64(rv_locals+i*8,used);used=used+1;}else {store64(rv_locals+i*8,-1);}i=i+1;}let frame=((used*8+15)/16)*16;if frame>16384 {fail("RISC-V function frame exceeds 16 KiB");}
    let init_seen=alloc((end-pc)/2+8);let init_queue=alloc((end-pc)/2+8);if init_seen<0 || init_queue<0 {fail("cannot allocate RISC-V local flow analysis");}
    rv_addi(2,2,-16);rv_stack_check();rv_sw(1,2,0);rv_sw(8,2,4);if frame {rv_imm(5,-frame);rv_add(2,2,5);rv_stack_check();}rv_mov(8,2);
    i=0;while i<slots {if load64(rv_locals+i*8)>=0 && (i<arity || rv_local_needs_initial(i,pc+16,end,init_seen,init_queue)) {if i<arity {rv_frame_pair(frame+16+(arity-i-1)*8,0);}else {rv_imm(10,0);rv_imm(11,0);}rv_frame_pair(frame-8*(load64(rv_locals+i*8)+1),1);}i=i+1;}
    pc=pc+16;while pc<end {store64(rv_map+pc/2,output_size);let op=load64(rv_ir+pc);let arg=load64(rv_ir+pc+8);
        if op==1 {rv_imm(10,arg);rv_imm(11,arg>>32);}else if op==2 {rv_helper(1);}
        else if op==3 || op==4 {if load64(rv_locals+arg*8)>=0 {rv_frame_pair(frame-8*(load64(rv_locals+arg*8)+1),op==4);}}
        else if op==5 || op==6 {rv_imm(5,rv_data_base+arg);if op==5 {rv_lw(10,5,0);rv_lw(11,5,4);}else {rv_sw(10,5,0);rv_sw(11,5,4);}}
        else if op==7 {rv_helper(512+arg);}else if op==8 {rv_fix(arg,0);let bytes=load64(functions+arg*32+24)*8;if bytes {if bytes<=2047 {rv_addi(2,2,bytes);}else {rv_imm(5,bytes);rv_add(2,2,5);}}}else if op==9 {rv_epilogue(frame);}
        else if op>=10 && op<=12 {let skip=0;if op!=10 {rv_r(6,0,6,10,11);let f=0;if op==11 {f=1;}skip=rv_branch(f,6,0);}store64(rv_jumps+pc/2,rv_jump());if op!=10 {rv_patch_branch(skip,output_size);}}
        else if op==13 || op==15 {rv_bool(op==15);}else if op==14 {rv_neg(10,11);}else if op==16 {rv_i(0x13,4,10,10,-1);rv_i(0x13,4,11,11,-1);}
        else if op==17 {if arg==35 {rv_builtin(arg);}else {rv_helper(128+arg);}}else if op==19 || op==20 {rv_word_io(op==20);}else if op==21 || op==22 {rv_state(arg,op==22);}
        else if op==25 {rv_imm(5,rv_data_base+load64(esp_imports+arg*24+16));rv_lw(10,5,0);rv_imm(11,0);}
        else if op==23 || op==24 || op==26 || op==27 {let reference=1;if op==24 || op==26 {reference=2;}rv_fix(arg,reference);}else {fail("unsupported RISC-V instruction");}pc=pc+16;
    }return 0;
}
fn rv_register(address,value) {rv_imm(5,address);rv_imm(6,value);rv_ins(0x0ff0000f);rv_sw(6,5,0);rv_ins(0x0ff0000f);return 0;}
// Static TLS descriptor at control block+24: magic, template, initialized
// bytes, total bytes, alignment, main TP, two reserved words. All are u32.
fn rv_tls_boot() {
    rv_imm(4,0);rv_imm(12,rv_data_base+24);rv_lw(5,12,0);let absent=rv_branch(0,5,0);rv_imm(6,0x31534c54);rv_guard(0,5,6);
    rv_lw(13,12,4);rv_lw(14,12,8);rv_lw(15,12,12);rv_lw(16,12,16);rv_lw(4,12,20);
    rv_guard(1,15,0);rv_imm(28,65536);rv_guard(7,28,15);rv_guard(7,15,14);rv_guard(7,28,16);rv_imm(28,16);rv_guard(7,16,28);
    rv_addi(30,16,-1);rv_r(7,0,28,16,30);rv_guard(0,28,0);rv_r(7,0,28,4,30);rv_guard(0,28,0);rv_r(7,0,28,13,30);rv_guard(0,28,0);
    rv_imm(28,rv_data_base+56);rv_guard(7,13,28);rv_imm(28,rv_heap_begin());rv_r(0,32,29,28,15);rv_guard(7,29,4);rv_guard(7,29,13);rv_add(28,13,15);rv_guard(7,4,28);
    rv_lw(28,12,24);rv_lw(29,12,28);rv_r(6,0,28,28,29);rv_guard(0,28,0);
    rv_imm(16,0);let loop=output_size;let copied=rv_branch(7,16,15);rv_imm(7,0);let bss=rv_branch(7,16,14);rv_add(5,13,16);rv_lbu(7,5,0);rv_patch_branch(bss,output_size);rv_add(5,4,16);rv_store(0,7,5,0);rv_addi(16,16,1);rv_j(loop);rv_patch_branch(copied,output_size);let done=rv_jump();
    rv_patch_branch(absent,output_size);let i=1;while i<8 {rv_lw(5,12,i*4);rv_guard(0,5,0);i=i+1;}rv_patch_transfer(done,output_size,0);return 0;
}
fn rv_start(main) {
    // Direct-mode mtvec is 256-byte aligned; the trap path never uses a stack.
    rv_csr(7,0,0x300,8);rv_register(rv_data_base+4,0x54524150);rv_j(output_size);while output_size<128 {emit(0);}let entry=output_size;
    rv_csr(7,0,0x300,8);rv_csr(1,0,0x304,0);rv_imm(5,rv_code_base);rv_csr(1,0,0x305,5);rv_imm(2,rv_stack_top);rv_imm(8,0);
    if rv_target==1 {
        rv_register(0x600080a8,0x50d83aa1);rv_register(0x60008090,0);rv_register(0x600080a8,0);
        rv_register(0x600080b0,0x8f1d312a);rv_register(0x600080ac,0x80000000);rv_register(0x600080b0,0);
        rv_register(0x6001f064,0x50d83aa1);rv_register(0x6001f048,0);rv_register(0x6001f064,0);
        rv_register(0x60020064,0x50d83aa1);rv_register(0x60020048,0);rv_register(0x60020064,0);
    }else {
        rv_register(0x600b1c18,0x50d83aa1);rv_register(0x600b1c00,0);rv_register(0x600b1c18,0);
        rv_register(0x600b1c20,0x8f1d312a);rv_register(0x600b1c1c,0x40000);rv_register(0x600b1c20,0);
        rv_register(0x60008064,0x50d83aa1);rv_register(0x60008048,0);rv_register(0x60008064,0);
        rv_register(0x60009064,0x50d83aa1);rv_register(0x60009048,0);rv_register(0x60009064,0);
    }
    rv_register(rv_data_base,rv_heap_begin());rv_register(rv_data_base+20,rv_stack_floor);
    if rv_irq_dispatch>=0 {rv_irq_boot();}rv_tls_boot();if rv_flash {rv_fix(rv_flash_init,0);rv_r(6,0,6,10,11);rv_guard(0,6,0);rv_ins(0x0000100f);}if rv_platform_entry>=0 {rv_fix(rv_platform_entry,0);rv_r(6,0,6,10,11);rv_guard(0,6,0);}rv_fix(main,0);
    rv_imm(5,rv_data_base+8);rv_sw(10,5,0);rv_sw(11,5,4);rv_register(rv_data_base+4,0x444f4e45);rv_j(output_size);return entry;
}
fn rv_elf_image(code,code_size,entry) {
    let string_capacity=21;let symbols=2;let i=0;
    while i<function_count {if load64(rv_c_thunks+i*8) {symbols=symbols+1;string_capacity=string_capacity+load64(functions+i*32+8)+1;}i=i+1;}
    i=0;while i<global_count {symbols=symbols+1;string_capacity=string_capacity+load64(globals+i*32+8)+1;i=i+1;}
    let imports=0;i=0;while i<esp_import_count {if load64(esp_import_used+i*8) {imports=imports+1;symbols=symbols+1;string_capacity=string_capacity+load64(esp_imports+i*24+8)+1;}i=i+1;}
    esp_elf_names=alloc(string_capacity);if esp_elf_names<0 {fail("cannot allocate ESP32 ELF names");}esp_elf_name_size=1;
    let headers=116;let nsections=8;let nloads=2;let iram=code_size;let flash_size=0;if rv_flash {headers=148;nsections=9;nloads=3;iram=rv_iram_size;flash_size=code_size-0x50000;}
    let data_at=headers+iram;let flash_at=data_at+vm_heap_used;let imports_at=flash_at+flash_size;let info_at=imports_at+imports*8;let symbols_at=info_at+32;
    let strings_at=symbols_at+symbols*16;let names_at=strings_at+string_capacity;
    let names=".text,.data,.flex.imports,.flex.info,.symtab,.strtab,.shstrtab,";if rv_flash {names=".text,.data,.flex.imports,.flex.info,.symtab,.strtab,.shstrtab,.flex.irom,";}let names_size=length(names)+1;
    let sections_at=(names_at+names_size+3)&~3;output=alloc(sections_at+nsections*40);if output<0 {fail("cannot allocate ESP32 ELF image");}output_size=0;
    emit(127);emit(69);emit(76);emit(70);emit(1);emit(1);emit(1);while output_size<16 {emit(0);}
    esp_elf16(2);esp_elf16(243);emit32(1);emit32(rv_code_base+entry);emit32(52);emit32(sections_at);emit32(rv_compressed);
    esp_elf16(52);esp_elf16(32);esp_elf16(nloads);esp_elf16(40);esp_elf16(nsections);esp_elf16(7);
    i=0;while i<nloads {let base=rv_code_base;let offset=headers;let size=iram;let flags=5;if i==1 {base=rv_data_base;offset=data_at;size=vm_heap_used;flags=6;}else if i==2 {base=0x42000000;offset=flash_at;size=flash_size;}
        emit32(1);emit32(offset);emit32(base);emit32(base);emit32(size);emit32(size);emit32(flags);emit32(4);i=i+1;}
    i=0;while i<iram {emit(load8(code+i));i=i+1;}i=0;while i<vm_heap_used {emit(load8(vm_heap+i));i=i+1;}
    if rv_flash {i=0;while i<flash_size {emit(load8(code+0x50000+i));i=i+1;}}
    // Record import symbol-name offsets and the in-DRAM pointer slots to patch.
    let import_offsets=alloc(esp_import_count*8+8);if import_offsets<0 {fail("cannot allocate ESP32 ELF import offsets");}
    i=0;while i<esp_import_count {if load64(esp_import_used+i*8) {let at=esp_elf_name(load64(esp_imports+i*24),load64(esp_imports+i*24+8));store64(import_offsets+i*8,at);emit32(at);emit32(rv_data_base+load64(esp_imports+i*24+16));}i=i+1;}
    emit32(1);let chip=5;if rv_target==2 {chip=13;}emit32(chip);emit32(rv_code_base);emit32(rv_data_base);emit32(rv_stack_floor);emit32(rv_stack_top);let hb=rv_heap_begin();let he=rv_heap_end();emit32(hb);emit32(he);
    i=0;while i<16 {emit(0);i=i+1;}
    i=0;while i<function_count {if load64(rv_c_thunks+i*8) {let section=1;if rv_flash && load64(rv_c_thunks+i*8)>=0x50000 {section=8;}esp_elf_symbol(load64(functions+i*32),load64(functions+i*32+8),rv_address(load64(rv_c_thunks+i*8)),0,18,section);}i=i+1;}
    esp_elf_symbol("flex_tls_descriptor",19,rv_data_base+24,32,17,2);
    i=0;while i<global_count {esp_elf_symbol(load64(globals+i*32),load64(globals+i*32+8),rv_data_base+load64(globals+i*32+16),8,17,2);i=i+1;}
    i=0;while i<esp_import_count {if load64(esp_import_used+i*8) {emit32(load64(import_offsets+i*8));emit32(0);emit32(0);emit(16);emit(0);esp_elf16(0);}i=i+1;}
    if esp_elf_name_size!=string_capacity || output_size!=strings_at {fail("internal ESP32 ELF layout mismatch");}
    i=0;while i<string_capacity {emit(load8(esp_elf_names+i));i=i+1;}emit(0);i=0;while i<names_size-1 {let c=load8(names+i);if c==44 {c=0;}emit(c);i=i+1;}
    while output_size<sections_at {emit(0);}i=0;while i<40 {emit(0);i=i+1;}
    esp_elf_section(1,1,6,rv_code_base,headers,iram,0,0,4,0);esp_elf_section(7,1,3,rv_data_base,data_at,vm_heap_used,0,0,8,0);
    esp_elf_section(13,1,0,0,imports_at,imports*8,0,0,4,8);esp_elf_section(27,1,0,0,info_at,32,0,0,4,0);
    esp_elf_section(38,2,0,0,symbols_at,symbols*16,6,1,4,16);esp_elf_section(46,3,0,0,strings_at,string_capacity,0,0,1,0);
    esp_elf_section(54,3,0,0,names_at,names_size,0,0,1,0);if rv_flash {esp_elf_section(64,1,6,0x42000000,flash_at,flash_size,0,0,4,0);}return 0;
}

fn riscv32_finish() {
    if find(functions,function_count,"flex_tls_descriptor",19)>=0 || find(globals,global_count,"flex_tls_descriptor",19)>=0 {fail("reserved RISC-V TLS symbol");}
    let main=find(functions,function_count,"main",4);if main<0 || load64(functions+main*32+24) {fail("C3/C6 requires main() with no parameters");}if vm_heap_used>rv_data_capacity() {if rv_radio {fail("RISC-V radio static data exceeds 32 KiB");}fail("RISC-V static data exceeds 64 KiB");}
    rv_ir=output;rv_ir_size=output_size;rv_seen=alloc(function_count*8);rv_entries=alloc(function_count*8);rv_map=alloc(rv_ir_size/2);rv_jumps=alloc(rv_ir_size/2);rv_fixups=alloc(65536*24);rv_fixup_count=0;
    rv_iram_functions=alloc(function_count*8);rv_helpers=alloc(1024*8);rv_c_thunks=alloc(function_count*8);esp_import_used=alloc(esp_import_count*8+8);
    if rv_seen<0 || rv_entries<0 || rv_map<0 || rv_jumps<0 || rv_fixups<0 || rv_iram_functions<0 || rv_helpers<0 || rv_c_thunks<0 || esp_import_used<0 {fail("cannot allocate RISC-V backend tables");}rv_reachable(main);
    if esp_platform_path {rv_platform_entry=find(functions,function_count,"esp_platform_init",17);if rv_platform_entry>=0 {if load64(functions+rv_platform_entry*32+24) {fail("esp_platform_init must take no parameters");}rv_reachable(rv_platform_entry);}}
    rv_irq_dispatch=find(functions,function_count,"esp_irq_dispatch",16);rv_irq_tail=find(functions,function_count,"esp_irq_epilogue",16);
    if rv_irq_dispatch>=0 {if load64(functions+rv_irq_dispatch*32+24)!=1 {fail("esp_irq_dispatch must take one parameter");}rv_reachable(rv_irq_dispatch);}
    if rv_irq_tail>=0 {if rv_irq_dispatch<0 {fail("RISC-V IRQ epilogue requires a dispatcher");}if load64(functions+rv_irq_tail*32+24)!=1 {fail("esp_irq_epilogue must take one parameter");}rv_reachable(rv_irq_tail);}
    if rv_flash {rv_flash_prepare();}
    output=alloc(output_limit);if output<0 {fail("cannot allocate RISC-V code");}output_size=0;let entry=rv_start(main);if rv_irq_dispatch>=0 {rv_interrupt_entry();}let i=0;
    if rv_flash {
        while i<function_count {if load64(rv_seen+i*8) && load64(rv_iram_functions+i*8) {rv_function(i);}i=i+1;}
        i=0;while i<function_count {if load64(rv_c_thunks+i*8) && load64(rv_iram_functions+i*8) {rv_c_callback(i);}i=i+1;}rv_emit_helpers();while output_size%4 {rv_ins16(1);}rv_iram_size=output_size;while output_size<0x50000 {emit(0);}
    }
    i=0;while i<function_count {if load64(rv_seen+i*8) && (!rv_flash || !load64(rv_iram_functions+i*8)) {rv_function(i);}i=i+1;}
    i=0;while i<function_count {if load64(rv_c_thunks+i*8) && (!rv_flash || !load64(rv_iram_functions+i*8)) {rv_c_callback(i);}i=i+1;}if !rv_flash {rv_emit_helpers();}while output_size%4 {rv_ins16(1);}let size=output_size;
    i=0;while i<rv_fixup_count {let p=rv_fixups+i*24;let at=load64(p);let index=load64(p+8);let target=0;if load64(p+16)<0 {target=load64(rv_helpers+index*8);}else {target=load64(rv_entries+index*8);}if load64(p+16)>0 {if load64(p+16)==2 {target=load64(rv_c_thunks+index*8);}output_size=at;rv_const(10,rv_address(target));}else {rv_patch_transfer(at,target,1);}i=i+1;}output_size=size;
    i=0;while i<function_count {if load64(rv_seen+i*8) {let pc=load64(functions+i*32+16)+16;let end=rv_end(i);while pc<end {let op=load64(rv_ir+pc);if op>=10 && op<=12 {rv_patch_transfer(load64(rv_jumps+pc/2),load64(rv_map+load64(rv_ir+pc+8)/2),0);}pc=pc+16;}}i=i+1;}
    let code=output;if rv_elf {rv_elf_image(code,size,entry);return 0;}
    i=0;while i<esp_import_count {if load64(esp_import_used+i*8) {fail("esp32_external requires an esp32c3-elf or esp32c6-elf link target");}i=i+1;}
    output=alloc(size+vm_heap_used+128);if output<0 {fail("cannot allocate RISC-V ROM image");}output_size=0;
    emit(233);emit(2);emit(2);emit(0x20);emit32(rv_code_base+entry);emit(0xee);emit(0);emit(0);emit(0);let chip=5;if rv_target==2 {chip=13;}esp_elf16(chip);emit(0);esp_elf16(0);esp_elf16(65535);while output_size<23 {emit(0);}emit(1);
    let sum=239;emit32(rv_code_base);emit32(size);i=0;while i<size {let b=load8(code+i);emit(b);sum=sum^b;i=i+1;}emit32(rv_data_base);emit32(vm_heap_used);i=0;while i<vm_heap_used {let b=load8(vm_heap+i);emit(b);sum=sum^b;i=i+1;}while output_size%16!=15 {emit(0);}emit(sum);
    up_k=alloc(512);up_hash=alloc(64);up_words=alloc(512);up_block=alloc(64);up_digest=alloc(65);if up_k<0 || up_hash<0 || up_words<0 || up_block<0 || up_digest<0 {fail("cannot allocate RISC-V image digest");}up_sha_constants();let digest=up_sha256(output,output_size);i=0;while i<64 {emit(up_hex(load8(digest+i))*16+up_hex(load8(digest+i+1)));i=i+2;}return 0;
}
