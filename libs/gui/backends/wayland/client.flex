// Native Linux Wayland connection and xdg-shell surface. All protocol requests
// use the six-argument array API, and events use one typed array dispatcher.
// This first client owns one window; the GUI backend will share its connection.
import "protocols.flex";
import "../../../../lib/ffi.flex";
import "display.flex";
import "toplevel.flex";
import "presentation.flex";
global wl_error=0;
fn wl_equal(a,b){let i=0;while load8(a+i)==load8(b+i){if !load8(a+i){return 1;}i=i+1;}return 0;}
fn wl_zero(p,n){let i=0;while i<n{store64(p+i,0);i=i+8;}return p;}
fn wl_fail(c,text){wl_error=text;if c{store64(c+120,text);store64(c+112,1);}return 0;}
fn wl_symbol(c,name){return ffi_symbol(load64(c),name);}
fn wl_call(c,name,a,b,d,e,f,g){return ffi_call(wl_symbol(c,name),a,b,d,e,f,g);}
fn wl_int(c,name,a,b,d,e,f,g){return ffi_call_i32(wl_symbol(c,name),a,b,d,e,f,g);}
fn wl_args(c,a,b,d,e,f,g){let p=c+256;store64(p,a);store64(p+8,b);store64(p+16,d);store64(p+24,e);store64(p+32,f);store64(p+40,g);return p;}
fn wl_req(c,proxy,opcode,iface,args,destroy){
    let wrapper=0;if load64(c+472) && iface && (proxy==load64(c+8) || proxy==load64(c+48)){wrapper=wl_call(c,"wl_proxy_create_wrapper",proxy,0,0,0,0,0);if !wrapper{return wl_fail(c,"Cannot wrap borrowed Wayland factory");}wl_call(c,"wl_proxy_set_queue",wrapper,load64(c+472),0,0,0,0);proxy=wrapper;}
    let version=wl_call(c,"wl_proxy_get_version",proxy,0,0,0,0,0);let result=wl_call(c,"wl_proxy_marshal_array_flags",proxy,opcode,iface,version,destroy,args);if wrapper{wl_call(c,"wl_proxy_wrapper_destroy",wrapper,0,0,0,0,0);}return result;
}
// Metadata: proxy, dispatch kind, connection, next, object-specific user data.
fn wl_watch(c,proxy,kind,user){
    if !proxy{return wl_fail(c,"Wayland object allocation failed");}
    let m=load64(c+200);while m && (load64(m) || load64(m+8)!=kind){m=load64(m+24);}
    if !m{m=alloc(40);if m<0{return wl_fail(c,"Wayland listener allocation failed");}store64(m+24,load64(c+200));store64(c+200,m);}
    store64(m,proxy);store64(m+8,kind);store64(m+16,c);store64(m+32,user);
    if load64(c+472){wl_call(c,"wl_proxy_set_queue",proxy,load64(c+472),0,0,0,0);}let dispatcher=load64(c+480);if !dispatcher{dispatcher=native_callback(wl_dispatch);}
    if wl_int(c,"wl_proxy_add_dispatcher",proxy,dispatcher,m,m,0,0)!=0{return wl_fail(c,"Cannot install Wayland dispatcher");}return proxy;
}
fn wl_destroy(c,proxy,request){
    if !proxy{return 0;}let m=load64(c+200);while m{if load64(m)==proxy{store64(m,0);}m=load64(m+24);}
    if request>=0{wl_req(c,proxy,request,0,0,1);}else{wl_call(c,"wl_proxy_destroy",proxy,0,0,0,0,0);}return 0;
}
fn wl_bind(c,name,iface,version,kind){return wl_bind_user(c,name,iface,version,kind,0);}
fn wl_bind_user(c,name,iface,version,kind,user){
    if !iface{return wl_fail(c,"Required Wayland interface metadata is unavailable");}let supported=bytes_load32(iface+8);if version>supported{version=supported;}
    let args=wl_args(c,name,load64(iface),version,0,0,0);
    let proxy=wl_call(c,"wl_proxy_marshal_array_flags",load64(c+16),0,iface,version,0,args);
    return wl_watch(c,proxy,kind,user);
}
fn wl_dispatch(metadata,proxy,opcode,message,args,unused){
    let c=load64(metadata+16);let kind=load64(metadata+8);let lib=load64(c);
    if kind==1{
        if opcode==0{let id=bytes_load32(args);let name=load64(args+8);let version=bytes_load32(args+16);
            if wl_equal(name,"wl_compositor") && !load64(c+24){if version>6{version=6;}store64(c+24,wl_bind(c,id,ffi_symbol(lib,"wl_compositor_interface"),version,3));store64(c+224,id);}
            else if wl_equal(name,"wl_shm") && !load64(c+32){store64(c+32,wl_bind(c,id,ffi_symbol(lib,"wl_shm_interface"),1,6));store64(c+232,id);}
            else if wl_equal(name,"xdg_wm_base") && !load64(c+40){if version>6{version=6;}store64(c+40,wl_bind(c,id,wp_i_xdg_wm_base,version,2));store64(c+240,id);}
        }else if opcode==1{let id=bytes_load32(args);if id==load64(c+224) || id==load64(c+232) || id==load64(c+240){wl_fail(c,"Required Wayland global was removed");}}
    }else if kind==2 && opcode==0{wl_req(c,proxy,3,0,wl_args(c,bytes_load32(args),0,0,0,0,0),0);}
    else if kind==4 && opcode==0{
        wl_req(c,proxy,4,0,wl_args(c,bytes_load32(args),0,0,0,0,0),0);wt_configured(c);
    }else if kind==5{
        if opcode==0{wt_pending(c,bytes_load32(args),bytes_load32(args+8),load64(args+16));}
        else if opcode==1{store64(c+112,1);}
    }else if kind==7 && opcode==0{store64(load64(metadata+32)+40,0);}
    else if kind==8 && opcode==0{store64(c+168,0);store64(c+208,load64(c+208)+1);wl_destroy(c,proxy,-1);}
    else if kind==13 && opcode==0{store64(c+152,1);wl_destroy(c,proxy,-1);}
    else if kind==14 && opcode==0{wt_remap(c,proxy);}
    wpd_dispatch(c,metadata,proxy,opcode,args);ws_dispatch(c,metadata,proxy,opcode,args);if load64(c+184) && (kind==1 || kind>=20){ffi_call(load64(c+184),metadata,proxy,opcode,message,args,0);}
    store64(c+176,load64(c+176)+1);return 0;
}
// Optional private queue for a borrowed display; native clients use queue 0.
fn wl_pending(c){if load64(c+472){return wl_int(c,"wl_display_dispatch_queue_pending",load64(c+8),load64(c+472),0,0,0,0);}return wl_int(c,"wl_display_dispatch_pending",load64(c+8),0,0,0,0,0);}
fn wl_prepare(c){if load64(c+472){return wl_int(c,"wl_display_prepare_read_queue",load64(c+8),load64(c+472),0,0,0,0);}return wl_int(c,"wl_display_prepare_read",load64(c+8),0,0,0,0,0);}
fn wl_client_wait(c,ms){
    if !c || ms<0 || ms>2147483647{return wl_fail(c,"Invalid Wayland wait");}if load64(c+112){return 0;}
    let display=load64(c+8);let pending=wl_pending(c);if pending<0{return wl_fail(c,"Wayland dispatch failed");}if load64(c+112){return 0;}if pending>0{return 1;}
    // Prepare/read/cancel must remain paired even for timeouts and EINTR.
    let prepared=wl_prepare(c);let attempts=0;
    while prepared!=0 && attempts<64{pending=wl_pending(c);if pending<0{return wl_fail(c,"Wayland dispatch failed");}if pending>0{return 1;}prepared=wl_prepare(c);attempts=attempts+1;}
    if prepared!=0{return wl_fail(c,"Wayland event queue did not settle");}
    let events=1;if wl_int(c,"wl_display_flush",display,0,0,0,0,0)<0{let error=wl_int(c,"wl_display_get_error",display,0,0,0,0,0);if error{wl_call(c,"wl_display_cancel_read",display,0,0,0,0,0);return wl_fail(c,"Wayland connection failed");}events=events|4;}
    let poll=c+384;let count=1;if load64(c+136){poll=load64(c+136);count=load64(c+144);}store64(poll,load64(c+128)|(events<<32));let ready=syscall(7,poll,count,ms,0,0,0);
    if ready<=0{wl_call(c,"wl_display_cancel_read",display,0,0,0,0,0);if ready<0 && ready!=-4{return wl_fail(c,"Wayland socket polling failed");}return 1;}
    let result=(load64(poll)>>48)&65535;
    if result&1{if wl_int(c,"wl_display_read_events",display,0,0,0,0,0)<0{return wl_fail(c,"Wayland connection closed");}}
    else{wl_call(c,"wl_display_cancel_read",display,0,0,0,0,0);}
    if result&56{return wl_fail(c,"Wayland socket closed");}
    if result&4{wl_int(c,"wl_display_flush",display,0,0,0,0,0);}
    if wl_pending(c)<0{return wl_fail(c,"Wayland dispatch failed");}return !load64(c+112);
}
fn wl_now(c){syscall(228,1,c+400,0,0,0,0);return load64(c+400)*1000+load64(c+408)/1000000;}
fn wl_sync(c){
    store64(c+152,0);let callback=wl_req(c,load64(c+8),0,ffi_symbol(load64(c),"wl_callback_interface"),wl_args(c,0,0,0,0,0,0),0);if !wl_watch(c,callback,13,0){return 0;}
    let until=wl_now(c)+3000;while !load64(c+152) && !load64(c+112) && wl_now(c)<until{wl_client_wait(c,20);}if !load64(c+152){return wl_fail(c,"Wayland handshake timed out");}return 1;
}
fn wl_client_close(c){
    if !c{return 0;}let m=load64(c+200);while m{let next=load64(m+24);if load64(m){wl_call(c,"wl_proxy_destroy",load64(m),0,0,0,0,0);}syscall(11,m,40,0,0,0,0);m=next;}
    if load64(c+8){wl_call(c,"wl_display_disconnect",load64(c+8),0,0,0,0,0);}
    let b=load64(c+160);while b{let next=load64(b+48);if load64(b+8){syscall(11,load64(b+8),load64(b+16),0,0,0,0);}syscall(11,b,56,0,0,0,0);b=next;}
    wpd_close(c);wt_close(c);ws_close(c);wp_protocol_close();if load64(c){ffi_close(load64(c));}syscall(11,c,512,0,0,0,0);return 0;
}
fn wl_client_open(socket_name,title,width,height){return wl_client_open_with(socket_name,title,width,height,0,0);}
fn wl_client_open_with(socket_name,title,width,height,dispatch,user){
    return wl_client_open_flags(socket_name,title,width,height,dispatch,user,1);
}
fn wl_client_open_flags(socket_name,title,width,height,dispatch,user,flags){
    wl_error=0;if wp_protocol_memory{return wl_fail(0,"One native Wayland connection is supported");}
    if width<1 || height<1 || width>16384 || height>16384 || width>24000000/height{return wl_fail(0,"Invalid Wayland window dimensions");}
    let c=alloc(512);if c<0{return wl_fail(0,"Wayland connection allocation failed");}wl_zero(c,512);store64(c+72,width);store64(c+80,height);store64(c+184,dispatch);store64(c+192,user);
    if !wt_context(c,title,width,height,flags){wl_client_close(c);return 0;}
    store64(c+448,ws_context());if !load64(c+448){wl_client_close(c);return wl_fail(0,"Cannot allocate native display state");}
    store64(c+464,wpd_context());if !load64(c+464){wl_client_close(c);return wl_fail(0,"Cannot allocate presentation state");}
    let lib=ffi_open("libwayland-client.so.0");store64(c,lib);if !lib{wl_client_close(c);return wl_fail(0,"libwayland-client is required");}
    if !wp_protocol_init(lib){wl_client_close(c);return wl_fail(0,"Cannot allocate Wayland protocol metadata");}
    let display=wl_call(c,"wl_display_connect",socket_name,0,0,0,0,0);store64(c+8,display);if !display{wl_client_close(c);return wl_fail(0,"Cannot connect to the Wayland display");}
    store64(c+128,wl_int(c,"wl_display_get_fd",display,0,0,0,0,0));
    let registry=wl_req(c,display,1,ffi_symbol(lib,"wl_registry_interface"),wl_args(c,0,0,0,0,0,0),0);store64(c+16,registry);wl_watch(c,registry,1,0);
    if !wl_sync(c) || !load64(c+24) || !load64(c+32) || !load64(c+40){wl_client_close(c);return wl_fail(0,"Wayland compositor, shared memory and xdg-shell are required");}
    let surface=wl_req(c,load64(c+24),0,ffi_symbol(lib,"wl_surface_interface"),wl_args(c,0,0,0,0,0,0),0);store64(c+48,surface);wl_watch(c,surface,3,0);
    ws_attach(c);
    if !wt_role(c){wl_client_close(c);return 0;}
    wt_attributes(c);
    wl_req(c,surface,6,0,0,0);let until=wl_now(c)+3000;while !load64(c+104) && !load64(c+112) && wl_now(c)<until{wl_client_wait(c,20);}
    if !load64(c+104) || load64(c+112){wl_client_close(c);return wl_fail(0,"Wayland window configure failed");}return c;
}
fn wl_client_buffer(c){
    let width=ws_width(c);let height=ws_height(c);let b=load64(c+160);let free=0;
    while b{if !load64(b+40){if load64(b+24)==width && load64(b+32)==height{return b;}free=b;}b=load64(b+48);}
    if !free{if load64(c+216)>=3{return 0;}free=alloc(56);if free<0{return wl_fail(c,"Wayland buffer allocation failed");}wl_zero(free,56);store64(free+48,load64(c+160));store64(c+160,free);store64(c+216,load64(c+216)+1);}
    if load64(free){wl_destroy(c,load64(free),0);store64(free,0);}if load64(free+8){syscall(11,load64(free+8),load64(free+16),0,0,0,0);store64(free+8,0);}
    let bytes=width*height*4;let fd=syscall(319,"flexscript-wayland",1,0,0,0,0);if fd<0{return wl_fail(c,"Cannot create Wayland shared memory");}
    if syscall(77,fd,bytes,0,0,0,0)<0{syscall(3,fd,0,0,0,0,0);return wl_fail(c,"Cannot size Wayland shared memory");}
    let pixels=syscall(9,0,bytes,3,1,fd,0);if pixels<0{syscall(3,fd,0,0,0,0,0);return wl_fail(c,"Cannot map Wayland shared memory");}
    store64(free+8,pixels);store64(free+16,bytes);store64(free+24,width);store64(free+32,height);
    let pool=wl_req(c,load64(c+32),0,ffi_symbol(load64(c),"wl_shm_pool_interface"),wl_args(c,0,fd,bytes,0,0,0),0);syscall(3,fd,0,0,0,0,0);
    let buffer=wl_req(c,pool,0,ffi_symbol(load64(c),"wl_buffer_interface"),wl_args(c,0,0,width,height,width*4,0),0);store64(free,buffer);wl_watch(c,buffer,7,free);wl_req(c,pool,1,0,0,1);return free;
}
fn wl_client_present_shm(c,color){
    if !c || !wt_ready(c) || load64(c+168){return 0;}let buffer=wl_client_buffer(c);if !buffer{return 0;}
    let p=load64(buffer+8);let end=p+load64(buffer+16);while p<end{bytes_store32(p,color);p=p+4;}
    let surface=load64(c+48);let callback=wl_req(c,surface,3,ffi_symbol(load64(c),"wl_callback_interface"),wl_args(c,0,0,0,0,0,0),0);wl_watch(c,callback,8,0);store64(c+168,callback);
    if !wpd_submit(c){return 0;}store64(buffer+40,1);wl_req(c,surface,1,0,wl_args(c,load64(buffer),0,0,0,0,0),0);
    if !ws_apply(c) || !wt_geometry(c) || !wt_opaque(c,1){return 0;}let damage=2;if wl_call(c,"wl_proxy_get_version",surface,0,0,0,0,0)>=4{damage=9;}wl_req(c,surface,damage,0,wl_args(c,0,0,ws_width(c),ws_height(c),0,0),0);wl_req(c,surface,6,0,0,0);wl_int(c,"wl_display_flush",load64(c+8),0,0,0,0,0);return wt_presented(c);
}
