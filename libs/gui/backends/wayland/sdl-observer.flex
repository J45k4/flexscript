// Optional comparison instrumentation, never a native renderer dependency.
// Borrow SDL's display/surface without changing their listener or event queue.
// One private registry/queue per GUI lifetime; one instrumented SDL window.
// c+472 queue, +480 dispatcher, +488 protocol reference, +496 owner GUI record.
// SDL record +696 points here only while it owns the observer.
global gd_context=0;
fn gd_output_remove(c,id){let p=load64(c+448);let previous=0;let node=load64(p+56);while node{let next=load64(node+16);if load64(node+8)==id{if previous{store64(previous+16,next);}else{store64(p+56,next);}wl_destroy(c,load64(node),0);syscall(11,node,48,0,0,0,0);store64(p+64,load64(p+64)-1);return 1;}previous=node;node=next;}return 0;}
fn gd_dispatch(metadata,proxy,opcode,message,args,unused){
    let c=load64(metadata+16);let kind=load64(metadata+8);let p=load64(c+448);
    if kind==1 && opcode==0 && wl_equal(load64(args+8),"wl_output") && bytes_load32(args+16)>=3{if load64(p+64)>=32{return wl_fail(c,"Observer output limit exceeded");}let node=alloc(48);if node<0{return wl_fail(c,"Cannot allocate observer output");}bytes_fill(node,0,48);store64(node+8,bytes_load32(args));store64(node+16,load64(p+56));store64(p+56,node);store64(p+64,load64(p+64)+1);let version=bytes_load32(args+16);if version>4{version=4;}store64(node,wl_bind_user(c,bytes_load32(args),ffi_symbol(load64(c),"wl_output_interface"),version,44,node));}
    else if kind==1 && opcode==1{gd_output_remove(c,bytes_load32(args));}
    else if kind==8 && opcode==0{if load64(c+168)==proxy{store64(c+168,0);store64(c+208,load64(c+208)+1);}wl_destroy(c,proxy,-1);}
    else if kind==13 && opcode==0{store64(c+152,1);wl_destroy(c,proxy,-1);}
    wpd_dispatch(c,metadata,proxy,opcode,args);store64(c+176,load64(c+176)+1);return 0;
}
fn gd_frame_cancel(c){if load64(c+168){wl_destroy(c,load64(c+168),-1);store64(c+168,0);}return 0;}
fn gd_reset(c){let p=load64(c+464);if !p{return 0;}wpd_cancel(c);gd_frame_cancel(c);if load64(p+128){syscall(11,load64(p+128),40960,0,0,0,0);}let manager=load64(p);let global_id=load64(p+8);let clock=load64(p+16);let valid=load64(p+24);bytes_fill(p,0,256);store64(p,manager);store64(p+8,global_id);store64(p+16,clock);store64(p+24,valid);return 0;}
fn gd_release(record){let c=load64(record+696);if !c{return 0;}gd_reset(c);store64(record+696,0);store64(c+496,0);store64(c+48,0);store64(c+104,0);store64(load64(c+456),0);return 0;}
fn gd_stop(){
    let c=gd_context;if !c{return 0;}if load64(c+496){gd_release(load64(c+496));}let p=load64(c+464);if p && load64(p){wl_destroy(c,load64(p),0);}let outputs=load64(c+448);if outputs{let node=load64(outputs+56);while node{if load64(node){wl_destroy(c,load64(node),0);}node=load64(node+16);}}
    let m=load64(c+200);while m{let next=load64(m+24);if load64(m){wl_call(c,"wl_proxy_destroy",load64(m),0,0,0,0,0);}syscall(11,m,40,0,0,0,0);m=next;}if load64(c+472){wl_call(c,"wl_event_queue_destroy",load64(c+472),0,0,0,0,0);}wpd_close(c);wt_close(c);ws_close(c);if load64(c+488){wp_protocol_close();}if load64(c){ffi_close(load64(c));}syscall(11,c,512,0,0,0,0);gd_context=0;return 0;
}
fn gd_refresh(record,c){
    let info=c+304;bytes_fill(info,0,72);gui__call("SDL_GetVersion",info,0,0,0,0,0);if !gui__int("SDL_GetWindowWMInfo",load64(record),info,0,0,0,0) || bytes_load32(info+4)!=6{return 0;}let display=load64(info+8);let surface=load64(info+16);if !display || !surface{return 0;}if load64(c+8) && load64(c+8)!=display{return wl_fail(c,"SDL changed the observed Wayland connection");}store64(c+8,display);if load64(c+48)!=surface{wpd_cancel(c);gd_frame_cancel(c);store64(c+48,surface);}let flags=gui__call("SDL_GetWindowFlags",load64(record),0,0,0,0,0);store64(load64(c+456),(flags&4)!=0 && !(flags&72));store64(c+104,1);return 1;
}
fn gd_open(record){
    let driver=gui_video_driver();if !driver || !wl_equal(driver,"wayland") || load64(record+648){return 0;}let c=gd_context;if c{if load64(c+112){return gui__fail(load64(c+120));}if load64(c+496) && load64(c+496)!=record{return 0;}if !gd_refresh(record,c){return 0;}return c;}
    c=alloc(512);if c<0{return 0;}bytes_fill(c,0,512);gd_context=c;store64(c+448,ws_context());store64(c+456,alloc(256));if load64(c+456)>0{bytes_fill(load64(c+456),0,256);}store64(c+464,wpd_context());if !load64(c+448) || load64(c+456)<0 || !load64(c+464){if load64(c+456)<0{store64(c+456,0);}gd_stop();return 0;}
    let lib=ffi_open("libwayland-client.so.0");store64(c,lib);if !lib || !wp_protocol_init(lib){gd_stop();return 0;}store64(c+488,1);if !gd_refresh(record,c){gd_stop();return 0;}let queue=wl_call(c,"wl_display_create_queue",load64(c+8),0,0,0,0,0);store64(c+472,queue);store64(c+480,native_callback(gd_dispatch));if !queue{gd_stop();return 0;}store64(c+128,wl_int(c,"wl_display_get_fd",load64(c+8),0,0,0,0,0));let registry=wl_req(c,load64(c+8),1,ffi_symbol(lib,"wl_registry_interface"),wl_args(c,0,0,0,0,0,0),0);store64(c+16,wl_watch(c,registry,1,0));if !load64(c+16) || !wl_sync(c) || !wl_sync(c){gd_stop();return 0;}return c;
}
fn gd_enable(record,enabled){if !enabled{let c=load64(record+696);if !c{return 1;}gd_frame_cancel(c);return wpd_enable(c,0);}let c=gd_open(record);if !c || !wpd_enable(c,1){return 0;}store64(c+496,record);store64(record+696,c);return 1;}
fn gd_pending(){let c=gd_context;if !c || !load64(c+472) || load64(c+112){return 0;}let n=wl_pending(c);if n<0{wl_fail(c,"SDL observer dispatch failed");wpd_cancel(c);gd_frame_cancel(c);return 0;}return n;}
fn gd_active(){let c=gd_context;return c && load64(c+496) && load64(load64(c+464)+32);}
fn gd_wait(ms){
    let c=gd_context;gui__call("SDL_PumpEvents",0,0,0,0,0,0);let events=gd_pending();if gui__int("SDL_HasEvents",0,65535,0,0,0,0)>0{return 1;}if events || load64(c+112){return 0;}
    // Wayland wakes immediately; bounded fallback also services SDL events
    // pushed by other threads/devices that have no Wayland socket readiness.
    if ms>16{ms=16;}wl_client_wait(c,ms);if load64(c+112){wpd_cancel(c);gd_frame_cancel(c);}gui__call("SDL_PumpEvents",0,0,0,0,0,0);gd_pending();return gui__int("SDL_HasEvents",0,65535,0,0,0,0)>0;
}
fn gd_submit(record){let c=load64(record+696);if !c || !load64(load64(c+464)+32){return 1;}if !gd_refresh(record,c) || !wt_ready(c){wpd_cancel(c);gd_frame_cancel(c);return 1;}if !wpd_submit(c){return gui__fail(wl_error);}if !load64(c+168){let callback=wl_req(c,load64(c+48),3,ffi_symbol(load64(c),"wl_callback_interface"),wl_args(c,0,0,0,0,0,0),0);store64(c+168,wl_watch(c,callback,8,0));if !load64(c+168){return gui__fail(wl_error);}}return 1;}
