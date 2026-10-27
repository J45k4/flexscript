import "../../lib/tls.flex";

global http_client_message=0;
// Request (512 bytes), private to the implementation:
// 0 state; 8 fd; 16 SSL; 24 SSL_CTX; 32 deadline; 40 error; 48 status;
// 56 output; 64 output size; 72 limit; 80 allow truncation; 88 truncated;
// 96 URL; 104 host; 112 authority; 120 target; 128 TLS; 136 service;
// 144 method; 152 request headers; 160 upload; 168 upload size; 176 sent;
// 184 redirects left; 192 ever TLS; 200 arena; 208 arena used;
// 216 wire headers; 224 wire size; 232 input; 240 line; 248 line size;
// 256 parser state; 264 remaining; 272 Content-Length; 280 chunked;
// 288 Location; 296 header bytes; 304 Content-Encoding seen; 312 line CR;
// 320 chunk CRLF; 328 resolver pid; 336 resolver pipe; 344 resolver bytes;
// 352 addresses; 360 address count; 368 next address; 376 wanted events;
// 384 interim responses; 392 CA file; 400 scratch; 408 HTTP minor version;
// 416 HEAD; 424 request credentials; 432 request body present;
// 440 HTTPS only; 448 redirect budget; 456 reserved;
// 464 response header count; 472 response headers (128 name/value pairs).
// States: 1 resolving, 2 connecting, 3 TLS, 4 sending, 5 receiving,
// 6 complete, 7 failed. Each request owns all storage until free().

fn hc_alloc(r,n) {
    let used=load64(r+208);
    if n<1 || n>1048576-used {return 0;}
    store64(r+208,used+n);return load64(r+200)+used;
}
fn hc_string(r,text,n) {
    if !text {return 0;}
    let p=hc_alloc(r,n+1);if !p {return 0;}
    net_copy(p,text,n);store8(p+n,0);return p;
}
fn hc_join(r,a,b,c) {
    if !a || !b || !c {return 0;}
    let an=net_length(a);let bn=net_length(b);let cn=net_length(c);
    if an+bn+cn>131072 {return 0;}
    let p=hc_alloc(r,an+bn+cn+1);if !p {return 0;}
    net_copy(p,a,an);net_copy(p+an,b,bn);net_copy(p+an+bn,c,cn);
    store8(p+an+bn+cn,0);return p;
}
fn hc_lower(c) {if c>=65 && c<=90 {return c+32;}return c;}
fn hc_equal(a,b) {
    let i=0;while load8(a+i) && hc_lower(load8(a+i))==hc_lower(load8(b+i)) {i=i+1;}
    return hc_lower(load8(a+i))==hc_lower(load8(b+i));
}
fn hc_prefix(a,b) {
    let i=0;while load8(b+i) {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;
}
fn hc_token(c) {
    return (c>=65 && c<=90)||(c>=97 && c<=122)||(c>=48 && c<=57)
        || c==33 || c==35 || c==36 || c==37 || c==38 || c==39
        || c==42 || c==43 || c==45 || c==46 || c==94 || c==95
        || c==96 || c==124 || c==126;
}
fn hc_decimal(text) {
    let i=0;let n=0;if !load8(text) {return -1;}
    while load8(text+i) {
        let d=load8(text+i)-48;
        if d<0 || d>9 || n>(9223372036854775807-d)/10 {return -1;}
        n=n*10+d;i=i+1;
    }return n;
}
fn hc_number(r,n) {
    let tmp=hc_alloc(r,32);if !tmp {return 0;}let at=30;store8(tmp+31,0);
    store8(tmp+at,48+n%10);n=n/10;
    while n {at=at-1;store8(tmp+at,48+n%10);n=n/10;}return tmp+at;
}
fn hc_drop_io(r) {
    if load64(r+16) {ffi_call(tls_free,load64(r+16),0,0,0,0,0);store64(r+16,0);}
    if load64(r+24) {ffi_call(tls_ctx_free,load64(r+24),0,0,0,0,0);store64(r+24,0);}
    if load64(r+8)>=0 {tcp_close(load64(r+8));store64(r+8,-1);}
    if load64(r+336)>=0 {tcp_close(load64(r+336));store64(r+336,-1);}
    if load64(r+328)>0 {
        syscall(62,load64(r+328),9,0,0,0,0);
        let result=syscall(61,load64(r+328),0,0,0,0,0);
        while result==-4 {result=syscall(61,load64(r+328),0,0,0,0,0);}
        store64(r+328,0);
    }return 0;
}
fn hc_fail(r,message) {
    store64(r+40,message);store64(r,7);hc_drop_io(r);return -1;
}
fn hc_done(r) {store64(r,6);hc_drop_io(r);return 1;}
fn hc_ready(r,fd,events) {
    if !events {return 1;}let p=load64(r+400);
    store64(p,(fd&0xffffffff)|(events<<32));
    return syscall(7,p,1,0,0,0,0)>0;
}
fn hc_now(r) {
    let p=load64(r+400)+72;if syscall(228,1,p,0,0,0,0)<0 {return -1;}
    return load64(p)*1000+load64(p+8)/1000000;
}
