// The imported production functions are verification roots themselves.
import "../allocation.flex";

// Restricted execution starts with zero native usage and cannot allocate native
// mappings. This root closes its combined managed quota from the allocator's
// checked cursor bound. Initialization and dispatch must prove that premise.
requires vm_restricted != 0;
requires vm_native_used == 0;
requires vm_heap_used >= 16 && vm_heap_used <= vm_heap_limit;
requires vm_heap_limit <= 1000000000;
requires vm_heap > 0 && vm_heap <= 0x7fffffffffffffff - vm_heap_limit;
reads vm_heap_used, vm_heap_limit, vm_native_used, vm_heap, vm_restricted;
modifies vm_heap_used;
ensures vm_heap_used + vm_native_used <= vm_heap_limit;
ensures vm_native_used == 0;
fn restricted_allocation_budget(size) {return vm_allocate(size);}

// Mixed bump/native usage: the allocator's own guards bound the rounded bump
// increment by the remaining combined budget, so the strengthened checked
// postcondition closes the combined quota directly. The entry premise bounds
// native usage within the remaining budget; initialization and the native
// allocator's own accounting must establish and preserve it.
requires vm_heap_used >= 16 && vm_heap_used <= vm_heap_limit;
requires vm_heap_limit <= 1000000000;
requires vm_native_used >= 0 && vm_native_used <= vm_heap_limit - vm_heap_used;
requires vm_heap > 0 && vm_heap <= 0x7fffffffffffffff - vm_heap_limit;
reads vm_heap_used, vm_heap_limit, vm_native_used, vm_heap, vm_restricted;
modifies vm_heap_used;
ensures vm_heap_used + vm_native_used <= vm_heap_limit;
fn mixed_allocation_budget(size) {return vm_allocate(size);}
