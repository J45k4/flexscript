// Optional native Linux x86-64 host adapter. Every worker calls the unchanged
// shared solver, one world at a time. No allocation occurs inside ph_advance.
import "physics.flex";

fn ph_cpu_batch_layout(w,stride) {
    if load64(w)!=1 || load64(w+112)!=stride {return 0;}
    let bodies=load64(w+40);let shapes=load64(w+48);
    let contacts=load64(w+56);let joints=load64(w+64);
    if bodies<=0 || bodies>1024 || shapes<0 || shapes>4096 || contacts<=0 || contacts>65536 || joints<0 || joints>1024 {return 0;}
    let bytes=256+bodies*448+shapes*256+contacts*384+joints*128+16384;
    if bytes!=stride || load64(w+72)!=256 || load64(w+80)!=256+bodies*448 || load64(w+88)!=256+bodies*448+shapes*256 {return 0;}
    if load64(w+96)!=256+bodies*448+shapes*256+contacts*256 || load64(w+104)!=bytes-16384 || load64(w+248)!=256+bodies*448+shapes*256+contacts*256+joints*128 {return 0;}
    if load64(w+8)<0 || load64(w+8)>bodies || load64(w+16)<0 || load64(w+16)>shapes || load64(w+24)<0 || load64(w+24)>contacts || load64(w+32)<0 || load64(w+32)>joints || load64(w+240)<0 || load64(w+240)>contacts {return 0;}
    if load64(w+168)<1 || load64(w+168)>128 {return 0;}
    let i=0;
    while i<load64(w+8) {let kind=load64(ph_body(w,i));if kind<0 || kind>2 {return 0;}i=i+1;}
    i=0;
    while i<load64(w+16) {let s=ph_shape(w,i);let id=load64(s);let kind=load64(s+8);if id<0 || id>=load64(w+8) || kind<1 || kind>3 {return 0;}i=i+1;}
    i=0;
    while i<load64(w+24) {let c=ph_contact(w,i);if load64(c)<0 || load64(c)>=load64(w+8) || load64(c+8)<0 || load64(c+8)>=load64(w+8) {return 0;}i=i+1;}
    i=0;
    while i<load64(w+32) {let j=ph_joint(w,i);if load64(j+16) && (load64(j)<0 || load64(j)>=load64(w+8) || load64(j+8)<0 || load64(j+8)>=load64(w+8)) {return 0;}i=i+1;}
    return 1;
}

fn ph_cpu_batch_copy(out,input,bytes) {
    let i=0;
    while i<bytes {store64(out+i,load64(input+i));i=i+8;}
    return 0;
}

fn ph_cpu_batch_worker(shared,count,stride,steps,lane,workers,parent) {
    // SIGKILL cannot be intercepted by handlers inherited from the caller.
    if syscall(157,1,9,0,0,0,0)<0 || syscall(110,0,0,0,0,0,0)!=parent {
        syscall(231,1,0,0,0,0,0);return 0;
    }
    // The parent grants work only after obtaining a stable pidfd. If opening
    // that handle fails, cancellation releases this child without running math.
    while !load64(shared+8+lane*8) && !load64(shared) {syscall(7,0,0,1,0,0,0);}
    if load64(shared) {syscall(231,1,0,0,0,0,0);return 0;}
    let i=lane;
    while i<count {
        let ok=1;let step=0;
        while step<steps && ok && !load64(shared) {ok=ph_step(shared+16384+i*stride);step=step+1;}
        if load64(shared) {syscall(231,1,0,0,0,0,0);return 0;}
        store64(shared+1024+i*8,ok);
        i=i+workers;
    }
    syscall(231,0,0,0,0,0,0);return 0;
}

// Kill/reap only the explicitly recorded children, never the caller's other
// processes. The shared arena remains mapped until every child is gone.
fn ph_cpu_batch_reap(shared,pids,workers,status) {
    store64(shared,1);
    let i=0;
    while i<workers {
        let fd=load64(pids+512+i*8);
        if fd>=0 {syscall(424,fd,9,0,0,0,0);}
        i=i+1;
    }
    i=0;
    while i<workers {
        let pid=load64(pids+i*8);
        if pid>0 {
            let result=syscall(61,pid,status,0,0,0,0);
            while result==-4 {result=syscall(61,pid,status,0,0,0,0);}
            // ECHILD is also quiescent if a caller's SIGCHLD handler reaped it.
            if result!=pid && result!=-10 {return 0;}
            store64(pids+i*8,0);
        }
        let fd=load64(pids+512+i*8);
        if fd>=0 {syscall(3,fd,0,0,0,0,0);store64(pids+512+i*8,-1);}
        i=i+1;
    }
    return 1;
}

// Synchronous batch over equal-layout contiguous version-1 world arenas.
//  1: completed; 0: physics fault (states copied back, inspect world+192).
// -1: invalid input; -2: allocation/fork failure; -3: worker failure;
// -4: deadline. Negative results leave all input arenas unchanged.
// Workers inherit the caller's numerical environment. Their floating-point
// status flags are process-local and are not merged into the parent.
fn ph_cpu_batch_advance(worlds,count,stride,steps,workers,timeout_ms) {
    if !worlds || (worlds&7) || count<=0 || count>1024 || stride<16384 || stride>67108864 || (stride&7) || count>(2147483647-16384)/stride || steps<0 || steps>1000000 || workers<=0 || workers>64 || timeout_ms<=0 || timeout_ms>3600000 {return -1;}
    let i=0;
    while i<count {
        if !ph_cpu_batch_layout(worlds+i*stride,stride) {return -1;}
        i=i+1;
    }
    if !steps {return 1;}
    if workers>count {workers=count;}
    // Require pidfds before starting any worker. Signals target kernel process
    // handles, so a recycled numerical PID can never kill an unrelated task.
    let probe=syscall(434,syscall(39,0,0,0,0,0,0),0,0,0,0,0);
    if probe<0 {return -2;}syscall(3,probe,0,0,0,0,0);
    let bytes=count*stride;let size=16384+bytes;
    let shared=syscall(9,0,size,3,33,-1,0);
    if shared<0 {return -2;}
    let pids=alloc(2048);
    if pids<=0 {syscall(11,shared,size,0,0,0,0);return -2;}
    i=0;while i<workers {store64(pids+i*8,0);store64(pids+512+i*8,-1);i=i+1;}
    let status=pids+1024;let parent=syscall(39,0,0,0,0,0,0);
    let started=net_now();let error=0;
    if started<=0 {error=-2;}
    if !error {ph_cpu_batch_copy(shared+16384,worlds,bytes);}
    i=0;
    while i<workers && !error {
        let now=net_now();
        if now<started || now-started>=timeout_ms {error=-4;}
        else {
            let pid=syscall(57,0,0,0,0,0,0);
            if !pid {ph_cpu_batch_worker(shared,count,stride,steps,i,workers,parent);syscall(231,1,0,0,0,0,0);}
            if pid<0 {error=-2;}
            else {
                store64(pids+i*8,pid);
                let fd=syscall(434,pid,0,0,0,0,0);
                if fd<0 {error=-2;}
                else {store64(pids+512+i*8,fd);store64(shared+8+i*8,1);}
            }
        }
        i=i+1;
    }
    let remaining=workers;
    while remaining && !error {
        i=0;
        while i<workers && !error {
            let pid=load64(pids+i*8);
            if pid>0 {
                let got=syscall(61,pid,status,1,0,0,0);
                if got==pid {
                    store64(pids+i*8,0);remaining=remaining-1;
                    let fd=load64(pids+512+i*8);if fd>=0 {syscall(3,fd,0,0,0,0,0);store64(pids+512+i*8,-1);}
                    if (load64(status)&4294967295)!=0 {error=-3;}
                }
                else if got<0 && got!=-4 {error=-3;}
            }
            i=i+1;
        }
        if remaining && !error {
            let now=net_now();
            if now<started || now-started>=timeout_ms {error=-4;}
            else {syscall(7,0,0,1,0,0,0);}
        }
    }
    if !error {
        let now=net_now();
        if now<started || now-started>=timeout_ms {error=-4;}
    }
    if error {
        // Do not unmap memory while a worker could still write it.
        if !ph_cpu_batch_reap(shared,pids,workers,status) {return -3;}
    }
    let result=1;
    if !error {
        i=0;
        while i<count {if !load64(shared+1024+i*8) {result=0;}i=i+1;}
        ph_cpu_batch_copy(worlds,shared+16384,bytes);
    }
    syscall(11,pids,2048,0,0,0,0);syscall(11,shared,size,0,0,0,0);
    if error {return error;}
    return result;
}
