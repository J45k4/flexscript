// TCP sockets are owned here; libc is used only for the system DNS resolver.
global net_libc=0;
global net_resolve=0;
global net_free_addresses=0;
global net_message=0;
fn net_length(text) {let n=0;while load8(text+n) {n=n+1;}return n;}
fn net_equal(a,b) {
    let i=0;while load8(a+i) && load8(a+i)==load8(b+i) {i=i+1;}
    return load8(a+i)==load8(b+i);
}
fn net_copy(to,from,n) {let i=0;while i<n {store8(to+i,load8(from+i));i=i+1;}return 0;}
fn net_now() {
    let clock=alloc(16);if clock<0 {return -1;}
    if syscall(228,1,clock,0,0,0,0)<0 {return -1;}
    let result=load64(clock)*1000+load64(clock+8)/1000000;
    syscall(11,clock,16,0,0,0,0);return result;
}
fn net_wait(fd,events,deadline) {
    let poll=alloc(8);if poll<0 {return 0;}let result=0;let more=1;
    while more {
        let now=net_now();let left=deadline-now;
        if now<0 || left<=0 {net_message="Network operation timed out.";more=0;}
        else {
            store64(poll,(fd&0xffffffff)|(events<<32));
            let ready=syscall(7,poll,1,left,0,0,0);
            if ready>0 {result=1;more=0;}
            else if ready!=-4 {net_message="Network operation timed out or polling failed.";more=0;}
        }
    }
    syscall(11,poll,8,0,0,0,0);return result;
}
fn net_init() {
    if net_libc {return 1;}
    net_libc=ffi_open("libc.so.6");if !net_libc {net_message="Cannot load the system resolver.";return 0;}
    net_resolve=ffi_symbol(net_libc,"getaddrinfo");
    net_free_addresses=ffi_symbol(net_libc,"freeaddrinfo");
    return net_resolve && net_free_addresses;
}
fn tcp_connect(host,service,timeout) {
    net_message="Cannot resolve or connect to host.";
    if timeout<=0 || !net_init() {return -1;}
    let deadline=net_now()+timeout;let hints=alloc(48);let result=alloc(8);
    if hints<0 || result<0 {return -1;}
    store64(hints+8,1); // ai_socktype=SOCK_STREAM, ai_protocol=0
    let code=ffi_call_i32(net_resolve,host,service,hints,result,0,0);
    syscall(11,hints,48,0,0,0,0);
    if code {syscall(11,result,8,0,0,0,0);return -1;}
    let addresses=load64(result);let address=addresses;let connected=-1;
    while address && connected<0 {
        let family=load64(address)>>32;let fd=syscall(41,family,0x80801,0,0,0,0);
        if fd>=0 {
            let status=syscall(42,fd,load64(address+24),load64(address+16)&0xffffffff,0,0,0);
            if status==-115 && net_wait(fd,4,deadline) {
                let error=alloc(8);let size=alloc(8);
                if error>=0 && size>=0 {
                    store64(size,4);status=syscall(55,fd,1,4,error,size,0);
                    if status==0 && load64(error)!=0 {status=-1;}
                } else {status=-1;}
                if error>=0 {syscall(11,error,8,0,0,0,0);}
                if size>=0 {syscall(11,size,8,0,0,0,0);}
            }
            if status==0 {connected=fd;}else {syscall(3,fd,0,0,0,0,0);}
        }
        address=load64(address+40);
    }
    ffi_call(net_free_addresses,addresses,0,0,0,0,0);syscall(11,result,8,0,0,0,0);
    return connected;
}
fn tcp_read(fd,bytes,size,deadline) {
    while 1 {
        let n=syscall(0,fd,bytes,size,0,0,0);
        if n>=0 {return n;}
        if n!=-4 && n!=-11 {net_message="TCP read failed.";return -1;}
        if n==-11 && !net_wait(fd,1,deadline) {return -1;}
    }
    return -1;
}
fn tcp_write(fd,bytes,size,deadline) {
    let sent=0;while sent<size {
        let n=syscall(44,fd,bytes+sent,size-sent,16384,0,0);
        if n>0 {sent=sent+n;}
        else if n==-11 {if !net_wait(fd,4,deadline) {return 0;}}
        else if n!=-4 {net_message="TCP write failed.";return 0;}
    }
    return 1;
}
fn tcp_close(fd) {return syscall(3,fd,0,0,0,0,0);}
fn tcp_listen(host,service,backlog) {
    net_message="Cannot bind or listen on TCP address.";
    if backlog<=0 || !net_init() {return -1;}
    let hints=alloc(48);let result=alloc(8);let reuse=alloc(4);
    if hints<0 || result<0 || reuse<0 {return -1;}
    store64(hints,1);store64(hints+8,1);store8(reuse,1);
    let code=ffi_call_i32(net_resolve,host,service,hints,result,0,0);
    syscall(11,hints,48,0,0,0,0);let listener=-1;
    if !code {
        let addresses=load64(result);let address=addresses;
        while address && listener<0 {
            let fd=syscall(41,load64(address)>>32,0x80801,0,0,0,0);
            if fd>=0 {
                if syscall(54,fd,1,2,reuse,4,0)==0
                    && syscall(49,fd,load64(address+24),load64(address+16)&0xffffffff,0,0,0)==0
                    && syscall(50,fd,backlog,0,0,0,0)==0 {listener=fd;}
                else {tcp_close(fd);}
            }
            address=load64(address+40);
        }
        ffi_call(net_free_addresses,addresses,0,0,0,0,0);
    }
    syscall(11,result,8,0,0,0,0);syscall(11,reuse,4,0,0,0,0);return listener;
}
fn tcp_accept(listener,deadline) {
    while 1 {
        let fd=syscall(288,listener,0,0,0x80800,0,0);if fd>=0 {return fd;}
        if fd==-11 {if !net_wait(listener,1,deadline) {return -1;}}
        else if fd!=-4 {net_message="TCP accept failed.";return -1;}
    }
    return -1;
}
