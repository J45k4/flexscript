// These roots call the same implementation imported by vm/runtime.flex.
// Globals are arbitrary at entry; their initializers are not proof premises.
import "../address.flex";

// A live restricted VM has a positive, nonwrapping host heap span. The used
// prefix is bounded by the CLI's maximum heap size. Inputs offset and size
// remain unrestricted signed 64-bit words, including negative/wrapping cases.
requires vm_restricted != 0;
requires vm_heap_used >= 16 && vm_heap_used <= 1000000000;
requires vm_heap > 0 && vm_heap <= 0x7fffffffffffffff - vm_heap_used;
requires vm_error == 0;
reads vm_restricted, vm_heap, vm_heap_used, vm_error;
modifies vm_error;
ensures result == 0 || offset >= 16;
ensures result == 0 || offset <= vm_heap_used;
ensures result == 0 || size >= 0;
ensures result == 0 || size <= vm_heap_used - offset;
ensures result == 0 || result == vm_heap + old(offset);
ensures result != 0 || vm_error == 3;
ensures result == 0 || vm_error == 0;
fn restricted_address(offset, size) {
    return vm_address(offset, size);
}

// Safety alone could be satisfied by rejecting every access. Prove that the
// complete admissible domain is accepted, including a zero-length access at
// the end of the used prefix. A pre-existing error must be preserved.
requires vm_restricted != 0;
requires vm_heap_used >= 16 && vm_heap_used <= 1000000000;
requires vm_heap > 0 && vm_heap <= 0x7fffffffffffffff - vm_heap_used;
requires offset >= 16 && offset <= vm_heap_used;
requires size >= 0 && size <= vm_heap_used - offset;
reads vm_restricted, vm_heap, vm_heap_used, vm_error;
modifies nothing;
ensures result == vm_heap + old(offset);
fn restricted_address_accepts(offset, size) {
    return vm_address(offset, size);
}
