import "atomic.flex";
// Process-local, nonrecursive, nonrobust mutex: 0 unlocked, 1 uncontended owner,
// 2 owner with possible waiters. Destruction requires external quiescence.
fn mutex_create() {if !thread_supported() {return -38;}return alloc(8);}
fn mutex_try_lock(mutex) {
    if !thread_supported() {return -38;}if mutex<=0 || (mutex&3) {return -22;}
    if !atomic_compare_exchange32(mutex,0,1) {return 0;}return -16;
}
fn mutex_lock(mutex) {
    let result=mutex_try_lock(mutex);if result!= -16 {return result;}
    while atomic_exchange32(mutex,2) {
        let error=syscall(202,mutex,128,2,0,0,0);
        if error<0 && error!= -11 && error!= -4 {return error;}
    }return 0;
}
fn mutex_unlock(mutex) {
    if !thread_supported() {return -38;}if mutex<=0 || (mutex&3) {return -22;}
    let prior=atomic_exchange32(mutex,0);if !prior {return -22;}
    if prior==2 {let error=syscall(202,mutex,129,1,0,0,0);if error<0 {return error;}}
    return 0;
}
fn mutex_destroy(mutex) {
    if !thread_supported() {return -38;}if mutex<=0 || (mutex&3) {return -22;}
    if atomic_load32(mutex) {return -16;}return syscall(11,mutex,8,0,0,0,0);
}
