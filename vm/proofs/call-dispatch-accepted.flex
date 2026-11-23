// A selected interpreter CALL with an accepting callee and writable frame.

requires output_size>=16 && output_size<=268435456;
requires at>=0 && at<=output_size-16 && (at&15)==0;
requires vm_pc==at && vm_fuel>=1;
requires vm_steps>=0 && vm_steps<0x7fffffffffffffff;
requires function_count<=18432;
requires readable_bytes(output+vm_pc,16);
requires load64(output+vm_pc)==8;
requires load64(output+vm_pc+8)==index;
// Production accepted-entry premises.
requires load64(functions+index*32+16)==callee;
requires load64(functions+index*32+24)==arity;
requires load64(output+load64(functions+index*32+16)+8)==slots;
modifies vm_error,vm_pc,vm_fuel,vm_steps,vm_depth,vm_sp,vm_local_base,vm_local_top,
    bytes(vm_frames+vm_depth*40,40),bytes(vm_local_memory+vm_local_top,load64(output+load64(functions+index*32+16)+8)*8);
ensures result==1 && vm_error==old(vm_error);
ensures vm_fuel==old(vm_fuel)-1 && vm_steps==old(vm_steps)+1;
ensures vm_depth==old(vm_depth)+1;
ensures vm_pc==callee+16;
ensures vm_sp==old(vm_sp)-old(load64(functions+index*32+24))*8;
ensures vm_local_base==old(vm_local_top);
ensures vm_local_top==old(vm_local_top)+slots*8;
ensures load64(vm_frames+old(vm_depth)*40)==at+16;
ensures load64(vm_frames+old(vm_depth)*40+8)==old(vm_local_base);
ensures load64(vm_frames+old(vm_depth)*40+16)==old(vm_local_top);
ensures load64(vm_frames+old(vm_depth)*40+24)==old(vm_sp)-old(load64(functions+index*32+24))*8;
ensures load64(vm_frames+old(vm_depth)*40+32)==index;
fn vm_dispatch_accepted_linked_call(at,index,callee,arity,slots) {
    // Production fetch and metering.
    proof {
        assert op==8;
        assert arg==index;
        assert vm_pc==at+16;
    }
    if op==8 {
        return vm_enter(arg,vm_pc);
    }
    return 0;
}
