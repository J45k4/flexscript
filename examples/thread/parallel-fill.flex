import "../../libs/thread.flex";
// Two workers own disjoint halves. The parent reads only after joining both.
// This example needs no mutex; it is runtime code, not a concurrency proof.
fn fill(argument,b,c,d,e,f) {
    let buffer=load64(argument);let size=load64(argument+8);let i=0;
    while i<size {store8(buffer+i,7);i=i+1;}return size;
}
fn main() {
    let data=alloc(4096);let arguments=alloc(32);
    if data<0 || arguments<0 {return 1;}
    store64(arguments,data);store64(arguments+8,2048);
    store64(arguments+16,data+2048);store64(arguments+24,2048);
    let callback=native_callback(fill);let first=thread_start(callback,arguments);
    if first<0 {return 2;}
    let second=thread_start(callback,arguments+16);let failed=0;
    if thread_join(first,0)<0 {syscall(231,3,0,0,0,0,0);}
    if thread_destroy(first)<0 {failed=1;}
    if second<0 {failed=1;}
    else {
        if thread_join(second,0)<0 {syscall(231,4,0,0,0,0,0);}
        if thread_destroy(second)<0 {failed=1;}
    }
    let i=0;while i<4096 {if load8(data+i)!=7 {failed=1;}i=i+1;}
    syscall(11,data,4096,0,0,0,0);syscall(11,arguments,32,0,0,0,0);
    return failed;
}
