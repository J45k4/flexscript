import "address.flex";

global vm_stack=0;
global vm_sp=0;
global vm_frames=0;
global vm_depth=0;

fn vm_push(value) {
    if vm_sp>=524288 {vm_error=4;return 0;}
    store64(vm_stack+vm_sp,value);vm_sp=vm_sp+8;return 1;
}

// A pop reads exactly the old top slot. Frame-floor validation belongs to
// vm_pop; the local memory contract exposes the remaining caller obligation.
requires vm_sp >= 8 && vm_sp <= 524288;
requires readable_bytes(vm_stack+(vm_sp-8),8);
reads vm_stack,vm_sp,vm_error,bytes(vm_stack+(vm_sp-8),8);
modifies vm_sp;
ensures vm_sp == old(vm_sp)-8;
ensures result == old(load64(vm_stack+(vm_sp-8)));
ensures vm_error == old(vm_error);
fn vm_pop_value() {
    vm_sp=vm_sp-8;return load64(vm_stack+vm_sp);
}

fn vm_pop() {
    let floor=0;if vm_depth {floor=load64(vm_frames+(vm_depth-1)*40+24);}
    if vm_sp<=floor {vm_error=4;return 0;}
    return vm_pop_value();
}
