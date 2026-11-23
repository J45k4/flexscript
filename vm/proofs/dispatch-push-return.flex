import "../../compiler/program-state.flex";
import "operand-stack.flex";
import "frame-state.flex";

global vm_acc=0;
global vm_steps=0;
global vm_fuel=10000000;
global vm_yielded=0;

requires frames_size>=32 && frames_size<=40960;
requires stack_size>=8 && stack_size<=524288;
requires offset>=0 && offset<=frames_size-32;
requires cursor>=0 && cursor<=stack_size-8;
requires disjoint_bytes(frames,frames_size,stack,stack_size);
ensures disjoint_bytes(frames+offset,32,stack+cursor,8);
lemma fn operand_slot_separate_from_return_fields(frames,frames_size,stack,stack_size,offset,cursor) {}

requires size>=32 && size<=268435456;
requires pc>=0 && pc<=size-32 && (pc&15)==0;
ensures !(size<16 || pc+16<0 || pc+16>size-16 || ((pc+16)&15)!=0);
lemma fn vm_next_instruction_bounded(pc,size) {
    let limit=size-32;
    assert limit>=0 && limit<=268435424;
    assert pc>=0 && pc<=limit;
    assert (limit+16)==size-16;
    assert pc+16<=limit+16;
    assert pc+16>=0 && ((pc+16)&15)==0;
}

requires vm_depth>=1 && vm_depth<=1024;
requires vm_sp>=0 && vm_sp<=524280;
requires vm_error==0;
requires vm_finished==0 && vm_yielded==0;
requires vm_fuel>=2;
requires vm_steps>=0 && vm_steps<0x7ffffffffffffffe && vm_steps%4096>=1 && vm_steps%4096<=4094;
requires output_size>=32 && output_size<=268435456 && vm_pc>=0 && vm_pc<=output_size-32 && (vm_pc&15)==0;
requires readable_bytes(output+vm_pc,32);
requires load64(output+vm_pc)==2;
requires load64(output+vm_pc+16)==9;
requires disjoint_bytes(output+vm_pc,32,vm_stack+vm_sp,8);
requires readable_bytes(vm_frames,40960);
requires writable_bytes(vm_stack,524288);
requires disjoint_bytes(vm_frames,40960,vm_stack,524288);
modifies vm_fuel,vm_steps,vm_acc,vm_sp,vm_error,vm_depth,vm_pc,vm_local_base,vm_local_top,vm_finished,bytes(vm_stack+vm_sp,8);
ensures result==0 && vm_error==0;
ensures vm_depth==old(vm_depth)-1;
ensures vm_pc==old(load64(vm_frames+(vm_depth-1)*40));
ensures vm_local_base==old(load64(vm_frames+(vm_depth-1)*40+8));
ensures vm_local_top==old(load64(vm_frames+(vm_depth-1)*40+16));
ensures vm_sp==old(load64(vm_frames+(vm_depth-1)*40+24));
ensures vm_pc!=-1 || vm_finished==1;
ensures vm_pc==-1 || vm_finished==old(vm_finished);
ensures vm_fuel==old(vm_fuel)-2;
ensures vm_steps==old(vm_steps)+2;
ensures vm_acc==old(vm_acc);
ensures load64(vm_stack+old(vm_sp))==old(vm_acc);
fn vm_dispatch_push_and_return() {
    ghost let slot=vm_stack+vm_sp;
    ghost let first_pc=vm_pc;
    ghost let code=output+vm_pc;
    ghost let frame=vm_frames+(vm_depth-1)*40;
    proof {
        frame_stride_bounds(vm_depth);
        operand_stack_slot_permission(vm_stack,vm_sp);
        operand_slot_separate_from_return_fields(vm_frames,40960,vm_stack,524288,(vm_depth-1)*40,vm_sp);
    }
    proof {
        assert !vm_finished && !vm_error && !vm_yielded && vm_fuel>0;
        assert vm_steps%4096!=0;
        assert !(output_size<16 || vm_pc<0 || vm_pc>output_size-16 || (vm_pc&15)!=0);
    }
    let op=load64(output+vm_pc);let arg=load64(output+vm_pc+8);
    vm_pc=vm_pc+16;vm_fuel=vm_fuel-1;vm_steps=vm_steps+1;
    proof {assert op==2;}
    operand_push_slot(vm_acc);
    proof {
        vm_next_instruction_bounded(first_pc,output_size);
        assert !vm_finished && !vm_error && !vm_yielded && vm_fuel>0;
        assert vm_steps%4096!=0;
        assert !(output_size<16 || vm_pc<0 || vm_pc>output_size-16 || (vm_pc&15)!=0);
        assert disjoint_bytes(code,32,slot,8);
    }
    let op_next=load64(output+vm_pc);let arg_next=load64(output+vm_pc+8);
    vm_pc=vm_pc+16;vm_fuel=vm_fuel-1;vm_steps=vm_steps+1;
    proof {
        assert op_next==9;
        assert disjoint_bytes(frame,32,slot,8);
    }
    return frame_return_buffer();
}
