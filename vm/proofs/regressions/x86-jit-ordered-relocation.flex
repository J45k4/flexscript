fn fixture_patch_branches(map_count) {
    return vm_jit_patch_branches(vm_jit_branches,vm_jit_branch_count,0,output_size,map_count);
}

fn mixed_relocations() {
    output=alloc(48);
    vm_jit_branches=alloc(32);
    vm_jit_errors=alloc(32);
    vm_jit_map=alloc(24);
    if output<=0 || vm_jit_branches<=0 || vm_jit_errors<=0 || vm_jit_map<=0 {return 11;}
    store64(vm_jit_branches,8);store64(vm_jit_branches+8,1);
    store64(vm_jit_branches+16,28);store64(vm_jit_branches+24,2);
    store64(vm_jit_errors,16);store64(vm_jit_errors+16,20);
    store64(vm_jit_map+8,36);store64(vm_jit_map+16,4);
    store64(output+16,0x136598bd823401bc);
    if !vm_jit_patch_branches(vm_jit_branches,2,2,48,3) {return 12;}
    if 12+branch_displacement(8)!=36 || 32+branch_displacement(28)!=4 {return 13;}
    if load64(output+16)!=0x136598bd823401bc {return 14;}
    store64(vm_jit_branches,16);
    if vm_jit_patch_branches(vm_jit_branches,2,2,48,3) {return 15;}
    return 0;
}

fn main() {
    let result=branch_only();
    if result {return result;}
    return mixed_relocations();
}
