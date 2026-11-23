// Publication extent, byte copy and cache update in the production x86-64 JIT.

global output=0;
global output_size=0;
global vm_mode=0;
global vm_jit_cache=0;
global vm_jit_bytes=0;
global vm_jit_compilations=0;

requires output_size>=1 && output_size<=1048576;
requires observed>=0 && observed<output_size;
requires readable_bytes(output,output_size);
requires writable_bytes(code,output_size);
requires code>0 && code<=9223372036854775807-output_size+1;
requires disjoint_bytes(output,output_size,code,output_size);
modifies bytes(code,output_size);
ensures result==output_size;
ensures load8(code+observed)==old(load8(output+observed));
ensures load8(output+observed)==old(load8(output+observed));
fn vm_jit_copy_published_bytes(code,observed) {
    proof {vm_jit_copy_selected_grants(output,code,output_size,observed);}
    ghost let expected=load8(output+observed);
    let i=0;
    invariant i>=0 && i<=output_size;
    invariant i<=observed || load8(code+observed)==expected;
    invariant load8(output+observed)==expected;
    decreases output_size-i;
    while i<output_size {
        proof {
            vm_jit_copy_selected_grants(output,code,output_size,i);
            vm_jit_copy_offset_bounds(code,i,output_size);
            vm_jit_copy_step_rank(output_size,i);
            vm_jit_copy_disjoint_byte(output,code,output_size,i,observed);
            if i==observed {
                vm_jit_copy_equal_byte(output+i,output+observed);
                assert load8(output+i)==expected;
            }
            if i>observed {vm_jit_copy_separates_observations(code,output_size,observed,i);}
        }
        ghost let copying=load8(output+i);
        store8(code+i,load8(output+i));
        proof {
            if i==observed {
                assert code+i==code+observed;
                assert output+i==output+observed;
                assert load8(code+i)==copying;
                vm_jit_copy_equal_byte(code+i,code+observed);
                assert load8(code+observed)==expected;
            }
        }
        i=i+1;
    }
    proof {
        assert i==output_size;
        vm_jit_copy_exit_observer(output_size,i,observed);
        assert load8(code+observed)==expected;
    }
    return i;
}

requires size>=1 && size<=1048576;
requires index>=0 && index<size;
requires readable_bytes(source,size);
requires writable_bytes(destination,size);
requires disjoint_bytes(source,size,destination,size);
ensures readable_bytes(source+index,1);
ensures writable_bytes(destination+index,1);
ensures disjoint_bytes(source,size,destination+index,1);
lemma fn vm_jit_copy_selected_grants(source,destination,size,index) {}

requires size>=1 && size<=1048576;
requires earlier>=0 && earlier<later && later<size;
requires writable_bytes(code,size);
ensures disjoint_bytes(code+earlier,1,code+later,1);
lemma fn vm_jit_copy_separates_observations(code,size,earlier,later) {
    assert writable_bytes(code+earlier,1);
    assert writable_bytes(code+later,1);
    assert code+earlier!=code+later;
    vm_jit_copy_distinct_bytes(code+earlier,code+later);
}

requires length>=1 && length<=1048576;
requires index>=0 && index<length;
ensures (base+index)-base>=0;
ensures (base+index)-base<=length-1;
lemma fn vm_jit_copy_offset_bounds(base,index,length) {
    assert (base+index)-base==index;
}

requires a==b;
requires readable_bytes(a,1);
requires readable_bytes(b,1);
ensures load8(a)==load8(b);
lemma fn vm_jit_copy_equal_byte(a,b) {}

requires first!=second;
requires readable_bytes(first,1);
requires readable_bytes(second,1);
ensures disjoint_bytes(first,1,second,1);
lemma fn vm_jit_copy_distinct_bytes(first,second) {}

requires size>=1 && size<=1048576;
requires index>=0 && index<size;
requires observed>=0 && observed<size;
requires readable_bytes(source,size);
requires writable_bytes(destination,size);
requires disjoint_bytes(source,size,destination,size);
ensures disjoint_bytes(source+observed,1,destination+index,1);
lemma fn vm_jit_copy_disjoint_byte(source,destination,size,index,observed) {}

requires size>=1 && size<=1048576;
requires index>=0 && index<size;
ensures index+1>=0 && index+1<=size;
ensures size-(index+1)>=0;
ensures size-(index+1)<size-index;
lemma fn vm_jit_copy_step_rank(size,index) {
    assert size-index>=1;
    assert size-(index+1)==size-index-1;
}

requires index==length;
requires observed>=0 && observed<length;
ensures index>observed;
lemma fn vm_jit_copy_exit_observer(length,index,observed) {}

requires size>=1 && size<=67108864;
requires used>=0 && used<=16777216;
modifies nothing;
ensures result==0 || result>=size && result<size+4096;
ensures result==0 || (result&4095)==0;
ensures result==0 || result<=1048576 && used+result<=16777216;
ensures result==0 || result==((size+4095)/4096)*4096;
ensures result!=0 || size>1048576 || used+((size+4095)/4096)*4096>16777216;
fn vm_jit_admitted_publication_extent(size,used) {
    let bytes=((size+4095)/4096)*4096;
    proof {vm_jit_rounded_extent(size,bytes);}
    if bytes<=1048576 && bytes<=16777216-used {return bytes;}
    return 0;
}

requires size>=1 && size<=67108864;
requires extent==((size+4095)/4096)*4096;
ensures extent>=size && extent<size+4096;
ensures (extent&4095)==0 && extent<=67108864;
ensures (extent<=1048576)==(size<=1048576);
lemma fn vm_jit_rounded_extent(size,extent) {
    assert (size+4095)/4096==(size+4095)>>12;
    assert extent==((size+4095)&(~4095));
    assert (size+4095)==extent+((size+4095)&4095);
}

// Cache decision after both syscall outcomes have been supplied. The VM
// gate derives the executable projection from vm_jit_compile.
requires output_size>=1 && output_size<=67108864;
requires vm_jit_bytes>=0 && vm_jit_bytes<=16777216;
requires index>=0 && index<18432;
requires writable_bytes(vm_jit_cache+index*32,16);
requires readable_bytes(vm_jit_cache+index*32+16,16);
requires disjoint_bytes(vm_jit_cache+index*32,16,vm_jit_cache+index*32+16,16);
modifies output,output_size,vm_mode,vm_jit_bytes,vm_jit_compilations,bytes(vm_jit_cache+index*32,16);
ensures output==bytecode && output_size==bytecode_size && vm_mode==1;
ensures result==0 || result==mapped && mapped>0 && protection>=0;
ensures result==0 || ((old(output_size)+4095)/4096)*4096<=1048576;
ensures result==0 || old(vm_jit_bytes)+((old(output_size)+4095)/4096)*4096<=16777216;
ensures result!=0 || load64(vm_jit_cache+index*32)==old(load64(vm_jit_cache+index*32));
ensures result!=0 || load64(vm_jit_cache+index*32+8)==old(load64(vm_jit_cache+index*32+8));
ensures result==0 || load64(vm_jit_cache+index*32)==mapped;
ensures result==0 || load64(vm_jit_cache+index*32+8)==((old(output_size)+4095)/4096)*4096;
ensures load64(vm_jit_cache+index*32+16)==old(load64(vm_jit_cache+index*32+16));
ensures load64(vm_jit_cache+index*32+24)==old(load64(vm_jit_cache+index*32+24));
ensures result!=0 || vm_jit_bytes==old(vm_jit_bytes) && vm_jit_compilations==old(vm_jit_compilations);
ensures result==0 || vm_jit_bytes==old(vm_jit_bytes)+((old(output_size)+4095)/4096)*4096;
ensures result==0 || vm_jit_compilations==old(vm_jit_compilations)+1;
fn vm_jit_publication_outcome(index,bytecode,bytecode_size,mapped,protection) {
    let bytes=((output_size+4095)/4096)*4096;let code=0;
    if bytes<=1048576 && bytes<=16777216-vm_jit_bytes {
        code=mapped;
        if code>0 {
            // The distinct checked copy runs before this modeled OS outcome.
            if protection<0 {code=0;}
        }else {code=0;}
    }
    proof {
        assert !code || (bytes<=1048576 && bytes<=16777216-vm_jit_bytes && mapped>0 && protection>=0);
        assert !code || code==mapped;
    }
    output=bytecode;output_size=bytecode_size;vm_mode=1;
    if code {
        let cache=vm_jit_cache+index*32;store64(cache,code);store64(cache+8,bytes);
        vm_jit_bytes=vm_jit_bytes+bytes;vm_jit_compilations=vm_jit_compilations+1;
    }
    return code;
}

// Pointwise handoff for an admitted positive mapping. Negative protection
// models rejection by the cache decision. Mapping lifetime is outside this
// model, so the byte observation refers to the buffer before any release.
requires output_size>=1 && output_size<=1048576;
requires observed>=0 && observed<output_size;
requires vm_jit_bytes>=0 && vm_jit_bytes<=16777216;
requires vm_jit_bytes+((output_size+4095)/4096)*4096<=16777216;
requires index>=0 && index<18432;
requires mapped>0 && mapped<=9223372036854775807-output_size+1;
requires readable_bytes(output,output_size);
requires readable_bytes(output+observed,1);
requires writable_bytes(mapped,output_size);
requires disjoint_bytes(output,output_size,mapped,output_size);
requires writable_bytes(vm_jit_cache+index*32,16);
requires readable_bytes(vm_jit_cache+index*32+16,16);
requires disjoint_bytes(vm_jit_cache+index*32,16,vm_jit_cache+index*32+16,16);
requires disjoint_bytes(mapped,output_size,vm_jit_cache+index*32,16);
requires disjoint_bytes(mapped,output_size,vm_jit_cache+index*32+16,16);
requires disjoint_bytes(mapped+observed,1,vm_jit_cache+index*32,16);
modifies output,output_size,vm_mode,vm_jit_bytes,vm_jit_compilations,bytes(mapped,output_size),bytes(vm_jit_cache+index*32,16);
ensures load8(mapped+observed)==old(load8(output+observed));
ensures output==bytecode && output_size==bytecode_size && vm_mode==1;
ensures result==0 || result==mapped && protection>=0;
ensures result==0 || load64(vm_jit_cache+index*32)==mapped;
fn vm_jit_publish_admitted_image(index,bytecode,bytecode_size,mapped,protection,observed) {
    ghost let expected=load8(output+observed);
    vm_jit_copy_published_bytes(mapped,observed);
    proof {assert load8(mapped+observed)==expected;}
    let code=vm_jit_publication_outcome(index,bytecode,bytecode_size,mapped,protection);
    proof {
        assert disjoint_bytes(mapped+observed,1,vm_jit_cache+index*32,16);
        assert load8(mapped+observed)==expected;
    }
    return code;
}
