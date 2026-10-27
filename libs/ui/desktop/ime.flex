import "paint.flex";
// Preedit is display-only. The committed local_value never contains it.
fn ud_ime_clear(){
    let node=ud_ime_node;if ud_ime_text{syscall(11,ud_ime_text,ud_ime_bytes+1,0,0,0,0);}ud_ime_node=0;ud_ime_text=0;ud_ime_bytes=0;ud_ime_begin=0;ud_ime_end=0;if node && ud_nodes{ud_invalidate(node);ud_dirty=1;}return 0;
}
fn ud_ime_restart(){ud_ime_clear();if ud_window{gui_text_focus(ud_window,0);if ud_focus && load64(ud_focus+8)==8 && !ud_ime_suspended{gui_text_focus(ud_window,load64(ud_focus+192));}}return 0;}
fn ud_ime_reset(){if ud_ime_node{return ud_ime_restart();}return 0;}
fn ud_ime_sync(cause){
    if !ud_window{return 0;}let node=ud_focus;if node && load64(node+8)==8 && ud_enabled(node) && !ud_ime_suspended{gui_text_focus(ud_window,load64(node+192));gui_text_surrounding(ud_window,ud_content(node),load64(node+144),load64(node+152),cause);}else{gui_text_focus(ud_window,0);}return 0;
}
fn ud_ime_complete(event){
    let p=gui_ime_data(gui_event_code(event));let node=ud_focus;if !p || !node || load64(node+8)!=8 || !ud_enabled(node) || ud_ime_suspended || load64(p+8)!=gui__ime_epoch{return 0;}
    if load64(p+80){ud_ime_clear();return 0;}let value=ud_content(node);let old=value;let n=h_len(value);let cursor=load64(node+144);let anchor=load64(node+152);let start=ud_min(cursor,anchor);let end=ud_max(cursor,anchor);let before=load64(p+32);let after=load64(p+40);let cn=load64(p+64);let pn=load64(p+72);
    if before<0 || after<0 || before>start || after>n-end || !gui__ime_boundary(value,n,start-before) || !gui__ime_boundary(value,n,end+after){ud_paste_cancel();ud_ime_restart();return 0;}
    // Protocol acknowledgements still update serial/hold state in the adapter.
    // An editor with no composition has nothing to clear for an empty payload;
    // do not cancel unrelated paste, discard its layout or restart its caret.
    if !before && !after && !cn && !pn && !ud_ime_node{return 0;}ud_paste_cancel();
    ud_ime_clear();if before || after{value=h_cat3(h_slice(value,start-before),h_slice(value+start,end-start),value+end+after);cursor=cursor-before;anchor=anchor-before;start=start-before;end=end-before;}
    if cn || pn{if h_len(value)-(end-start)+cn+pn>1048576{return 0;}value=h_cat3(h_slice(value,start),load64(p+96),value+end);cursor=start+cn;anchor=cursor;}
    j_set(load64(node+16),"local_value",j_string(value));store64(node+248,0);store64(node+144,cursor);store64(node+152,anchor);ud_invalidate(node);ud_dirty=1;ud_caret_epoch=gui_ticks();
    if pn{let text=alloc(pn+1);if text>0{bytes_copy(text,load64(p+104),pn+1);ud_ime_text=text;ud_ime_bytes=pn;ud_ime_node=node;ud_ime_begin=load64(p+48);ud_ime_end=load64(p+56);}}
    if !h_equal(old,value){return ud_emit(node,"change",j_string(value));}return 0;
}
