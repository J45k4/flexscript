import "host.flex";
fn hp_resize(p,rows,cols) {
    let size=h_take(8);
    store64(size,rows|(cols<<16));
    h_assert(syscall(16,load64(p+96),0x5414,size,0,0,0)==0,"PTY resize failed");
    return 0;
}
fn hp_open(binary) {
    let libc=ffi_open("libc.so.6");
    let open=ffi_symbol(libc,"openpty");
    if !open {
        open=ffi_symbol(ffi_open("libutil.so.1"),"openpty");
    }
    h_assert(open,"openpty is unavailable");
    let master=h_take(8);
    let slave=h_take(8);
    h_assert(ffi_call_i32(open,master,slave,0,0,0,0)==0,"openpty failed");
    let m=load64(master)&0xffffffff;
    let s=load64(slave)&0xffffffff;
    let p=h_zero(h_take(112),112);
    store64(p+96,s);
    hp_resize(p,24,80);
    let original=h_zero(h_take(64),64);
    h_assert(syscall(16,s,0x5401,original,0,0,0)==0,"PTY TCGETS failed");
    store64(p+104,original);
    let args=h_take(16);
    store64(args,binary);
    store64(args+8,0);
    let pid=syscall(57,0,0,0,0,0,0);
    h_assert(pid>=0,"PTY fork failed");
    if pid==0 {
        h_restore_sigpipe();
        syscall(157,1,9,0,0,0,0);
        syscall(112,0,0,0,0,0,0);
        syscall(33,s,0,0,0,0,0);
        syscall(33,s,1,0,0,0,0);
        syscall(33,s,2,0,0,0,0);
        h_close(m);
        h_close(s);
        syscall(59,binary,args,h_env,0,0,0);
        syscall(60,127,0,0,0,0,0);
    }
    store64(p,pid);
    store64(p+8,-999);
    store64(p+16,h_buffer());
    store64(p+24,h_buffer());
    store64(p+32,m);
    store64(p+40,m);
    store64(p+48,-1);
    store64(p+80,net_now());
    syscall(72,m,4,2048,0,0,0);
    return p;
}
fn hp_pump(p,ms) {
    let end=net_now()+ms;
    while net_now()<end {
        h_pump(p,5);
    }
    return 0;
}
fn hp_clear(p) {
    let b=load64(p+16);
    store64(b+8,0);
    if load64(b) {
        store8(load64(b),0);
    }
    return 0;
}
fn hp_send(p,keys) {
    hp_clear(p);
    h_trigger(p,keys);
    hp_pump(p,120);
    return 0;
}
fn hp_finish(p,keys,signal) {
    if keys {
        h_trigger(p,keys);
    }
    if signal {
        syscall(62,load64(p),signal,0,0,0,0);
    }
    let end=net_now()+3000;
    while h_status(p)==-999 {
        h_pump(p,5);
        h_assert(net_now()<end,"PTY child did not exit");
    }
    hp_pump(p,50);
    h_check(p,0,0);
    let current=h_zero(h_take(64),64);
    h_assert(syscall(16,load64(p+96),0x5401,current,0,0,0)==0,"terminal read after exit failed");
    h_assert(h_bytes(current,load64(p+104),36),"terminal attributes were not restored");
    let escape=h_take(2);
    store8(escape,27);
    store8(escape+1,0);
    h_assert(h_has(h_out(p),h_cat(escape,"[?25h")) && h_has(h_out(p),h_cat(escape,"[?1049l")),"cursor or alternate screen was not restored");
    h_close(load64(p+96));
    h_close(load64(p+40));
    return 0;
}
