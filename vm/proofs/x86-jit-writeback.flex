// The saved pre-call fuel, native result word, and returned context are
// supplied at this boundary. The same frame return runs in both engines.
import "../frame-state.flex";

global vm_jit_context=0;
global vm_acc=0;
global vm_fuel=0;
global vm_steps=0;
global vm_jit_calls=0;

requires initial>=0 && remaining>=0 && remaining<=initial;
ensures initial-remaining>=0 && initial-remaining<=initial;
lemma fn jit_consumption_bounds(initial,remaining) {}

requires prior>=0 && debit>=0 && prior<=0x7fffffffffffffff-debit;
ensures prior+debit>=prior;
ensures (prior+debit)-prior==debit;
lemma fn jit_charge_bounds(prior,debit) {}

requires fuel>=0;
requires vm_steps>=0 && vm_steps<=0x7fffffffffffffff-fuel;
requires vm_jit_calls>=0 && vm_jit_calls<0x7fffffffffffffff;
requires readable_bytes(vm_jit_context+8,16);
requires load64(vm_jit_context+8)>=0 && load64(vm_jit_context+8)<=fuel;
requires load64(vm_jit_context+16)!=0 || vm_depth>=1 && vm_depth<=1024;
requires load64(vm_jit_context+16)!=0 || readable_bytes(vm_frames+(vm_depth-1)*40,32);
modifies vm_acc,vm_fuel,vm_error,vm_steps,vm_jit_calls,vm_depth,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished;
ensures result==1 && vm_acc==native_result;
ensures vm_fuel==old(load64(vm_jit_context+8)) && vm_error==old(load64(vm_jit_context+16));
ensures vm_steps==old(vm_steps)+(fuel-vm_fuel);
ensures vm_steps>=old(vm_steps);
ensures vm_steps-old(vm_steps)>=0 && vm_steps-old(vm_steps)<=fuel;
ensures vm_jit_calls==old(vm_jit_calls)+1 && vm_jit_calls>old(vm_jit_calls);
ensures old(load64(vm_jit_context+16))==0 || vm_depth==old(vm_depth);
ensures old(load64(vm_jit_context+16))==0 ||
    vm_pc==old(vm_pc) && vm_local_base==old(vm_local_base) && vm_local_top==old(vm_local_top);
ensures old(load64(vm_jit_context+16))==0 || vm_sp==old(vm_sp) && vm_finished==old(vm_finished);
ensures old(load64(vm_jit_context+16))!=0 || vm_depth==old(vm_depth)-1;
ensures old(load64(vm_jit_context+16))!=0 || vm_pc==old(load64(vm_frames+(vm_depth-1)*40));
ensures old(load64(vm_jit_context+16))!=0 || vm_local_base==old(load64(vm_frames+(vm_depth-1)*40+8));
ensures old(load64(vm_jit_context+16))!=0 || vm_local_top==old(load64(vm_frames+(vm_depth-1)*40+16));
ensures old(load64(vm_jit_context+16))!=0 || vm_sp==old(load64(vm_frames+(vm_depth-1)*40+24));
ensures vm_error!=0 || vm_pc!=-1 || vm_finished==1;
ensures vm_error!=0 || vm_pc==-1 || vm_finished==old(vm_finished);
fn vm_jit_writeback(fuel,native_result) {
    vm_acc=native_result;
    vm_fuel=load64(vm_jit_context+8);vm_error=load64(vm_jit_context+16);
    proof {
        jit_consumption_bounds(fuel,vm_fuel);
        assert vm_steps<=0x7fffffffffffffff-(fuel-vm_fuel);
        jit_charge_bounds(vm_steps,fuel-vm_fuel);
    }
    vm_steps=vm_steps+(fuel-vm_fuel);vm_jit_calls=vm_jit_calls+1;
    if !vm_error {vm_return();}return 1;
}
