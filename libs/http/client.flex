import "parser.flex";

// Options: timeout ms, response limit, redirects (0..10), HTTPS only,
// CA file (0 = OpenSSL system trust), truncate instead of fail. Free after start.
fn http_client_options() {
    let p=alloc(64);if p<0 {return 0;}
    store64(p,30000);store64(p+8,8388608);return p;
}
fn http_client_options_free(options) {if options {syscall(11,options,64,0,0,0,0);}return 0;}
fn http_client_free(r) {
    if !r {return 0;}hc_drop_io(r);
    if load64(r+56)>0 {syscall(11,load64(r+56),load64(r+72)+1,0,0,0,0);}
    if load64(r+160)>0 {syscall(11,load64(r+160),load64(r+168)+1,0,0,0,0);}
    if load64(r+200)>0 {syscall(11,load64(r+200),1048576,0,0,0,0);}
    syscall(11,r,512,0,0,0,0);return 0;
}
fn hc_request_headers(r,headers) {
    let n=net_length(headers);if n>65536 {return 0;}
    let at=0;let owned=hc_alloc(r,n+3);if !owned {return 0;}let used=0;
    while at<n {
        let start=at;while at<n && hc_token(load8(headers+at)) {at=at+1;}
        if at==start || load8(headers+at)!=58 {return 0;}
        let name=hc_string(r,headers+start,at-start);if !name {return 0;}
        // The library owns connection and message framing. Reject overrides.
        if hc_equal(name,"host") || hc_equal(name,"content-length") || hc_equal(name,"transfer-encoding")
            || hc_equal(name,"connection") || hc_equal(name,"accept-encoding") || hc_equal(name,"expect")
            || hc_equal(name,"upgrade") || hc_equal(name,"proxy-connection") {return 0;}
        if hc_equal(name,"authorization") || hc_equal(name,"proxy-authorization") || hc_equal(name,"cookie") {store64(r+424,1);}
        at=at+1;while at<n && load8(headers+at)!=13 {
            let c=load8(headers+at);if (c<32 && c!=9) || c==127 {return 0;}at=at+1;
        }
        let count=at-start;net_copy(owned+used,headers+start,count);used=used+count;
        store8(owned+used,13);store8(owned+used+1,10);used=used+2;
        if at<n {if at+1>=n || load8(headers+at+1)!=10 {return 0;}at=at+2;}
    }store8(owned+used,0);store64(r+152,owned);return 1;
}
fn hc_wire(r) {
    let line=hc_join(r,load64(r+144)," ",load64(r+120));if !line {return 0;}
    line=hc_join(r,line," HTTP/1.1\r\nHost: ",load64(r+112));if !line {return 0;}
    line=hc_join(r,line,"\r\nConnection: close\r\nAccept-Encoding: identity\r\n",load64(r+152));if !line {return 0;}
    if load64(r+432) {
        let number=hc_number(r,load64(r+168));if !number {return 0;}
        line=hc_join(r,line,"Content-Length: ",number);if !line {return 0;}
        line=hc_join(r,line,"\r\n","");if !line {return 0;}
    }
    line=hc_join(r,line,"\r\n","");if !line {return 0;}
    store64(r+216,line);store64(r+224,net_length(line));return 1;
}
fn http_client_start(method,url,headers,body,size,options) {
    http_client_message="Invalid HTTP client request or options";
    if !method || !url || !options || size<0 || size>67108864 || (size && !body) {return 0;}
    let timeout=load64(options);let limit=load64(options+8);let redirects=load64(options+16);
    if timeout<1 || timeout>3600000 || limit<0 || limit>67108864 || redirects<0 || redirects>10 {return 0;}
    let length=net_length(method);if length<1 || length>32 || net_equal(method,"CONNECT") {return 0;}
    let i=0;while i<length {if !hc_token(load8(method+i)) {return 0;}i=i+1;}
    let r=alloc(512);if r<0 {return 0;}store64(r+8,-1);store64(r+336,-1);
    let arena=alloc(1048576);if arena<0 {syscall(11,r,512,0,0,0,0);return 0;}store64(r+200,arena);
    store64(r+32,net_now()+timeout);store64(r+72,limit);store64(r+80,load64(options+40));
    store64(r+184,redirects);store64(r+448,redirects);store64(r+440,load64(options+24));
    store64(r+400,hc_alloc(r,96));store64(r+232,hc_alloc(r,16384));store64(r+240,hc_alloc(r,8193));
    store64(r+352,hc_alloc(r,800));store64(r+472,hc_alloc(r,2048));
    store64(r+144,hc_string(r,method,length));store64(r+416,net_equal(method,"HEAD"));
    if load64(options+32) {
        let ca=load64(options+32);let n=net_length(ca);
        if n>4096 {http_client_free(r);return 0;}store64(r+392,hc_string(r,ca,n));
    }
    if !headers {headers="";}
    if !hc_url(r,url) || !hc_request_headers(r,headers) {http_client_free(r);return 0;}
    let output=alloc(limit+1);if output<0 {http_client_free(r);return 0;}store64(r+56,output);
    if body {
        let owned=alloc(size+1);if owned<0 {http_client_free(r);return 0;}
        net_copy(owned,body,size);store64(r+160,owned);store64(r+168,size);store64(r+432,1);
    }
    hc_reset_response(r);
    if !hc_wire(r) {http_client_free(r);return 0;}
    if hc_resolve(r)<0 {http_client_message=load64(r+40);http_client_free(r);return 0;}return r;
}
// One bounded scheduling quantum: no blocking DNS, connect, handshake or read.
// Call for every active request, including streams and requests being cancelled.
fn http_client_step(r) {
    if !r {return -1;}let state=load64(r);if state==6 {return 1;}if state==7 {return -1;}
    let now=hc_now(r);if now<0 || now>=load64(r+32) {return hc_fail(r,"HTTP request timed out");}
    if load64(r+328)>0 && state!=1 {
        let pid=load64(r+328);if syscall(61,pid,0,1,0,0,0)==pid {store64(r+328,0);}
    }
    if state==1 {hc_dns_step(r);}else if state==2 {hc_connect_step(r);}
    else if state==3 {hc_tls_step(r);}else if state==4 {hc_send_step(r);}
    else if state==5 {hc_receive_step(r);}
    state=load64(r);if state==6 {return 1;}if state==7 {return -1;}return 0;
}
fn http_client_cancel(r) {if r && load64(r)<6 {hc_fail(r,"HTTP request cancelled");}return 0;}
fn http_client_allow_truncation(r,enabled) {store64(r+80,enabled!=0);return 0;}
fn http_client_wait(r) {
    if !r {return -1;}let result=http_client_step(r);
    while !result {
        let p=load64(r+400)+56;store64(p,0);store64(p+8,1000000);
        syscall(35,p,0,0,0,0,0);result=http_client_step(r);
    }return result;
}
fn http_client_data(r) {return load64(r+56);}
fn http_client_size(r) {return load64(r+64);}
fn http_client_status(r) {return load64(r+48);}
fn http_client_url(r) {return load64(r+96);}
fn http_client_error(r) {return load64(r+40);}
fn http_client_truncated(r) {return load64(r+88);}
fn http_client_header(r,name) {
    let i=0;while i<load64(r+464) {let pair=load64(r+472)+i*16;if hc_equal(load64(pair),name) {return load64(pair+8);}i=i+1;}return 0;
}
