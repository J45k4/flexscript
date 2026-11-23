// The selected meter starts with zero fuel. Its published bytes and the
// caller's saved host frame and stack ownership are input premises.
import "x86-jit-meter-model.flex";
import "x86-jit-fuel-handler-model.flex";
import "x86-jit-writeback.flex";

global x86_fuel_path_rip=0;

requires slot>=-32776 && slot<=-8;
requires displacement>=6 && displacement<=67108864;
requires at>=0 && at<=0x7fffffffffffffff-67108882;
requires readable_bytes(at,23);
requires readable_bytes(rbp+slot,8);
requires load64(rbp+slot)==vm_jit_context;
requires writable_bytes(vm_jit_context+8,8);
requires load64(vm_jit_context+8)==0;
requires disjoint_bytes(vm_jit_context+8,8,at,23);
requires disjoint_bytes(vm_jit_context+8,8,rbp+slot,8);
requires load8(at+0)==76;
requires load8(at+1)==139;
requires load8(at+2)==157;
requires load8(at+7)==73;
requires load8(at+8)==131;
requires load8(at+9)==123;
requires load8(at+10)==8;
requires load8(at+11)==0;
requires load8(at+12)==15;
requires load8(at+13)==132;
requires load8(at+18)==73;
requires load8(at+19)==131;
requires load8(at+20)==107;
requires load8(at+21)==8;
requires load8(at+22)==1;
requires load8(at+3)==((slot>>0)&255);
requires load8(at+4)==((slot>>8)&255);
requires load8(at+5)==((slot>>16)&255);
requires load8(at+6)==((slot>>24)&255);
requires load8(at+14)==((displacement>>0)&255);
requires load8(at+15)==((displacement>>8)&255);
requires load8(at+16)==((displacement>>16)&255);
requires load8(at+17)==((displacement>>24)&255);
requires handler>=0 && handler<=0x7fffffffffffffff-22;
requires rbp>=32776 && rbp<=0x7fffffffffffffff-16;
requires readable_bytes(handler,22);
requires readable_bytes(rbp,16);
requires writable_bytes(vm_jit_context+16,8);
requires disjoint_bytes(vm_jit_context+16,8,rbp,16);
requires disjoint_bytes(vm_jit_context+16,8,rbp+slot,8);
requires disjoint_bytes(vm_jit_context+16,8,handler,22);
requires load8(handler+0)==76;
requires load8(handler+1)==139;
requires load8(handler+2)==157;
requires load8(handler+7)==73;
requires load8(handler+8)==199;
requires load8(handler+9)==67;
requires load8(handler+10)==16;
requires load8(handler+11)==1;
requires load8(handler+12)==0;
requires load8(handler+13)==0;
requires load8(handler+14)==0;
requires load8(handler+15)==184;
requires load8(handler+16)==0;
requires load8(handler+17)==0;
requires load8(handler+18)==0;
requires load8(handler+19)==0;
requires load8(handler+20)==201;
requires load8(handler+21)==195;
requires load8(handler+3)==((slot>>0)&255);
requires load8(handler+4)==((slot>>8)&255);
requires load8(handler+5)==((slot>>16)&255);
requires load8(handler+6)==((slot>>24)&255);
requires handler==at+18+displacement;
requires disjoint_bytes(vm_jit_context+8,8,handler,22);
requires disjoint_bytes(vm_jit_context+8,8,rbp,16);
requires disjoint_bytes(vm_jit_context+16,8,vm_jit_context+8,8);
requires readable_bytes(vm_jit_context+8,16);
requires fuel>=0;
requires vm_steps>=0 && vm_steps<=0x7fffffffffffffff-fuel;
requires vm_jit_calls>=0 && vm_jit_calls<0x7fffffffffffffff;
modifies x86_meter_r11,x86_fuel_return_rax,x86_fuel_return_r11,x86_fuel_return_rbp,x86_fuel_return_rsp,x86_fuel_path_rip,
    vm_acc,vm_fuel,vm_error,vm_steps,vm_jit_calls,vm_depth,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished,
    bytes(vm_jit_context+8,8),bytes(vm_jit_context+16,8);
ensures x86_fuel_path_rip==old(load64(rbp+8));
ensures x86_fuel_return_rbp==old(load64(rbp));
ensures x86_fuel_return_rsp==rbp+16;
ensures x86_fuel_return_r11==vm_jit_context && x86_fuel_return_rax==0;
ensures result==1 && vm_error==1 && vm_acc==0 && vm_fuel==0;
ensures load64(vm_jit_context+8)==0 && load64(vm_jit_context+16)==1;
ensures vm_steps==old(vm_steps)+fuel && vm_jit_calls==old(vm_jit_calls)+1;
ensures vm_depth==old(vm_depth) && vm_pc==old(vm_pc);
ensures vm_local_base==old(vm_local_base) && vm_local_top==old(vm_local_top);
ensures vm_sp==old(vm_sp) && vm_finished==old(vm_finished);
fn x86_fuel_exhaustion_path(at,handler,rbp,slot,displacement,fuel) {
    let reached=x86_meter_step(at,rbp,slot,vm_jit_context,displacement);
    proof {
        assert reached==handler;
        assert load64(vm_jit_context+8)==0;
    }
    x86_fuel_path_rip=x86_fuel_return(reached,rbp,slot,vm_jit_context);
    proof {
        assert load64(vm_jit_context+8)==0;
        assert load64(vm_jit_context+16)==1;
    }
    return vm_jit_writeback(fuel,x86_fuel_return_rax);
}
