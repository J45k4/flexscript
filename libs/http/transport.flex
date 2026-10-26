import "url.flex";
global hc_tls_ca=0;
global hc_tls_param=0;
global hc_tls_ip=0;
global hc_tls_clear=0;

// The system resolver runs in a short-lived, owned helper process. Polling a
// request never blocks in getaddrinfo, and cancel/timeout reaps the helper.
// The helper has no application descriptors or credentials in its output:
// only up to sixteen IPv4/IPv6 socket addresses cross its private pipe.
fn hc_resolve(r) {
    if !net_init() {return hc_fail(r,"Cannot initialize the system resolver");}
    let p=load64(r+400);
    if syscall(293,p,0x80800,0,0,0,0)<0 {return hc_fail(r,"Cannot create resolver channel");}
    let input=load64(p)&0xffffffff;let output=(load64(p)>>32)&0xffffffff;
    let parent=syscall(39,0,0,0,0,0,0);let pid=syscall(57,0,0,0,0,0,0);
    if !pid {
        if syscall(157,1,9,0,0,0,0)<0 {syscall(60,1,0,0,0,0,0);}
        if syscall(110,0,0,0,0,0,0)!=parent {syscall(60,1,0,0,0,0,0);}
        if output!=3 {if syscall(33,output,3,0,0,0,0)!=3 {syscall(60,1,0,0,0,0,0);}}
        if syscall(436,4,0xffffffff,0,0,0,0)<0 {syscall(60,1,0,0,0,0,0);}
        syscall(3,0,0,0,0,0,0);syscall(3,1,0,0,0,0,0);syscall(3,2,0,0,0,0,0);
        let hints=alloc(48);let result=alloc(8);let packet=load64(r+352);
        if hints<0 || result<0 {syscall(60,1,0,0,0,0,0);}
        store64(hints,1024);store64(hints+8,1);
        let code=ffi_call_i32(net_resolve,load64(r+104),load64(r+136),hints,result,0,0);
        let count=0;
        if !code {
            let address=load64(result);
            while address && count<16 {
                let family=load64(address)>>32;let size=load64(address+16)&0xffffffff;
                if (family==2 && size==16) || (family==10 && size==28) {
                    let row=packet+8+count*48;store64(row,family);store64(row+8,size);
                    net_copy(row+16,load64(address+24),size);count=count+1;
                }address=load64(address+40);
            }
        }
        store64(packet,count);let written=syscall(1,3,packet,8+count*48,0,0,0);
        while written==-4 {written=syscall(1,3,packet,8+count*48,0,0,0);}
        syscall(60,0,0,0,0,0,0);
    }
    tcp_close(output);
    if pid<0 {tcp_close(input);return hc_fail(r,"Cannot start system resolver");}
    store64(r+328,pid);store64(r+336,input);store64(r+344,0);
    store64(r+360,0);store64(r+368,0);store64(r,1);return 0;
}
fn hc_dns_step(r) {
    let used=load64(r+344);let n=syscall(0,load64(r+336),load64(r+352)+used,800-used,0,0,0);
    if n>0 {store64(r+344,used+n);if used+n==800 {return hc_fail(r,"Invalid resolver response");}return 0;}
    if n==-11 || n==-4 {return 0;}
    tcp_close(load64(r+336));store64(r+336,-1);
    let count=load64(load64(r+352));
    if n<0 || count<1 || count>16 || used!=8+count*48 {return hc_fail(r,"Cannot resolve HTTP host");}
    let pid=load64(r+328);if syscall(61,pid,0,1,0,0,0)==pid {store64(r+328,0);}
    store64(r+360,count);return hc_connect_next(r);
}
fn hc_connect_next(r) {
    if load64(r+8)>=0 {tcp_close(load64(r+8));store64(r+8,-1);}
    let index=load64(r+368);
    while index<load64(r+360) {
        let row=load64(r+352)+8+index*48;index=index+1;store64(r+368,index);
        let fd=syscall(41,load64(row),0x80801,0,0,0,0);
        if fd>=0 {
            let code=syscall(42,fd,row+16,load64(row+8),0,0,0);
            if code==0 || code==-115 {
                store64(r+8,fd);store64(r,2);
                if !code {return hc_connected(r);}return 0;
            }tcp_close(fd);
        }
    }return hc_fail(r,"Cannot connect to HTTP host");
}
fn hc_connect_step(r) {
    if !hc_ready(r,load64(r+8),4) {return 0;}let p=load64(r+400);
    store64(p+8,0);store64(p+16,4);
    if syscall(55,load64(r+8),1,4,p+8,p+16,0)<0 || load64(p+8)!=0 {return hc_connect_next(r);}
    return hc_connected(r);
}
fn hc_connected(r) {
    store64(r+376,0);if !load64(r+128) {store64(r,4);return 0;}
    if !tls_init() {return hc_fail(r,"OpenSSL 3 is required for HTTPS");}
    if !hc_tls_clear {
        hc_tls_ca=ffi_symbol(tls_library,"SSL_CTX_load_verify_locations");
        hc_tls_param=ffi_symbol(tls_library,"SSL_get0_param");
        hc_tls_ip=ffi_symbol(tls_library,"X509_VERIFY_PARAM_set1_ip_asc");
        hc_tls_clear=ffi_symbol(tls_library,"ERR_clear_error");
    }
    if !hc_tls_ca || !hc_tls_param || !hc_tls_ip || !hc_tls_clear {return hc_fail(r,"OpenSSL is missing required verification functions");}
    let method=ffi_call(tls_method,0,0,0,0,0,0);
    let ctx=ffi_call(tls_ctx_new,method,0,0,0,0,0);store64(r+24,ctx);
    if !ctx {return hc_fail(r,"Cannot create TLS context");}
    ffi_call(tls_ctx_verify,ctx,1,0,0,0,0);
    let trusted=0;let ca=load64(r+392);
    if ca && load8(ca) {
        trusted=ffi_call_i32(hc_tls_ca,ctx,ca,0,0,0,0);
    }else {trusted=ffi_call_i32(tls_ctx_paths,ctx,0,0,0,0,0);}
    if trusted!=1 || ffi_call(tls_ctx_ctrl,ctx,123,0x303,0,0,0)!=1 {return hc_fail(r,"Cannot load trusted TLS certificates");}
    let ssl=ffi_call(tls_new,ctx,0,0,0,0,0);store64(r+16,ssl);
    if !ssl {return hc_fail(r,"Cannot create TLS session");}
    let host=load64(r+104);let scratch=load64(r+400);let inet=ffi_symbol(net_libc,"inet_pton");
    let ip=ffi_call_i32(inet,2,host,scratch,0,0,0)==1;
    if !ip {ip=ffi_call_i32(inet,10,host,scratch,0,0,0)==1;}
    let verified=0;
    if ip {
        let params=ffi_call(hc_tls_param,ssl,0,0,0,0,0);
        verified=ffi_call_i32(hc_tls_ip,params,host,0,0,0,0);
    }else {
        verified=ffi_call_i32(tls_host,ssl,host,0,0,0,0);
        if ffi_call(tls_ctrl,ssl,55,0,host,0,0)!=1 {verified=0;}
    }
    if verified!=1 || ffi_call_i32(tls_fd,ssl,load64(r+8),0,0,0,0)!=1 {return hc_fail(r,"Cannot configure verified TLS");}
    store64(r,3);return 0;
}
// OpenSSL's socket BIO uses write(). Block SIGPIPE on this thread for the call,
// consume only a newly generated pending SIGPIPE, then restore the caller mask.
// No process-wide signal disposition is changed. SSL_get_error is immediate,
// before other OpenSSL calls or syscalls can disturb its error information.
fn hc_ssl(r,operation,bytes,n) {
    let p=load64(r+400);store64(p+48,4096);
    syscall(127,p+40,8,0,0,0,0);syscall(14,0,p+48,p+32,8,0,0);
    ffi_call(hc_tls_clear,0,0,0,0,0,0);
    let result=0;
    if operation==0 {result=ffi_call_i32(tls_handshake,load64(r+16),0,0,0,0,0);}
    else if operation==1 {result=ffi_call_i32(tls_write_ex,load64(r+16),bytes,n,p+24,0,0);}
    else {result=ffi_call_i32(tls_read_ex,load64(r+16),bytes,n,p+24,0,0);}
    let error=0;if result!=1 {error=ffi_call_i32(tls_get_error,load64(r+16),result,0,0,0,0);}
    if !(load64(p+32)&4096) && !(load64(p+40)&4096) {
        store64(p+56,0);store64(p+64,0);syscall(128,p+48,0,p+56,8,0,0);
    }syscall(14,2,p+32,0,8,0,0);
    store64(r+376,0);
    if result==1 {if !operation {return 1;}return load64(p+24);}
    if error==2 {store64(r+376,1);return -2;}
    if error==3 {store64(r+376,4);return -2;}
    if error==6 && operation==2 {return 0;}
    return -1;
}
fn hc_tls_step(r) {
    if !hc_ready(r,load64(r+8),load64(r+376)) {return 0;}
    let result=hc_ssl(r,0,0,0);if result==-2 {return 0;}
    if result!=1 || ffi_call(tls_verify_result,load64(r+16),0,0,0,0,0)!=0 {
        return hc_fail(r,"TLS connection or certificate verification failed");
    }store64(r,4);return 0;
}
fn hc_send_step(r) {
    let at=load64(r+176);let header=load64(r+224);
    if at>=header+load64(r+168) {store64(r,5);store64(r+376,0);return 0;}
    if !hc_ready(r,load64(r+8),load64(r+376)) {return 0;}
    let bytes=load64(r+216)+at;let n=header-at;
    if at>=header {bytes=load64(r+160)+at-header;n=load64(r+168)-(at-header);}
    if n>16384 {n=16384;}let sent=0;
    if load64(r+16) {sent=hc_ssl(r,1,bytes,n);if sent==-2 {return 0;}}
    else {sent=syscall(44,load64(r+8),bytes,n,16384,0,0);if sent==-11 || sent==-4 {store64(r+376,4);return 0;}}
    if sent<=0 {return hc_fail(r,"HTTP request write failed");}
    store64(r+176,at+sent);store64(r+376,0);return 0;
}
