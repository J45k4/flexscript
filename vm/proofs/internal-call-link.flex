// Selected compiler CALL emission and the successful internal resolver patch.
// The resolver projection starts with a matching function index and arity.
requires output_limit>=16 && output_limit<=268435456;
requires output_size>=0 && output_size<=output_limit-16 && (output_size&15)==0;
requires call_count>=0 && call_count<65536;
requires writable_bytes(calls+call_count*32,32);
requires writable_bytes(output+output_size,16);
requires disjoint_bytes(calls+call_count*32,32,output+output_size,16);
modifies output_size,call_count,native_address_site,native_boolean_end,
    bytes(calls+call_count*32,32),bytes(output+output_size,16);
ensures result==0;
ensures call_count==old(call_count)+1 && output_size==old(output_size)+16;
ensures load64(calls+old(call_count)*32)==name;
ensures load64(calls+old(call_count)*32+8)==size;
ensures load64(calls+old(call_count)*32+16)==old(output_size)+8;
ensures load64(calls+old(call_count)*32+24)==arity;
ensures load64(output+old(output_size))==8;
ensures load64(output+old(output_size)+8)==0;
fn compiler_emit_call_record(name,size,arity) {
    ghost let entry_count=call_count;
    let site=calls+call_count*32;
    store64(site,name);
    store64(site+8,size);
    proof {
        assert load64(site)==name;
        assert load64(site+8)==size;
        assert disjoint_bytes(site,8,output+output_size,16);
        assert disjoint_bytes(site+8,8,output+output_size,16);
        assert disjoint_bytes(site,8,site+16,8);
        assert disjoint_bytes(site+8,8,site+16,8);
        assert disjoint_bytes(site,8,site+24,8);
        assert disjoint_bytes(site+8,8,site+24,8);
    }
    store64(site+16,vm_emit(8,0)+8);
    store64(site+24,arity);
    call_count=call_count+1;
    proof {
        assert load64(site)==name;
        assert load64(site+8)==size;
        assert site==calls+entry_count*32;
    }
    return 0;
}

requires actual==expected;
ensures base+actual==base+expected;
lemma fn vm_resolve_operand_address(base,actual,expected) {}

requires readable_bytes(site,32);
requires writable_bytes(code,16);
requires disjoint_bytes(site,32,code,16);
ensures disjoint_bytes(site,8,code+8,8);
ensures disjoint_bytes(site+8,8,code+8,8);
ensures disjoint_bytes(site+16,8,code+8,8);
ensures disjoint_bytes(site+24,8,code+8,8);
ensures disjoint_bytes(code,8,code+8,8);
lemma fn vm_resolve_call_site_separation(site,code) {
    assert disjoint_bytes(site,32,code+8,8);
    assert code>0 && code<=0x7ffffffffffffff0;
    assert writable_bytes(code+8,8);
}

requires function_count>=1 && function_count<=18432;
requires index>=0 && index<function_count;
requires output_size>=16 && output_size<=268435456;
requires expected_pc>=0 && expected_pc<=output_size-16 && (expected_pc&15)==0;
requires readable_bytes(site,32);
requires readable_bytes(functions+index*32+24,8);
requires load64(site+24)==load64(functions+index*32+24);
requires load64(site+16)==expected_pc+8;
requires writable_bytes(output+expected_pc,16);
requires load64(output+expected_pc)==8;
modifies bytes(output+expected_pc+8,8);
ensures result==1;
ensures load64(output+expected_pc)==8;
ensures load64(output+expected_pc+8)==index;
fn vm_resolve_internal_record_at(site,index,expected_pc) {
    let at=load64(site+16);
    proof {
        assert at==expected_pc+8;
        assert index>=0;
        assert load64(site+24)==load64(functions+index*32+24);
        vm_resolve_operand_address(output,at,expected_pc+8);
        assert disjoint_bytes(output+expected_pc,8,output+at,8);
    }
    store64(output+at,index);
    proof {assert load64(output+expected_pc)==8;}
    return 1;
}

requires output_limit>=16 && output_limit<=268435456;
requires output_size>=0 && output_size<=output_limit-16 && (output_size&15)==0;
requires call_count>=0 && call_count<65536;
requires writable_bytes(calls+call_count*32,32);
requires writable_bytes(output+output_size,16);
requires disjoint_bytes(calls+call_count*32,32,output+output_size,16);
requires function_count>=1 && function_count<=18432;
requires index>=0 && index<function_count;
requires readable_bytes(functions+index*32+24,8);
requires load64(functions+index*32+24)==arity;
requires disjoint_bytes(functions+index*32+24,8,calls+call_count*32,32);
requires disjoint_bytes(functions+index*32+24,8,output+output_size,16);
modifies output_size,call_count,native_address_site,native_boolean_end,
    bytes(calls+call_count*32,32),bytes(output+output_size,16);
ensures result==1;
ensures call_count==old(call_count)+1 && output_size==old(output_size)+16;
ensures load64(calls+old(call_count)*32)==name;
ensures load64(calls+old(call_count)*32+8)==size;
ensures load64(calls+old(call_count)*32+16)==old(output_size)+8;
ensures load64(calls+old(call_count)*32+24)==arity;
ensures load64(output+old(output_size))==8;
ensures load64(output+old(output_size)+8)==index;
fn compiler_emit_then_resolve_internal_call(name,size,arity,index) {
    let site=calls+call_count*32;
    let original=output_size;
    compiler_emit_call_record(name,size,arity);
    proof {
        assert (original&15)==0;
        assert readable_bytes(site,32);
        assert load64(functions+index*32+24)==arity;
        assert load64(site+24)==arity;
        assert load64(site+16)==original+8;
        assert output_size==original+16;
        assert original<=output_size-16;
        assert 16<=output_size && output_size<=268435456;
        assert load64(output+original)==8;
        assert writable_bytes(output+original,16);
        assert disjoint_bytes(site,32,output+original,16);
        vm_resolve_call_site_separation(site,output+original);
    }
    let result=vm_resolve_internal_record_at(site,index,original);
    proof {
        assert result==1;
        assert disjoint_bytes(site,8,output+original+8,8);
        assert disjoint_bytes(site+8,8,output+original+8,8);
        assert disjoint_bytes(site+16,8,output+original+8,8);
        assert disjoint_bytes(site+24,8,output+original+8,8);
        assert load64(site)==name;
        assert load64(site+8)==size;
        assert load64(site+16)==original+8;
        assert load64(site+24)==arity;
        assert load64(output+original)==8;
    }
    return result;
}
