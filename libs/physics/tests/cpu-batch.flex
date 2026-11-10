import "../cpu-batch.flex";
import "fixtures.flex";

fn cb_equal(a,b,bytes) {
    let i=0;while i<bytes {if load64(a+i)!=load64(b+i) {return 0;}i=i+8;}return 1;
}
fn cb_physical(a,b,stride) {
    return cb_equal(a,b,load64(a+104)) && cb_equal(a+stride-32,b+stride-32,32);
}
fn cb_no_children() {
    let status=alloc(8);let result=syscall(61,-1,status,1,0,0,0);
    syscall(11,status,8,0,0,0,0);h_assert(result==-10,"CPU batch left a child behind");return 0;
}
fn cb_worlds(count,stride,scene) {
    let worlds=alloc(count*stride);let i=0;
    while i<count {let which=scene;if which<0 {which=i%15;}pt_scene(worlds+i*stride,which);i=i+1;}
    return worlds;
}
fn cb_parity(stride) {
    let count=15;let worlds=cb_worlds(count,stride,-1);let reference=alloc(count*stride);
    ph_cpu_batch_copy(reference,worlds,count*stride);
    let step=0;
    while step<100 {
        let i=0;while i<count {h_assert(ph_advance(reference+i*stride,1),"sequential fixture failed");i=i+1;}
        h_assert(ph_cpu_batch_advance(worlds,count,stride,1,2,30000)==1,"CPU batch advance failed");
        i=0;while i<count {h_assert(cb_physical(worlds+i*stride,reference+i*stride,stride),"CPU batch every-step physical parity");i=i+1;}
        cb_no_children();step=step+1;
    }
    // Copyback must preserve warm starts, and both CPU paths can resume it.
    let i=0;while i<count {ph_advance(worlds+i*stride,25);ph_advance(reference+i*stride,50);i=i+1;}
    h_assert(ph_cpu_batch_advance(worlds,count,stride,25,2,30000)==1,"CPU batch resume failed");
    i=0;while i<count {h_assert(cb_physical(worlds+i*stride,reference+i*stride,stride),"CPU batch warm-cache resume parity");i=i+1;}
    // Requesting more workers than worlds must not create unnecessary workers.
    ph_advance(reference,1);h_assert(ph_cpu_batch_advance(worlds,1,stride,1,64,30000)==1 && cb_physical(worlds,reference,stride),"CPU batch worker clamp");
    cb_no_children();syscall(11,reference,count*stride,0,0,0,0);syscall(11,worlds,count*stride,0,0,0,0);
    h_print(1,"CPU batch every-step and resume checks pass\n");return 0;
}
fn cb_failures(stride) {
    let worlds=cb_worlds(2,stride,0);let original=alloc(2*stride);ph_cpu_batch_copy(original,worlds,2*stride);
    h_assert(ph_cpu_batch_advance(worlds,2,stride,0,2,1000)==1 && cb_equal(worlds,original,2*stride),"CPU batch zero steps");
    h_assert(ph_cpu_batch_advance(worlds,0,stride,1,2,1000)==-1 && ph_cpu_batch_advance(worlds,2,stride,-1,2,1000)==-1 && ph_cpu_batch_advance(worlds,2,stride,1,0,1000)==-1 && ph_cpu_batch_advance(worlds,2,stride,1,65,1000)==-1 && ph_cpu_batch_advance(worlds,2,stride,1,2,0)==-1,"CPU batch argument guards");
    store64(worlds+112,stride+8);store64(original+112,stride+8);
    h_assert(ph_cpu_batch_advance(worlds,2,stride,1,2,1000)==-1 && cb_equal(worlds,original,2*stride),"CPU batch layout guard");
    store64(worlds+112,stride);store64(original+112,stride);
    let shape=ph_shape(worlds,0);let id=load64(shape);store64(shape,99999);
    ph_cpu_batch_copy(original,worlds,2*stride);
    h_assert(ph_cpu_batch_advance(worlds,2,stride,1,2,1000)==-1 && cb_equal(worlds,original,2*stride),"CPU batch cross-world shape guard");
    store64(shape,id);ph_cpu_batch_copy(original,worlds,2*stride);
    let repeat=0;
    while repeat<3 {
        h_assert(ph_cpu_batch_advance(worlds,2,stride,1000000,2,20)==-4 && cb_equal(worlds,original,2*stride),"CPU batch deadline must not publish partial worlds");
        cb_no_children();repeat=repeat+1;
    }
    h_assert(ph_cpu_batch_advance(worlds,2,stride,2,2,30000)==1,"CPU batch cannot resume after cancelled call");cb_no_children();
    pt_scene(worlds,0);pt_scene(worlds+stride,0);store64(worlds+stride+144,0x7fc00000);
    ph_cpu_batch_copy(original,worlds,2*stride);h_assert(ph_advance(original,1) && !ph_advance(original+stride,1),"CPU batch fault reference");
    h_assert(ph_cpu_batch_advance(worlds,2,stride,1,2,30000)==0 && load64(worlds+stride+192)==2 && cb_physical(worlds,original,stride) && cb_physical(worlds+stride,original+stride,stride),"CPU batch solver fault propagation");
    cb_no_children();syscall(11,original,2*stride,0,0,0,0);syscall(11,worlds,2*stride,0,0,0,0);
    h_print(1,"CPU batch guards, deadlines and fault checks pass\n");return 0;
}
fn cb_unrelated(stride) {
    let parent=syscall(39,0,0,0,0,0,0);let pid=syscall(57,0,0,0,0,0,0);
    h_assert(pid>=0,"unrelated child fixture fork");
    if !pid {
        if syscall(157,1,9,0,0,0,0)<0 || syscall(110,0,0,0,0,0,0)!=parent {syscall(231,1,0,0,0,0,0);}
        while 1 {syscall(7,0,0,1000,0,0,0);}
    }
    let fd=syscall(434,pid,0,0,0,0,0);h_assert(fd>=0,"unrelated child pidfd");
    let worlds=cb_worlds(2,stride,0);let status=alloc(8);
    let result=ph_cpu_batch_advance(worlds,2,stride,1000000,2,20);
    let still_live=syscall(61,pid,status,1,0,0,0)==0;
    syscall(424,fd,9,0,0,0,0);let reaped=syscall(61,pid,status,0,0,0,0);
    while reaped==-4 {reaped=syscall(61,pid,status,0,0,0,0);}
    syscall(3,fd,0,0,0,0,0);syscall(11,status,8,0,0,0,0);syscall(11,worlds,2*stride,0,0,0,0);
    h_assert(result==-4 && still_live && reaped==pid,"CPU batch must preserve unrelated children");cb_no_children();return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let stride=ph_world_bytes(16,24,256,4);
    if argc>1 {
        let mode=load64(argv+8);let worlds=cb_worlds(2,stride,0);let original=alloc(2*stride);ph_cpu_batch_copy(original,worlds,2*stride);
        h_print(1,"BATCH_PARENT_READY\n");
        let result=ph_cpu_batch_advance(worlds,2,stride,1000000,2,60000);
        if h_equal(mode,"--worker-failure") {
            h_assert(result==-3 && cb_equal(worlds,original,2*stride),"CPU batch worker death must not publish partial worlds");cb_no_children();h_print(1,"CPU batch worker failure checks pass\n");return 0;
        }
        h_die("parent-death fixture unexpectedly returned");
    }
    cb_parity(stride);cb_failures(stride);cb_unrelated(stride);h_print(1,"CPU batch checks pass\n");return 0;
}
