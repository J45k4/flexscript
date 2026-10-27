// Native canvas adapter to the stable gui_* records. Generic GUI consumers
// retain SDL selection; Collie selects native Wayland in Wayland sessions.
import "../../text/atlas.flex";
import "../../text/shaping.flex";
import "../../text/carets.flex";
import "input.flex";
global gui__native=0;
global gui__backend_selected=0;
global gn_fonts=0;
global gn_shapes=0;
global gn_wait_event=0;
global gn_text_enabled=0;
fn gui_backend_select(name){
    if gui__initialized{return gui__fail("Select the GUI backend before initialization");}
    if wl_equal(name,"wayland"){gui__native=1;gui__backend_selected=1;return 1;}if wl_equal(name,"sdl2"){gui__native=0;gui__backend_selected=1;return 1;}return gui__fail("Unknown GUI backend");
}
fn gn_configure(){
    let library=ffi_open("libc.so.6");if !library{return 1;}let name=ffi_call(ffi_symbol(library,"getenv"),"FLEX_GUI_BACKEND",0,0,0,0,0);let ok=1;if name && load8(name){ok=gui_backend_select(name);}ffi_close(library);return ok;
}
fn gn_dimensions(p){let client=load64(p);let w=load64(client+72);let h=load64(client+80);store64(p+56,w);store64(p+64,h);store64(p+72,ws_width(client));store64(p+80,ws_height(client));if load64(p+8){return gr_resize(load64(p+8));}return 1;}
fn gn_create(title,width,height,flags,gl){
    if gl{return gui__fail("The native canvas backend does not expose SDL GL contexts");}
    let client=wi_client_open_flags(title,width,height,flags);if !client{return gui__fail(wl_error);}let p=gui__records;let generation=load64(p+48)+1;gui__zero(p,704);store64(p,client);store64(p+48,generation);store64(p+32,1);gn_dimensions(p);let life=load64(client+456);store64(life+112,load64(life+24));let handle=gui__handle(p);let input=load64(client+192);store64(input+8,handle);store64(p+640,load64(input+64));return handle;
}
fn gn_signal(p,kind){if !gn_wait_event{gn_wait_event=gui_event();}let event=gn_wait_event;gui__zero(event,128);store64(event,kind);store64(event+8,gui__handle(p));if kind==GUI_RESIZE{store64(event+24,load64(p+56));store64(event+32,load64(p+64));}return gui_event_enqueue(event);}
fn gn_resize(p,width,height){let c=load64(p);let oldw=load64(c+72);let oldh=load64(c+80);if !wt_resize(c,width,height){return gui__fail(wl_error);}if !gn_dimensions(p){return 0;}if oldw!=load64(c+72) || oldh!=load64(c+80){gn_signal(p,GUI_RESIZE);}return 1;}
fn gn_show(p,visible){let c=load64(p);let life=load64(c+456);let was=load64(life);if was && !visible && load64(p+8){if !gr_suspend(load64(p+8)){return gui__fail(gr_error);}}if !wt_show(c,visible){return gui__fail(wl_error);}if was && !visible{let w=load64(c+192);wi_buttons_release(w);wi_blur(w);store64(w+56,0);let cursor=load64(w+248);store64(cursor+96,0);wn_stop(c,cursor);wm_cancel(c,load64(w+256),w);}return 1;}
fn gn_restore(p){let c=load64(p);let life=load64(c+456);if load64(life+104){store64(life+88,0);store64(life+96,0);if !gn_show(p,0){return 0;}return gn_show(p,1);}return wt_restore(c);}
fn gn_canvas(p){
    if load64(p+8){return 1;}let renderer=gr_open(load64(p));if !renderer{return gui__fail(gr_error);}store64(p+8,renderer);let atlas=ta_context(renderer);if !atlas{gr_close(renderer);store64(p+8,0);return gui__fail(tf_error);}store64(p+680,atlas);return gn_dimensions(p);
}
fn gn_font_context(){
    if !gn_fonts{gn_fonts=tf_context();if !gn_fonts{return gui__fail(tf_error);}}if !gn_shapes{gn_shapes=ts_context();if !gn_shapes{return gui__fail(tf_error);}}return gn_fonts;
}
fn gn_text(p,font,text,color,x,y){
    return gn_text_direction(p,font,text,color,x,y,0);
}
fn gn_text_direction(p,font,text,color,x,y,direction){let s=ts_run_direction(gn_shapes,font,text,direction);if !s{return gui__fail(tf_error);}let ok=ta_draw(load64(p+680),font,s,x,y+load64(font+56),color);if !ok{return gui__fail(tf_error);}return 1;}
fn gn_close(p){ta_context_free(load64(p+680));if load64(p+8){gr_close(load64(p+8));}wi_close(load64(p));wl_client_close(load64(p));store64(p,0);store64(p+8,0);store64(p+680,0);return 1;}
fn gn_quit(){ts_context_free(gn_shapes);tf_context_free(gn_fonts);gn_shapes=0;gn_fonts=0;if gn_wait_event{syscall(11,gn_wait_event,128,0,0,0,0);gn_wait_event=0;}return 0;}
fn gn_wait(ms){return gn_pump(ms);}
fn gn_poll(event,wait){gn_pump(wait);gui__zero(event,128);return gui__event_pop(event);}
fn gn_pump(wait){
    let p=gui__records;if !p || !load64(p){return 0;}let c=load64(p);let w=load64(c+192);let oldw=load64(p+56);let oldh=load64(p+64);let oldpw=load64(p+72);let oldph=load64(p+80);if !gn_wait_event{gn_wait_event=gui_event();}let event=gn_wait_event;
    let clipboard=load64(w+224);wm_apply(c,load64(w+256));wc_io(c,clipboard);if gui__event_read!=gui__event_write{wait=0;}wait=wc_poll(c,clipboard,wn_timeout(load64(w+248),wi_timeout(w,wait)));gui__wait_join(c);wl_client_wait(c,wait);wi_repeat(w);wc_io(c,clipboard);wn_apply(c,load64(w+248));
    if load64(c+112){if !load64(p+688){store64(p+688,1);wi_buttons_release(w);wi_blur(w);wn_stop(c,load64(w+248));wm_cancel(c,load64(w+256),w);wc_detach(c,clipboard);gn_signal(p,GUI_CLOSE);}}
    else if oldw!=load64(c+72) || oldh!=load64(c+80) || oldpw!=ws_width(c) || oldph!=ws_height(c){gn_dimensions(p);gui__zero(event,128);store64(event,GUI_RESIZE);store64(event+8,gui__handle(p));store64(event+24,load64(p+56));store64(event+32,load64(p+64));gui_event_enqueue(event);}
    let life=load64(c+456);if !load64(c+112) && load64(life) && load64(c+104) && load64(life+24)!=load64(life+112){store64(life+112,load64(life+24));gn_signal(p,GUI_EXPOSE);}return gui__event_read!=gui__event_write;
}
fn gn_pixels(p,pixels,width,height,pitch){
    let g=load64(p+8);if load64(p+16) && (width!=load64(p+88) || height!=load64(p+96)){gr_texture_free(load64(p+16));store64(p+16,0);}
    let packed=pixels;let bytes=width*height*4;if pitch!=width*4{packed=alloc(bytes);if packed<0{return gui__fail("Cannot pack native pixel upload");}let y=0;while y<height{bytes_copy(packed+y*width*4,pixels+y*pitch,width*4);y=y+1;}}
    let texture=load64(p+16);if !texture{texture=gr_texture(g,width,height,packed,0,1);store64(p+16,texture);store64(p+88,width);store64(p+96,height);}else{gr_texture_patch(g,texture,0,0,width,height,packed);}
    if packed!=pixels{syscall(11,packed,bytes,0,0,0,0);}if !texture{return gui__fail(gr_error);}return gr_texture_draw(g,texture,0,0,load64(g+112),load64(g+120));
}
