// Local test server: Flexscript owns TCP/processes; OpenSSL supplies TLS.
import "../../lib/tls.flex";
import "json.flex";
global sf_context=0;
global sf_accept=0;
global sf_shutdown=0;
global sf_listener=0;
global sf_port=0;
global sf_url=0;
global sf_directory=0;
global sf_mode=0;
fn sf_ssl(name) {
    let lib=ffi_open("libssl.so.3");
    h_assert(lib,"OpenSSL 3 is required for TLS fixtures");
    let symbol=ffi_symbol(lib,name);
    h_assert(symbol,h_cat("missing TLS symbol: ",name));
    return symbol;
}
fn sf_cert(dir) {
    let args=h_args("openssl","req","-x509","-newkey","rsa:2048","-nodes");
    h_add(args,"-keyout");
    h_add(args,h_join(dir,"localhost.key"));
    h_add(args,"-out");
    h_add(args,h_join(dir,"localhost.pem"));
    h_add(args,"-days");
    h_add(args,"1");
    h_add(args,"-subj");
    h_add(args,"/CN=localhost");
    h_add(args,"-addext");
    h_add(args,"subjectAltName=DNS:localhost");
    h_ok(args);
    return 0;
}
fn sf_port_of(fd) {
    let address=h_take(16);
    let size=h_take(8);
    store64(size,16);
    h_assert(syscall(51,fd,address,size,0,0,0)==0,"getsockname failed");
    return (load8(address+2)<<8)|load8(address+3);
}
fn sf_start(dir,mode) {
    sf_directory=dir;
    sf_mode=mode;
    sf_listener=tcp_listen("127.0.0.1","0",128);
    h_assert(sf_listener>=0,net_message);
    sf_port=sf_port_of(sf_listener);
    sf_url=h_cat("https://localhost:",h_int(sf_port));
    sf_context=0;
    if mode!=3 {
        sf_cert(dir);
        h_assert(tls_init(),net_message);
        sf_accept=sf_ssl("SSL_accept");
        sf_shutdown=sf_ssl("SSL_shutdown");
        let method=ffi_call(sf_ssl("TLS_server_method"),0,0,0,0,0,0);
        sf_context=ffi_call(tls_ctx_new,method,0,0,0,0,0);
        h_assert(sf_context,"TLS server context failed");
        h_assert(ffi_call_i32(sf_ssl("SSL_CTX_use_certificate_file"),sf_context,h_join(dir,"localhost.pem"),1,0,0,0)==1 && ffi_call_i32(sf_ssl("SSL_CTX_use_PrivateKey_file"),sf_context,h_join(dir,"localhost.key"),1,0,0,0)==1 && ffi_call_i32(sf_ssl("SSL_CTX_check_private_key"),sf_context,0,0,0,0,0)==1,"TLS server certificate failed");
    }
    let pid=syscall(57,0,0,0,0,0,0);
    h_assert(pid>=0,"fixture fork failed");
    if pid==0 {
        syscall(157,1,15,0,0,0,0);
        syscall(109,0,0,0,0,0,0);
        let mark=h_mark();
        while 1 {
            let fd=tcp_accept(sf_listener,net_now()+1000);
            if fd>=0 {
                let worker=syscall(57,0,0,0,0,0,0);
                if worker==0 {
                    syscall(157,1,15,0,0,0,0);
                    h_close(sf_listener);
                    sf_serve(fd);
                    syscall(60,0,0,0,0,0,0);
                }
                h_close(fd);
            }
            let status=h_take(8);
            while syscall(61,-1,status,1,0,0,0)>0 {
            }
            h_reset(mark);
        }
    }
    h_close(sf_listener);
    if sf_context {
        ffi_call(tls_ctx_free,sf_context,0,0,0,0,0);
    }
    let process=h_zero(h_take(96),96);
    store64(process,pid);
    store64(process+8,-999);
    store64(process+32,-1);
    store64(process+40,-1);
    store64(process+48,-1);
    return process;
}
fn sf_write(session,p,n) {
    return tls_write(session,p,n);
}
fn sf_payload(session,content,n,status,headers) {
    let head=h_cat3("HTTP/1.1 ",h_int(status)," Response\r\nContent-Length: ");
    head=h_cat3(head,h_int(n),"\r\nConnection: close\r\n");
    head=h_cat3(head,headers,"\r\n");
    if sf_write(session,head,h_len(head)) {
        sf_write(session,content,n);
    }
    return 0;
}
fn sf_ends(s,end) {
    let n=h_len(s);
    let m=h_len(end);
    return n>=m && h_bytes(s+n-m,end,m);
}
fn sf_append_file(path,text) {
    let fd=syscall(2,path,1089,384,0,0,0);
    h_assert(fd>=0,"fixture log failed");
    h_write(fd,text,h_len(text));
    h_close(fd);
    return 0;
}
fn sf_serve(fd) {
    if sf_mode==3 {
        let p=h_take(16);
        let n=tcp_read(fd,p,16,net_now()+2000);
        if n>0 {
            if n==4 && h_bytes(p,"slow",4) {
                h_sleep(300);
            }else {
                let i=0;
                while i<n {
                    tcp_write(fd,p+i,1,net_now()+1000);
                    i=i+1;
                }
            }
        }
        h_close(fd);
        return 0;
    }
    let ssl=ffi_call(tls_new,sf_context,0,0,0,0,0);
    if !ssl {
        h_close(fd);
        return 0;
    }
    let session=h_zero(alloc(32),32);
    store64(session,ssl);
    store64(session+16,fd);
    store64(session+24,net_now()+10000);
    if ffi_call_i32(tls_fd,ssl,fd,0,0,0,0)!=1 {
        tls_close(session);
        return 0;
    }
    let accepted=0;
    let more=1;
    while !accepted && more {
        let n=ffi_call_i32(sf_accept,ssl,0,0,0,0,0);
        if n==1 {
            accepted=1;
        }else if !tls_retry(session,n) {
            more=0;
        }
    }
    if !accepted {
        tls_close(session);
        return 0;
    }
    let request=h_buffer();
    let p=h_take(4096);
    while !h_has(h_data(request),"\r\n\r\n") && h_size(request)<65536 {
        let n=tls_read(session,p,4096);
        if n<=0 {
            tls_close(session);
            return 0;
        }
        h_append(request,p,n);
    }
    let text=h_data(request);
    if !h_starts(text,"GET ") {
        tls_close(session);
        return 0;
    }
    let at=4;
    while load8(text+at) && load8(text+at)!=32 {
        at=at+1;
    }
    let path=h_slice(text+4,at-4);
    if sf_mode==1 {
        sf_network(session,path);
    }else {
        sf_upgrade(session,path);
    }
    ffi_call_i32(sf_shutdown,ssl,0,0,0,0,0);
    tls_close(session);
    return 0;
}
fn sf_network(session,path) {
    let body="hello https\n";
    if h_equal(path,"/slow") {
        h_sleep(400);
        sf_payload(session,body,12,200,"");
    }else if h_equal(path,"/plain") {
        sf_payload(session,body,12,200,"");
    }else if h_equal(path,"/large") {
        let p=h_take(25600);
        let i=0;
        while i<25600 {
            store8(p+i,i%256);
            i=i+1;
        }
        sf_payload(session,p,25600,200,"");
    }else if h_equal(path,"/redirect") {
        sf_payload(session,"",0,302,"Location: /plain\r\n");
    }else if h_equal(path,"/absolute") {
        sf_payload(session,"",0,307,h_cat3("Location: ",sf_url,"/plain\r\n"));
    }else if h_equal(path,"/loop") {
        sf_payload(session,"",0,302,"Location: /loop\r\n");
    }else if h_equal(path,"/downgrade") {
        sf_payload(session,"",0,302,"Location: http://localhost/plain\r\n");
    }else {
        let file=h_join(sf_directory,h_cat("responses",path));
        if h_exists(file) {
            let p=h_read(file);
            let n=h_file_size;
            if h_equal(path,"/fragmented") {
                let i=0;
                while i<n {
                    if !sf_write(session,p+i,1) {
                        return 0;
                    }
                    i=i+1;
                }
            }else {
                sf_write(session,p,n);
            }
        }
    }
    return 0;
}
fn sf_upgrade(session,path) {
    let current=h_trim(h_read(h_join(sf_directory,"current")));
    let name="binary";
    if sf_ends(path,"/releases/latest") {
        name="metadata";
    }else if sf_ends(path,"/SHA256SUMS") {
        name="manifest";
    }else if sf_ends(path,"/SHA256SUMS.sig") {
        name="signature";
    }
    sf_append_file(h_join(current,"requests"),h_cat3(sf_url,path,"\n"));
    let control=j_parse(h_read(h_join(current,"control")));
    let fail=j_get(control,"fail");
    if fail && h_equal(j_value(fail),name) {
        sf_payload(session,"download failed",15,503,"");
        return 0;
    }
    if h_equal(name,"binary") {
        let target=j_s(control,"target");
        if j_get(control,"replace") {
            let p=h_read(h_join(current,"replacement"));
            let temp=h_join(current,"replacement-install");
            h_save_bytes(temp,p,h_file_size,493);
            syscall(90,temp,493,0,0,0,0);
            h_assert(syscall(82,temp,target,0,0,0,0)==0,"fixture replacement failed");
        }
        if j_get(control,"collision") {
            let end=net_now()+5000;
            while !h_exists(h_join(current,"parent-pid")) && net_now()<end {
                h_sleep(10);
            }
            let pid=h_trim(h_read(h_join(current,"parent-pid")));
            let stage=h_cat3(target,".upgrade.",pid);
            h_mkdir(stage);
            h_save(h_join(stage,"sentinel"),"keep me");
        }
    }
    let hold=j_get(control,"hold");
    if hold && h_equal(j_value(hold),name) {
        h_save(h_join(current,"ready"),"");
        let end=net_now()+15000;
        while !h_exists(h_join(current,"continue")) && net_now()<end {
            h_sleep(10);
        }
    }
    let data=h_read(h_join(current,name));
    sf_payload(session,data,h_file_size,200,"");
    return 0;
}
