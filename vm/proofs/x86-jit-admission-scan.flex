// On a successful scan, an arbitrary selected body instruction was admitted.
spec fn jit_leaf_opcode_admitted(op,arg,start,end,slots,heap_used) {
    return ((op>=1 && op<=16 && op!=8) || op==21 || op==22)
        && ((op!=3 && op!=4) || (arg>=0 && arg<slots))
        && ((op!=5 && op!=6) || (arg>=16 && arg<=heap_used-8))
        && ((op!=21 && op!=22) || ((arg>>32)>=1 && (arg&4294967295)>=16
            && (arg>>32)<=(heap_used-(arg&4294967295))/8))
        && ((op!=10 && op!=11 && op!=12) || (arg>=start+16 && arg<end && arg%16==0))
        && (op!=7 || jit_supported_binary_operator(arg));
}

requires vm_restricted!=0;
requires vm_heap_used>=16 && vm_heap_used<=1000000000;
requires start>=0 && start<=268435440;
requires count>=2 && count<=8192;
requires end==start+count*16 && end<=268435456;
requires slots>=0 && slots<=4096;
requires observed>=1 && observed<count;
requires readable_bytes(bytecode+start,count*16);
ensures result==0 || jit_leaf_opcode_admitted(
    load64(bytecode+(start+observed*16)),load64(bytecode+(start+observed*16)+8),
    start,end,slots,vm_heap_used);
fn jit_scan_admission_observed(bytecode,start,end,count,slots,observed) {
PRODUCTION_SCAN_PC
    ghost let slot=1;
    ghost let selected=0;
    ghost let observed_pc=start+observed*16;
    proof {jit_read_slot_at_pc(bytecode,start,observed_pc,observed,count);}
    ghost let observed_op=load64(bytecode+(start+observed*16));
    ghost let observed_arg=load64(bytecode+(start+observed*16)+8);
    invariant slot>=1 && slot<=count;
    invariant pc==start+slot*16;
    invariant observed_pc==start+observed*16;
    invariant observed_op==load64(bytecode+(start+observed*16));
    invariant observed_arg==load64(bytecode+(start+observed*16)+8);
    invariant selected==0 || selected==1;
    invariant slot<=observed || selected==1;
    invariant selected==0 || jit_leaf_opcode_admitted(observed_op,observed_arg,start,end,slots,vm_heap_used);
    decreases count-slot;
PRODUCTION_SCAN_LOOP
        proof {
            jit_scan_slot_in_range(pc,start,end,slot,count);
            jit_read_slot_at_pc(bytecode,start,pc,slot,count);
        }
PRODUCTION_SCAN_LOADS
PRODUCTION_SCAN_GUARDS
        proof {
            assert jit_leaf_opcode_admitted(op,arg,start,end,slots,vm_heap_used);
            if slot==observed {
                jit_scan_same_pc(pc,observed_pc,start,slot,observed);
                assert op==observed_op && arg==observed_arg;
                jit_scan_same_predicate(op,arg,observed_op,observed_arg,start,end,slots,vm_heap_used);
                selected=1;
            }
            jit_admission_scan_rank(pc,start,slot,count,observed);
            assert slot<=observed || selected==1;
            assert slot!=observed || selected==1;
            jit_observation_after_step(slot,observed,selected);
        }
PRODUCTION_SCAN_ADVANCE
        proof {slot=slot+1;}
    }
    proof {
        jit_scan_slot_in_range(pc,start,end,slot,count);
        assert slot==count;
        assert slot>observed;
    }
    return 1;
}

requires start>=0 && start<=268435440;
requires slot>=1 && slot<=count && count<=8192;
requires pc==start+slot*16 && end==start+count*16;
ensures pc<end || slot==count;
ensures pc>=end || slot<count;
lemma fn jit_scan_slot_in_range(pc,start,end,slot,count) {
    if slot==count {assert pc==end;return 0;}
    assert slot*16==slot<<4 && count*16==count<<4;
    assert slot*16<count*16;
    assert slot*16>=16 && count*16<=131072;
    assert pc<end;
}


requires start>=0 && start<=268435440;
requires count>=1 && count<=8192;
requires slot>=1 && slot<count;
requires pc==start+slot*16;
requires readable_bytes(bytecode+start,count*16);
ensures readable_bytes(bytecode+pc,8);
ensures readable_bytes(bytecode+pc+8,8);
lemma fn jit_read_slot_at_pc(bytecode,start,pc,slot,count) {
    assert slot*16>=16 && slot*16<=131056;
    jit_slot_pc_difference(pc,start,slot*16);
    assert slot+1<=count;
    assert 16*(slot+1)==slot*16+16;
    assert ((slot+1)<<4)<=(count<<4);
    assert slot*16+16<=count*16;
    jit_absolute_slot_grant(bytecode,start,pc,count*16,slot*16);
    jit_granted_instruction_words(bytecode+pc);
}

requires offset==pc-start;
requires offset>=16 && offset<=131056;
requires offset+16<=length && length<=131072;
requires readable_bytes(bytecode+start,length);
ensures readable_bytes(bytecode+pc,16);
lemma fn jit_absolute_slot_grant(bytecode,start,pc,length,offset) {
    assert (bytecode+pc)-(bytecode+start)==pc-start;
    assert (bytecode+pc)-(bytecode+start)==offset;
}

requires readable_bytes(pair,16);
ensures readable_bytes(pair,8);
ensures readable_bytes(pair+8,8);
lemma fn jit_granted_instruction_words(pair) {}

requires current_slot==observed_slot;
requires current==start+current_slot*16;
requires observed==start+observed_slot*16;
ensures current==observed;
lemma fn jit_scan_same_pc(current,observed,start,current_slot,observed_slot) {
    assert current_slot*16==observed_slot*16;
}


requires op==saved_op && arg==saved_arg;
requires jit_leaf_opcode_admitted(op,arg,start,end,slots,heap);
ensures jit_leaf_opcode_admitted(saved_op,saved_arg,start,end,slots,heap);
lemma fn jit_scan_same_predicate(op,arg,saved_op,saved_arg,start,end,slots,heap) {}

requires pc==start+slot*16;
requires start>=0 && start<=268435440;
requires slot>=1 && slot<count && count<=8192;
requires observed>=1 && observed<count;
ensures slot+1>=1 && slot+1<=count;
ensures slot>=observed || slot+1<=observed;
ensures count-(slot+1)>=0 && count-(slot+1)<count-slot;
ensures pc+16==start+(slot+1)*16;
lemma fn jit_admission_scan_rank(pc,start,slot,count,observed) {
    assert slot+1<=count;
    assert count-(slot+1)==count-slot-1;
    assert (slot+1)*16==slot*16+16;
    assert pc+16==start+slot*16+16;
}

requires pc==start+offset;
requires start>=0 && start<=268435440;
requires offset>=16 && offset<=131056;
ensures pc-start==offset;
lemma fn jit_slot_pc_difference(pc,start,offset) {
    assert pc>=start;
}

requires slot>=1 && slot<8192;
requires observed>=1 && observed<8192;
requires slot<=observed || selected==1;
requires slot!=observed || selected==1;
ensures slot+1<=observed || selected==1;
lemma fn jit_observation_after_step(slot,observed,selected) {
    if selected!=1 {
        assert slot<observed;
        assert slot+1<=observed;
    }
}
