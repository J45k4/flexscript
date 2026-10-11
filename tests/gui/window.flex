import "../../libs/gui.flex";
import "../../scripts/lib/host.flex";
global gt_checks=0;
global gt_event=0;
global gt_emit=0;
fn check(ok,message) {if !ok && gui_error {h_print(2,h_cat3("GUI error: ",gui_error,"\n"));}h_assert(ok,message);gt_checks=gt_checks+1;return 0;}
fn emit(kind,window,a,b,c,d) {
    let p=gui__record(window);let id=0;if p {id=load64(p+32);}
    check(ffi_call_i32(gt_emit,kind,id,a,b,c,d)==1,"fixture event queued");return 0;
}
fn drain() {while gui_poll(gt_event) {}return 0;}
fn expect(kind,window) {
    let end=gui_ticks()+1000;let found=0;
    while !found && gui_ticks()<end {
        if gui_poll(gt_event) {
            if gui_event_kind(gt_event)==kind && gui_event_window(gt_event)==window {found=1;}
        }else {gui_delay(1);}
    }check(found,"expected normalized event");return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);check(argc>=2,"fixture library required");
    if argc>2 && h_equal(load64(argv+16),"--failure") {
        check(!gui_open("Invalid display",32,32,0),"invalid display rejects window");
        check(gui_error && load8(gui_error),"SDL initialization error is reported");
        gui_quit();h_print(1,"GUI unavailable-display checks passed\n");return 0;
    }
    let fixture=ffi_open(load64(argv+8));check(fixture,"fixture loaded");gt_emit=ffi_symbol(fixture,"gui_fixture_event");check(gt_emit,"fixture symbol");
    gt_event=gui_event();check(!gui_poll(gt_event),"poll before initialization is empty");
    check(!gui_open("bad",0,32,0),"zero width rejected");check(!gui_open("bad",32,-1,0),"negative height rejected");
    check(!gui_open("bad",16385,32,0),"large width rejected");check(!gui_open(0,32,32,0),"null title rejected");check(!gui_open("bad",32,32,8),"unknown flags rejected");
    let a=gui_open("GUI test A",64,48,GUI_HIDDEN|GUI_RESIZABLE);check(a,"first window opened");
    let b=gui_open("GUI test B",32,24,GUI_HIDDEN);check(b && a!=b,"second window has independent handle");
    check(gui_width(a)==64 && gui_height(a)==48,"window dimensions");
    check(gui_pixel_width(a)==64 && gui_pixel_height(a)==48,"drawable dimensions");
    check(gui_title(a,"Renamed GUI test"),"title changed");
    check(gui_canvas_open(a,1),"software canvas");check(gui_canvas_open(b,1),"second canvas");
    check(gui_clear(a,0x123456),"canvas clear");check(gui_fill(a,8,6,20,12,0xdac08e),"canvas rectangle");
    let image=alloc(64*48*4);check(gui_read_pixels(a,image,64*4,64*48*4),"canvas readback");
    check(load8(image)==0x12 && load8(image+1)==0x34 && load8(image+2)==0x56 && load8(image+3)==255,"clear RGBA byte order");
    let hit=image+(8+6*64)*4;check(load8(hit)==0xda && load8(hit+1)==0xc0 && load8(hit+2)==0x8e,"rectangle pixels");
    check(gui_present(a),"canvas presentation");
    let pixels=alloc(24);gui__zero(pixels,24);let i=0;while i<2 {store8(pixels+i*12,30);store8(pixels+i*12+1,90);store8(pixels+i*12+2,170);store8(pixels+i*12+3,255);store8(pixels+i*12+4,30);store8(pixels+i*12+5,90);store8(pixels+i*12+6,170);store8(pixels+i*12+7,255);i=i+1;}
    check(gui_pixels(a,pixels,2,2,12,20),"padded RGBA upload (minimum byte length)");
    let texture=load64(gui__record(a)+16);check(gui_pixels(a,pixels,2,2,12,24),"repeat upload");check(load64(gui__record(a)+16)==texture,"streaming texture reused");
    check(gui_read_pixels(a,image,64*4,64*48*4),"uploaded pixels readback");
    check(load8(image)==30 && load8(image+1)==90 && load8(image+2)==170,"RGBA upload not channel swapped");
    check(!gui_pixels(a,pixels,2,2,12,19),"short pixel buffer rejected");check(!gui_pixels(a,pixels,2,2,7,24),"short pitch rejected");
    check(!gui_pixels(a,0,2,2,12,24),"null pixel buffer rejected");check(!gui_read_pixels(a,image,64*4,12),"short readback rejected");
    check(!gui_fill(a,0,0,-1,12,0),"negative rectangle rejected");check(!gui_gl_current(a),"canvas rejects GL calls");
    check(!gui_gl_cached_proc(a,"glGetString"),"canvas rejects cached GL dispatch");
    check(!gui_gl_shader(a,0x8b31,0),"null GLSL rejected without a device call");
    check(gui_resize(a,80,60),"resize requested");check(gui_width(a)==80 && gui_height(a)==60,"resized dimensions");
    check(!gui_resize(a,0,60),"invalid resize rejected");drain();
    gui__poll_fn=ffi_symbol(fixture,"gui_fixture_poll");check(gui__poll_fn,"independent SDL structure decoder oracle");
    emit(512,a,6,80,60,0);expect(GUI_RESIZE,a);check(gui_event_x(gt_event)==80 && gui_event_y(gt_event)==60,"normalized resize");
    emit(768,a,26,119,3,1);expect(GUI_KEY_DOWN,a);check(gui_event_code(gt_event)==26 && gui_event_repeat(gt_event)==1 && gui_event_modifiers(gt_event)==3,"key ABI, modifiers and repeat");
    check(gui_key(a,26) && !gui_key(b,26),"keys isolated between windows");check(!gui_key(a,-1) && !gui_key(a,512),"key bounds");
    emit(769,a,26,119,0,0);expect(GUI_KEY_UP,a);check(!gui_key(a,26),"key released");
    emit(771,b,0,0,0,0);expect(GUI_TEXT,b);check(h_equal(gui_event_text(gt_event),"你好"),"UTF-8 text preserved");
    emit(1024,b,-10,30,-7,5);expect(GUI_MOUSE_MOVE,b);check(gui_event_x(gt_event)==-10 && gui_event_y(gt_event)==30 && gui_event_dx(gt_event)==-7 && gui_event_dy(gt_event)==5,"signed mouse coordinates and relative motion");
    check(gui_mouse_buttons(b)==1,"motion button mask");
    emit(1025,b,3,12,23,0);expect(GUI_MOUSE_DOWN,b);check(gui_event_button(gt_event)==3 && gui_event_x(gt_event)==12 && gui_event_y(gt_event)==23,"mouse button ABI");
    check(gui_mouse_buttons(b)==5,"right button held");emit(1026,b,3,12,23,0);expect(GUI_MOUSE_UP,b);check(gui_mouse_buttons(b)==1,"right button released");
    emit(1027,b,-2,3,1,0);expect(GUI_WHEEL,b);check(gui_event_dx(gt_event)==2 && gui_event_dy(gt_event)==-3,"flipped wheel normalized");
    emit(768,b,4,97,0,0);expect(GUI_KEY_DOWN,b);emit(512,b,12,0,0,0);expect(GUI_FOCUS,b);check(gui_focused(b),"focus gained");
    emit(512,b,13,0,0,0);expect(GUI_FOCUS,b);check(!gui_focused(b) && !gui_key(b,4) && !gui_mouse_buttons(b),"focus loss clears held input");
    check(gui_event_code(gt_event)==0,"focus event payload");check(!gui_relative_mouse(b,1),"unfocused capture rejected");
    emit(0x1000,a,0,0,0,0);emit(0x1001,a,0,0,0,0);emit(0x305,a,0,0,0,0);emit(512,a,3,0,0,0);expect(GUI_EXPOSE,a);
    emit(0x2001,a,0,0,0,0);expect(GUI_RENDER_RESET,0);check(!load64(gui__record(a)+16),"reset invalidates texture");check(gui_pixels(a,pixels,2,2,12,24),"upload recreates reset texture");
    emit(768,a,7,100,0,0);expect(GUI_KEY_DOWN,a);emit(512,a,14,0,0,0);expect(GUI_CLOSE,a);check(!gui_key(a,7),"close request releases input");
    check(gui_width(a)==80,"close request lets application release resources");
    check(gui_close(a),"close first window");check(!gui_close(a),"repeated close is safe");check(gui_width(b)==32 && gui_clear(b,0x334455) && gui_present(b),"other window survives close");
    let c=gui_open("GUI replacement",16,16,GUI_HIDDEN);check(c && c!=a,"reused slot has new generation");check(!gui_clear(a,0),"stale handle cannot access replacement");
    emit(768,b,26,119,0,0);expect(GUI_KEY_DOWN,b);emit(256,b,0,0,0,0);expect(GUI_QUIT,0);check(!gui_key(b,26),"application quit releases input");
    gui_quit();check(!gui__initialized,"video subsystem shut down");check(!gui_clear(c,0),"quit closes every window");
    let windows=alloc(32*8);i=0;while i<32 {let window=gui_open("GUI capacity",8,8,GUI_HIDDEN);check(window,"window capacity slot");store64(windows+i*8,window);i=i+1;}
    check(!gui_open("overflow",8,8,GUI_HIDDEN),"window capacity is bounded");gui_quit();
    c=gui_open("GUI reopen",8,8,GUI_HIDDEN);check(c && c!=load64(windows),"reinitialize with generation preserved");
    check(gui_text_input(1) && gui_text_input(0),"text input control");check(gui_delay(1) && gui_ticks()>0,"timer and delay");check(!gui_delay(-1),"negative delay rejected");
    if argc>2 && h_equal(load64(argv+16),"--gl") {
        let gl=gui_gl_open("GUI GL test",64,48,GUI_HIDDEN,3,3,0);check(gl,"OpenGL context created");check(!gui_clear(gl,0),"GL window rejects SDL canvas");
        let version=gui_gl_proc(gl,"glGetString");check(version,"GL symbol lookup");check(ffi_call(version,0x1f02,0,0,0,0,0),"GL version string");
        let clear=gui_gl_proc(gl,"glClear");ffi_call(clear,0x4000,0,0,0,0,0);check(gui_gl_swap(gl),"OpenGL window swap");
        let name=h_take(12);h_copy(name,"glGetString",12);
        check(gui_gl_cached_proc(gl,name)==version,"cached function resolution");store8(name,88);
        check(gui_gl_cached_proc(gl,"glGetString")==version && load64(gui__record(gl)+664)==1,"cache owns symbol name rather than caller storage");
        check(!gui_gl_cached_proc(gl,0) && !gui_gl_cached_proc(gl,""),"invalid cached names rejected");
        let vs="#version 330 core\nout vec3 shade;void main(){shade=vec3(1);gl_Position=vec4(0,0,0,1);}";
        let fs="#version 330 core\nin vec3 shade;out vec4 color;void main(){color=vec4(shade,1);}";
        check(!gui_gl_shader(gl,0x8b31,"#version 330 core\ninvalid shader"),"invalid GLSL returns failure");
        check(gui_error && load8(gui_error),"shader compiler diagnostic survives cleanup");
        check(!gui_gl_program(gl,vs,"#version 330 core\nin vec2 shade;out vec4 color;void main(){color=vec4(shade,0,1);}"),"incompatible shader interfaces reject linking");
        check(gui_error && load8(gui_error),"link diagnostic survives cleanup");
        check(!gui_gl_program(gl,vs,"invalid fragment"),"fragment failure cleans up vertex stage");
        let program=gui_gl_program(gl,vs,fs);check(program,"shader/program helpers recover after errors");
        check(gui_gl_call(gl,"glIsProgram",program,0,0,0,0,0),"linked program exists");
        let other=gui_gl_open("GUI second GL test",24,20,GUI_HIDDEN,3,3,0);check(other,"second OpenGL context");
        check(!gui_gl_call(other,"glIsProgram",program,0,0,0,0,0),"dispatch switches to independent context");
        check(gui_gl_call(gl,"glIsProgram",program,0,0,0,0,0),"cached dispatch switches back to owning context");
        gui_gl_call(gl,"glDeleteProgram",program,0,0,0,0,0);
        check(gui_gl_current(gl) && gui_gl_current(other),"switch between OpenGL contexts");check(gui_close(gl),"OpenGL context cleanup");
        check(!gui_gl_cached_proc(gl,"glGetString"),"closed GL handle rejects cached dispatch");
        check(gui_gl_current(other) && gui_gl_swap(other),"other GL window survives context close");check(gui_close(other),"second GL context cleanup");
        let replacement=gui_gl_open("GUI replacement GL",16,16,GUI_HIDDEN,3,3,0);check(replacement && replacement!=gl,"GL slot reopens with new generation");
        check(!load64(gui__record(replacement)+664),"replacement context starts with empty function cache");
        check(gui_gl_call(replacement,"glGetString",0x1f02,0,0,0,0,0),"replacement context resolves fresh functions");
        check(gui_close(replacement),"replacement GL cleanup");
    }else {
        check(!gui_gl_open("GUI GL unavailable",32,32,GUI_HIDDEN,3,3,0),"dummy driver rejects OpenGL");check(gui_width(c)==8,"failed GL open preserves other window");
    }
    gui_quit();check(!gui_poll(gt_event) && !gui_event_kind(gt_event) && !gui_event_window(gt_event),"empty poll clears event payload");
    h_print(1,h_cat3("GUI: ",h_int(gt_checks)," checks passed\n"));return 0;
}
