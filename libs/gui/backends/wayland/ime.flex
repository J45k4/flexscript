// text-input-v3 v1: bounded UTF-8 state and atomic done transactions.
// 12544 bytes, owned by the input context at w+256. One seat/editor session.
// Header: manager0,input8,global16,seat24,entered32,enabled40,desired48,
// enable serial56,epoch64,commit count72,last done80,dirty88,reset96,surrounding valid104,
// bytes112,cursor120,anchor128,rect136..160,cause168,pending commit/preedit
// bytes176/184,cursor192/200,delete208/216,hold240,composing248.
// Buffers: surrounding256, commit4352, preedit8448 (each 4001 bytes).
fn wm_context(){let p=alloc(12544);if p<0{return 0;}bytes_fill(p,0,12544);store64(p+152,1);store64(p+160,1);return p;}
fn wm_pending_clear(p){bytes_fill(p+176,0,64);store8(p+4352,0);store8(p+8448,0);return 0;}
fn wm_commit(c,p){wl_req(c,load64(p+8),7,0,0,0);store64(p+72,(load64(p+72)+1)&0xffffffff);return 1;}
fn wm_reset(c,p){if !p{return 0;}store64(p+96,1);store64(p+88,1);store64(p+64,gui__ime_epoch);store64(p+240,0);store64(p+248,0);wm_pending_clear(p);return 1;}
fn wm_enable(c,p,enabled){
    if !p{return 0;}enabled=enabled!=0;if load64(p+48)!=enabled{store64(p+48,enabled);wm_reset(c,p);}return 1;
}
fn wm_apply(c,p){
    if !p || !load64(p+8) || !load64(p+32) || load64(p+240){return 1;}let desired=load64(p+48);let enabled=load64(p+40);let reset=load64(p+96);
    if enabled && (!desired || reset){wl_req(c,load64(p+8),2,0,0,0);wm_commit(c,p);store64(p+40,0);enabled=0;}
    if !desired{store64(p+96,0);return 1;}let send=load64(p+88) || !enabled;
    if !enabled{wl_req(c,load64(p+8),1,0,0,0);store64(p+40,1);store64(p+64,gui__ime_epoch);}
    if send{
        if load64(p+104){wl_req(c,load64(p+8),3,0,wl_args(c,p+256,load64(p+120),load64(p+128),0,0,0),0);}
        wl_req(c,load64(p+8),4,0,wl_args(c,load64(p+168),0,0,0,0,0),0);
        wl_req(c,load64(p+8),5,0,wl_args(c,0,0,0,0,0,0),0);
        wl_req(c,load64(p+8),6,0,wl_args(c,load64(p+136),load64(p+144),load64(p+152),load64(p+160),0,0),0);wm_commit(c,p);if !enabled{store64(p+56,load64(p+72));}
    }store64(p+88,0);store64(p+96,0);return 1;
}
fn wm_surrounding(c,p,text,cursor,anchor,cause){
    if !p || !text{return gui__fail("Invalid IME surrounding text");}let n=gui__clipboard_length(text);if n>1048576 || !gui__ime_boundary(text,n,cursor) || !gui__ime_boundary(text,n,anchor){return gui__fail("Invalid IME surrounding cursor");}
    let low=cursor;let high=anchor;if low>high{low=anchor;high=cursor;}let valid=high-low<=4000;let start=0;let end=0;
    if valid{start=low-(4000-(high-low))/2;if start<0{start=0;}end=start+4000;if end>n{end=n;start=end-4000;if start<0{start=0;}}while start<low && (load8(text+start)&192)==128{start=start+1;}while end>high && end<n && (load8(text+end)&192)==128{end=end-1;}}
    let bytes=end-start;let changed=load64(p+104)!=valid;if valid{if !wc_valid(text+start,bytes){return gui__fail("Invalid UTF-8 IME surrounding text");}changed=changed || load64(p+112)!=bytes || load64(p+120)!=cursor-start || load64(p+128)!=anchor-start || bytes_common_prefix(p+256,text+start,bytes)!=bytes;}
    if changed{if !valid && load64(p+104){store64(p+96,1);}store64(p+104,valid);store64(p+112,bytes);store64(p+120,cursor-start);store64(p+128,anchor-start);if valid{bytes_copy(p+256,text+start,bytes);store8(p+256+bytes,0);}store64(p+88,1);if cause!=0{cause=1;}store64(p+168,cause);}return 1;
}
fn wm_rectangle(p,x,y,width,height){
    if !p || width<0 || height<0 || width>16384 || height>16384{return 0;}if load64(p+136)!=x || load64(p+144)!=y || load64(p+152)!=width || load64(p+160)!=height{store64(p+136,x);store64(p+144,y);store64(p+152,width);store64(p+160,height);store64(p+88,1);}return 1;
}
fn wm_cancel(c,p,w){
    if load64(p+248) && load64(w+8){gui__ime_emit(load64(w+8),load64(p+64),0,1,0,0,"","",0,0,1);}store64(p+248,0);wm_pending_clear(p);return 0;
}
fn wm_done(c,p,w,serial){
    // Old-session replies cannot insert text into an editor enabled later.
    if load64(p+96) || ((serial-load64(p+56))&0xffffffff)>0x7fffffff{wm_pending_clear(p);return 0;}
    let match=serial==load64(p+72);store64(p+80,serial);store64(p+240,!match);
    if load64(p+40) && load64(p+32) && load64(p+48) && load64(p+64)==gui__ime_epoch && !load64(p+96){
        if !gui__ime_emit(load64(w+8),load64(p+64),serial,match,load64(p+208),load64(p+216),p+4352,p+8448,load64(p+192),load64(p+200),0){return wl_fail(c,"Cannot queue IME transaction");}store64(p+248,load64(p+184)!=0);
    }wm_pending_clear(p);return 0;
}
fn wm_string(c,p,text,dest,length){let n=gui__ime_length(text);if n>4000 || (n && !wc_valid(text,n)){return wl_fail(c,"Compositor sent invalid IME text");}if n{bytes_copy(p+dest,text,n);}store8(p+dest+n,0);store64(p+length,n);return 1;}
fn wm_dispatch(c,w,metadata,proxy,opcode,args){
    let p=load64(w+256);let kind=load64(metadata+8);if !p{return 0;}
    if kind==1 && opcode==0 && wl_equal(load64(args+8),"zwp_text_input_manager_v3") && !load64(p){store64(p,wl_bind(c,bytes_load32(args),wp_i_zwp_text_input_manager_v3,1,60));store64(p+16,bytes_load32(args));}
    else if kind==1 && opcode==1 && bytes_load32(args)==load64(p+16){wm_cancel(c,p,w);if load64(p+8){wl_destroy(c,load64(p+8),0);}wl_destroy(c,load64(p),0);store64(p,0);store64(p+8,0);store64(p+32,0);store64(p+40,0);store64(p+72,0);store64(p+240,0);if !load64(w+40){wi_blur(w);}}
    else if kind==61{
        if opcode==0{store64(p+32,load64(args)==load64(c+48));store64(p+40,0);store64(p+240,0);wm_reset(c,p);if !load64(w+40) && load64(p+32){wi_focus(w,1);}}
        else if opcode==1{wm_cancel(c,p,w);store64(p+32,0);store64(p+40,0);store64(p+240,0);if !load64(w+40){wi_blur(w);}}
        else if opcode==2{if wm_string(c,p,load64(args),8448,184){let begin=tf_i32(args+8);let end=tf_i32(args+16);let n=load64(p+184);if !((begin== -1 && end== -1) || (gui__ime_boundary(p+8448,n,begin) && gui__ime_boundary(p+8448,n,end))){wl_fail(c,"Compositor IME cursor is not a UTF-8 boundary");}else{store64(p+192,begin);store64(p+200,end);}}}
        else if opcode==3{wm_string(c,p,load64(args),4352,176);}
        else if opcode==4{store64(p+208,bytes_load32(args));store64(p+216,bytes_load32(args+8));}
        else if opcode==5{wm_done(c,p,w,bytes_load32(args));}
    }
    let seat=load64(w+24);if load64(p+8) && seat!=load64(p+24){wm_cancel(c,p,w);wl_destroy(c,load64(p+8),0);store64(p+8,0);store64(p+32,0);store64(p+40,0);store64(p+72,0);store64(p+240,0);if !load64(w+40){wi_blur(w);}}
    if load64(p) && seat && !load64(p+8){let input=wl_req(c,load64(p),1,wp_i_zwp_text_input_v3,wl_args(c,0,seat,0,0,0,0),0);store64(p+8,wl_watch(c,input,61,0));store64(p+24,seat);}
    return 0;
}
fn wm_close(c,p){if p{if c && load64(p+8){wl_destroy(c,load64(p+8),0);}if c && load64(p){wl_destroy(c,load64(p),0);}syscall(11,p,12544,0,0,0,0);}return 0;}
