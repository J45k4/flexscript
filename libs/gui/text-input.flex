// Composition transactions carry tokens, never owning pointers, in GUI events.
// gui_ime_data(token) is borrowed until the next gui_poll / gui_ime_release.
// At most 128 transactions, with two <=4000-byte strings each, can be retained.
// Data layout: window0, focus epoch8, serial16, matching24, delete before32 /
// after40, preedit cursor begin48 / end56, commit bytes64 / preedit bytes72,
// cancel80, allocation bytes88, commit string96 / preedit string104.
global gui__ime_window=0;
global gui__ime_identity=0;
global gui__ime_epoch=0;
global gui__ime_slots=0;
global gui__ime_next=0;
global gui__ime_active=0;
global gui__text_enabled=0;
fn gui_text_epoch(window){if window==gui__ime_window{return gui__ime_epoch;}return 0;}
fn gui__ime_length(text){if !text{return 0;}let n=0;while n<=4000 && load8(text+n){n=n+1;}return n;}
fn gui__ime_boundary(text,n,at){return at>=0 && at<=n && (at==n || (load8(text+at)&192)!=128);}
fn gui_ime_data(token){if !gui__ime_slots || token<1{return 0;}let slot=gui__ime_slots+(token%128)*16;if load64(slot)!=token{return 0;}return load64(slot+8);}
fn gui_ime_release(token){let p=gui_ime_data(token);if p{store64(gui__ime_slots+(token%128)*16,0);store64(gui__ime_slots+(token%128)*16+8,0);syscall(11,p,load64(p+88),0,0,0,0);}if gui__ime_active==token{gui__ime_active=0;}return 0;}
fn gui__ime_clear(){if gui__ime_slots{let i=0;while i<128{gui_ime_release(load64(gui__ime_slots+i*16));i=i+1;}syscall(11,gui__ime_slots,2048,0,0,0,0);gui__ime_slots=0;}gui__ime_active=0;return 0;}
fn gui__ime_emit(window,epoch,serial,matching,before,after,commit,preedit,begin,end,cancel){
    let cn=gui__ime_length(commit);let pn=gui__ime_length(preedit);if cn>4000 || pn>4000 || (cn && !wc_valid(commit,cn)) || (pn && !wc_valid(preedit,pn)){return gui__fail("Invalid or oversized IME text");}
    if !((begin== -1 && end== -1) || (gui__ime_boundary(preedit,pn,begin) && gui__ime_boundary(preedit,pn,end))){return gui__fail("IME cursor is not a UTF-8 boundary");}
    if !gui__ime_slots{gui__ime_slots=alloc(2048);if gui__ime_slots<0{gui__ime_slots=0;return gui__fail("Cannot allocate IME queue");}bytes_fill(gui__ime_slots,0,2048);}
    let token=gui__ime_next+1;let slot=gui__ime_slots+(token%128)*16;if load64(slot){return gui__fail("IME transaction queue overflow");}
    let bytes=114+cn+pn;let p=alloc(bytes);if p<0{return gui__fail("Cannot allocate IME transaction");}bytes_fill(p,0,bytes);store64(p,window);store64(p+8,epoch);store64(p+16,serial);store64(p+24,matching);store64(p+32,before);store64(p+40,after);store64(p+48,begin);store64(p+56,end);store64(p+64,cn);store64(p+72,pn);store64(p+80,cancel);store64(p+88,bytes);store64(p+96,p+112);store64(p+104,p+113+cn);if cn{bytes_copy(p+112,commit,cn);}if pn{bytes_copy(p+113+cn,preedit,pn);}
    let event=gui_event();store64(event,GUI_IME);store64(event+8,window);store64(event+16,token);let ok=gui_event_enqueue(event);syscall(11,event,128,0,0,0,0);if !ok{syscall(11,p,bytes,0,0,0,0);return 0;}store64(slot,token);store64(slot+8,p);gui__ime_next=token;return token;
}
// Stable application editor identity, independent of temporary model addresses.
// A changed identity starts a new composition session, even on the same surface.
fn gui_text_focus(window,identity){
    if !gui__record(window){return 0;}if gui__ime_window==window && gui__ime_identity==identity{return 1;}
    gui__ime_window=window;gui__ime_identity=identity;gui__ime_epoch=gui__ime_epoch+1;
    if gui__native{let c=load64(gui__record(window));wm_reset(c,load64(load64(c+192)+256));}
    return gui_text_input(identity!=0);
}
fn gui_text_surrounding(window,text,cursor,anchor,cause){
    if !gui__record(window) || gui__ime_window!=window || !gui__ime_identity{return 0;}
    if gui__native{let c=load64(gui__record(window));return wm_surrounding(c,load64(load64(c+192)+256),text,cursor,anchor,cause);}return 1;
}
fn gui__sdl_preedit(window,text,start,count){
    if !gui__text_enabled{return 0;}
    let n=gui__ime_length(text);if n>4000 || start<0 || count<0{return 0;}let i=0;let point=0;let begin=0;let end=0;
    while i<n{if point==start{begin=i;}if point==start+count{end=i;}i=i+1;while i<n && (load8(text+i)&192)==128{i=i+1;}point=point+1;}
    if start>=point{begin=n;}if start+count>=point{end=n;}return gui__ime_emit(window,gui__ime_epoch,0,1,0,0,"",text,begin,end,0);
}
