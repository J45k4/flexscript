import "address.flex";

global vm_heap_limit=16777216;
global vm_native_used=0;

// A checked modular summary keeps the allocator's cursor proof independent of
// the internal division circuit. Normal compilation erases these annotations.
requires size > 0 && size <= 1000000000;
reads nothing;
modifies nothing;
ensures result == ((old(size)+7)/8)*8;
ensures result >= old(size);
ensures result <= old(size)+7;
ensures (result & 7) == 0;
fn vm_round_allocation(size) {return ((size+7)/8)*8;}

// These are live-VM entry premises, not established by global initializers.
// Both execution modes are covered; restricted mode returns a guest offset.
requires vm_heap_used >= 16 && vm_heap_used <= vm_heap_limit;
requires vm_heap_limit <= 1000000000;
requires vm_native_used >= 0 && vm_native_used <= vm_heap_limit - vm_heap_used;
requires vm_heap > 0 && vm_heap <= 0x7fffffffffffffff - vm_heap_limit;
reads vm_heap_used, vm_heap_limit, vm_native_used, vm_heap, vm_restricted;
modifies vm_heap_used;
ensures vm_heap_used >= old(vm_heap_used);
ensures vm_heap_used <= vm_heap_limit;
// The allocator's own guards maintain the mixed bump/native budget in both
// execution modes; the pending combined obligation consumes this postcondition.
ensures vm_heap_used + vm_native_used <= vm_heap_limit;
ensures (vm_heap_used & 7) == (old(vm_heap_used) & 7);
ensures result < 0 || (vm_restricted != 0 && result == old(vm_heap_used)) || (vm_restricted == 0 && result == vm_heap + old(vm_heap_used));
ensures result < 0 || size > 0;
ensures result < 0 || vm_restricted == 0 || size <= vm_heap_used - result;
ensures result < 0 || vm_restricted != 0 || size <= vm_heap_used - (result - vm_heap);
ensures result >= 0 || vm_heap_used == old(vm_heap_used);
ensures result >= 0 || result == -12 || result == -22;
ensures size != 0 || result == -22;
// Every positive request whose rounded size fits is accepted, including exact
// fits. An implementation that rejects every request cannot satisfy this root.
ensures size <= 0 || size > vm_heap_limit - old(vm_heap_used) - vm_native_used || ((size+7)/8)*8 > vm_heap_limit - old(vm_heap_used) - vm_native_used || result >= 0;
fn vm_allocate(size) {
    if !size {return -22;}
    if size<0 || size>vm_heap_limit-vm_heap_used-vm_native_used {return -12;}
    let rounded=vm_round_allocation(size);if rounded>vm_heap_limit-vm_heap_used-vm_native_used {return -12;}
    let address=vm_heap_used;vm_heap_used=vm_heap_used+rounded;
    if !vm_restricted {return vm_heap+address;}return address;
}
