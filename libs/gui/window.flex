import "metrics.flex";
import "platform.flex";
import "wait.flex";
import "presentation.flex";
// All GUI operations belong on the main thread. No SDL headers or linker needed.
// Private record layout and SDL2 ABI are contained in this module.
global GUI_RESIZABLE=1;
global GUI_HIDDEN=2;
global GUI_HIGH_DPI=4;
global GUI_QUIT=1;
global GUI_CLOSE=2;
global GUI_RESIZE=3;
global GUI_FOCUS=4;
global GUI_KEY_DOWN=5;
global GUI_KEY_UP=6;
global GUI_TEXT=7;
global GUI_MOUSE_MOVE=8;
global GUI_MOUSE_DOWN=9;
global GUI_MOUSE_UP=10;
global GUI_WHEEL=11;
global GUI_EXPOSE=12;
global GUI_RENDER_RESET=13;
global GUI_CLIPBOARD=14;
global GUI_IME=15;
global GUI_KEY_ESCAPE=41;
global GUI_KEY_LEFT=80;
global GUI_KEY_RIGHT=79;
global GUI_KEY_UP_ARROW=82;
global GUI_KEY_DOWN_ARROW=81;
global gui_error=0;
global gui__sdl=0;
global gui__initialized=0;
global gui__records=0;
global gui__raw=0;
global gui__scratch=0;
global gui__poll_fn=0;
global gui__relative=0;
global gui__gl_current=0;
fn gui__zero(p,n) {let i=0;while i<n {store8(p+i,0);i=i+1;}return p;}
fn gui__u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn gui__i32(p) {let n=gui__u32(p);if n&0x80000000 {return n-0x100000000;}return n;}
fn gui__put32(p,n) {let i=0;while i<4 {store8(p+i,n>>(i*8));i=i+1;}return 0;}
fn gui__fail(message) {gui_error=message;return 0;}
fn gui__symbol(name) {
    if !gui__sdl {return gui__fail("GUI is not initialized");}
    let p=ffi_symbol(gui__sdl,name);if !p {gui_error=name;}return p;
}
fn gui__call(name,a,b,c,d,e,f) {
    let p=gui__symbol(name);if !p {return 0;}return ffi_call(p,a,b,c,d,e,f);
}
fn gui__int(name,a,b,c,d,e,f) {
    let p=gui__symbol(name);if !p {return -1;}return ffi_call_i32(p,a,b,c,d,e,f);
}
fn gui__sdl_error() {
    // Copy SDL's transient error, so cleanup cannot overwrite the explanation.
    let text=gui__call("SDL_GetError",0,0,0,0,0,0);
    if !text {return gui__fail("SDL operation failed");}
    let i=0;while i<1023 && load8(text+i) {store8(gui__scratch+64+i,load8(text+i));i=i+1;}
    store8(gui__scratch+64+i,0);gui_error=gui__scratch+64;return 0;
}
fn gui_init() {
    if gui__initialized {return 1;}
    if !gui__backend_selected && !gn_configure(){return 0;}
    if !gui__records {
        gui__records=gui__zero(alloc(32*704),32*704);
        gui__raw=alloc(64);gui__scratch=alloc(1088);
    }
    if gui__native{gui__initialized=1;gui_error=0;return 1;}
    if !gui__sdl {gui__sdl=ffi_open("libSDL2-2.0.so.0");}
    if !gui__sdl {return gui__fail("SDL2 runtime is required (libSDL2-2.0.so.0)");}
    gui__call("SDL_GetVersion",gui__scratch,0,0,0,0,0);
    if load8(gui__scratch)!=2 || load8(gui__scratch+1)<26 {return gui__fail("SDL2 2.26 or newer is required");}
    if gui__int("SDL_InitSubSystem",32,0,0,0,0,0)<0 {return gui__sdl_error();}
    gui__poll_fn=gui__symbol("SDL_PollEvent");
    if !gui__poll_fn {gui__call("SDL_QuitSubSystem",32,0,0,0,0,0);return 0;}
    gui__initialized=1;gui_error=0;return 1;
}
fn gui__record(window) {
    let slot=(window&255)-1;
    if !gui__records || window<=0 || slot<0 || slot>=32 {return gui__fail("Invalid or closed GUI window");}
    let p=gui__records+slot*704;
    if !load64(p) || load64(p+48)!=(window>>8) {return gui__fail("Invalid or closed GUI window");}
    return p;
}
fn gui__handle(p) {return (load64(p+48)<<8)|((p-gui__records)/704+1);}
fn gui__by_id(id) {
    let i=0;while i<32 {let p=gui__records+i*704;if load64(p) && load64(p+32)==id {return p;}i=i+1;}return 0;
}
fn gui__dimensions(p) {
    if gui__native{return gn_dimensions(p);}
    gui__zero(gui__scratch,16);
    gui__call("SDL_GetWindowSize",load64(p),gui__scratch,gui__scratch+4,0,0,0);
    store64(p+56,gui__u32(gui__scratch));store64(p+64,gui__u32(gui__scratch+4));
    if load64(p+24) {
        gui__call("SDL_GL_GetDrawableSize",load64(p),gui__scratch,gui__scratch+4,0,0,0);
    }else if load64(p+8) {
        if gui__int("SDL_GetRendererOutputSize",load64(p+8),gui__scratch,gui__scratch+4,0,0,0)<0 {return gui__sdl_error();}
    }else {
        // Before renderer creation, drawable pixels need not equal window units.
        gui__call("SDL_GetWindowSizeInPixels",load64(p),gui__scratch,gui__scratch+4,0,0,0);
    }
    store64(p+72,gui__u32(gui__scratch));store64(p+80,gui__u32(gui__scratch+4));return 1;
}
fn gui__create(title,width,height,flags,gl) {
    if !title || width<1 || height<1 || width>16384 || height>16384 || flags<0 || flags>7 {return gui__fail("Invalid window title, dimensions or flags");}
    if !gui_init() {return 0;}
    if gui__native{return gn_create(title,width,height,flags,gl);}
    let i=0;while i<32 && load64(gui__records+i*704) {i=i+1;}
    if i==32 {return gui__fail("GUI window limit (32) reached");}
    let native_flags=0;if flags&GUI_RESIZABLE {native_flags=native_flags|32;}
    if flags&GUI_HIDDEN {native_flags=native_flags|8;}else {native_flags=native_flags|4;}
    if flags&GUI_HIGH_DPI {native_flags=native_flags|8192;}if gl {native_flags=native_flags|2;}
    let native=gui__call("SDL_CreateWindow",title,0x2fff0000,0x2fff0000,width,height,native_flags);
    if !native {return gui__sdl_error();}
    let p=gui__records+i*704;let generation=load64(p+48)+1;
    let dispatch=load64(p+656);let shader_scratch=load64(p+672);
    gui__zero(p,704);store64(p+656,dispatch);store64(p+672,shader_scratch);store64(p,native);store64(p+48,generation);
    store64(p+32,gui__call("SDL_GetWindowID",native,0,0,0,0,0));store64(p+648,gl);
    store64(p+640,(gui__call("SDL_GetWindowFlags",native,0,0,0,0,0)&512)!=0);
    gui__dimensions(p);gui_error=0;return gui__handle(p);
}
fn gui_open(title,width,height,flags) {return gui__create(title,width,height,flags,0);}
fn gui_close(window) {
    let p=gui__record(window);if !p {return 0;}
    if gui__clipboard_window==window{gui_clipboard_cancel(gui__clipboard_id);}
    if gui__ime_window==window{gui_text_focus(window,0);gui__ime_clear();gui__ime_window=0;}
    if gui__native{return gn_close(p);}
    gd_release(p);
    if gui__relative==window {gui__int("SDL_SetRelativeMouseMode",0,0,0,0,0,0);gui__relative=0;}
    if load64(p+16) {gui__call("SDL_DestroyTexture",load64(p+16),0,0,0,0,0);}
    if load64(p+8) {gui__call("SDL_DestroyRenderer",load64(p+8),0,0,0,0,0);}
    if gui__gl_current==window {gui__gl_current=0;}
    if load64(p+24) {gui__call("SDL_GL_DeleteContext",load64(p+24),0,0,0,0,0);}
    gui__call("SDL_DestroyWindow",load64(p),0,0,0,0,0);store64(p,0);return 1;
}
fn gui_quit() {
    gui_platform_close();
    let i=0;while gui__records && i<32 {let p=gui__records+i*704;if load64(p) {gui_close(gui__handle(p));}i=i+1;}
    if gui__native{gn_quit();gui__initialized=0;return 0;}
    gd_stop();
    if gui__initialized {gui__call("SDL_QuitSubSystem",32,0,0,0,0,0);gui__initialized=0;}return 0;
}
fn gui_width(window) {let p=gui__record(window);if !p {return 0;}gui__dimensions(p);return load64(p+56);}
fn gui_height(window) {let p=gui__record(window);if !p {return 0;}gui__dimensions(p);return load64(p+64);}
fn gui_pixel_width(window) {let p=gui__record(window);if !p {return 0;}gui__dimensions(p);return load64(p+72);}
fn gui_pixel_height(window) {let p=gui__record(window);if !p {return 0;}gui__dimensions(p);return load64(p+80);}
// Density in thousandths, independent of pixel rounding at odd window sizes.
fn gui_scale(window){let p=gui__record(window);if !p{return 0;}if gui__native{return ws_scale(load64(p))*1000/120;}gui__dimensions(p);let w=load64(p+56);let h=load64(p+64);if w<1{w=1;}if h<1{h=1;}let x=load64(p+72)*1000/w;let y=load64(p+80)*1000/h;if y>x{return y;}return x;}
fn gui_title(window,title) {
    let p=gui__record(window);if !p || !title {return gui__fail("Invalid window or title");}
    if gui__native{if !wt_title(load64(p),title){return gui__fail(wl_error);}return wt_flush(load64(p));}
    gui__call("SDL_SetWindowTitle",load64(p),title,0,0,0,0);return 1;
}
fn gui_resize(window,width,height) {
    let p=gui__record(window);if !p {return 0;}
    if width<1 || height<1 || width>16384 || height>16384 {return gui__fail("Invalid window dimensions");}
    if gui__native{return gn_resize(p,width,height);}
    gui__call("SDL_SetWindowSize",load64(p),width,height,0,0,0);return gui__dimensions(p);
}
fn gui_show(window,visible) {
    let p=gui__record(window);if !p {return 0;}
    if gui__native{return gn_show(p,visible);}
    if !visible && load64(p+696){wpd_cancel(load64(p+696));gd_frame_cancel(load64(p+696));}if visible {gui__call("SDL_ShowWindow",load64(p),0,0,0,0,0);}else {gui__call("SDL_HideWindow",load64(p),0,0,0,0,0);}if load64(p+696){gd_refresh(p,load64(p+696));}return 1;
}
fn gui_fullscreen(window,enabled) {
    let p=gui__record(window);if !p {return 0;}let flags=0;if enabled {flags=4097;}
    if gui__native{return wt_mode(load64(p),1,enabled);}
    if gui__int("SDL_SetWindowFullscreen",load64(p),flags,0,0,0,0)<0 {return gui__sdl_error();}return 1;
}
fn gui_maximize(window,enabled){let p=gui__record(window);if !p{return 0;}if gui__native{return wt_mode(load64(p),0,enabled);}let name="SDL_RestoreWindow";if enabled{name="SDL_MaximizeWindow";}gui__call(name,load64(p),0,0,0,0,0);return 1;}
fn gui_minimize(window){let p=gui__record(window);if !p{return 0;}if gui__native{return wt_minimize(load64(p));}gui__call("SDL_MinimizeWindow",load64(p),0,0,0,0,0);return 1;}
fn gui_restore(window){let p=gui__record(window);if !p{return 0;}if gui__native{return gn_restore(p);}if gui__int("SDL_SetWindowFullscreen",load64(p),0,0,0,0,0)<0{return gui__sdl_error();}gui__call("SDL_RestoreWindow",load64(p),0,0,0,0,0);gui__call("SDL_ShowWindow",load64(p),0,0,0,0,0);return 1;}
fn gui_relative_mouse(window,enabled) {
    let p=gui__record(window);if !p {return 0;}
    if gui__native{return gui__fail("Native relative pointer mode is not supported yet");}
    if enabled && (!load64(p+640) || (gui__relative && gui__relative!=window)) {return gui__fail("Relative mouse requires the focused window and one owner");}
    if !enabled && gui__relative!=window {return 1;}
    gui__call("SDL_SetWindowGrab",load64(p),enabled!=0,0,0,0,0);
    if gui__int("SDL_SetRelativeMouseMode",enabled!=0,0,0,0,0,0)<0 {
        gui__call("SDL_SetWindowGrab",load64(p),0,0,0,0,0);return gui__sdl_error();
    }
    gui__relative=0;if enabled {gui__relative=window;}return 1;
}
fn gui_key(window,scancode) {
    let p=gui__record(window);if !p || scancode<0 || scancode>=512 {return 0;}return load8(p+128+scancode);
}
fn gui_mouse_buttons(window) {let p=gui__record(window);if !p {return 0;}return load64(p+120);}
fn gui_focused(window) {let p=gui__record(window);if !p {return 0;}return load64(p+640);}
fn gui_text_input(enabled) {
    if !gui__initialized {return gui__fail("GUI is not initialized");}
    gui__text_enabled=enabled!=0;
    if gui__native{gn_text_enabled=enabled!=0;let p=gui__records;if p && load64(p){let c=load64(p);wm_enable(c,load64(load64(c+192)+256),enabled);}return 1;}
    if enabled {gui__call("SDL_StartTextInput",0,0,0,0,0,0);}else {gui__call("SDL_StopTextInput",0,0,0,0,0,0);}return 1;
}
fn gui_ticks() {if !gui_init() {return 0;}if gui__native{return gui_monotonic_ns()/1000000;}return gui__call("SDL_GetTicks64",0,0,0,0,0,0);}
fn gui_delay(ms) {
    if ms<0 || ms>0xffffffff {return gui__fail("Invalid delay");}if !gui_init() {return 0;}
    if gui__native{store64(gui__scratch,ms/1000);store64(gui__scratch+8,(ms%1000)*1000000);syscall(35,gui__scratch,0,0,0,0,0);return 1;}
    gui__call("SDL_Delay",ms,0,0,0,0,0);return 1;
}
// Wait for input without consuming it. gui_poll still owns event normalization.
// Unlike gui_delay, this wakes as soon as an event reaches the SDL queue.
fn gui_wait(ms){if gui__event_read!=gui__event_write{return 1;}if ms<0 || ms>2147483647{return gui__fail("Invalid event wait timeout");}if !gui_init(){return 0;}if gui__native{return gn_wait(ms);}if gd_active(){return gd_wait(ms);}return gui__int("SDL_WaitEventTimeout",0,ms,0,0,0,0)>0;}
// Caller owns one 128-byte event buffer; polling does not allocate.
fn gui_event() {return gui__zero(alloc(128),128);}
fn gui_event_kind(event) {return load64(event);}
fn gui_event_window(event) {return load64(event+8);}
fn gui_event_code(event) {return load64(event+16);}
fn gui_event_x(event) {return load64(event+24);}
fn gui_event_y(event) {return load64(event+32);}
fn gui_event_dx(event) {return load64(event+40);}
fn gui_event_dy(event) {return load64(event+48);}
fn gui_event_button(event) {return load64(event+56);}
fn gui_event_repeat(event) {return load64(event+64);}
fn gui_event_modifiers(event) {return load64(event+72);}
fn gui_event_text(event) {return event+80;}
fn gui__release_input(p) {
    gui__zero(p+128,512);store64(p+120,0);
    if gui__relative==gui__handle(p) {gui_relative_mouse(gui__relative,0);}return 0;
}
fn gui_poll(event){if !gui__native{gd_pending();}gui_ime_release(gui__ime_active);if gui__event_pop(event){gui_metrics_add(14,1);return 1;}let found=0;if gui__native{found=gn_poll(event,0);}else{found=gui__sdl_poll(event);gd_pending();}if found{gui_metrics_add(14,1);}return found;}
fn gui__sdl_poll(event) {
    if !event {return gui__fail("Event buffer is null");}gui__zero(event,128);
    if !gui__initialized {return 0;}
    while ffi_call_i32(gui__poll_fn,gui__raw,0,0,0,0,0)>0 {
        let kind=gui__u32(gui__raw);
        if kind==256 {
            let i=0;while i<32 {let p=gui__records+i*704;if load64(p) {gui__release_input(p);}i=i+1;}
            store64(event,GUI_QUIT);return 1;
        }
        // Free payloads of unsupported owning SDL events even when ignored.
        if kind==0x1000 || kind==0x1001 {
            gui__call("SDL_free",load64(gui__raw+8),0,0,0,0,0);
        }else if kind==0x305 {
            let p=gui__by_id(gui__u32(gui__raw+8));let text=load64(gui__raw+16);if p && text{gui__sdl_preedit(gui__handle(p),text,gui__i32(gui__raw+24),gui__i32(gui__raw+28));}
            gui__call("SDL_free",text,0,0,0,0,0);if gui__event_pop(event){return 1;}
        }else if kind==0x2000 || kind==0x2001 {
            // Streaming textures can be recreated on the next pixels upload.
            let i=0;while i<32 {let p=gui__records+i*704;if load64(p) && load64(p+16) {
                gui__call("SDL_DestroyTexture",load64(p+16),0,0,0,0,0);store64(p+16,0);
            }i=i+1;}store64(event,GUI_RENDER_RESET);return 1;
        }else {
            let p=gui__by_id(gui__u32(gui__raw+8));
            if p {
                store64(event+8,gui__handle(p));
                if kind==512 {
                    let action=load8(gui__raw+12);
                    if action==14 {gui__release_input(p);store64(event,GUI_CLOSE);return 1;}
                    if action==5 || action==6 {
                        gui__dimensions(p);store64(event,GUI_RESIZE);
                        store64(event+24,load64(p+56));store64(event+32,load64(p+64));return 1;
                    }
                    if action==12 || action==13 {
                        store64(p+640,action==12);if action==13 {gui__release_input(p);}
                        store64(event,GUI_FOCUS);store64(event+16,action==12);return 1;
                    }
                    if action==3 {store64(event,GUI_EXPOSE);return 1;}
                }else if kind==768 || kind==769 {
                    let code=gui__i32(gui__raw+16);if code>=0 && code<512 {store8(p+128+code,kind==768);}
                    store64(event,GUI_KEY_DOWN);if kind==769 {store64(event,GUI_KEY_UP);}
                    store64(event+16,code);store64(event+64,load8(gui__raw+13));
                    store64(event+72,load8(gui__raw+24)|(load8(gui__raw+25)<<8));return 1;
                }else if kind==770 {
                    gui__sdl_preedit(gui__handle(p),gui__raw+12,gui__i32(gui__raw+44),gui__i32(gui__raw+48));if gui__event_pop(event){return 1;}
                }else if kind==771 {
                    let i=0;while i<31 && load8(gui__raw+12+i) {store8(event+80+i,load8(gui__raw+12+i));i=i+1;}
                    store64(event,GUI_TEXT);return 1;
                }else if kind==1024 {
                    store64(event,GUI_MOUSE_MOVE);store64(event+24,gui__i32(gui__raw+20));store64(event+32,gui__i32(gui__raw+24));
                    store64(event+40,gui__i32(gui__raw+28));store64(event+48,gui__i32(gui__raw+32));
                    store64(p+104,load64(event+24));store64(p+112,load64(event+32));store64(p+120,gui__u32(gui__raw+16));return 1;
                }else if kind==1025 || kind==1026 {
                    let button=load8(gui__raw+16);let mask=0;if button>0 && button<=32 {mask=1<<(button-1);}
                    if kind==1025 {store64(event,GUI_MOUSE_DOWN);store64(p+120,load64(p+120)|mask);}
                    else {store64(event,GUI_MOUSE_UP);store64(p+120,load64(p+120)&~mask);}
                    store64(event+56,button);store64(event+24,gui__i32(gui__raw+20));store64(event+32,gui__i32(gui__raw+24));return 1;
                }else if kind==1027 {
                    let x=gui__i32(gui__raw+16);let y=gui__i32(gui__raw+20);
                    if gui__u32(gui__raw+24)==1 {x=-x;y=-y;}
                    store64(event,GUI_WHEEL);store64(event+40,x);store64(event+48,y);store64(event+72,gui__call("SDL_GetModState",0,0,0,0,0,0));return 1;
                }
            }
        }
        // Unknown events never leak the previous event's window or payload.
        gui__zero(event,128);
    }return 0;
}
