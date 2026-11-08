// Sequentially consistent, naturally aligned 32/64-bit atomics. Modifying
// operations return the OLD value. 32-bit results are zero-extended.
lowering thread_supported "linux.thread.available" "native-x86_64";
lowering atomic_load32 "atomic.load32" "native-x86_64";
lowering atomic_load64 "atomic.load64" "native-x86_64";
lowering atomic_exchange32 "atomic.exchange32" "native-x86_64";
lowering atomic_exchange64 "atomic.exchange64" "native-x86_64";
lowering atomic_compare_exchange32 "atomic.compare_exchange32" "native-x86_64";
lowering atomic_compare_exchange64 "atomic.compare_exchange64" "native-x86_64";
lowering atomic_fetch_add32 "atomic.fetch_add32" "native-x86_64";
lowering atomic_fetch_add64 "atomic.fetch_add64" "native-x86_64";
fn thread_supported() {return 0;}
// No pretend atomic fallback in the VM, reference mode, or other targets.
fn thread_atomic_unavailable() {return 1/0;}
fn atomic_load32(p) {return thread_atomic_unavailable();}
fn atomic_load64(p) {return thread_atomic_unavailable();}
fn atomic_exchange32(p,value) {return thread_atomic_unavailable();}
fn atomic_exchange64(p,value) {return thread_atomic_unavailable();}
fn atomic_compare_exchange32(p,expected,value) {return thread_atomic_unavailable();}
fn atomic_compare_exchange64(p,expected,value) {return thread_atomic_unavailable();}
fn atomic_fetch_add32(p,value) {return thread_atomic_unavailable();}
fn atomic_fetch_add64(p,value) {return thread_atomic_unavailable();}
