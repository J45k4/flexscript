// Optional GUI test driver: sends events only to its newly created window.
import "host.flex";
global x_library=0;
global x_display=0;
global x_root=0;
global x_window=0;
fn x_symbol(name) {
    let p=ffi_symbol(x_library,name);
    h_assert(p,h_cat("missing Xlib symbol: ",name));
    return p;
}
fn x_open() {
    x_library=ffi_open("libX11.so.6");
    h_assert(x_library,"Xlib is required for --gui");
    x_display=ffi_call(x_symbol("XOpenDisplay"),0,0,0,0,0,0);
    h_assert(x_display,"Cannot open DISPLAY for GUI tests");
    x_root=ffi_call(x_symbol("XDefaultRootWindow"),x_display,0,0,0,0,0);
    return 0;
}
fn x_visit(window,result,depth) {
    h_assert(depth<64,"X11 window tree nesting");
    let name=h_take(8);
    store64(name,0);
    if ffi_call_i32(x_symbol("XFetchName"),x_display,window,name,0,0,0) && load64(name) {
        if h_equal(load64(name),"Flexscript Todo") {
            h_add(result,window);
        }
        ffi_call(x_symbol("XFree"),load64(name),0,0,0,0,0);
    }
    let root=h_take(8);
    let parent=h_take(8);
    let children=h_zero(h_take(8),8);
    let count=h_zero(h_take(8),8);
    if ffi_call_i32(x_symbol("XQueryTree"),x_display,window,root,parent,children,count) {
        let values=load64(children);
        let n=load64(count)&0xffffffff;
        h_assert(n<=4095,"too many child windows");
        let copied=h_take(n*8);
        h_copy(copied,values,n*8);
        if values {
            ffi_call(x_symbol("XFree"),values,0,0,0,0,0);
        }
        let i=0;
        while i<n {
            x_visit(load64(copied+i*8),result,depth+1);
            i=i+1;
        }
    }
    return 0;
}
fn x_windows() {
    let result=h_vec();
    x_visit(x_root,result,0);
    return result;
}
fn x_send(event,mask) {
    h_assert(ffi_call_i32(x_symbol("XSendEvent"),x_display,x_window,0,mask,event,0)!=0,"XSendEvent failed");
    ffi_call(x_symbol("XFlush"),x_display,0,0,0,0,0);
    return 0;
}
fn x_event(kind) {
    let p=h_zero(h_take(192),192);
    store64(p,kind);
    store64(p+24,x_display);
    store64(p+32,x_window);
    return p;
}
fn x_key(symbol,state) {
    let p=x_event(2);
    store64(p+40,x_root);
    let code=ffi_call_u32(x_symbol("XKeysymToKeycode"),x_display,symbol,0,0,0,0);
    h_assert(code,"no X11 key mapping");
    store64(p+80,state|(code<<32));
    store64(p+88,1);
    x_send(p,1);
    return 0;
}
fn x_text(text) {
    let i=0;
    while load8(text+i) {
        let c=load8(text+i);
        let state=0;
        if c>=65 && c<=90 {
            state=1;
        }
        x_key(c,state);
        i=i+1;
    }
    return 0;
}
fn x_click(x,y,button) {
    let p=x_event(4);
    store64(p+40,x_root);
    store64(p+64,(x&0xffffffff)|(y<<32));
    store64(p+80,button<<32);
    store64(p+88,1);
    x_send(p,4);
    h_sleep(70);
    return 0;
}
fn x_close_window() {
    let p=x_event(33);
    store64(p+40,ffi_call(x_symbol("XInternAtom"),x_display,"WM_PROTOCOLS",0,0,0,0));
    store64(p+48,32);
    store64(p+56,ffi_call(x_symbol("XInternAtom"),x_display,"WM_DELETE_WINDOW",0,0,0,0));
    x_send(p,0);
    return 0;
}
fn x_size() {
    let p=h_zero(h_take(144),144);
    h_assert(ffi_call_i32(x_symbol("XGetWindowAttributes"),x_display,x_window,p,0,0,0)!=0,"XGetWindowAttributes failed");
    let size=h_take(16);
    store64(size,load64(p+8)&0xffffffff);
    store64(size+8,load64(p+8)>>32);
    return size;
}
fn x_screenshot(path) {
    ffi_call(x_symbol("XSync"),x_display,0,0,0,0,0);
    let size=x_size();
    let w=load64(size);
    let h=load64(size+8);
    h_assert(w>0 && h>0 && w<=8192 && h<=8192,"GUI image dimensions");
    let image=h_ffi8(x_symbol("XGetImage"),x_display,x_window,0,0,w,h,-1,2);
    h_assert(image,"XGetImage failed");
    let raw=load64(image+16);
    let stride=load64(image+40)>>32;
    let bits=load64(image+48)&0xffffffff;
    h_assert(bits==32 && (load64(image+24)&0xffffffff)==0,"unsupported XImage format");
    let pixel=raw+(h/2)*stride+10*4;
    h_assert(load8(pixel)==50 && load8(pixel+1)==61 && load8(pixel+2)==25,"Todo sidebar was not drawn");
    pixel=raw+10*stride+220*4;
    h_assert(load8(pixel)==239 && load8(pixel+1)==244 && load8(pixel+2)==244,"Todo page was not drawn");
    let rgb=h_take(w*h*3);
    let y=0;
    while y<h {
        let x=0;
        while x<w {
            let source=raw+y*stride+x*4;
            let target=rgb+(y*w+x)*3;
            store8(target,load8(source+2));
            store8(target+1,load8(source+1));
            store8(target+2,load8(source));
            x=x+1;
        }
        y=y+1;
    }
    let png=ffi_open("libpng16.so.16");
    h_assert(png,"libpng is required for a GUI screenshot");
    let info=h_zero(h_take(104),104);
    store64(info+8,1|(w<<32));
    store64(info+16,h|(2<<32));
    h_assert(ffi_call_i32(ffi_symbol(png,"png_image_write_to_file"),info,path,0,rgb,w*3,0)==1,"PNG export failed");
    ffi_call(x_symbol("XDestroyImage"),image,0,0,0,0,0);
    return 0;
}
