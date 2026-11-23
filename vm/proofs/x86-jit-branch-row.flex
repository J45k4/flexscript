// The proof gate inserts the ordinary branch row stores from vm_jit_compile.
requires writable_bytes(vm_jit_branches,8192*16);
requires vm_jit_branch_count>=0 && vm_jit_branch_count<8192;
modifies vm_jit_branch_count,bytes(vm_jit_branches+vm_jit_branch_count*16,16);
ensures vm_jit_branch_count==old(vm_jit_branch_count)+1;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16)==at;
ensures load64(vm_jit_branches+old(vm_jit_branch_count)*16+8)==(arg-start)/16;
fn jit_write_branch_row(at,arg,start) {
    proof {jit_branch_record_grant(vm_jit_branches,vm_jit_branch_count);}
PRODUCTION_BRANCH_ROW_STORE
}
