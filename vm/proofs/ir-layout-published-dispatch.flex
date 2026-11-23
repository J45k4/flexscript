// Read the relocated record after production size publication.
requires compacted_size>=16 && compacted_size<=268435456;
requires at>=0 && at<=compacted_size-16 && (at&15)==0;
requires writable_bytes(output,compacted_size);
requires index>=0 && index<function_count;
requires vm_depth>=1 && vm_depth<1024;
requires writable_bytes(functions+index*32,32);
requires load64(functions+index*32+16)==at && load64(functions+index*32+24)==arity;
requires readable_bytes(output+at,16);
requires load64(output+at)==18 && load64(output+at+8)==slots;
requires disjoint_bytes(output,compacted_size,functions+index*32,32);
requires vm_sp>=0 && vm_sp<=524288;
requires vm_local_top>=0 && vm_local_top<=8388608;
requires arity>=0 && arity<=slots && slots<=4096;
requires arity*8<=vm_sp;
requires vm_local_top+slots*8<=8388608;
requires readable_bytes(vm_frames+(vm_depth-1)*40+24,8);
requires load64(vm_frames+(vm_depth-1)*40+24)==floor;
requires (floor>=0 && floor<=vm_sp && arity*8<=vm_sp-floor);
requires disjoint_bytes(output+at,16,vm_frames+(vm_depth-1)*40+24,8);
requires disjoint_bytes(functions+index*32+16,8,vm_frames+(vm_depth-1)*40+24,8);
requires vm_local_base>=0 && vm_local_base<=vm_local_top;
requires writable_bytes(vm_frames+vm_depth*40,40);
requires readable_bytes(vm_stack+(vm_sp-arity*8),arity*8);
requires writable_bytes(vm_local_memory+vm_local_top,slots*8);
requires disjoint_bytes(vm_stack+(vm_sp-arity*8),arity*8,vm_local_memory+vm_local_top,slots*8);
requires disjoint_bytes(vm_frames+vm_depth*40,40,vm_stack+(vm_sp-arity*8),arity*8);
requires disjoint_bytes(vm_frames+vm_depth*40,40,vm_local_memory+vm_local_top,slots*8);
requires disjoint_bytes(output+at,16,vm_frames+vm_depth*40,40);
requires disjoint_bytes(functions+index*32+16,8,vm_frames+vm_depth*40,40);
requires disjoint_bytes(output+at,16,vm_stack+(vm_sp-arity*8),arity*8);
requires disjoint_bytes(functions+index*32+16,8,vm_stack+(vm_sp-arity*8),arity*8);
requires disjoint_bytes(output+at,16,vm_local_memory+vm_local_top,slots*8);
requires disjoint_bytes(functions+index*32+16,8,vm_local_memory+vm_local_top,slots*8);
requires at<=compacted_size-48;
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
modifies output_size,vm_error,vm_depth,vm_sp,vm_local_base,vm_local_top,vm_pc,bytes(vm_frames+vm_depth*40,40),bytes(vm_local_memory+vm_local_top,slots*8),vm_finished,vm_fuel,vm_steps,vm_acc,bytes(vm_stack+(vm_sp-arity*8),8);
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
fn vm_publish_relocated_then_push_and_return(at,slots,arity,compacted_size,index,return_pc,floor) {
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

    // Production size publication.
    vm_enter_installs_copied_header_framed(index,return_pc,at,arity,slots,floor);
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
