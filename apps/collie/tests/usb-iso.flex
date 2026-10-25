import "../lib/json.flex";
import "../guest/runtime.flex";
import "../guest/usb-iso.flex";
fn word(p,n){let i=0;while i<4{store8(p+i,(n>>(i*8))&255);i=i+1;}return 0;}
fn field(map,key){let i=0;while i<db_count(map){let pair=db_at(map,i);if h_equal(db_word(db_at(pair,0)),key){return db_at(pair,1);}i=i+1;}return 0;}
fn base(p,count,bytes){let n=64+count*16+bytes;let i=0;while i<n{store8(p+i,0);i=i+1;}i=0;while i<8{store8(p+i,load8("COLLISO1"+i));i=i+1;}word(p+8,1);word(p+12,19);word(p+32,count);word(p+36,bytes);word(p+44,bytes);word(p+56,1);return n;}
fn good(p){let n=base(p,2,12);word(p+24,-1);word(p+28,1);word(p+40,7);store64(p+48,0x123456789abcdef);word(p+64,5);word(p+68,3);word(p+80,7);word(p+84,4);word(p+88,-18);word(p+92,5);let i=0;while i<12{store8(p+96+i,(i*17+128)%256);i=i+1;}return n;}
fn rejects(p,n){h_assert(!usb_iso_decode(db_blob(p,n))&&db_last_error_details,"malformed ISO frame is a structured error");h_assert(h_equal(db_word(db_at(db_last_error_details,0)),"invalid_usb_iso_frame"),"ISO decoder has its own error code");return 0;}
fn main(){
    let p=alloc(26689);let n=good(p);let r=usb_iso_decode(db_blob(p,n));h_assert(r,"independent valid frame");
    h_assert(db_word(field(r,"submitted"))==1&&db_word(field(r,"reaped"))==1&&db_word(field(r,"input"))==1&&!db_word(field(r,"cancel_requested")),"completion flags stay distinct");
    h_assert(db_word(field(r,"requested_start_frame"))==(-1)&&db_kind(field(r,"start_frame"))==0&&!db_word(field(r,"start_frame_known"))&&db_word(field(r,"elapsed_ns"))==0x123456789abcdef&&db_word(field(r,"actual"))==7,"signed request frame and exact64-bit time are preserved without inventing an unreported actual bus start");
    let packets=field(r,"packets");h_assert(db_count(packets)==2,"all packets retained");let a=db_at(packets,0);let b=db_at(packets,1);
    h_assert(db_word(field(a,"requested"))==5&&db_word(field(a,"actual"))==3&&db_bytes(field(a,"data"))==3&&db_word(field(b,"status"))==(-18)&&db_bytes(field(b,"data"))==4,"short/failed packets retain their own sizes/status/data");
    h_assert(load8(db_word(field(a,"data")))==128&&load8(db_word(field(b,"data")))==(5*17+128)%256,"packet data uses requested offsets rather than compacting across short packets");
    word(p+12,21);word(p+40,0);word(p+68,0);word(p+84,0);word(p+60,1);word(p+72,-115);word(p+88,-115);r=usb_iso_decode(db_blob(p,n));h_assert(r&&!db_word(field(r,"reaped"))&&db_word(field(r,"cleanup_required"))&&!db_word(field(r,"urb_status_known")),"unreaped cancellation retains cleanup and unknown kernel status");h_assert(!db_word(field(db_at(field(r,"packets"),0),"status_known"))&&!db_bytes(field(db_at(field(r,"packets"),0),"data")),"unreaped packets never manufacture transferred bytes");
    let offsets=alloc(14*8);let values=alloc(14*8);
    store64(offsets,8);store64(values,2);store64(offsets+8,12);store64(values+8,32);store64(offsets+16,32);store64(values+16,129);store64(offsets+24,36);store64(values+24,24577);store64(offsets+32,40);store64(values+32,8);store64(offsets+40,44);store64(values+40,11);store64(offsets+48,56);store64(values+48,0);store64(offsets+56,60);store64(values+56,1);store64(offsets+64,64);store64(values+64,0);store64(offsets+72,68);store64(values+72,6);store64(offsets+80,92);store64(values+80,3);store64(offsets+88,88);store64(values+88,1);store64(offsets+96,16);store64(values+96,4096);store64(offsets+104,28);store64(values+104,3);
    let i=0;while i<14{good(p);word(p+load64(offsets+i*8),load64(values+i*8));rejects(p,n);i=i+1;}good(p);store8(p,0);rejects(p,n);good(p);rejects(p,n-1);rejects(p,n+1);rejects(p,63);
    good(p);word(p+12,18);rejects(p,n);good(p);store64(p+48,-1);rejects(p,n);h_assert(!usb_iso_decode(db_text("COLLISO1")),"text is not a binary packet frame");
    n=base(p,128,24576);i=0;while i<128{word(p+64+i*16,192);word(p+64+i*16+12,i*192);i=i+1;}r=usb_iso_decode(db_blob(p,n));h_assert(r&&n==26688&&db_count(field(r,"packets"))==128,"complete maximum result is bounded and never truncated");
    h_assert(!db_last_error,"a valid decode clears stale diagnostics");h_print(1,"PASS portable ISO packets: exact fields, short/failed/cancelled frames, binary offsets, malformed inputs and maximum bounds; no USB I/O\n");return 0;
}
