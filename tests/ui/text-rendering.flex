// Compare the retained text cache with independently rasterized direct text.
// Density is simulated on a fixed framebuffer; no visible display is required.
import "../../libs/ui/desktop.flex";
global tr_checks=0;
global tr_direct=0;
global tr_cached=0;
fn tr_check(ok,message){h_assert(ok,message);tr_checks=tr_checks+1;return 0;}
fn tr_capture(pixels){h_assert(gui_read_pixels(ud_window,pixels,640*4,640*160*4),gui_error);return 0;}
fn tr_case(scale,size,foreground,background,bold,opacity){
    let node=ud_need("sample");let props=ud_props(node);j_set(props,"size",j_int(size));j_set(props,"color",j_string(foreground));let family="";if bold{family="medium";}j_set(props,"font",j_string(family));ud_invalidate(node);ud_set_scale(scale);
    let font=gui_font_open("sans-serif",size*scale/1000,bold);h_assert(font,gui_error);
    gui_canvas_size(ud_window,0,0);gui_clear(ud_window,background);gui_text_draw(ud_window,font,"Clarity0123456789",ud_color(foreground,0),16*scale/1000,20*scale/1000);tr_capture(tr_direct);gui_font_close(font);
    ud_text_texture(node,300);let texture=load64(node+160);let dimensions=h_take(16);gui__int("SDL_QueryTexture",texture,0,0,dimensions,dimensions+4,0);
    tr_check(gui__i32(dimensions)==ud_pixels(load64(node+208)) && gui__i32(dimensions+4)==ud_pixels(load64(node+216)),"text cache follows device-pixel density");
    gui_canvas_size(ud_window,640*1000/scale,160*1000/scale);gui_clear(ud_window,background);gui_texture_alpha(texture,opacity);gui_texture_draw(ud_window,texture,16,20,load64(node+208),load64(node+216));tr_capture(tr_cached);
    let i=0;let maximum=0;let covered=0;
    while i<640*160*4{let channel=i%4;if channel!=3{let bg=(background>>((2-channel)*8))&255;let direct=load8(tr_direct+i);if direct!=bg{covered=covered+1;}let expected=(direct*opacity+bg*(255-opacity)+127)/255;let error=expected-load8(tr_cached+i);if error<0{error=-error;}maximum=ud_max(maximum,error);}i=i+1;}
    tr_check(covered>100,"font raster contains real antialiased glyph pixels");
    h_print(1,h_cat3("density ",h_int(scale),h_cat3(" size ",h_int(size),h_cat3(" opacity ",h_int(opacity),h_cat3(" max RGB error ",h_int(maximum),"\n")))));
    if maximum>2{h_save_bytes("build/text-direct.rgba",tr_direct,640*160*4,420);h_save_bytes("build/text-cached.rgba",tr_cached,640*160*4,420);h_print(1,h_cat3("layout ",j_dump(ud_edit_layout(node)),"\n"));}tr_check(maximum<=2,"cached glyph coverage matches direct text on its final background");
    // Use the real hit-testing code against the density-adjusted caret metrics.
    store64(node+64,16);store64(node+72,20);store64(node+80,300);store64(node+88,70);store64(node+144,h_len(ud_content(node)));let layout=ud_edit_layout(node);let origin=ud_text_origin(node);
    tr_check(ud_caret_at(node,load64(origin)+j_n(layout,"caret_x"),load64(origin+8)+j_n(layout,"line")/2)==h_len(ud_content(node)),"density-aware caret hit test lands at the end of the text");
    return 0;
}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(ui_desktop_open("Headless text verification",640,160,GUI_HIDDEN),gui_error);tr_direct=alloc(640*160*4);tr_cached=alloc(640*160*4);
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"insert\",\"key\":\"sample\",\"parent\":\"mount\",\"after\":\"\",\"node\":{\"kind\":\"input\",\"key\":\"sample\",\"text\":\"\",\"props\":{\"value\":\"Clarity0123456789\",\"size\":12,\"single_line\":1},\"children\":[]}}]}"));
    let scale=1000;while scale<=2000{let size=12;while size<=16{tr_case(scale,size,"#edf2ed",0x151c21,0,255);tr_case(scale,size,"#10151a",0xc5e3ae,1,255);tr_case(scale,size,"#a4b2b5",0x151c21,0,128);size=size+2;}scale=scale+1000;}
    let node=ud_need("sample");let identity=load64(node+192);let caret=load64(node+144);ud_set_scale(1000);tr_check(!load64(node+160) && !ud_font_count && load64(node+192)==identity && load64(node+144)==caret && h_equal(ud_content(node),"Clarity0123456789"),"density change discards raster resources and preserves editor state");
    ui_desktop_close();gui_quit();h_print(1,h_cat3("PASS: ",h_int(tr_checks)," text raster checks\n"));return 0;
}
