// Incremental VT input parser. Handles sequences split across read() calls.
import "terminal.flex";
global ti_buffer=0;
global ti_pasting=0;
global ti_kind=0;
global ti_key=0;
global ti_mod=0;
global ti_text=0;
global ti_x=0;
global ti_y=0;
global ti_button=0;
global ti_release=0;
global ti_at=0;
global ti_overflow=0;
global ti_poll=0;
global ti_input=0;
global ti_signal=0;
fn ti_init() {ti_buffer=h_buffer();h_data(ti_buffer);ti_pasting=0;ti_poll=h_take(16);ti_input=h_take(8192);ti_signal=h_take(128);return 0;}
// 0 timeout, 1 input queued, 2 termination signal / terminal disconnected.
fn ti_wait(ms) {
    store64(ti_poll,1<<32);store64(ti_poll+8,(tu_signal_fd&0xffffffff)|(1<<32));let ready=syscall(7,ti_poll,2,ms,0,0,0);
    if (load64(ti_poll+8)>>48)&1 {syscall(0,tu_signal_fd,ti_signal,128,0,0,0);return 2;}
    if (load64(ti_poll)>>48)&(8|16) {return 2;}
    if (load64(ti_poll)>>48)&1 {let n=syscall(0,0,ti_input,8192,0,0,0);if n>0 {ti_feed(ti_input,n);return 1;}if !n {return 2;}}
    return 0;
}
fn ti_feed(bytes,n) {if h_size(ti_buffer)+n>131072 {ti_overflow=1;ti_buffer=h_buffer();ti_pasting=0;return 0;}h_append(ti_buffer,bytes,n);return 0;}
fn ti_consume(n) {let s=h_data(ti_buffer);let size=h_size(ti_buffer);h_copy(s,s+n,size-n);store64(ti_buffer+8,size-n);store8(s+size-n,0);return 0;}
fn ti_number(s) {let n=0;while load8(s+ti_at)>=48 && load8(s+ti_at)<=57 {n=n*10+load8(s+ti_at)-48;ti_at=ti_at+1;}return n;}
fn ti_next(flush_escape) {
    ti_kind=0;ti_mod=0;ti_text="";let s=h_data(ti_buffer);let n=h_size(ti_buffer);if !n {return 0;}
    if ti_pasting {let stop=h_find(s,tu_ansi("@[201~"));if stop<0 {return 0;}ti_text=tu_clean(h_slice(s,stop));ti_consume(stop+6);ti_pasting=0;ti_kind=4;return 1;}
    let c=load8(s);if c!=27 {if c<32 || c==127 {ti_kind=2;ti_key=c;ti_consume(1);return 1;}
        let bytes=1;if c>=192 {bytes=2;}if c>=224 {bytes=3;}if c>=240 {bytes=4;}if n<bytes {return 0;}ti_kind=1;ti_text=h_slice(s,bytes);ti_consume(bytes);return 1;}
    if n==1 {if !flush_escape {return 0;}ti_kind=2;ti_key=27;ti_consume(1);return 1;}
    if load8(s+1)==13 || load8(s+1)==10 {ti_kind=2;ti_key=13;ti_mod=1;ti_consume(2);return 1;}
    if load8(s+1)!=91 && load8(s+1)!=79 {ti_kind=2;ti_key=27;ti_consume(1);return 1;}
    let end=2;while end<n && !(load8(s+end)>=64 && load8(s+end)<=126) {end=end+1;}if end==n {return 0;}
    let final=load8(s+end);ti_at=2;let first=ti_number(s);let mod=1;if load8(s+ti_at)==59 {ti_at=ti_at+1;mod=ti_number(s);}ti_mod=mod-1;
    if load8(s+2)==60 {ti_at=3;ti_button=ti_number(s);ti_at=ti_at+1;ti_x=ti_number(s);ti_at=ti_at+1;ti_y=ti_number(s);ti_release=final==109;ti_mod=(ti_button>>2)&7;ti_kind=3;}
    else {ti_kind=2;ti_key=27;
        if final==65 {ti_key=1001;}else if final==66 {ti_key=1002;}else if final==67 {ti_key=1003;}else if final==68 {ti_key=1004;}
        else if final==72 {ti_key=1005;}else if final==70 {ti_key=1006;}
        else if final==117 {ti_key=first;}
        else if final==126 {if first==1 || first==7 {ti_key=1005;}else if first==4 || first==8 {ti_key=1006;}else if first==3 {ti_key=1007;}else if first==5 {ti_key=1008;}else if first==6 {ti_key=1009;}else if first==200 {ti_pasting=1;ti_kind=0;}}
    }
    ti_consume(end+1);if !ti_kind {return ti_next(0);}return 1;
}
