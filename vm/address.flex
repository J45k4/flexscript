// Shared by the running VM and its source-level confinement proofs.
// Restricted pointers are guest offsets; trusted pointers are host addresses.
global vm_restricted=0;
global vm_heap=0;
global vm_heap_used=16;
global vm_error=0;

fn vm_address(offset,size) {
    if !vm_restricted {
        if !offset || size<0 {vm_error=3;return 0;}
        return offset;
    }
    if offset<16 || offset>vm_heap_used || size<0 || size>vm_heap_used-offset {
        vm_error=3;return 0;
    }
    return vm_heap+offset;
}
