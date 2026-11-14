import "operand-stack.flex";

global vm_local_memory=0;
global vm_local_base=0;
global vm_local_top=0;
global vm_pc=0;
global vm_finished=0;

// Shared production frame restoration. Entry proofs must establish ownership
// of the saved fields and, for a valid-state claim, their value invariants.
fn vm_return() {
    if !vm_depth {vm_error=9;return 0;}
    vm_depth=vm_depth-1;let frame=vm_frames+vm_depth*40;
    vm_pc=load64(frame);vm_local_base=load64(frame+8);vm_local_top=load64(frame+16);
    vm_sp=load64(frame+24);if vm_pc==-1 {vm_finished=1;}return 0;
}
