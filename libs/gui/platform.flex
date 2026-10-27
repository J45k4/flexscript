// Backend-neutral application operations. Native key numbers are the stable
// USB-HID-style GUI key ABI; SDL wire events stay inside its compatibility path.
import "backends/wayland/gui.flex";
import "clipboard.flex";
import "text-input.flex";
global GUI_CURSOR_DEFAULT=0;
global GUI_CURSOR_SIZE_HORIZONTAL=1;
global gui__resize_cursor=0;
global gui__event_queue=0;
global gui__event_read=0;
global gui__event_write=0;
global gui__diagnostics=0;
fn gui_pointer_capture(window,enabled){
    if !gui__record(window){return 0;}
    if gui__native{return 1;} // wl_pointer button grabs are implicit.
    if gui__int("SDL_CaptureMouse",enabled!=0,0,0,0,0,0)<0{return gui__sdl_error();}return 1;
}
fn gui_cursor(window,kind){
    if !gui__record(window){return 0;}
    if gui__native{let p=gui__record(window);let c=load64(p);return wn_set(c,load64(c+192),kind);}
    if kind!=GUI_CURSOR_DEFAULT && kind!=GUI_CURSOR_SIZE_HORIZONTAL{return gui__fail("Unknown GUI cursor");}
    let cursor=0;if kind==GUI_CURSOR_SIZE_HORIZONTAL{
        if !gui__resize_cursor{gui__resize_cursor=gui__call("SDL_CreateSystemCursor",7,0,0,0,0,0);}cursor=gui__resize_cursor;
    }else{cursor=gui__call("SDL_GetDefaultCursor",0,0,0,0,0,0);}
    if !cursor{return gui__sdl_error();}gui__call("SDL_SetCursor",cursor,0,0,0,0,0);return 1;
}
fn gui_platform_close(){
    gui__wait_close();
    gui__ime_clear();gui__ime_window=0;gui__ime_identity=0;gui__ime_epoch=gui__ime_epoch+1;gui__text_enabled=0;
    gui_clipboard_cancel(gui__clipboard_id);
    if gui__resize_cursor{gui__call("SDL_FreeCursor",gui__resize_cursor,0,0,0,0,0);gui__resize_cursor=0;}
    gui__event_read=0;gui__event_write=0;return 0;
}
// A bounded normalized event queue shared by native platform callbacks and test
// replay. Queueing does not fake native protocol/OS delivery in acceptance tests.
fn gui_event_enqueue(event){
    let kind=load64(event);if kind<1 || kind>15{return gui__fail("Invalid GUI event kind");}
    if kind!=GUI_QUIT && kind!=GUI_RENDER_RESET && !gui__record(load64(event+8)){return 0;}
    if gui__event_write-gui__event_read>=128{return gui__fail("GUI event queue overflow");}
    if !gui__event_queue{gui__event_queue=alloc(128*128);}
    let to=gui__event_queue+(gui__event_write%128)*128;let i=0;while i<128{store64(to+i,load64(event+i));i=i+8;}
    gui__event_write=gui__event_write+1;return 1;
}
fn gui_event_text_set(event,text){
    let n=0;while load8(text+n){n=n+1;if n>=48{return gui__fail("GUI text event exceeds 47 bytes");}}
    let i=0;while i<48{let c=0;if i<n{c=load8(text+i);}store8(event+80+i,c);i=i+1;}return 1;
}
fn gui__event_pop(event){
    if gui__event_read==gui__event_write{return 0;}
    let from=gui__event_queue+(gui__event_read%128)*128;let i=0;while i<128{store64(event+i,load64(from+i));i=i+8;}
    gui__event_read=gui__event_read+1;let kind=load64(event);let p=0;
    if load64(event+8){p=gui__record(load64(event+8));if !p{gui__zero(event,128);return 0;}}
    if p{
        // Non-text input uses the text union for its platform serial. Remember
        // the event being consumed, not a later packet already read from Wayland.
        if gui__native && (kind==GUI_KEY_DOWN || kind==GUI_KEY_UP || kind==GUI_MOUSE_DOWN || kind==GUI_MOUSE_UP){store64(load64(load64(p)+192)+240,load64(event+80));}
        if kind==GUI_KEY_DOWN || kind==GUI_KEY_UP{let key=load64(event+16);if key>=0 && key<512{store8(p+128+key,kind==GUI_KEY_DOWN);}}
        if kind==GUI_MOUSE_MOVE || kind==GUI_MOUSE_DOWN || kind==GUI_MOUSE_UP{store64(p+104,load64(event+24));store64(p+112,load64(event+32));}
        if kind==GUI_MOUSE_DOWN || kind==GUI_MOUSE_UP{let b=load64(event+56);if b>0 && b<=32{let mask=1<<(b-1);if kind==GUI_MOUSE_DOWN{store64(p+120,load64(p+120)|mask);}else{store64(p+120,load64(p+120)&~mask);}}}
        if kind==GUI_FOCUS{store64(p+640,load64(event+16)!=0);if !load64(event+16){gui__release_input(p);}}
    }if kind==GUI_IME{gui__ime_active=load64(event+16);}return 1;
}
fn gui_backend_name(){if gui__native{return "wayland";}return "sdl2";}
fn gui_video_driver(){if gui__native{return "wayland";}return gui__call("SDL_GetCurrentVideoDriver",0,0,0,0,0,0);}
fn gui_renderer_info(window){
    let p=gui__canvas(window);if !p{return 0;}if !gui__diagnostics{gui__diagnostics=alloc(96);}
    if gui__native{gui__zero(gui__diagnostics,96);store64(gui__diagnostics,gr_gl(load64(p+8),46,0x1f01,0,0,0,0,0));gui__put32(gui__diagnostics+8,10);return gui__diagnostics;}
    gui__zero(gui__diagnostics,96);if gui__int("SDL_GetRendererInfo",load64(p+8),gui__diagnostics,0,0,0,0)<0{return gui__sdl_error();}return gui__diagnostics;
}

fn gui_video_driver_count(){if !gui_init(){return 0;}if gui__native{return 1;}return gui__int("SDL_GetNumVideoDrivers",0,0,0,0,0,0);}
fn gui_video_driver_at(index){if gui__native{if index==0{return "wayland";}return 0;}return gui__call("SDL_GetVideoDriver",index,0,0,0,0,0);}
