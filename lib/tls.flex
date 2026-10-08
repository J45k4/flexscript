import "net.flex";
global tls_library=0;
global tls_method=0;
global tls_ctx_new=0;
global tls_ctx_free=0;
global tls_ctx_verify=0;
global tls_ctx_paths=0;
global tls_ctx_ctrl=0;
global tls_new=0;
global tls_free=0;
global tls_fd=0;
global tls_host=0;
global tls_ctrl=0;
global tls_handshake=0;
global tls_read_ex=0;
global tls_write_ex=0;
global tls_get_error=0;
global tls_verify_result=0;
fn tls_init() {
    if tls_library {return 1;}
    let lib=ffi_open("libssl.so.3");if !lib {net_message="OpenSSL 3 (libssl.so.3) is required for HTTPS.";return 0;}
    tls_method=ffi_symbol(lib,"TLS_client_method");tls_ctx_new=ffi_symbol(lib,"SSL_CTX_new");
    tls_ctx_free=ffi_symbol(lib,"SSL_CTX_free");tls_ctx_verify=ffi_symbol(lib,"SSL_CTX_set_verify");
    tls_ctx_paths=ffi_symbol(lib,"SSL_CTX_set_default_verify_paths");tls_ctx_ctrl=ffi_symbol(lib,"SSL_CTX_ctrl");
    tls_new=ffi_symbol(lib,"SSL_new");tls_free=ffi_symbol(lib,"SSL_free");
    tls_fd=ffi_symbol(lib,"SSL_set_fd");tls_host=ffi_symbol(lib,"SSL_set1_host");
    tls_ctrl=ffi_symbol(lib,"SSL_ctrl");tls_handshake=ffi_symbol(lib,"SSL_connect");
    tls_read_ex=ffi_symbol(lib,"SSL_read_ex");tls_write_ex=ffi_symbol(lib,"SSL_write_ex");
    tls_get_error=ffi_symbol(lib,"SSL_get_error");tls_verify_result=ffi_symbol(lib,"SSL_get_verify_result");
    if !tls_method || !tls_ctx_new || !tls_ctx_free || !tls_ctx_verify || !tls_ctx_paths || !tls_ctx_ctrl
        || !tls_new || !tls_free || !tls_fd || !tls_host || !tls_ctrl || !tls_handshake
        || !tls_read_ex || !tls_write_ex || !tls_get_error || !tls_verify_result {
        net_message="OpenSSL 3 is missing a required TLS symbol.";return 0;
    }
    tls_library=lib;return 1;
}
// Session records: SSL pointer, SSL_CTX pointer, socket, absolute deadline.
fn tls_retry(session,result) {
    let error=ffi_call_i32(tls_get_error,load64(session),result,0,0,0,0);
    if error==2 {return net_wait(load64(session+16),1,load64(session+24));}
    if error==3 {return net_wait(load64(session+16),4,load64(session+24));}
    net_message="TLS handshake or I/O failed; certificate verification is required.";return 0;
}
fn tls_close(session) {
    if session {
        if load64(session) {ffi_call(tls_free,load64(session),0,0,0,0,0);}
        if load64(session+8) {ffi_call(tls_ctx_free,load64(session+8),0,0,0,0,0);}
        if load64(session+16)>=0 {tcp_close(load64(session+16));}
        syscall(11,session,32,0,0,0,0);
    }
    return 0;
}
fn tls_connect(host,service,timeout) {
    if !tls_init() {return 0;}
    let session=alloc(32);if session<0 {return 0;}store64(session+16,-1);
    store64(session+24,net_now()+timeout);
    let method=ffi_call(tls_method,0,0,0,0,0,0);
    let ctx=ffi_call(tls_ctx_new,method,0,0,0,0,0);store64(session+8,ctx);
    net_message="Cannot configure trusted TLS certificates.";
    if !ctx {tls_close(session);return 0;}
    ffi_call(tls_ctx_verify,ctx,1,0,0,0,0); // SSL_VERIFY_PEER
    if ffi_call_i32(tls_ctx_paths,ctx,0,0,0,0,0)!=1
        || ffi_call(tls_ctx_ctrl,ctx,123,0x303,0,0,0)!=1 {tls_close(session);return 0;}
    let ssl=ffi_call(tls_new,ctx,0,0,0,0,0);store64(session,ssl);
    if !ssl || ffi_call_i32(tls_host,ssl,host,0,0,0,0)!=1
        || ffi_call(tls_ctrl,ssl,55,0,host,0,0)!=1 {tls_close(session);return 0;}
    let fd=tcp_connect(host,service,timeout);store64(session+16,fd);
    if fd<0 || ffi_call_i32(tls_fd,ssl,fd,0,0,0,0)!=1 {tls_close(session);return 0;}
    let connected=0;
    while !connected {
        let result=ffi_call_i32(tls_handshake,ssl,0,0,0,0,0);
        if result==1 {connected=1;}else if !tls_retry(session,result) {tls_close(session);return 0;}
    }
    if ffi_call(tls_verify_result,ssl,0,0,0,0,0)!=0 {net_message="TLS certificate verification failed.";tls_close(session);return 0;}
    return session;
}
fn tls_read(session,bytes,size) {
    let received=alloc(8);if received<0 {return -1;}let more=1;let n=-1;
    while more {
        let result=ffi_call_i32(tls_read_ex,load64(session),bytes,size,received,0,0);
        if result==1 {n=load64(received);more=0;}
        else {
            let error=ffi_call_i32(tls_get_error,load64(session),result,0,0,0,0);
            if error==6 {n=0;more=0;}
            else if !tls_retry(session,result) {more=0;}
        }
    }
    syscall(11,received,8,0,0,0,0);return n;
}
fn tls_write(session,bytes,size) {
    let written=alloc(8);if written<0 {return 0;}let sent=0;let ok=1;
    while sent<size && ok {
        let result=ffi_call_i32(tls_write_ex,load64(session),bytes+sent,size-sent,written,0,0);
        if result==1 {let n=load64(written);if n<=0 {ok=0;}else {sent=sent+n;}}
        else if !tls_retry(session,result) {ok=0;}
    }
    syscall(11,written,8,0,0,0,0);return ok;
}
