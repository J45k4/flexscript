fn main() {
    let branches=alloc(8192*16);
    let errors=alloc(32768*16);
    if branches<=0 || errors<=0 {return 1;}
    if !vm_jit_check_patch_order(branches,errors,0,0,0) {return 2;}
    if vm_jit_check_patch_order(branches,errors,-1,0,0) ||
       vm_jit_check_patch_order(branches,errors,8193,0,0) ||
       vm_jit_check_patch_order(branches,errors,0,-1,0) ||
       vm_jit_check_patch_order(branches,errors,0,32769,0) {return 2;}

    // Alternate rows through the full branch table, then consume the error tail.
    let i=0;
    while i<8192 {
        store64(branches+i*16,1+i*8);
        store64(errors+i*16,5+i*8);
        i=i+1;
    }
    while i<32768 {
        store64(errors+i*16,65537+(i-8192)*4);
        i=i+1;
    }
    let size=163841;
    if !vm_jit_check_patch_order(branches,errors,8192,32768,size) ||
       !vm_jit_check_patch_order(branches,errors,0,32768,size) ||
       !vm_jit_check_patch_order(branches,errors,8192,0,size) {return 3;}
    if vm_jit_check_patch_order(branches,errors,8192,32768,size-1) {return 4;}

    // Equal sites and partial overlaps in either direction.
    store64(branches,8);
    store64(errors,8);
    if vm_jit_check_patch_order(branches,errors,1,1,16) {return 5;}
    store64(errors,11);
    if vm_jit_check_patch_order(branches,errors,1,1,16) {return 6;}
    store64(errors,5);
    if vm_jit_check_patch_order(branches,errors,1,1,16) {return 6;}
    store64(errors,4);
    if !vm_jit_check_patch_order(branches,errors,1,1,12) {return 7;}
    store64(errors,12);
    if !vm_jit_check_patch_order(branches,errors,1,1,16) {return 7;}

    // Invalid sites in either table and records out of order after one table ends.
    store64(branches,0);
    if vm_jit_check_patch_order(branches,errors,1,0,16) {return 8;}
    store64(errors,1);
    if vm_jit_check_patch_order(branches,errors,0,1,16) {return 8;}
    store64(branches,8);
    store64(branches+16,4);
    if vm_jit_check_patch_order(branches,errors,2,0,16) {return 9;}
    store64(errors,8);
    store64(errors+16,4);
    if vm_jit_check_patch_order(branches,errors,0,2,16) {return 9;}
    return 0;
}
