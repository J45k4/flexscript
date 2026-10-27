// One owned toplevel state per connection (c+456), 256 bytes. xdg-shell state
// becomes current only at xdg_surface.configure, never at toplevel.configure.
// shown0,mapped8,remap16,expose generation24,normal width32/height40,
// current states48,pending states56,owned title64/bytes72,flags80,
// desired maximized88/fullscreen96,minimize requested104,last expose112,
// last geometry128/136,explicit restore size144,successful presents152,
// remap sync callback160,cached size constraints168/176,opaque size184/192,
// opaque enabled200.
// The barrier drains
// pre-unmap configure events before
// asking for a fresh initial configure; hide/show never blocks for a roundtrip.
fn wt_context(c,title,width,height,flags){
    let p=alloc(256);if p<0{return wl_fail(0,"Cannot allocate native toplevel state");}bytes_fill(p,0,256);store64(c+456,p);store64(p,!(flags&2));store64(p+32,width);store64(p+40,height);store64(p+80,flags);return wt_title(c,title);
}
fn wt_title(c,title){
    if !title{return wl_fail(0,"Native window title is null");}let n=0;while n<=4096 && load8(title+n){n=n+1;}if n>4096{return wl_fail(0,"Native window title exceeds 4096 bytes");}let owned=alloc(n+1);if owned<0{return wl_fail(0,"Cannot allocate native window title");}bytes_copy(owned,title,n+1);let p=load64(c+456);if load64(p+64){syscall(11,load64(p+64),load64(p+72)+1,0,0,0,0);}store64(p+64,owned);store64(p+72,n);if load64(c+64){wl_req(c,load64(c+64),2,0,wl_args(c,owned,0,0,0,0,0),0);}return 1;
}
fn wt_limits(c){
    if !load64(c+64){return 1;}let p=load64(c+456);let w=0;let h=0;if !(load64(p+80)&1) && !load64(p+88) && !load64(p+96){w=load64(p+32);h=load64(p+40);}if w==load64(p+168) && h==load64(p+176){return 1;}if w || h{wl_req(c,load64(c+64),7,0,wl_args(c,0,0,0,0,0,0),0);}wl_req(c,load64(c+64),8,0,wl_args(c,w,h,0,0,0,0),0);wl_req(c,load64(c+64),7,0,wl_args(c,w,h,0,0,0,0),0);store64(p+168,w);store64(p+176,h);return 1;
}
fn wt_role(c){let xdg=wl_req(c,load64(c+40),2,wp_i_xdg_surface,wl_args(c,0,load64(c+48),0,0,0,0),0);store64(c+56,wl_watch(c,xdg,4,0));let top=wl_req(c,xdg,1,wp_i_xdg_toplevel,wl_args(c,0,0,0,0,0,0),0);store64(c+64,wl_watch(c,top,5,0));let p=load64(c+456);store64(p+168,0);store64(p+176,0);return top!=0;}
fn wt_attributes(c){
    let p=load64(c+456);let top=load64(c+64);wl_req(c,top,2,0,wl_args(c,load64(p+64),0,0,0,0,0),0);wl_req(c,top,3,0,wl_args(c,"org.flexscript.Collie",0,0,0,0,0),0);wt_limits(c);
    if load64(p+88){wl_req(c,top,9,0,0,0);}if load64(p+96){wl_req(c,top,11,0,wl_args(c,0,0,0,0,0,0),0);}return 1;
}
fn wt_pending(c,width,height,array){
    if width>16384 || height>16384 || (width && height && width>24000000/height){return wl_fail(c,"Compositor window size exceeds limit");}let n=load64(array);let data=load64(array+16);if n<0 || n>256 || n%4 || (n && !data){return wl_fail(c,"Invalid compositor toplevel state array");}let state=0;let i=0;while i<n{let value=bytes_load32(data+i);if value>0 && value<=9{state=state|(1<<value);}i=i+4;}store64(load64(c+456)+56,state);store64(c+88,width);store64(c+96,height);return 1;
}
// xdg states 1/2 are maximized/fullscreen; 5..8 are tiled edges.
fn wt_constrained(state){return (state&486)!=0;}
fn wt_configured(c){
    let p=load64(c+456);if load64(p+16){return 1;}let state=load64(p+56);let width=load64(c+88);let height=load64(c+96);if !width{width=load64(p+32);if wt_constrained(state) && load64(c+72)>0{width=load64(c+72);}}if !height{height=load64(p+40);if wt_constrained(state) && load64(c+80)>0{height=load64(c+80);}}if !wt_constrained(state) && (load64(p+144) || !(load64(p+80)&1)){width=load64(p+32);height=load64(p+40);store64(p+144,0);}store64(c+72,width);store64(c+80,height);store64(p+48,state);if !wt_constrained(state){store64(p+32,width);store64(p+40,height);}store64(c+104,1);store64(p+24,load64(p+24)+1);return 1;
}
fn wt_remap(c,proxy){let p=load64(c+456);if proxy!=load64(p+160){return 0;}store64(p+160,0);wl_destroy(c,proxy,-1);if load64(p) && load64(p+16){store64(c+88,0);store64(c+96,0);store64(p+56,0);if !wt_role(c){return 0;}wt_attributes(c);wl_req(c,load64(c+48),6,0,0,0);store64(p+16,0);wt_flush(c);}return 1;}
fn wt_ready(c){let p=load64(c+456);return p && load64(p) && load64(c+104) && !load64(c+112);}
// Advertise only known opaque content. The hint is in logical coordinates,
// independent of buffer density. The server copies the temporary region.
fn wt_opaque(c,enabled){
    let p=load64(c+456);let width=load64(c+72);let height=load64(c+80);if !enabled{if load64(p+200){wl_req(c,load64(c+48),4,0,wl_args(c,0,0,0,0,0,0),0);store64(p+200,0);}return 1;}if load64(p+200) && width==load64(p+184) && height==load64(p+192){return 1;}let iface=ffi_symbol(load64(c),"wl_region_interface");if !iface{return wl_fail(c,"Wayland region interface is unavailable");}let region=wl_req(c,load64(c+24),1,iface,wl_args(c,0,0,0,0,0,0),0);if !region{return wl_fail(c,"Cannot allocate the opaque window region");}wl_req(c,region,1,0,wl_args(c,0,0,width,height,0,0),0);wl_req(c,load64(c+48),4,0,wl_args(c,region,0,0,0,0,0),0);wl_destroy(c,region,0);store64(p+184,width);store64(p+192,height);store64(p+200,1);return 1;
}
fn wt_geometry(c){let p=load64(c+456);let width=load64(c+72);let height=load64(c+80);if width!=load64(p+128) || height!=load64(p+136){wl_req(c,load64(c+56),3,0,wl_args(c,0,0,width,height,0,0),0);store64(p+128,width);store64(p+136,height);}return 1;}
fn wt_presented(c){let p=load64(c+456);store64(p+8,1);store64(p+152,load64(p+152)+1);return 1;}
fn wt_flush(c){if wl_int(c,"wl_display_flush",load64(c+8),0,0,0,0,0)<0 && wl_int(c,"wl_display_get_error",load64(c+8),0,0,0,0,0){return wl_fail(c,"Cannot submit native window state");}return 1;}
fn wt_show(c,visible){
    let p=load64(c+456);visible=visible!=0;if load64(p)==visible{return 1;}store64(p,visible);let surface=load64(c+48);
    if !visible{wpd_cancel(c);if load64(p+160){wl_destroy(c,load64(p+160),-1);store64(p+160,0);}if load64(p+8){if load64(c+168){wl_destroy(c,load64(c+168),-1);store64(c+168,0);}wl_req(c,surface,1,0,wl_args(c,0,0,0,0,0,0),0);wl_req(c,surface,6,0,0,0);wl_destroy(c,load64(c+64),0);wl_destroy(c,load64(c+56),0);store64(c+64,0);store64(c+56,0);store64(p+8,0);store64(p+16,1);store64(c+104,0);store64(c+88,0);store64(c+96,0);store64(p+48,0);store64(p+56,0);store64(p+128,0);store64(p+136,0);}}
    else{store64(p+104,0);if load64(p+16){let callback=wl_req(c,load64(c+8),0,ffi_symbol(load64(c),"wl_callback_interface"),wl_args(c,0,0,0,0,0,0),0);store64(p+160,wl_watch(c,callback,14,0));}else if load64(c+104){store64(p+24,load64(p+24)+1);}}return wt_flush(c);
}
fn wt_resize(c,width,height){
    let w=ws_pixels(width,ws_scale(c));let h=ws_pixels(height,ws_scale(c));if width<1 || height<1 || width>16384 || height>16384 || w>16384 || h>16384 || w>24000000/h{return wl_fail(0,"Requested native framebuffer exceeds the size limit");}let p=load64(c+456);store64(p+32,width);store64(p+40,height);if wt_constrained(load64(p+48)){store64(p+144,1);}else{store64(c+72,width);store64(c+80,height);store64(c+88,0);store64(c+96,0);}if !(load64(p+80)&1){wt_limits(c);}return wt_flush(c);
}
fn wt_mode(c,fullscreen,enabled){
    let p=load64(c+456);let at=88;let opcode=10;if enabled{opcode=9;}if fullscreen{at=96;opcode=12;if enabled{opcode=11;}}store64(p+at,enabled!=0);if load64(p+16){return 1;}wt_limits(c);wl_req(c,load64(c+64),opcode,0,wl_args(c,0,0,0,0,0,0),0);return wt_flush(c);
}
fn wt_minimize(c){let p=load64(c+456);if !load64(p){return 1;}store64(p+104,1);wl_req(c,load64(c+64),13,0,0,0);return wt_flush(c);}
fn wt_restore(c){let p=load64(c+456);store64(p+88,0);store64(p+96,0);if load64(p+104){wt_show(c,0);return wt_show(c,1);}if !wt_mode(c,1,0) || !wt_mode(c,0,0){return 0;}if !load64(p){return wt_show(c,1);}return 1;}
fn wt_close(c){let p=load64(c+456);if p{if load64(p+64){syscall(11,load64(p+64),load64(p+72)+1,0,0,0,0);}syscall(11,p,256,0,0,0,0);store64(c+456,0);}return 0;}
