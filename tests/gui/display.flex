// Optional real X11/Xwayland acceptance. Only newly opened test windows receive
// input or screenshots. The default test-gui suite needs no desktop.
import "../../scripts/lib/x11.flex";
global gd_title=0;
global gd_child=0;
global gd_fixture=0;
global gd_red=233;
global gd_green=189;
global gd_blue=124;
fn gd_find(window,depth) {
    h_assert(depth<64,"window tree depth");let name=h_zero(h_take(8),8);let found=0;
    if ffi_call_i32(x_symbol("XFetchName"),x_display,window,name,0,0,0) && load64(name) {
        if h_equal(load64(name),gd_title) {found=window;}
        ffi_call(x_symbol("XFree"),load64(name),0,0,0,0,0);
    }
    if found {return found;}
    let root=h_take(8);let parent=h_take(8);let children=h_zero(h_take(8),8);let count=h_zero(h_take(8),8);
    if ffi_call_i32(x_symbol("XQueryTree"),x_display,window,root,parent,children,count) {
        let n=load64(count)&0xffffffff;h_assert(n<4096,"window tree size");
        let copy=h_take(n*8);h_copy(copy,load64(children),n*8);if load64(children) {ffi_call(x_symbol("XFree"),load64(children),0,0,0,0,0);}
        let i=0;while !found && i<n {found=gd_find(load64(copy+i*8),depth+1);i=i+1;}
    }return found;
}
fn gd_start(binary,title,ready) {
    gd_title=title;h_assert(!gd_find(x_root,0),"close previous example window before GUI tests");
    gd_child=h_spawn(h_args(binary,0,0,0,0,0),"",0);let end=net_now()+8000;x_window=0;
    while !x_window || !h_has(h_out(gd_child),ready) {
        x_window=gd_find(x_root,0);h_pump(gd_child,20);
        if h_status(gd_child)!=-999 {h_print(2,h_out(gd_child));h_print(2,h_err(gd_child));h_die("GUI example exited before ready");}
        if net_now()>end {h_stop(gd_child);h_die("GUI example did not map");}
    }
    h_sleep(300);h_pump(gd_child,0);
    if h_status(gd_child)!=-999 {h_print(2,h_out(gd_child));h_print(2,h_err(gd_child));h_die("GUI example exited after mapping");}
    // SDL can replace its native X11 window when creating a GPU renderer.
    x_window=gd_find(x_root,0);h_assert(x_window,"rendering window disappeared");
    let attrs=h_zero(h_take(144),144);
    h_assert(ffi_call_i32(x_symbol("XGetWindowAttributes"),x_display,x_window,attrs,0,0,0) && (load64(attrs+88)>>32)==2,"GUI window must be viewable");return 0;
}
fn gd_image(path) {
    ffi_call(x_symbol("XSync"),x_display,0,0,0,0,0);let size=x_size();let w=load64(size);let h=load64(size+8);
    h_assert(w>=100 && h>=100 && w<=8192 && h<=8192,"visible window dimensions");
    let image=h_ffi8(x_symbol("XGetImage"),x_display,x_window,0,0,w,h,-1,2);h_assert(image,"window readback");
    let raw=load64(image+16);let stride=load64(image+40)>>32;let bits=load64(image+48)&0xffffffff;
    h_assert(bits==32 && (load64(image+24)&0xffffffff)==0,"XImage pixel format");
    let rgb=h_take(w*h*3);let count=0;let sum=0;let y=0;
    while y<h {let x=0;while x<w {
        let source=raw+y*stride+x*4;let dest=rgb+(y*w+x)*3;
        let r=load8(source+2);let g=load8(source+1);let b=load8(source);
        store8(dest,r);store8(dest+1,g);store8(dest+2,b);
        if r>=gd_red-1 && r<=gd_red+1 && g>=gd_green-1 && g<=gd_green+1 && b>=gd_blue-1 && b<=gd_blue+1 {count=count+1;sum=sum+x;}
        x=x+1;
    }y=y+1;}
    h_assert(count>2500,"visible colored geometry is missing");
    if path {
        let png=ffi_open("libpng16.so.16");h_assert(png,"libpng for GUI capture");let info=h_zero(h_take(104),104);
        store64(info+8,1|(w<<32));store64(info+16,h|(2<<32));
        h_assert(ffi_call_i32(ffi_symbol(png,"png_image_write_to_file"),info,path,0,rgb,w*3,0)==1,"GUI PNG capture");
    }
    ffi_call(x_symbol("XDestroyImage"),image,0,0,0,0,0);return sum/count;
}
fn gd_stop() {x_close_window();h_check(h_wait(gd_child),0,0);h_assert(!gd_find(x_root,0),"closed test window remained mapped");return 0;}
fn gd_right_key() {
    // SDL's XInput2 path ignores synthetic core KeyPress events. Exercise the
    // server's input path, with focus verified on this newly created window.
    let xtest=ffi_open("libXtst.so.6");h_assert(xtest,"XTest is required for --gui keyboard acceptance");
    let fake=ffi_symbol(xtest,"XTestFakeKeyEvent");h_assert(fake,"XTest key symbol");
    let focus=h_zero(h_take(8),8);let revert=h_zero(h_take(8),8);
    ffi_call(x_symbol("XGetInputFocus"),x_display,focus,revert,0,0,0);let previous=load64(focus);
    ffi_call(x_symbol("XSetInputFocus"),x_display,x_window,2,0,0,0);
    ffi_call(x_symbol("XSync"),x_display,0,0,0,0,0);
    ffi_call(x_symbol("XGetInputFocus"),x_display,focus,revert,0,0,0);h_assert(load64(focus)==x_window,"test window must own keyboard focus");
    // SDL defers focus-in processing briefly; wait before sending the press.
    h_sleep(200);
    let code=ffi_call_u32(x_symbol("XKeysymToKeycode"),x_display,0xff53,0,0,0,0);
    ffi_call_i32(fake,x_display,code,1,0,0,0);ffi_call(x_symbol("XFlush"),x_display,0,0,0,0,0);h_sleep(160);
    // Release even if the assertion below will fail, then restore prior focus.
    ffi_call_i32(fake,x_display,code,0,0,0,0);ffi_call(x_symbol("XSync"),x_display,0,0,0,0,0);
    ffi_call(x_symbol("XSetInputFocus"),x_display,previous,2,0,0,0);ffi_call(x_symbol("XFlush"),x_display,0,0,0,0,0);h_sleep(50);return 0;
}
fn gd_click() {
    let xtest=ffi_open("libXtst.so.6");let fake=ffi_symbol(xtest,"XTestFakeButtonEvent");h_assert(fake,"XTest button symbol");
    let query=ffi_symbol(gd_fixture,"gui_fixture_pointer");let warp=ffi_symbol(gd_fixture,"gui_fixture_warp");h_assert(query && warp,"pointer restoration helpers");
    let position=ffi_call(query,x_display,x_root,0,0,0,0);
    let focus=h_zero(h_take(8),8);let revert=h_zero(h_take(8),8);ffi_call(x_symbol("XGetInputFocus"),x_display,focus,revert,0,0,0);let previous=load64(focus);
    ffi_call(x_symbol("XSetInputFocus"),x_display,x_window,2,0,0,0);ffi_call(warp,x_display,x_window,40,50,0,0);
    ffi_call(x_symbol("XSync"),x_display,0,0,0,0,0);h_sleep(200);
    ffi_call(x_symbol("XGetInputFocus"),x_display,focus,revert,0,0,0);h_assert(load64(focus)==x_window,"test window must own mouse click focus");
    ffi_call(fake,x_display,1,1,0,0,0);ffi_call(x_symbol("XFlush"),x_display,0,0,0,0,0);h_sleep(80);
    ffi_call(fake,x_display,1,0,0,0,0);ffi_call(warp,x_display,x_root,position&0xffffffff,position>>32,0,0);
    ffi_call(x_symbol("XSetInputFocus"),x_display,previous,2,0,0,0);ffi_call(x_symbol("XFlush"),x_display,0,0,0,0,0);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==4,"provide window, OpenGL and fixture library paths");gd_fixture=ffi_open(load64(argv+24));h_assert(gd_fixture,"GUI fixture loaded");x_open();
    gd_start(load64(argv+8),"Flexscript Native Window - arrows move, click recolors, Esc closes","Native window ready.");
    let before=gd_image("build/gui-window.png");gd_right_key();let after=gd_image(0);
    h_assert(after>before+12,"native keyboard input did not move the rectangle");
    gd_click();h_sleep(100);gd_red=140;gd_green=17;gd_blue=69;gd_image("build/gui-input.png");
    gd_stop();h_print(1,"Visible window, native keyboard/mouse input, and WM close passed.\n");
    gd_red=232;gd_green=189;gd_blue=122;
    gd_start(load64(argv+16),"Flexscript Native OpenGL - Esc closes","OpenGL renderer:");gd_image("build/gui-opengl.png");
    h_print(1,h_out(gd_child));gd_stop();h_print(1,"Visible OpenGL triangle and WM close passed.\n");
    ffi_call(x_symbol("XCloseDisplay"),x_display,0,0,0,0,0);return 0;
}
