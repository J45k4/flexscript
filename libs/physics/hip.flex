// Optional HIP loader, also used for directly compiled RDNA ELF code objects.
// The caller owns the HIP context and module. Creation uploads once; advancing
// keeps every body, collider, constraint and integration step on the device.
import "physics.flex";
import "../../lib/hip.flex";
fn ph_hip_check(status) {
    h_assert(!status,hip_error());
    return 0;
}
fn ph_device_create(module,worlds,count,stride) {
    h_assert(count>0 && count<=1024 && stride>=16384 && stride<=67108864 && count<=2147483647/stride,"invalid physics batch allocation");
    let i=0;
    while i<count {
        h_assert(load64(worlds+i*stride)==1 && load64(worlds+i*stride+112)==stride,"physics batch arenas must have equal valid layout");
        i=i+1;
    }
    let p=alloc(64);
    h_assert(p>0,"physics device handle allocation failed");
    let device=hip_buffer(count*stride);
    h_assert(device,hip_error());
    ph_hip_check(hip_upload(device,worlds,count*stride));
    let words=alloc(64);
    h_assert(words>0,"physics launch allocation failed");
    h_zero(words,64);
    let config=hip_config(count,1,1,64,1,1,0,0);
    h_assert(config,hip_error());
    let workspace=hip_buffer(count*64*16384);
    h_assert(workspace,hip_error());
    store64(p+56,workspace);
    store64(p,device);
    store64(p+8,count*stride);
    store64(p+16,count);
    store64(p+24,stride);
    store64(p+32,module);
    store64(p+40,words);
    store64(p+48,config);
    return p;
}
fn ph_device_advance(p,steps) {
    h_assert(steps>=0 && steps<=1000000,"invalid physics step count");
    if !steps {
        return 0;
    }
    let words=load64(p+40);
    store64(words,load64(p+24));
    store64(words+8,steps);
    store64(words+16,load64(p+56));
    return hip_launch_words(load64(p+32),load64(p),0,load64(p+16)*64,load64(p+48),words);
}
fn ph_device_read(p,host) {
    return hip_download(host,load64(p),load64(p+8));
}
fn ph_device_close(p) {
    ph_hip_check(hip_synchronize());
    ph_hip_check(hip_free(load64(p)));
    ph_hip_check(hip_free(load64(p+56)));
    syscall(11,load64(p+40),64,0,0,0,0);
    syscall(11,load64(p+48),88,0,0,0,0);
    return syscall(11,p,64,0,0,0,0);
}
