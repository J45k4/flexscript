// Compositor shapes, with themed/animated fallback. Theme buffers are immutable.
// Four cached integer densities; one cursor surface and at most one callback.
// State: lib0/surface8/manager16/device24, kind32, enter serial40,
// last kind48/scale56, themes64..88, inside96, pointer104, force fallback112,
// updates120, theme name128, size136, last path144 (1 shape, 2 theme),
// selected cursor152, animation start ns160/deadline168/frame176/period ns184,
// callback192, callback count200, image commits208, manager global216,
// image-buffer fn224, theme-get fn232, theme-destroy fn240, reserved248.
fn wn_context(){let p=alloc(256);if p<0{return 0;}bytes_fill(p,0,256);store64(p+48,-1);store64(p+176,-1);store64(p+136,24);return p;}
fn wn_stop(c,p){if load64(p+192) && c{wl_destroy(c,load64(p+192),-1);}store64(p+192,0);store64(p+152,0);store64(p+160,0);store64(p+168,0);store64(p+176,-1);store64(p+184,0);return 0;}
fn wn_environment(p){
    let libc=ffi_open("libc.so.6");if !libc{return 0;}let getenv=ffi_symbol(libc,"getenv");let name=ffi_call(getenv,"XCURSOR_THEME",0,0,0,0,0);if name{let n=0;while n<255 && load8(name+n){n=n+1;}if n<255{let owned=alloc(n+1);if owned>0{bytes_copy(owned,name,n+1);store64(p+128,owned);}}}
    let size=ffi_call(getenv,"XCURSOR_SIZE",0,0,0,0,0);if size{let value=0;let i=0;while i<4 && load8(size+i)>=48 && load8(size+i)<=57{value=value*10+load8(size+i)-48;i=i+1;}if !load8(size+i) && value>=8 && value<=128{store64(p+136,value);}}ffi_close(libc);return 1;
}
fn wn_device(c,p){
    if load64(p+24){wl_destroy(c,load64(p+24),0);store64(p+24,0);}if load64(p+104) && load64(p+16){let device=wl_req(c,load64(p+16),1,wp_i_wp_cursor_shape_device_v1,wl_args(c,0,load64(p+104),0,0,0,0),0);store64(p+24,wl_watch(c,device,54,0));}store64(p+48,-1);return 1;
}
fn wn_pointer(c,p,pointer){if pointer==load64(p+104){return 1;}wn_stop(c,p);store64(p+96,0);store64(p+104,pointer);return wn_device(c,p);}
fn wn_dispatch(c,w,metadata,opcode,args){
    let p=load64(w+248);let kind=load64(metadata+8);
    if kind==1 && opcode==0 && wl_equal(load64(args+8),"wp_cursor_shape_manager_v1") && !load64(p+16){store64(p+216,bytes_load32(args));store64(p+16,wl_bind(c,bytes_load32(args),wp_i_wp_cursor_shape_manager_v1,1,53));wn_stop(c,p);wn_device(c,p);}
    else if kind==1 && opcode==1 && load64(p+216) && bytes_load32(args)==load64(p+216){wn_stop(c,p);if load64(p+24){wl_destroy(c,load64(p+24),0);store64(p+24,0);}wl_destroy(c,load64(p+16),0);store64(p+16,0);store64(p+216,0);store64(p+48,-1);}
    else if kind==20 && opcode==0{wn_pointer(c,p,load64(w+32));}
    else if kind==21 && opcode==0{wn_stop(c,p);store64(p+40,bytes_load32(args));store64(p+96,1);store64(p+48,-1);}
    else if kind==21 && opcode==1{store64(p+96,0);wn_stop(c,p);store64(p+48,-1);}
    else if kind==55 && opcode==0{if load64(p+192)==load64(metadata){store64(p+192,0);store64(p+200,load64(p+200)+1);wl_destroy(c,load64(metadata),-1);}}
    return 0;
}
fn wn_theme(c,p,scale){
    let at=p+64+(scale-1)*8;if load64(at){return load64(at);}
    if !load64(p){store64(p,ffi_open("libwayland-cursor.so.0"));if !load64(p){return gui__fail("libwayland-cursor is required for themed cursors");}store64(p+224,ffi_symbol(load64(p),"wl_cursor_image_get_buffer"));store64(p+232,ffi_symbol(load64(p),"wl_cursor_theme_get_cursor"));store64(p+240,ffi_symbol(load64(p),"wl_cursor_theme_destroy"));if !load64(p+224) || !load64(p+232) || !load64(p+240){return gui__fail("Wayland cursor library entry point missing");}wn_environment(p);}
    let theme=ffi_call(ffi_symbol(load64(p),"wl_cursor_theme_load"),load64(p+128),load64(p+136)*scale,load64(c+32),0,0,0);if !theme{return gui__fail("Cannot load the Wayland cursor theme");}store64(at,theme);return theme;
}
// Public wayland-cursor.h LP64 layout. No protocol or FFI calls in selection.
fn wn_select(p,cursor,now){
    if !cursor || now<0{return gui__fail("Invalid cursor animation");}let count=bytes_load32(cursor);let images=load64(cursor+8);if count<1 || count>1024 || !images{return gui__fail("Cursor image count exceeds supported bounds");}let period=0;let i=0;
    while i<count{let image=load64(images+i*8);if !image{return gui__fail("Cursor image missing");}let width=bytes_load32(image);let height=bytes_load32(image+4);if width<1 || height<1 || width>4096 || height>4096 || bytes_load32(image+8)>=width || bytes_load32(image+12)>=height{return gui__fail("Invalid cursor image dimensions or hotspot");}period=period+bytes_load32(image+16)*1000000;i=i+1;}
    if count==1{period=0;}store64(p+152,cursor);store64(p+160,now);store64(p+168,0);store64(p+176,-1);store64(p+184,period);return 1;
}
fn wn_frame(p,now){
    let period=load64(p+184);if !period{store64(p+168,0);return 0;}let elapsed=now-load64(p+160);if elapsed<0{elapsed=0;}let phase=elapsed%period;let cursor=load64(p+152);let images=load64(cursor+8);let count=bytes_load32(cursor);let i=0;
    while i<count{let duration=bytes_load32(load64(images+i*8)+16)*1000000;if phase<duration{store64(p+168,now+duration-phase);return i;}phase=phase-duration;i=i+1;}return gui__fail("Invalid cursor animation period");
}
fn wn_timeout(p,ms){if !load64(p+96) || !load64(p+104) || !load64(p+184) || load64(p+192){return ms;}let left=(load64(p+168)-gui_monotonic_ns()+999999)/1000000;if left<0{left=0;}if left<ms{return left;}return ms;}
fn wn_flush(c){if wl_int(c,"wl_display_flush",load64(c+8),0,0,0,0,0)<0 && wl_int(c,"wl_display_get_error",load64(c+8),0,0,0,0,0){return wl_fail(c,"Cannot submit native cursor");}return 1;}
fn wn_image(c,p,index,scale){
    let cursor=load64(p+152);let image=load64(load64(cursor+8)+index*8);let width=bytes_load32(image);let height=bytes_load32(image+4);let hx=bytes_load32(image+8)/scale;let hy=bytes_load32(image+12)/scale;let buffer=ffi_call(load64(p+224),image,0,0,0,0,0);if !buffer{return gui__fail("Cannot create the cursor buffer");}
    if !load64(p+8){let surface=wl_req(c,load64(c+24),0,ffi_symbol(load64(c),"wl_surface_interface"),wl_args(c,0,0,0,0,0,0),0);store64(p+8,wl_watch(c,surface,52,0));}let surface=load64(p+8);let version=wl_call(c,"wl_proxy_get_version",surface,0,0,0,0,0);
    wl_req(c,load64(p+104),0,0,wl_args(c,load64(p+40),surface,hx,hy,0,0),0);if version>=3{wl_req(c,surface,8,0,wl_args(c,scale,0,0,0,0,0),0);}
    if load64(p+184){let callback=wl_req(c,surface,3,ffi_symbol(load64(c),"wl_callback_interface"),wl_args(c,0,0,0,0,0,0),0);store64(p+192,wl_watch(c,callback,55,0));if !load64(p+192){return 0;}}
    wl_req(c,surface,1,0,wl_args(c,buffer,0,0,0,0,0),0);let damage=9;if version<4{damage=2;width=(width+scale-1)/scale;height=(height+scale-1)/scale;}wl_req(c,surface,damage,0,wl_args(c,0,0,width,height,0,0),0);wl_req(c,surface,6,0,0,0);
    store64(p+176,index);store64(p+144,2);store64(p+120,load64(p+120)+1);store64(p+208,load64(p+208)+1);return wn_flush(c);
}
fn wn_apply(c,p){
    if !load64(p+96) || !load64(p+104){if load64(p+152) || load64(p+192){wn_stop(c,p);}return 1;}let kind=load64(p+32);let scale=(ws_scale(c)+119)/120;let shape=load64(p+24) && !load64(p+112);if !shape && wl_call(c,"wl_proxy_get_version",load64(c+48),0,0,0,0,0)<3{scale=1;}
    let path=2;if shape{path=1;}let changed=kind!=load64(p+48) || scale!=load64(p+56) || path!=load64(p+144);
    if shape{if !changed{return 1;}wn_stop(c,p);let value=1;if kind==1{value=26;}wl_req(c,load64(p+24),1,0,wl_args(c,load64(p+40),value,0,0,0,0),0);store64(p+144,1);store64(p+48,kind);store64(p+56,scale);store64(p+120,load64(p+120)+1);return wn_flush(c);}
    let now=gui_monotonic_ns();if changed || !load64(p+152){wn_stop(c,p);let theme=wn_theme(c,p,scale);if !theme{return 0;}let name="left_ptr";if kind==1{name="ew-resize";}let cursor=ffi_call(load64(p+232),theme,name,0,0,0,0);if !cursor{if kind==1{name="sb_h_double_arrow";}else{name="default";}cursor=ffi_call(load64(p+232),theme,name,0,0,0,0);}now=gui_monotonic_ns();if !wn_select(p,cursor,now){return 0;}let index=wn_frame(p,now);if !wn_image(c,p,index,scale){return 0;}store64(p+48,kind);store64(p+56,scale);return 1;}
    if load64(p+192) || !load64(p+184) || now<load64(p+168){return 1;}let index=wn_frame(p,now);if index!=load64(p+176){return wn_image(c,p,index,scale);}return 1;
}
fn wn_set(c,w,kind){if kind!=0 && kind!=1{return gui__fail("Unknown GUI cursor");}let p=load64(w+248);store64(p+32,kind);return wn_apply(c,p);}
fn wn_close(c,p){
    if !p{return 0;}wn_stop(c,p);if c && load64(p+24){wl_destroy(c,load64(p+24),0);}if c && load64(p+8){wl_destroy(c,load64(p+8),0);}if c && load64(p+16){wl_destroy(c,load64(p+16),0);}
    if load64(p){let i=0;while i<4{let theme=load64(p+64+i*8);if theme && load64(p+240){ffi_call(load64(p+240),theme,0,0,0,0,0);}i=i+1;}ffi_close(load64(p));}if load64(p+128){let name=load64(p+128);let n=0;while load8(name+n){n=n+1;}syscall(11,name,n+1,0,0,0,0);}syscall(11,p,256,0,0,0,0);return 0;
}
