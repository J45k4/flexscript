// Stateless AArch64 instruction words shared by native output and the VM JIT.
// Callers validate operands and own their output buffer and relocations.
fn arm64_word_mov(dst,src) {return 0xaa0003e0|(src<<16)|dst;}
fn arm64_word_movz(reg,value) {return 0xd2800000|((value&65535)<<5)|reg;}
fn arm64_word_movk(reg,value,shift) {return 0xf2800000|((shift/16)<<21)|((value&65535)<<5)|reg;}
fn arm64_word_rr(op,dst,left,right) {return op|(right<<16)|(left<<5)|dst;}
fn arm64_word_cmp(left,right) {return arm64_word_rr(0xeb000000,31,left,right);}
fn arm64_word_cset(dst,condition) {return 0x9a9f07e0|((condition^1)<<12)|dst;}
fn arm64_word_mem(store,reg,base,offset) {
    let op=0xf9400000;if store {op=0xf9000000;}
    return op|((offset/8)<<10)|(base<<5)|reg;
}
fn arm64_word_branch(delta,link) {
    let op=0x14000000;if link {op=0x94000000;}
    return op|((delta/4)&0x3ffffff);
}
fn arm64_word_cond(delta,condition) {return 0x54000000|(((delta/4)&0x7ffff)<<5)|condition;}
