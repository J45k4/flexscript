// RFC 6455 codec. No socket ownership or blocking I/O in the protocol API.
import "../../lib/tls.flex";
import "../unicode/utf8.flex";
global ws_message=0;
fn ws_fail(w,message,code) {ws_message=message;if w {store64(w+80,message);store64(w+88,code);}return -1;}
fn ws_utf8(p,n) {let i=0;while i<n {let c=unicode_utf8_read(p,n,i);if c<0 {return 0;}i=i+(c&7);}return 1;}
fn ws_random(p,n) {let at=0;while at<n {let k=syscall(318,p+at,n-at,0,0,0,0);if k>0 {at=at+k;}else if k!=-4 {return 0;}}return 1;}
fn ws_close_code(code) {return (code>=1000 && code<=1014 && code!=1004 && code!=1005 && code!=1006) || (code>=3000 && code<=4999);}
// Fixed state (256 bytes), then bounded receive/message/transmit/control buffers.
// server=1 receives masked client frames; server=0 receives unmasked server frames.
fn websocket_new(server,limit) {
    ws_message=0;if (server!=0 && server!=1) || limit<125 || limit>16777216 {ws_fail(0,"Invalid WebSocket role or message limit",1009);return 0;}
    let w=alloc(256);if w<=0 {return 0;}let block=alloc(limit*3+157);if block<=0 {syscall(11,w,256,0,0,0,0);return 0;}
    store64(w,server);store64(w+8,limit);store64(w+16,block);store64(w+32,block+limit+14);store64(w+96,block+limit*2+15);store64(w+128,block+limit*3+29);store64(w+160,-1);return w;
}
fn websocket_free(w) {if !w {return 0;}if load64(w+168) {tls_close(load64(w+168));}else if load64(w+160)>=0 {tcp_close(load64(w+160));}syscall(11,load64(w+16),load64(w+8)*3+157,0,0,0,0);syscall(11,w,256,0,0,0,0);return 0;}
fn websocket_data(w) {return load64(w+64);}
fn websocket_size(w) {return load64(w+72);}
fn websocket_error(w) {if w {return load64(w+80);}return ws_message;}
fn websocket_close_code(w) {return load64(w+88);}
fn websocket_output(w) {return load64(w+96);}
fn websocket_output_size(w) {return load64(w+104);}
fn websocket_input_capacity(w) {return load64(w+8)+14-load64(w+24);}
// Returns bytes accepted (possibly less than n); drain next() before feeding more.
fn websocket_feed(w,p,n) {if !w || load64(w+80) || n<0 || (n && !p) || load64(w+112) {return -1;}let room=load64(w+8)+14-load64(w+24);if n>room {n=room;}net_copy(load64(w+16)+load64(w+24),p,n);store64(w+24,load64(w+24)+n);return n;}
fn ws_consume(w,n) {let remaining=load64(w+24)-n;net_copy(load64(w+16),load64(w+16)+n,remaining);store64(w+24,remaining);return 0;}
// 0 needs input, -1 protocol error; otherwise opcode 1/2/8/9/10.
// Event bytes remain valid until next() or free(). Ping/pong/close are exposed.
fn websocket_next(w) {
    if !w || load64(w+80) {return -1;}if load64(w+112) {return 0;}let more=1;
    while more {let p=load64(w+16);let n=load64(w+24);if n<2 {return 0;}let first=load8(p);let second=load8(p+1);let fin=(first&128)!=0;let op=first&15;let masked=(second&128)!=0;let size=second&127;let header=2;
        if (first&112) || (op!=0 && op!=1 && op!=2 && op!=8 && op!=9 && op!=10) || masked!=load64(w) {return ws_fail(w,"Invalid WebSocket frame flags, opcode or mask",1002);}
        if size==126 {if n<4 {return 0;}size=load8(p+2)*256+load8(p+3);header=4;if size<126 {return ws_fail(w,"Nonminimal WebSocket frame length",1002);}}
        else if size==127 {if n<10 {return 0;}if load8(p+2)&128 {return ws_fail(w,"Invalid WebSocket 64-bit length",1002);}size=0;let j=2;while j<10 {if size>16777216 {return ws_fail(w,"WebSocket frame exceeds limit",1009);}size=(size<<8)|load8(p+j);j=j+1;}header=10;if size<65536 {return ws_fail(w,"Nonminimal WebSocket frame length",1002);}}
        if op>=8 && (!fin || size>125) {return ws_fail(w,"Invalid WebSocket control frame",1002);}if size>load64(w+8) {return ws_fail(w,"WebSocket frame exceeds limit",1009);}let key=p+header;if masked {header=header+4;}if n<header+size {return 0;}
        let target=load64(w+128);let used=0;if op<8 {let fragment=load64(w+48);if (op==0 && !fragment) || (op!=0 && fragment) {return ws_fail(w,"Invalid WebSocket continuation sequence",1002);}used=load64(w+40);if size>load64(w+8)-used {return ws_fail(w,"WebSocket message exceeds limit",1009);}target=load64(w+32)+used;if op!=0 {store64(w+48,op);}}
        let i=0;while i<size {let c=load8(p+header+i);if masked {c=c^load8(key+(i%4));}store8(target+i,c);i=i+1;}store8(target+size,0);ws_consume(w,header+size);
        if op>=8 {if op==8 {if size==1 {return ws_fail(w,"Invalid WebSocket close payload",1002);}if size>=2 {let code=load8(target)*256+load8(target+1);if !ws_close_code(code) {return ws_fail(w,"Invalid WebSocket close code",1002);}if !ws_utf8(target+2,size-2) {return ws_fail(w,"Invalid UTF-8 WebSocket close reason",1007);}store64(w+88,code);}else {store64(w+88,1005);}store64(w+112,1);}store64(w+64,target);store64(w+72,size);store64(w+56,op);return op;}
        used=used+size;store64(w+40,used);if fin {let kind=load64(w+48);if kind==1 && !ws_utf8(load64(w+32),used) {return ws_fail(w,"Invalid UTF-8 WebSocket text",1007);}store64(w+48,0);store64(w+40,0);store64(w+64,load64(w+32));store64(w+72,used);store64(w+56,kind);return kind;}
    }return 0;
}
// Build a complete outbound message/control frame, using fresh random client masks.
// Output is owned by w and valid until the next frame() or free().
fn websocket_frame(w,op,p,n) {
    if !w || load64(w+80) || n<0 || (n && !p) || n>load64(w+8) || load64(w+120) {return 0;}if op!=1 && op!=2 && op!=8 && op!=9 && op!=10 {return 0;}if op>=8 && n>125 {return 0;}if load64(w+112) && op!=8 {return 0;}if op==1 && !ws_utf8(p,n) {return 0;}if op==8 {if n==1 {return 0;}if n>=2 && (!ws_close_code(load8(p)*256+load8(p+1)) || !ws_utf8(p+2,n-2)) {return 0;}}
    let out=load64(w+96);store8(out,128|op);let at=2;let mask=0;if !load64(w) {mask=128;}if n<126 {store8(out+1,mask|n);}else if n<65536 {store8(out+1,mask|126);store8(out+2,n>>8);store8(out+3,n&255);at=4;}else {store8(out+1,mask|127);let i=0;while i<8 {store8(out+2+i,(n>>((7-i)*8))&255);i=i+1;}at=10;}
    let key=out+at;if mask {if !ws_random(key,4) {return 0;}at=at+4;}let i=0;while i<n {let c=load8(p+i);if mask {c=c^load8(key+(i%4));}store8(out+at+i,c);i=i+1;}store64(w+104,at+n);if op==8 {store64(w+120,1);}return 1;
}
