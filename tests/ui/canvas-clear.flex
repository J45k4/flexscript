// Public canvas clear semantics: whole target, independent of clip/logical size.
import "../../libs/gui/draw.flex";
import "../../scripts/lib/json.flex";
global cc_out=0;global cc_checks=0;
fn cc_pixels(window,width,height){
    let pixels=alloc(width*height*4);h_assert(pixels>0,"Cannot allocate clear capture");let p=gui__record(window);let ok=0;
    if gui__native{ok=gr_read(load64(p+8),pixels,width*4,width*height*4);}else{ok=gui__int("SDL_RenderReadPixels",load64(p+8),0,0x16762004,pixels,width*4,0)==0;}
    if !ok{if gui__native{h_assert(0,gr_error);}else{gui__sdl_error();h_assert(0,gui_error);}}return pixels;
}
fn cc_expect(window,name,width,height,outside,inside,rectangle){
    let pixels=cc_pixels(window,width,height);h_save_bytes(h_cat3(cc_out,name,".rgba"),pixels,width*height*4,420);let y=0;
    while y<height{let x=0;while x<width{let color=outside;if rectangle && x>=width/4 && x<width*3/4 && y>=height/4 && y<height*3/4{color=inside;}let p=pixels+(y*width+x)*4;h_assert(load8(p)==((color>>16)&255) && load8(p+1)==((color>>8)&255) && load8(p+2)==(color&255) && load8(p+3)==((color>>24)&255),h_cat("Whole-target clear or restored clipping differs: ",name));x=x+1;}y=y+1;}
    syscall(11,pixels,width*height*4,0,0,0,0);cc_checks=cc_checks+1;return 0;
}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==3,"capture-prefix report.json");cc_out=load64(argv+8);
    let window=gui_open("Canvas clear fixture",320,240,GUI_RESIZABLE|GUI_HIGH_DPI);h_assert(window && gui_canvas_open(window,0),gui_error);let event=gui_event();let warm=0;while warm<3{h_assert(gui_clear(window,0x101820) && gui_present(window),gui_error);let until=gui_ticks()+40;while gui_ticks()<until{while gui_poll(event){}gui_wait(1);}warm=warm+1;}
    let width=gui_pixel_width(window);let height=gui_pixel_height(window);let vw=gui_width(window)/2;let vh=gui_height(window)/2;h_assert(width%4==0 && height%4==0 && vw%4==0 && vh%4==0,"Clear fixture needs integral quarter boundaries");h_assert(gui_canvas_size(window,vw,vh) && gui_canvas_unclip(window) && gui_clear(window,0x102030) && gui_canvas_clip(window,vw/4,vh/4,vw/2,vh/2),gui_error);
    // A queued draw before clear must not survive or be reordered after it.
    h_assert(gui_fill(window,0,0,vw,vh,0xff0000) && gui_clear(window,0x234567) && gui_fill(window,0,0,vw,vh,0x60c080),gui_error);cc_expect(window,"window-clipped",width,height,0xff234567,0xff60c080,1);
    if gui__native{h_assert(load64(load64(gui__record(window)+8)+432),"Whole opaque clear failed to prove window opacity");}
    h_assert(gui_canvas_clip(window,0,0,0,0) && gui_clear(window,0x405060) && gui_fill(window,0,0,vw,vh,0xff0000),gui_error);cc_expect(window,"window-empty-clip",width,height,0xff405060,0,0);
    let layer=gui_texture_layer(window,32,24);h_assert(layer && gui_texture_target(window,layer) && gui_canvas_size(window,16,12) && gui_canvas_unclip(window) && gui_clear(window,0x803020) && gui_canvas_clip(window,4,3,8,6),gui_error);
    h_assert(gui_fill(window,0,0,16,12,0xff0000) && gui_texture_clear(window) && gui_fill(window,0,0,16,12,0x60c080),gui_error);cc_expect(window,"layer-transparent",32,24,0,0xff60c080,1);
    h_assert(gui_canvas_clip(window,0,0,0,0) && gui_clear(window,0x204080) && gui_fill(window,0,0,16,12,0xff0000),gui_error);cc_expect(window,"layer-empty-clip",32,24,0xff204080,0,0);
    h_assert(gui_texture_clear(window),gui_error);cc_expect(window,"layer-empty-transparent",32,24,0,0,0);
    h_assert(gui_texture_target(window,0) && gui_canvas_unclip(window) && gui_canvas_size(window,vw,vh),gui_error);cc_expect(window,"window-after-layer",width,height,0xff405060,0,0);
    let error=0;if gui__native{error=gr_gl(load64(gui__record(window)+8),48,0,0,0,0,0,0);h_assert(h_find(h_read("/proc/self/maps"),"libSDL2")<0,"Native clear fixture loaded SDL");}h_assert(!error,"Canvas clearing caused a GL error");let report=j_object();j_set(report,"backend",j_string(gui_backend_name()));j_set(report,"checks",j_int(cc_checks));j_set(report,"width",j_int(width));j_set(report,"height",j_int(height));j_set(report,"gl_error",j_int(error));h_save(load64(argv+16),j_dump(report));h_print(1,h_cat(j_dump(report),"\n"));gui_texture_close(layer);gui_close(window);gui_quit();syscall(11,event,128,0,0,0,0);return 0;
}
