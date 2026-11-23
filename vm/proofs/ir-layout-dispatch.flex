requires size>=48 && size<=268435456;
requires at>=0 && at<=size-48 && (at&15)==0;
ensures at+16>=0 && at+16<=size-32 && ((at+16)&15)==0;
lemma fn io_selected_body_fits(at,size) {
    assert at<=268435408;
    assert at+16>=0 && ((at+16)&15)==0;
    assert (size-48)+16==size-32;
    assert at+16<=(size-48)+16;
}

ENTRY_REQUIREMENTSrequires at<=compacted_size-48;
requires vm_sp-arity*8<=524280;
requires vm_error==0 && vm_finished==0 && vm_yielded==0;
requires vm_fuel>=2;
requires vm_steps>=0 && vm_steps<0x7ffffffffffffffe && vm_steps%4096>=1 && vm_steps%4096<=4094;
requires readable_bytes(output+at+16,32);
requires load64(output+at+16)==2 && load64(output+at+32)==9;
requires readable_bytes(vm_frames,40960);
requires writable_bytes(vm_stack,524288);
requires disjoint_bytes(vm_frames,40960,vm_stack,524288);
requires disjoint_bytes(output+at+16,32,output+at,16);
requires disjoint_bytes(output+at+16,32,functions+index*32+16,8);
requires disjoint_bytes(output+at+16,32,vm_frames+vm_depth*40,40);
requires disjoint_bytes(output+at+16,32,vm_local_memory+vm_local_top,slots*8);
requires disjoint_bytes(output+at+16,32,vm_stack+(vm_sp-arity*8),8);
ENTRY_EFFECTS,vm_finished,vm_fuel,vm_steps,vm_acc,bytes(vm_stack+(vm_sp-arity*8),8);
ensures result==0 && vm_error==0;
ensures vm_depth==old(vm_depth);
ensures vm_pc==return_pc;
ensures vm_local_base==old(vm_local_base);
ensures vm_local_top==old(vm_local_top);
ensures vm_sp==old(vm_sp)-arity*8;
ensures vm_finished==(return_pc==-1);
ensures vm_fuel==old(vm_fuel)-2;
ensures vm_steps==old(vm_steps)+2;
ensures vm_acc==old(vm_acc);
ensures load64(vm_stack+(old(vm_sp)-arity*8))==old(vm_acc);
fn optimizer_relocated_call_push_and_return(pc,at,slots,arity,compacted_size,index,return_pc,floor) {
    ghost let depth=vm_depth;
    ghost let top=vm_local_top;
    ghost let locals=vm_local_base;
    ghost let tail=output+at+16;
    ghost let remaining=vm_sp-arity*8;
    ghost let new_frame=vm_frames+depth*40;
    proof {
        assert arity*8>=0 && arity*8<=32768;
        vm_call_argument_bounds(vm_sp,arity*8);
        assert remaining>=0;
        assert remaining<=524280;
        io_selected_body_fits(at,compacted_size);
    }

    optimizer_copies_header_to_vm_frame_framed(pc,at,slots,arity,compacted_size,index,return_pc,floor);
    proof {
        assert vm_depth==depth+1;
        assert vm_pc==at+16;
        assert output_size==compacted_size;
        assert vm_depth>=1 && vm_depth<=1024;
        assert vm_sp==remaining;
        assert vm_sp>=0 && vm_sp<=524280;
        assert disjoint_bytes(tail,32,vm_stack+remaining,8);

        assert disjoint_bytes(tail,32,output+at,16);
        assert disjoint_bytes(tail,32,functions+index*32+16,8);
        assert disjoint_bytes(tail,32,vm_frames+depth*40,40);
        assert disjoint_bytes(tail,32,vm_local_memory+top,slots*8);
        assert readable_bytes(tail,32);
        assert load64(tail)==2;
        assert load64(tail+16)==9;
        assert load64(new_frame)==return_pc;
        assert load64(new_frame+8)==locals;
        assert load64(new_frame+16)==top;
        assert load64(new_frame+24)==remaining;

    }
    return vm_dispatch_push_and_return();
}
