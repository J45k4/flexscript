// Chromium DevTools adapter for isolated headless UI tests, entirely Flexscript.
// Not an application WebSocket implementation. Owned loopback Chromium only.
import "../../scripts/lib/json.flex";
global cd_id=0;
global cd_port=0;
global cd_chrome=0;
// Chromium creates this file before its first line is necessarily written.
// A missing/partial/invalid line is not readiness; the caller owns the deadline.
fn cd_port_file(path) {
    let fd=syscall(2,path,0x80000,0,0,0,0);if fd<0{return 0;}
    let text=h_take(65);let n=syscall(0,fd,text,64,0,0,0);h_close(fd);
    if n<=0{return 0;}store8(text+n,0);
    let end=h_find(text,"\n");if end<1 || end>5{return 0;}
    let port=0;let i=0;
    while i<end{let c=load8(text+i);if c<48 || c>57{return 0;}port=port*10+c-48;i=i+1;}
    if port<1 || port>65535{return 0;}return port;
}
fn cd_http_failure(fd,path,reason,b) {
    if fd>=0{h_close(fd);}let preview=h_size(b);if preview>2048{preview=2048;}
    h_die(h_cat3("DevTools HTTP ",reason,h_cat3(" for ",path,h_cat3("; response bytes=",h_int(h_size(b)),h_cat("; response=",h_slice(h_data(b),preview))))));return 0;
}
fn cd_http_header(line,size,name){
    let n=h_len(name);if size<n+1 || load8(line+n)!=58{return 0;}let i=0;
    while i<n{let c=load8(line+i);if c>=65 && c<=90{c=c+32;}if c!=load8(name+i){return 0;}i=i+1;}return 1;
}
fn cd_http_length(fd,path,b,end){
    let text=h_data(b);if end>16384 || !h_starts(text,"HTTP/1.1 200 "){return cd_http_failure(fd,path,"invalid status/header",b);}
    let at=h_find(text,"\r\n")+2;let length=-1;
    while at<end{
        let n=h_find(text+at,"\r\n");let colon=h_find(text+at,":");
        if n<1 || at+n>end || colon<1 || colon>=n{return cd_http_failure(fd,path,"invalid header",b);}
        if cd_http_header(text+at,n,"transfer-encoding"){return cd_http_failure(fd,path,"unsupported transfer encoding",b);}
        if cd_http_header(text+at,n,"content-length"){
            if length>=0{return cd_http_failure(fd,path,"duplicate Content-Length",b);}let i=colon+1;
            while i<n && (load8(text+at+i)==32 || load8(text+at+i)==9){i=i+1;}
            let digits=0;length=0;
            while i<n && load8(text+at+i)>=48 && load8(text+at+i)<=57{
                let digit=load8(text+at+i)-48;if length>(1048576-digit)/10{return cd_http_failure(fd,path,"Content-Length exceeds 1 MiB",b);}
                length=length*10+digit;digits=digits+1;i=i+1;
            }
            while i<n && (load8(text+at+i)==32 || load8(text+at+i)==9){i=i+1;}
            if !digits || i!=n{return cd_http_failure(fd,path,"invalid Content-Length",b);}
        }
        at=at+n+2;
    }return length;
}
fn cd_http_timeout(path,ms) {
    h_assert(ms>0 && ms<=10000,"invalid DevTools HTTP deadline");let deadline=net_now()+ms;let b=h_buffer();
    let connect_ms=ms;if connect_ms>3000{connect_ms=3000;}
    let fd=tcp_connect("127.0.0.1",h_int(cd_port),connect_ms);if fd<0{return cd_http_failure(fd,path,"connection failed",b);}
    let request=h_cat3("PUT ",path," HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
    if !tcp_write(fd,request,h_len(request),deadline){return cd_http_failure(fd,path,"request send failed",b);}let scratch=h_take(4096);let header=-1;let length=-1;
    while 1 {
        // Drain owned browser pipes while its main thread serves this request.
        // EAGAIN is not EOF, and a slow stream never resets the total deadline.
        if cd_chrome{h_pump(cd_chrome,0);}if net_now()>=deadline{return cd_http_failure(fd,path,"read timed out",b);}
        let n=syscall(0,fd,scratch,4096,0,0,0);
        if n>0{
            if h_size(b)+n>1048576{return cd_http_failure(fd,path,"response exceeds 1 MiB",b);}h_append(b,scratch,n);
            if header<0{header=h_find(h_data(b),"\r\n\r\n");if header>=0{length=cd_http_length(fd,path,b,header);}else if h_size(b)>16384{return cd_http_failure(fd,path,"header exceeds 16 KiB",b);}}
            if header>=0 && length>=0{let bytes=h_size(b)-header-4;if bytes>length{return cd_http_failure(fd,path,"body exceeds Content-Length",b);}if bytes==length{h_close(fd);return h_data(b)+header+4;}}
        }
        else if n==0{if header<0{return cd_http_failure(fd,path,"invalid response or early EOF",b);}if length>=0{return cd_http_failure(fd,path,"truncated Content-Length body",b);}h_close(fd);return h_data(b)+header+4;}
        else if n==-11 || n==-4{h_sleep(5);}
        else{return cd_http_failure(fd,path,h_cat("read failed, errno=",h_int(0-n)),b);}
    }return 0;
}
fn cd_http(path){return cd_http_timeout(path,10000);}
fn cd_read(fd,p,n) {
    let end=net_now()+10000;let done=0;
    while done<n {if cd_chrome {h_pump(cd_chrome,0);}let k=syscall(0,fd,p+done,n-done,0,0,0);
        if k>0 {done=done+k;}else if k==-11 || k==-4 {h_assert(net_now()<end,"DevTools read timed out");h_sleep(5);}else {h_die("DevTools stream closed");}}
    return 0;
}
fn cd_open(path) {
    let lib=ffi_open("libcrypto.so.3");h_assert(lib,"browser tests need libcrypto.so.3");let base64=ffi_symbol(lib,"EVP_EncodeBlock");let sha1=ffi_symbol(lib,"SHA1");h_assert(base64 && sha1,"OpenSSL test symbols missing");
    let nonce=h_take(16);h_assert(syscall(318,nonce,16,0,0,0,0)==16,"WebSocket nonce failed");let key=h_take(32);ffi_call_i32(base64,key,nonce,16,0,0,0);
    let challenge=h_cat(key,"258EAFA5-E914-47DA-95CA-C5AB0DC85B11");let digest=h_take(20);ffi_call(sha1,challenge,h_len(challenge),digest,0,0,0);let accept=h_take(32);ffi_call_i32(base64,accept,digest,20,0,0,0);
    let fd=tcp_connect("127.0.0.1",h_int(cd_port),3000);h_assert(fd>=0,"DevTools WebSocket connection failed");
    let request=h_cat3("GET ",path,h_cat3(" HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ",key,"\r\n\r\n"));
    h_assert(tcp_write(fd,request,h_len(request),net_now()+3000),"DevTools upgrade send failed");let b=h_buffer();let one=h_take(1);
    while !h_has(h_data(b),"\r\n\r\n") {h_assert(h_size(b)<8192,"DevTools header limit");cd_read(fd,one,1);h_append(b,one,1);}
    h_assert(h_starts(h_data(b),"HTTP/1.1 101") && h_has(h_data(b),h_cat("Sec-WebSocket-Accept: ",accept)),"DevTools WebSocket verification failed");return fd;
}
fn cd_frame(fd,opcode,text,n) {
    h_assert(n<1048576,"DevTools frame limit");let p=h_take(n+14);store8(p,128|opcode);let at=2;
    if n<126 {store8(p+1,128|n);}else if n<65536 {store8(p+1,254);store8(p+2,n>>8);store8(p+3,n);at=4;}
    else {store8(p+1,255);let i=0;while i<8 {store8(p+2+i,n>>(56-i*8));i=i+1;}at=10;}
    h_assert(syscall(318,p+at,4,0,0,0,0)==4,"WebSocket mask failed");let i=0;while i<n {store8(p+at+4+i,load8(text+i)^load8(p+at+(i&3)));i=i+1;}
    h_assert(tcp_write(fd,p,n+at+4,net_now()+3000),"DevTools frame send failed");return 0;
}
fn cd_message(fd) {
    let message=h_buffer();let started=0;
    while 1 {
        let header=h_take(10);cd_read(fd,header,2);let first=load8(header);let second=load8(header+1);let opcode=first&15;let n=second&127;
        h_assert(!(second&128) && !(first&112),"invalid DevTools frame flags");
        if n==126 {cd_read(fd,header+2,2);n=(load8(header+2)<<8)|load8(header+3);}
        else if n==127 {cd_read(fd,header+2,8);n=0;let i=0;while i<8 {h_assert(n<1048576,"DevTools frame limit");n=(n<<8)|load8(header+2+i);i=i+1;}}
        h_assert(n<=1048576 && h_size(message)+n<=1048576,"DevTools message limit");let data=h_take(n+1);cd_read(fd,data,n);store8(data+n,0);
        if opcode==9 {cd_frame(fd,10,data,n);}else {
            h_assert(opcode==1 || (opcode==0 && started),"DevTools text frame expected");started=1;h_append(message,data,n);if first&128 {return h_data(message);}
        }
    }return 0;
}
fn cd_call(fd,method,params) {
    cd_id=cd_id+1;let id=cd_id;let request=j_object();j_set(request,"id",j_int(id));j_set(request,"method",j_string(method));j_set(request,"params",params);let text=j_dump(request);cd_frame(fd,1,text,h_len(text));
    while 1 {
        let raw=cd_message(fd);
        // Event timestamps may contain fractional numbers; ignore unsolicited
        // events before parsing. Requested results here contain integers/strings.
        if h_starts(raw,"{\"id\":") {let response=j_parse(raw);if j_n(response,"id")==id {h_assert(!j_get(response,"error"),raw);return j_need(response,"result");}}
    }return 0;
}
fn cd_tab(url) {
    let target=j_parse(cd_http(h_cat("/json/new?",url)));let ws=j_s(target,"webSocketDebuggerUrl");let at=h_find(ws,"/devtools/");h_assert(at>=0,"DevTools target URL invalid");
    let tab=h_take(16);store64(tab,cd_open(ws+at));store64(tab+8,j_s(target,"id"));cd_call(load64(tab),"Runtime.enable",j_object());cd_call(load64(tab),"Page.enable",j_object());return tab;
}
fn cd_eval(tab,expression) {
    let params=j_object();j_set(params,"expression",j_string(expression));j_set(params,"returnByValue",j_bool(1));j_set(params,"awaitPromise",j_bool(1));
    let result=cd_call(load64(tab),"Runtime.evaluate",params);h_assert(!j_get(result,"exceptionDetails"),j_dump(result));return j_need(j_need(result,"result"),"value");
}
fn cd_wait(tab,expression) {
    let end=net_now()+10000;while 1 {let value=cd_eval(tab,expression);if j_kind(value)==5 && j_value(value) {return 0;}h_assert(net_now()<end,h_cat("browser condition timed out: ",expression));h_sleep(40);}return 0;
}
fn cd_close(tab) {h_close(load64(tab));cd_http(h_cat("/json/close/",load64(tab+8)));return 0;}
fn cd_screenshot(tab,path,width,height,mobile) {
    cd_call(load64(tab),"Page.bringToFront",j_object());
    let metrics=j_object();j_set(metrics,"width",j_int(width));j_set(metrics,"height",j_int(height));j_set(metrics,"deviceScaleFactor",j_int(1));j_set(metrics,"mobile",j_bool(mobile));cd_call(load64(tab),"Emulation.setDeviceMetricsOverride",metrics);
    cd_eval(tab,"new Promise(resolve=>requestAnimationFrame(()=>{window.scrollTo(0,0);requestAnimationFrame(()=>resolve(true));}))");
    let options=j_object();j_set(options,"format",j_string("png"));j_set(options,"captureBeyondViewport",j_bool(0));let result=cd_call(load64(tab),"Page.captureScreenshot",options);let data=j_s(result,"data");let n=h_len(data);let bytes=h_take(n);let lib=ffi_open("libcrypto.so.3");
    let size=ffi_call_i32(ffi_symbol(lib,"EVP_DecodeBlock"),bytes,data,n,0,0,0);h_assert(size>0,"screenshot decode failed");if load8(data+n-1)==61 {size=size-1;}if load8(data+n-2)==61 {size=size-1;}h_save_bytes(path,bytes,size,420);return 0;
}
