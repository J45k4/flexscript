// Selected CALL emission, resolution, interpreter fetch, and metadata validation.

requires writable_bytes(site,32);
requires writable_bytes(code,16);
requires disjoint_bytes(site,32,code,16);
ensures disjoint_bytes(site,32,code,8);
ensures disjoint_bytes(site,32,code+8,8);
lemma fn linked_call_instruction_separate(site,code) {
    assert writable_bytes(code,8);
    assert writable_bytes(code+8,8);
}

requires caller>=16 && caller<=268435440;
requires callee>=0 && callee<=caller-16;
requires size==caller+16;
ensures size>=32 && size<=268435456;
ensures caller==size-16 && callee<=size-16;
lemma fn linked_call_append_bounds(caller,callee,size) {}

requires expected_pc>=0 && expected_pc<=output_size-16 && (expected_pc&15)==0;
requires output_size>=16 && output_size<=268435456;
requires vm_pc==expected_pc && vm_fuel>=1;
requires vm_steps>=0 && vm_steps<0x7fffffffffffffff;
requires vm_depth>=0 && vm_depth<1024;
requires index>=0 && index<function_count;
requires callee_pc>=0;
requires callee_pc<=output_size-16;
requires (callee_pc&15)==0;
requires readable_bytes(output+expected_pc,16);
requires load64(output+expected_pc)==8;
requires load64(output+expected_pc+8)==index;
requires readable_bytes(functions+index*32,32);
requires load64(functions+index*32+16)==callee_pc;
requires load64(functions+index*32+24)==arity;
requires readable_bytes(output+callee_pc,16);
requires load64(output+callee_pc)==18;
requires load64(output+callee_pc+8)==slots;
modifies vm_error,vm_pc,vm_fuel,vm_steps;
ensures result==1;
ensures vm_pc==expected_pc+16 && vm_fuel==old(vm_fuel)-1 && vm_steps==old(vm_steps)+1;
ensures vm_error==old(vm_error);
fn vm_fetch_linked_call_metadata(expected_pc,index,callee_pc,arity,slots) {
    // Production fetch and metering.
    proof {assert op==8 && arg==index;}
    if op==8 {return vm_enter_reads_copied_header(arg,vm_pc,callee_pc,arity,slots);}
    return 0;
}

requires output_limit>=32 && output_limit<=268435456;
requires output_size>=16 && output_size<=output_limit-16 && (output_size&15)==0;
requires call_count>=0 && call_count<65536;
requires vm_pc==output_size && vm_fuel>=1;
requires vm_steps>=0 && vm_steps<0x7fffffffffffffff;
requires vm_depth>=0 && vm_depth<1024;
requires function_count>=1 && function_count<=18432;
requires index>=0 && index<function_count;
requires callee_pc>=0 && callee_pc<=output_size-16 && (callee_pc&15)==0;
requires writable_bytes(calls+call_count*32,32);
requires writable_bytes(output+output_size,16);
requires disjoint_bytes(calls+call_count*32,32,output+output_size,16);
requires readable_bytes(functions+index*32,32);
requires load64(functions+index*32+16)==callee_pc;
requires load64(functions+index*32+24)==arity;
requires disjoint_bytes(functions+index*32,32,calls+call_count*32,32);
requires disjoint_bytes(functions+index*32,32,output+output_size,16);
requires readable_bytes(output+callee_pc,16);
requires load64(output+callee_pc)==18 && load64(output+callee_pc+8)==slots;
requires disjoint_bytes(output+callee_pc,16,calls+call_count*32,32);
requires disjoint_bytes(output+callee_pc,16,output+output_size,16);
modifies output_size,call_count,native_address_site,native_boolean_end,
    vm_error,vm_pc,vm_fuel,vm_steps,bytes(calls+call_count*32,32),bytes(output+output_size,16);
ensures result==1;
ensures call_count==old(call_count)+1 && output_size==old(output_size)+16;
ensures vm_pc==old(output_size)+16 && vm_fuel==old(vm_fuel)-1 && vm_steps==old(vm_steps)+1;
ensures vm_error==old(vm_error);
ensures load64(output+old(output_size))==8 && load64(output+old(output_size)+8)==index;
fn compiler_linked_call_to_vm_metadata(name,size,index,arity,slots,callee_pc) {
    let caller=output_size;
    let site=calls+call_count*32;
    let entry=functions+index*32;
    proof {
        linked_call_instruction_separate(site,output+caller);
        assert disjoint_bytes(entry+16,8,site,32);
        assert disjoint_bytes(entry+16,8,output+caller,16);
        assert disjoint_bytes(entry+24,8,site,32);
        assert disjoint_bytes(entry+24,8,output+caller,16);
    }
    compiler_emit_then_resolve_internal_call(name,size,arity,index);
    proof {
        assert vm_pc==caller;
        assert output_size==caller+16;
        assert caller==output_size-16;
        assert callee_pc<=caller-16;
        assert load64(output+caller)==8;
        assert load64(output+caller+8)==index;
        assert disjoint_bytes(entry+16,8,site,32);
        assert disjoint_bytes(entry+16,8,output+caller,16);
        assert disjoint_bytes(entry+24,8,site,32);
        assert disjoint_bytes(entry+24,8,output+caller,16);
        assert disjoint_bytes(output+callee_pc,16,site,32);
        assert disjoint_bytes(output+callee_pc,16,output+caller,16);
        assert load64(entry+16)==callee_pc;
        assert load64(entry+24)==arity;
        assert load64(output+callee_pc)==18;
        assert load64(output+callee_pc+8)==slots;
    }
    proof {
        assert caller>=0 && caller<=output_size-16 && (caller&15)==0;
        assert output_size>=16 && output_size<=268435456;
        assert vm_pc==caller && vm_fuel>=1;
        assert vm_steps>=0 && vm_steps<0x7fffffffffffffff;
        assert vm_depth>=0 && vm_depth<1024;
        assert index>=0 && index<function_count;
        linked_call_append_bounds(caller,callee_pc,output_size);
        assert callee_pc>=0;
        assert (callee_pc&15)==0;
        assert callee_pc<=output_size-16;
        assert readable_bytes(output+caller,16);
        assert readable_bytes(functions+index*32,32);
        assert readable_bytes(output+callee_pc,16);
        assert load64(functions+index*32+16)==callee_pc;
        assert load64(functions+index*32+24)==arity;
        assert load64(output+callee_pc)==18;
        assert load64(output+callee_pc+8)==slots;
    }
    return vm_fetch_linked_call_metadata(caller,index,callee_pc,arity,slots);
}
