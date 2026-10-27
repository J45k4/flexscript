// A custom 320x200 drawing coordinate system must survive output DPI changes.
// Optional numeric argv checks density before the first buffer is presented.
import "../../libs/gui/draw.flex";
import "../../scripts/lib/json.flex";
fn main(argc,argv){
    h_environment(argc,argv);let expected=0;if argc>1{expected=h_number(load64(argv+8));}h_assert(gui_backend_select("wayland"),gui_error);let window=gui_open("Native canvas scale fixture",800,600,GUI_RESIZABLE|GUI_HIGH_DPI);h_assert(window,gui_error);h_assert(!expected || gui_scale(window)==expected,"First native frame used a stale output density");h_assert(gui_canvas_open(window,0),gui_error);gui_canvas_size(window,320,200);
    let goal=5;if expected{goal=1;}let seen=j_array();let previous=0;let event=gui_event();let until=gui_ticks()+6000;
    while j_count(seen)<goal && gui_ticks()<until{while gui_poll(event){}let scale=gui_scale(window);if scale!=previous{
        h_assert(gui_clear(window,0x10151a) && gui_fill(window,10,10,20,20,0xc5e3ae),gui_error);let width=gui_pixel_width(window);let height=gui_pixel_height(window);let bytes=width*height*4;let pixels=alloc(bytes);h_assert(gui_read_pixels(window,pixels,width*4,bytes),gui_error);let p=pixels+((15*height/200)*width+15*width/320)*4;h_assert(load8(p)==197 && load8(p+1)==227 && load8(p+2)==174,"DPI resize reset the custom canvas coordinates");p=pixels+((5*height/200)*width+5*width/320)*4;h_assert(load8(p)==16 && load8(p+1)==21 && load8(p+2)==26,"Custom canvas rectangle escaped its bounds");syscall(11,pixels,bytes,0,0,0,0);h_assert(gui_present(window),gui_error);j_push(seen,j_int(scale));previous=scale;
    }gui_wait(20);}
    h_assert(j_count(seen)==goal,"Custom canvas scale transitions did not complete");if !expected{h_assert(h_equal(j_dump(seen),"[1000,1250,1500,2000,1000]"),"Custom canvas saw unexpected scale order");}gui_close(window);gui_quit();syscall(11,event,128,0,0,0,0);h_print(1,h_cat(j_dump(seen),"\n"));return 0;
}
