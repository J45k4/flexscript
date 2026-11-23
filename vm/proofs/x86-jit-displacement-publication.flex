// Observe all four bytes of a selected rel32 displacement through the
// production copy loop and cache update. The mapping and protection results
// come from the existing publication model.
requires output_size>=4 && output_size<=1048576;
requires observed>=1 && observed<=output_size-4;
requires target>=0 && target<output_size;
requires vm_jit_bytes>=0 && vm_jit_bytes<=16777216;
requires vm_jit_bytes+((output_size+4095)/4096)*4096<=16777216;
requires index>=0 && index<18432;
requires mapped>0;
requires readable_bytes(output,output_size);
requires readable_bytes(output+observed,4);
requires ((jit_rel32_bits(output+observed)<<32)>>32)==target-observed-4;
requires writable_bytes(mapped,output_size);
requires readable_bytes(mapped+observed,4);
requires disjoint_bytes(output,output_size,mapped,output_size);
requires writable_bytes(vm_jit_cache+index*32,16);
requires readable_bytes(vm_jit_cache+index*32+16,16);
requires disjoint_bytes(vm_jit_cache+index*32,16,vm_jit_cache+index*32+16,16);
requires disjoint_bytes(mapped,output_size,vm_jit_cache+index*32,16);
requires disjoint_bytes(mapped+observed,4,vm_jit_cache+index*32,16);
requires disjoint_bytes(mapped,output_size,vm_jit_cache+index*32+16,16);
modifies output,output_size,vm_mode,vm_jit_bytes,vm_jit_compilations,bytes(mapped,output_size),bytes(vm_jit_cache+index*32,16);
ensures output==bytecode && output_size==bytecode_size && vm_mode==1;
ensures result==0 || result==mapped && protection>=0;
ensures result==0 || load64(vm_jit_cache+index*32)==mapped;
ensures result==0 || readable_bytes(mapped+observed,4);
ensures result==0 || jit_rel32_bits(mapped+observed)==old(jit_rel32_bits(output+observed));
ensures result==0 || mapped+observed+4+((jit_rel32_bits(mapped+observed)<<32)>>32)==mapped+target;
fn jit_publish_relocated_displacement(index,bytecode,bytecode_size,mapped,protection,observed,target) {
    let cache=vm_jit_cache+index*32;
    proof {
        jit_copy_displacement_span(output,mapped,output_size,observed);
        jit_published_displacement_frame(mapped,observed,cache);
    }
    ghost let expected=jit_rel32_bits(output+observed);
    proof {assert ((expected<<32)>>32)==target-observed-4;}
    ghost let byte0=load8(output+(observed+0));
    ghost let byte1=load8(output+(observed+1));
    ghost let byte2=load8(output+(observed+2));
    ghost let byte3=load8(output+(observed+3));
    jit_copy_selected_displacement(mapped,observed);
    proof {
        assert load8(mapped+(observed+0))==byte0;
        assert load8(mapped+(observed+1))==byte1;
        assert load8(mapped+(observed+2))==byte2;
        assert load8(mapped+(observed+3))==byte3;
    }
    let code=vm_jit_publication_outcome(index,bytecode,bytecode_size,mapped,protection);
    proof {
        if code {
            assert load8(mapped+(observed+0))==byte0;
            assert load8(mapped+(observed+1))==byte1;
            assert load8(mapped+(observed+2))==byte2;
            assert load8(mapped+(observed+3))==byte3;
            jit_published_displacement_word(mapped,observed,byte0,byte1,byte2,byte3,expected);
            jit_published_branch_landing(mapped,observed,target,jit_rel32_bits(mapped+observed),expected);
        }
    }
    return code;
}

REL32_WORD_PROFILE

requires writable_bytes(mapped+observed,4);
requires writable_bytes(cache,16);
requires disjoint_bytes(mapped+observed,4,cache,16);
ensures disjoint_bytes(mapped+(observed+0),1,cache,16);
ensures disjoint_bytes(mapped+(observed+1),1,cache,16);
ensures disjoint_bytes(mapped+(observed+2),1,cache,16);
ensures disjoint_bytes(mapped+(observed+3),1,cache,16);
lemma fn jit_published_displacement_frame(mapped,observed,cache) {
    jit_copy_lane_address(mapped,observed+0,observed,0);
    assert writable_bytes(mapped+(observed+0),1);
    jit_copy_lane_address(mapped,observed+1,observed,1);
    assert writable_bytes(mapped+(observed+1),1);
    jit_copy_lane_address(mapped,observed+2,observed,2);
    assert writable_bytes(mapped+(observed+2),1);
    jit_copy_lane_address(mapped,observed+3,observed,3);
    assert writable_bytes(mapped+(observed+3),1);
}

requires observed>=0 && observed<=1048572;
requires readable_bytes(mapped+observed,4);
requires readable_bytes(mapped+(observed+0),1);
requires load8(mapped+(observed+0))==byte0;
requires readable_bytes(mapped+(observed+1),1);
requires load8(mapped+(observed+1))==byte1;
requires readable_bytes(mapped+(observed+2),1);
requires load8(mapped+(observed+2))==byte2;
requires readable_bytes(mapped+(observed+3),1);
requires load8(mapped+(observed+3))==byte3;
requires expected==(byte0|(byte1<<8)|(byte2<<16)|(byte3<<24));
ensures jit_rel32_bits(mapped+observed)==expected;
lemma fn jit_published_displacement_word(mapped,observed,byte0,byte1,byte2,byte3,expected) {
    jit_copy_lane_address(mapped,observed+0,observed,0);
    jit_copy_lane_address(mapped,observed+1,observed,1);
    jit_copy_lane_address(mapped,observed+2,observed,2);
    jit_copy_lane_address(mapped,observed+3,observed,3);
}

requires output_size>=4 && output_size<=1048576;
requires watched>=0 && watched<=output_size-4;
requires readable_bytes(output,output_size);
requires writable_bytes(code,output_size);
requires code>0;
requires disjoint_bytes(output,output_size,code,output_size);
modifies bytes(code,output_size);
ensures result==output_size;
ensures load8(code+(watched+0))==old(load8(output+(watched+0)));
ensures load8(code+(watched+1))==old(load8(output+(watched+1)));
ensures load8(code+(watched+2))==old(load8(output+(watched+2)));
ensures load8(code+(watched+3))==old(load8(output+(watched+3)));
fn jit_copy_selected_displacement(code,watched) {
    proof {jit_copy_displacement_span(output,code,output_size,watched);}
    ghost let byte0=load8(output+(watched+0));
    ghost let byte1=load8(output+(watched+1));
    ghost let byte2=load8(output+(watched+2));
    ghost let byte3=load8(output+(watched+3));
    let i=0;
    invariant i>=0 && i<=output_size;
    invariant i<=watched+0 || load8(code+(watched+0))==byte0;
    invariant load8(output+(watched+0))==byte0;
    invariant i<=watched+1 || load8(code+(watched+1))==byte1;
    invariant load8(output+(watched+1))==byte1;
    invariant i<=watched+2 || load8(code+(watched+2))==byte2;
    invariant load8(output+(watched+2))==byte2;
    invariant i<=watched+3 || load8(code+(watched+3))==byte3;
    invariant load8(output+(watched+3))==byte3;
    decreases output_size-i;
PRODUCTION_DISPLACEMENT_COPY_LOOP
        proof {
            vm_jit_copy_selected_grants(output,code,output_size,i);
            vm_jit_copy_offset_bounds(code,i,output_size);
            vm_jit_copy_step_rank(output_size,i);
            vm_jit_copy_disjoint_byte(output,code,output_size,i,watched+0);
            if i==watched+0 {
                jit_copy_lane_address(output,i,watched,0);
                jit_copy_expected_byte(output+i,output+(watched+0),byte0);
            }
            if i>watched+0 {
                vm_jit_copy_separates_observations(code,output_size,watched+0,i);
            }
            vm_jit_copy_disjoint_byte(output,code,output_size,i,watched+1);
            if i==watched+1 {
                jit_copy_lane_address(output,i,watched,1);
                jit_copy_expected_byte(output+i,output+(watched+1),byte1);
            }
            if i>watched+1 {
                vm_jit_copy_separates_observations(code,output_size,watched+1,i);
            }
            vm_jit_copy_disjoint_byte(output,code,output_size,i,watched+2);
            if i==watched+2 {
                jit_copy_lane_address(output,i,watched,2);
                jit_copy_expected_byte(output+i,output+(watched+2),byte2);
            }
            if i>watched+2 {
                vm_jit_copy_separates_observations(code,output_size,watched+2,i);
            }
            vm_jit_copy_disjoint_byte(output,code,output_size,i,watched+3);
            if i==watched+3 {
                jit_copy_lane_address(output,i,watched,3);
                jit_copy_expected_byte(output+i,output+(watched+3),byte3);
            }
            if i>watched+3 {
                vm_jit_copy_separates_observations(code,output_size,watched+3,i);
            }
        }
        ghost let prior0=load8(code+(watched+0));
        ghost let prior1=load8(code+(watched+1));
        ghost let prior2=load8(code+(watched+2));
        ghost let prior3=load8(code+(watched+3));
        ghost let copied=load8(output+i);
PRODUCTION_DISPLACEMENT_COPY_STORE
        proof {
            if i==watched+0 {
                jit_copy_lane_address(code,i,watched,0);
                assert load8(code+i)==copied;
                jit_copy_expected_byte(code+(watched+0),code+i,copied);
                assert copied==byte0;
                assert load8(code+(watched+0))==byte0;
            }
            if i>watched+0 {
                assert prior0==byte0;
                assert load8(code+(watched+0))==prior0;
            }
            jit_copy_step_retains_lane(i,watched+0,prior0,load8(code+(watched+0)),byte0);
            if i==watched+1 {
                jit_copy_lane_address(code,i,watched,1);
                assert load8(code+i)==copied;
                jit_copy_expected_byte(code+(watched+1),code+i,copied);
                assert copied==byte1;
                assert load8(code+(watched+1))==byte1;
            }
            if i>watched+1 {
                assert prior1==byte1;
                assert load8(code+(watched+1))==prior1;
            }
            jit_copy_step_retains_lane(i,watched+1,prior1,load8(code+(watched+1)),byte1);
            if i==watched+2 {
                jit_copy_lane_address(code,i,watched,2);
                assert load8(code+i)==copied;
                jit_copy_expected_byte(code+(watched+2),code+i,copied);
                assert copied==byte2;
                assert load8(code+(watched+2))==byte2;
            }
            if i>watched+2 {
                assert prior2==byte2;
                assert load8(code+(watched+2))==prior2;
            }
            jit_copy_step_retains_lane(i,watched+2,prior2,load8(code+(watched+2)),byte2);
            if i==watched+3 {
                jit_copy_lane_address(code,i,watched,3);
                assert load8(code+i)==copied;
                jit_copy_expected_byte(code+(watched+3),code+i,copied);
                assert copied==byte3;
                assert load8(code+(watched+3))==byte3;
            }
            if i>watched+3 {
                assert prior3==byte3;
                assert load8(code+(watched+3))==prior3;
            }
            jit_copy_step_retains_lane(i,watched+3,prior3,load8(code+(watched+3)),byte3);
        }
PRODUCTION_DISPLACEMENT_COPY_ADVANCE
    }
    proof {
        assert i==output_size;
        vm_jit_copy_exit_observer(output_size,i,watched+0);
        assert load8(code+(watched+0))==byte0;
        vm_jit_copy_exit_observer(output_size,i,watched+1);
        assert load8(code+(watched+1))==byte1;
        vm_jit_copy_exit_observer(output_size,i,watched+2);
        assert load8(code+(watched+2))==byte2;
        vm_jit_copy_exit_observer(output_size,i,watched+3);
        assert load8(code+(watched+3))==byte3;
    }
    return i;
}


requires size>=4 && size<=1048576;
requires watched>=0 && watched<=size-4;
requires readable_bytes(source,size);
requires writable_bytes(destination,size);
requires disjoint_bytes(source,size,destination,size);
ensures watched+0>=0 && watched+0<size;
ensures readable_bytes(source+(watched+0),1);
ensures writable_bytes(destination+(watched+0),1);
ensures watched+1>=0 && watched+1<size;
ensures readable_bytes(source+(watched+1),1);
ensures writable_bytes(destination+(watched+1),1);
ensures watched+2>=0 && watched+2<size;
ensures readable_bytes(source+(watched+2),1);
ensures writable_bytes(destination+(watched+2),1);
ensures watched+3>=0 && watched+3<size;
ensures readable_bytes(source+(watched+3),1);
ensures writable_bytes(destination+(watched+3),1);
lemma fn jit_copy_displacement_span(source,destination,size,watched) {
    assert watched+3<=size-1;
    jit_copy_lane_in_window(size,watched,0);
    vm_jit_copy_selected_grants(source,destination,size,watched+0);
    jit_copy_lane_in_window(size,watched,1);
    vm_jit_copy_selected_grants(source,destination,size,watched+1);
    jit_copy_lane_in_window(size,watched,2);
    vm_jit_copy_selected_grants(source,destination,size,watched+2);
    jit_copy_lane_in_window(size,watched,3);
    vm_jit_copy_selected_grants(source,destination,size,watched+3);
}

requires address==observed;
requires readable_bytes(address,1);
requires readable_bytes(observed,1);
requires load8(observed)==expected;
ensures load8(address)==expected;
lemma fn jit_copy_expected_byte(address,observed,expected) {
    vm_jit_copy_equal_byte(address,observed);
}

requires index!=observed || current==expected;
requires index<=observed || prior==expected;
requires index<=observed || current==prior;
ensures index+1<=observed || current==expected;
requires index>=0 && index<=1048575;
requires observed>=0 && observed<=1048575;
lemma fn jit_copy_step_retains_lane(index,observed,prior,current,expected) {
    if index<observed {
        assert index+1<=observed;
    }else {
        if index>observed {
            assert prior==expected && current==prior;
        }
        assert current==expected;
    }
}

requires size>=4 && size<=1048576;
requires observed>=0 && observed<=size-4;
requires lane>=0 && lane<4;
ensures observed+lane>=0 && observed+lane<size;
lemma fn jit_copy_lane_in_window(size,observed,lane) {}

requires i==start+lane;
ensures base+i==base+(start+lane);
lemma fn jit_copy_lane_address(base,i,start,lane) {}

requires actual==staged;
requires ((staged<<32)>>32)==target-site-4;
ensures mapped+site+4+((actual<<32)>>32)==mapped+target;
lemma fn jit_published_branch_landing(mapped,site,target,actual,staged) {
    let delta=(actual<<32)>>32;
    let next=site+4;
    assert delta==((staged<<32)>>32);
    assert target-next==target-site-4;
    jit_relative_address_translation(mapped,next,target,delta);
    jit_native_relative_step(mapped+next,mapped+target,delta);
    assert mapped+next==mapped+site+4;
}

requires delta==target-next;
ensures (base+target)-(base+next)==delta;
lemma fn jit_relative_address_translation(base,next,target,delta) {}

requires target-next==delta;
ensures next+delta==target;
lemma fn jit_native_relative_step(next,target,delta) {}
