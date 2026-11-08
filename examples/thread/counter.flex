import "../../libs/thread.flex";
global counter=0;
fn worker(lock,b,c,d,e,f) {
    let i=0;
    while i<10000 {
        if mutex_lock(lock)<0 {return -1;}
        counter=counter+1;
        if mutex_unlock(lock)<0 {return -2;}
        i=i+1;
    }return i;
}
fn main() {
    let lock=mutex_create();if lock<0 {return 1;}
    let callback=native_callback(worker);
    let first=thread_start(callback,lock);if first<0 {mutex_destroy(lock);return 2;}
    let second=thread_start(callback,lock);
    let result=alloc(8);if result<0 {syscall(231,3,0,0,0,0,0);}
    let failed=0;
    if thread_join(first,result)<0 {syscall(231,4,0,0,0,0,0);}
    if load64(result)!=10000 {failed=1;}
    if thread_destroy(first)<0 {failed=1;}
    if second<0 {failed=1;}
    else {
        if thread_join(second,result)<0 {syscall(231,5,0,0,0,0,0);}
        if load64(result)!=10000 {failed=1;}
        if thread_destroy(second)<0 {failed=1;}
    }
    if counter!=20000 {failed=1;}
    if mutex_destroy(lock)<0 {failed=1;}
    syscall(11,result,8,0,0,0,0);return failed;
}
