import "window.flex";
fn gui_canvas_open(window,software) {
    let p=gui__record(window);if !p {return 0;}
    if gui__native{return gn_canvas(p);}
    if load64(p+648) {return gui__fail("Canvas operations require a non-OpenGL window");}
    if load64(p+8) {return 1;}
    let flags=0;if software {flags=1;}
    let renderer=gui__call("SDL_CreateRenderer",load64(p),-1,flags,0,0,0);
    if !renderer {return gui__sdl_error();}store64(p+8,renderer);return gui__dimensions(p);
}
fn gui__canvas(window) {if !gui_canvas_open(window,0) {return 0;}return gui__record(window);}
fn gui__color(p,rgb) {
    if gui__int("SDL_SetRenderDrawColor",load64(p+8),(rgb>>16)&255,(rgb>>8)&255,rgb&255,255,0)<0 {return gui__sdl_error();}return 1;
}
fn gui_clear(window,rgb) {
    let p=gui__canvas(window);if !p{return 0;}if gui__native{return gr_clear_all(load64(p+8),0xff000000|(rgb&0xffffff));}if !gui__color(p,rgb) {return 0;}
    if gui__int("SDL_RenderClear",load64(p+8),0,0,0,0,0)<0 {return gui__sdl_error();}return 1;
}
fn gui_fill(window,x,y,width,height,rgb) {
    let p=gui__canvas(window);if !p {return 0;}
    if x< -2147483648 || x>2147483647 || y< -2147483648 || y>2147483647 || width<0 || width>2147483647 || height<0 || height>2147483647 {return gui__fail("Invalid canvas rectangle");}
    if gui__native{gui_metrics_add(0,1);return gr_fill(load64(p+8),x,y,width,height,0xff000000|(rgb&0xffffff));}
    if !gui__color(p,rgb) {return 0;}
    gui__put32(gui__scratch,x);gui__put32(gui__scratch+4,y);gui__put32(gui__scratch+8,width);gui__put32(gui__scratch+12,height);
    gui_metrics_add(0,1);if gui__int("SDL_RenderFillRect",load64(p+8),gui__scratch,0,0,0,0)<0 {return gui__sdl_error();}return 1;
}
fn gui__buffer(pixels,width,height,pitch,bytes) {
    if !pixels || width<1 || width>16384 || height<1 || height>16384 || pitch<width*4 || pitch>1073741824 || bytes<(height-1)*pitch+width*4 {return gui__fail("Invalid RGBA pixel buffer, pitch or byte length");}return 1;
}
// RGBA bytes, top-to-bottom rows. Upload is synchronous; caller retains memory.
// A streaming texture is reused until source dimensions change or device reset.
fn gui_pixels(window,pixels,width,height,pitch,bytes) {
    if !gui__buffer(pixels,width,height,pitch,bytes) {return 0;}
    let p=gui__canvas(window);if !p {return 0;}
    if gui__native{gui_metrics_add(1,1);return gn_pixels(p,pixels,width,height,pitch);}
    if !load64(p+16) || load64(p+88)!=width || load64(p+96)!=height {
        gui_metrics_add(2,1);let texture=gui__call("SDL_CreateTexture",load64(p+8),0x16762004,1,width,height,0);
        if !texture {return gui__sdl_error();}
        if load64(p+16) {gui__call("SDL_DestroyTexture",load64(p+16),0,0,0,0,0);}
        store64(p+16,texture);store64(p+88,width);store64(p+96,height);
    }
    gui_metrics_add(3,1);gui_metrics_add(4,width*height*4);if gui__int("SDL_UpdateTexture",load64(p+16),0,pixels,pitch,0,0)<0 {return gui__sdl_error();}
    gui_metrics_add(1,1);if gui__int("SDL_RenderCopy",load64(p+8),load64(p+16),0,0,0,0)<0 {return gui__sdl_error();}return 1;
}
fn gui_present(window) {
    let p=gui__canvas(window);if !p {return 0;}if gui__native{let c=load64(p);if load64(c+112){return gui__fail(wl_error);}if !wt_ready(c){store64(load64(p+8)+208,0);return 1;}}let start=gui_metrics_start();let ok=1;if gui__native{ok=gr_present(load64(p+8));}else{if !gd_submit(p){return 0;}gui__call("SDL_RenderPresent",load64(p+8),0,0,0,0,0);}gui_metrics_end(13,start);if !ok && gui__native{return gui__fail(gr_error);}if ok{gui_metrics_add(7,1);}return ok;
}
// Read before present: SDL does not promise to retain the backbuffer afterwards.
fn gui_read_pixels(window,pixels,pitch,bytes) {
    let p=gui__canvas(window);if !p || !gui__dimensions(p) {return 0;}
    if !gui__buffer(pixels,load64(p+72),load64(p+80),pitch,bytes) {return 0;}
    if gui__native{return gr_read(load64(p+8),pixels,pitch,bytes);}
    if gui__int("SDL_RenderReadPixels",load64(p+8),0,0x16762004,pixels,pitch,0)<0 {return gui__sdl_error();}return 1;
}
