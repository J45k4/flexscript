import "../../lib/net/http.flex";
fn hh_size(p) {let i=0;while load8(p+i) {i=i+1;}return i;}
fn hh_text(p) {return hp_feed(p,hh_size(p));}
fn hh_fragment(p) {let n=hh_size(p);let i=0;while i<n {let r=hp_feed(p+i,1);if r!=1 {return r;}i=i+1;}return 0;}
fn hh_find(p,n,text) {let size=hh_size(text);let i=0;while i+size<=n {if nb_equal(p+i,text,size) {return 1;}i=i+1;}return 0;}
fn hh_start(work,method,method_size,length,keep) {if hp_init(work,6144) || hp_begin(method,method_size,"/",1,length,keep) || hp_host("esp32.test",10,443) || hp_finish_request() {return -1;}return 0;}
fn main() {
    let work=alloc(6144);let out=alloc(1024);let input=alloc(4096);let pad=alloc(2048);
    if !nb_token(126) || nb_token(32) || nb_hex(103)!= -1 || nb_digits(0,10)!=1 || nb_number(out,65535,10)!=5 || !nb_equal(out,"65535",5) {return 1;}
    if hp_init(0,6144)!= -22 || hp_init(work,6143)!= -22 || hp_init(work,6144) {return 2;}
    if hp_begin("GET",3,"bad",3,0,1)!= -22 || hp_begin("GET",3,"/%x",3,0,1)!= -22 || hp_begin("GET",3,"/a b",4,0,1)!= -22 || hp_begin("CONNECT",7,"/",1,0,1)!= -95 {return 3;}
    if hp_begin("GET",3,"/",1,0,1) || hp_host("bad\r\n",5,443)!= -22 || hp_host("esp32.test",10,443) || hp_host("esp32.test",10,443)!= -16 {return 4;}
    if hp_add_header("Host",4,"bad",3)!= -95 || hp_add_header("Content-Length",14,"1",1)!= -95 || hp_add_header("Bad Name",8,"ok",2)!= -22 || hp_add_header("X",1,"ok\r\nX: y",8)!= -22 || hp_add_header("X",1,"\0",1)!= -22 || hp_add_header("X-Value",7,0,0) || hp_finish_request() {return 5;}
    let expected="GET / HTTP/1.1\r\nHost: esp32.test:443\r\nX-Value: \r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n";
    if hp_request_size!=hh_size(expected) || !nb_equal(hp_request,expected,hp_request_size) || hp_finish_request()!= -16 || hp_add_header("X",1,"v",1)!= -16 {return 6;}
    let response="HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 201 Created\r\nContent-Length: 3, 003\r\nSet-Cookie: a=1\r\nset-cookie: b=2\r\nConnection: keep-alive\r\n\r\nyes";
    if hh_fragment(response) || hp_state!=8 || hp_status!=201 || hp_received!=3 || !hp_reusable || hp_interim!=1 {return 7;}
    let p=hp_field("set-cookie",10,0,0);if p<=0 || hp_field_size!=3 || !nb_equal(p,"a=1",3) {return 8;}
    p=hp_field("SET-cookie",10,1,0);if p<=0 || hp_field_size!=3 || !nb_equal(p,"b=2",3) || hp_field("missing",7,0,0)!=0 || hp_field("x",1,-1,0)!= -22 {return 9;}
    if hp_read(out,2)!=2 || !nb_equal(out,"ye",2) || hp_begin("GET",3,"/",1,0,1)!= -16 || hp_read(out,1024)!=1 || load8(out)!=115 || hp_read(out,1) {return 10;}
    if hp_begin("POST",4,"/upload",7,-1,0) || hp_host("esp32.test",10,80) || hp_finish_request() || !hh_find(hp_request,hp_request_size,"Transfer-Encoding: chunked\r\n") || hh_find(hp_request,hp_request_size,"Content-Length") {return 11;}
    if hh_fragment("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: X-Sum\r\n\r\n3; a=token; b=\"quoted\\\"value\"\r\nabc\r\n0\r\nX-Sum: yes\r\n\r\n") || hp_state!=8 || hp_received!=3 || hp_reusable {return 12;}
    p=hp_field("x-sum",5,0,1);if p<=0 || hp_field_size!=3 || !nb_equal(p,"yes",3) || hp_field("x-sum",5,0,0) || hp_read(out,1024)!=3 || !nb_equal(out,"abc",3) {return 13;}
    if hh_start(work,"GET",3,0,1) || hh_text("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n")!= -74 || hp_state!=9 || hp_read(out,1)!= -74 {return 14;}
    if hp_init(work,6144) || hp_set_limit(0) || hp_begin("HEAD",4,"/",1,0,1) || hp_host("x",1,443) || hp_finish_request() || hh_fragment("HTTP/1.1 200 OK\r\nContent-Length: 9999\r\n\r\n") || hp_state!=8 || hp_received || hp_read(out,1) || !hp_reusable || hp_eof() || hp_reusable {return 15;}
    if hh_start(work,"GET",3,0,1) || hh_fragment("HTTP/1.0 200 OK\r\n\r\nEOF") || hp_state!=3 || hp_received!=3 || hp_reusable || hp_eof() || hp_state!=8 || hp_read(out,1024)!=3 || !nb_equal(out,"EOF",3) {return 16;}
    if hh_start(work,"GET",3,0,1) || hh_fragment("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nx") || hp_eof()!= -74 || hp_read(out,1024)!=1 || load8(out)!=120 || hp_read(out,1)!= -74 {return 17;}
    if hh_start(work,"GET",3,0,1) || hh_fragment("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n") || hp_eof()!= -74 {return 18;}
    // Finish framing must reject capacity exhaustion before touching headers.
    if hp_init(work,6144) || hp_begin("POST",4,"/",1,2147483647,1) || hp_host("x",1,80) {return 19;}
    let i=0;while i<2048 {store8(pad+i,97);i=i+1;}let padding=2048-53-hp_request_size-9;if hp_add_header("X-Pad",5,pad,padding) || hp_request_size!=2048-53 {return 20;}
    i=0;while i<64 {store8(hp_headers+i,85);i=i+1;}if hp_finish_request()!= -90 || hp_request_ready {return 21;}i=0;while i<64 {if load8(hp_headers+i)!=85 {return 22;}i=i+1;}
    // Oversized response metadata cannot overwrite the adjacent body queue.
    if hh_start(work,"GET",3,0,1) {return 23;}i=0;while i<64 {store8(hp_body+i,90);i=i+1;}
    let prefix="HTTP/1.1 200 OK\r\nX: ";let n=hh_size(prefix);nb_copy(input,prefix,n);i=0;while i<2200 {store8(input+n+i,97);i=i+1;}
    if hp_feed(input,n+2200)!= -90 || hp_header_used!=2048 {return 24;}i=0;while i<64 {if load8(hp_body+i)!=90 {return 25;}i=i+1;}
    // A larger body must stop at queue capacity and resume after short reads.
    if hh_start(work,"GET",3,0,1) || hh_fragment("HTTP/1.1 200 OK\r\nContent-Length: 3000\r\n\r\n") {return 26;}
    i=0;while i<3000 {store8(input+i,i%251);i=i+1;}let sent=0;let received=0;
    while sent<3000 {let used=hp_feed(input+sent,3000-sent);if used<=0 || used>1024 {return 27;}sent=sent+used;let got=hp_read(out,257);while got>0 {i=0;while i<got {if load8(out+i)!=((received+i)%251) {return 28;}i=i+1;}received=received+got;got=hp_read(out,257);}}
    if hp_state!=8 || hp_received!=3000 || received!=3000 || hp_read(out,1) || hp_feed(0,0) || hp_read(0,0) || hp_read(0,1)!= -22 || hp_feed(0,1)!= -22 {return 29;}
    if hh_start(work,"GET",3,0,1) || hh_text("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\nContent-Length: 0\r\n\r\n")!= -74 || hp_read(out,1024)!=3 || !nb_equal(out,"abc",3) || hp_read(out,1)!= -74 {return 30;}
    return 0;
}
