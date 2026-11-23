// Read-only leaf admission projections for the production x86-64 JIT.
global vm_restricted=0;
global vm_heap_used=0;

// Operand words accepted by the binary bytecode instruction.
spec fn jit_supported_binary_operator(op) {
    return (op>=259 && op<=262) || (op>=265 && op<=266)
        || (op>=42 && op<=43) || (op>=37 && op<=38) || op==45 || op==47
        || op==60 || op==62 || op==94 || op==124;
}
ensures result==jit_supported_binary_operator(op);
PRODUCTION_BINARY_OPERATOR

requires bytecode_size>=0 && bytecode_size<=268435456;
ensures result==0 || (result>=1 && result<=8192);
ensures result==0 || (start>=0 && end>start && end<=bytecode_size);
ensures result==0 || end==start+result*16;
fn jit_check_leaf_interval(start,end,bytecode_size) {
PRODUCTION_LEAF_INTERVAL
    let count=(end-start)/16;
    proof {jit_admitted_leaf_count(start,end,bytecode_size,count);}
    return count;
}

requires 0<=start && start<end && end<=size && size<=268435456;
requires (end-start)%16==0 && (end-start)/16<=8192;
requires count==(end-start)/16;
ensures count>=1 && count<=8192;
ensures end==start+count*16;
lemma fn jit_admitted_leaf_count(start,end,size,count) {
    let extent=end-start;
    assert extent>=1 && extent<=268435456;
    assert (extent&15)==0;
    assert extent>=16;
    assert count==extent>>4;
    assert count*16==extent;
    assert start+extent==end;
    jit_leaf_aligned_end(start,end,extent,count*16);
}

requires start>=0 && start<=268435440;
requires readable_bytes(bytecode+start,16);
ensures result== -1 ||
    (load64(bytecode+start)==18 && result==load64(bytecode+start+8) && result>=0 && result<=4096);
ensures result!= -1 || load64(bytecode+start)!=18 ||
    load64(bytecode+start+8)<0 || load64(bytecode+start+8)>4096;
fn jit_check_leaf_header(bytecode,start) {
PRODUCTION_LEAF_HEADER
    return slots;
}

requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires slots>=0 && slots<=4096;
requires start>=0 && end>start && end<=268435456;
ensures result==0 || ((op>=1 && op<=16 && op!=8) || op==21 || op==22);
ensures result==0 || (op!=3 && op!=4) || (arg>=0 && arg<slots);
ensures result==0 || (op!=5 && op!=6) || (arg>=16 && arg<=vm_heap_used-8);
ensures result==0 || (op!=21 && op!=22) ||
    ((arg>>32)>=1 && (arg&4294967295)>=16 && (arg>>32)<=(vm_heap_used-(arg&4294967295))/8);
ensures result==0 || (op!=10 && op!=11 && op!=12) || (arg>=start+16 && arg<end && arg%16==0);
ensures result==0 || op!=7 || jit_supported_binary_operator(arg);
fn jit_check_leaf_opcode(op,arg,start,end,slots) {
PRODUCTION_LEAF_OPCODE
    return 1;
}

PRODUCTION_SLOT_READ_GRANTS

requires limit==pos;
requires end==start+pos;
ensures end==start+limit;
lemma fn jit_leaf_aligned_end(start,end,pos,limit) {}
