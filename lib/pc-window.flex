import "gui/window.flex";
import "gui/canvas.flex";
import "pc-ps2.flex";
import "linux-framebuffer.flex";
import "pc-virtio-gpu.flex";
global pc_window_error=0;
fn pc_window_hex(c) {if c>=97 {return c-87;}return c-48;}
fn pc_window_code(scancode) {
    // SDL physical scancodes (USB usages) to raw PS/2 set-2 make codes.
    if scancode>=4 && scancode<=69 {
        let text="1c322123242b3433433b424b3a31444d152d1b2c3c2a1d22351a161e26252e363d3e46455a76660d294e55545b5d614c520e41494a580506040c030b830a01097807";
        let at=(scancode-4)*2;return pc_window_hex(load8(text+at))*16+pc_window_hex(load8(text+at+1));
    }
    if scancode>=73 && scancode<=82 {let text="706c7d71697a746b7275";let at=(scancode-73)*2;return 256+pc_window_hex(load8(text+at))*16+pc_window_hex(load8(text+at+1));}
    if scancode==71 {return 0x7e;}if scancode==83 {return 0x77;}if scancode==84 {return 0x14a;}
    if scancode>=85 && scancode<=99 {let text="7c7b795a69727a6b73746c757d7071";let at=(scancode-85)*2;let code=pc_window_hex(load8(text+at))*16+pc_window_hex(load8(text+at+1));if scancode==88 {code=code|256;}return code;}
    if scancode==100 {return 0x61;}if scancode==101 {return 0x12f;}
    if scancode>=224 && scancode<=231 {let text="1412111f14591127";let at=(scancode-224)*2;let code=pc_window_hex(load8(text+at))*16+pc_window_hex(load8(text+at+1));if scancode==227 || scancode==228 || scancode==230 || scancode==231 {code=code|256;}return code;}
    return 0;
}
fn pc_window_key(ps2,scancode,down) {
    if scancode==70 || scancode==72 {
        if !load64(ps2+64) || (load64(ps2+16)&16) {return 0;}
        let text="e012e07c";let n=4;
        if scancode==70 && !down {text="e0f07ce0f012";n=6;}
        if scancode==72 {if !down {return 1;}text="e11477e1f014f077";n=8;}
        if !pc_ps2_room(ps2,n) {return 0;}let i=0;while i<n {pc_ps2_put(ps2,pc_window_hex(load8(text+i*2))*16+pc_window_hex(load8(text+i*2+1)),0);i=i+1;}return 1;
    }
    let code=pc_window_code(scancode);if !code {return 1;}return pc_ps2_key(ps2,code&255,(code&256)!=0,down);
}
// State: window,event,framebuffer,PS2,next-frame,dx,dy,buttons,head,tail,
// mouse-pending; held SDL keys[256] at 128; pending key events[256] at 512;
// composed GPU frame key (device,generation,scanout pixels,cursor pixels) at 2560.
fn pc_window_open(ram,bytes,ps2) {
    pc_window_error=0;let usable=lnx_fb_usable(bytes);if !usable {pc_window_error="Invalid framebuffer memory size.";return 0;}
    let s=alloc(4096);if s<0 {pc_window_error="Cannot allocate display state.";return 0;}
    let pixels=alloc(3145728);if pixels<0 {pc_window_error="Cannot allocate display pixel buffer.";syscall(11,s,4096,0,0,0,0);return 0;}store64(s+88,pixels);
    let window=gui_open("Flexvirt - Linux guest",1024,768,GUI_RESIZABLE);
    if !window || !gui_canvas_open(window,0) {pc_window_error=gui_error;if window {gui_close(window);}syscall(11,pixels,3145728,0,0,0,0);syscall(11,s,4096,0,0,0,0);return 0;}
    let event=gui_event();if event<=0 {pc_window_error="Cannot allocate display event buffer.";gui_close(window);syscall(11,pixels,3145728,0,0,0,0);syscall(11,s,4096,0,0,0,0);return 0;}
    store64(s,window);store64(s+8,event);store64(s+16,ram+usable);store64(s+24,ps2);return s;
}
fn pc_window_close(s) {if s {gui_close(load64(s));syscall(11,load64(s+8),128,0,0,0,0);syscall(11,load64(s+88),3145728,0,0,0,0);syscall(11,s,4096,0,0,0,0);}return 0;}
// The guest's X byte is unused, whereas the host API takes RGBA. Make alpha
// opaque in a separate upload buffer without modifying any guest pixels.
fn pc_window_draw(s) {
    let gpu=load64(s+96);if gpu && (load64(gpu+8192) || load64(s+104)) {
        store64(s+104,1);let scanout=vg_find(gpu,load64(gpu+8192));let cursor=vg_find(gpu,load64(gpu+8256));let scanout_pixels=0;let cursor_pixels=0;
        if scanout {scanout_pixels=load64(scanout+32);}if cursor {cursor_pixels=load64(cursor+32);}
        let generation=load64(gpu+8240);
        // Compose only after a display update. Fresh resource pointers also
        // invalidate an equal-generation image loaded by the state codec.
        // Upload/present still runs so resize and expose events repaint normally.
        if load64(s+2560)!=gpu || load64(s+2568)!=generation || load64(s+2576)!=scanout_pixels || load64(s+2584)!=cursor_pixels {
            if vg_frame(gpu,load64(s+88),4096,3145728)<0 {pc_window_error=vg_message;return 0;}
            store64(s+2560,gpu);store64(s+2568,generation);store64(s+2576,scanout_pixels);store64(s+2584,cursor_pixels);
        }
        return gui_pixels(load64(s),load64(s+88),1024,768,4096,3145728);
    }
    store64(s+2560,0);
    let source=load64(s+16);let pixels=load64(s+88);let i=0;while i<3145728 {store64(pixels+i,load64(source+i)|0xff000000ff000000);i=i+8;}
    return gui_pixels(load64(s),pixels,1024,768,4096,3145728);
}
fn pc_window_queue(s,code,down) {
    if load64(s+72)-load64(s+64)>=256 {pc_window_error="Host keyboard event queue overflow.";return -1;}
    let tail=load64(s+72);store64(s+512+(tail&255)*8,code|(down<<16));store64(s+72,tail+1);return 1;
}
// 1 running, 0 user closed the window, -1 display/input failure.
fn pc_window_tick(s) {
    if gui_ticks()<load64(s+32) {return 1;}store64(s+32,gui_ticks()+32);
    let event=load64(s+8);while gui_poll(event) {
        let kind=gui_event_kind(event);if kind==GUI_QUIT {return 0;}
        if gui_event_window(event)==load64(s) {
            if kind==GUI_CLOSE {return 0;}
            if kind==GUI_KEY_DOWN || kind==GUI_KEY_UP {
                let code=gui_event_code(event);if code>=0 && code<256 {let down=kind==GUI_KEY_DOWN;store8(s+128+code,down);if pc_window_queue(s,code,down)<0 {return -1;}}
            }
            if kind==GUI_FOCUS && !gui_event_code(event) {let i=0;while i<256 {if load8(s+128+i) {store8(s+128+i,0);if pc_window_queue(s,i,0)<0 {return -1;}}i=i+1;}}
            if kind==GUI_MOUSE_MOVE {let dx=load64(s+40)+gui_event_dx(event);let dy=load64(s+48)-gui_event_dy(event);if dx< -32767 {dx=-32767;}if dx>32767 {dx=32767;}if dy< -32767 {dy=-32767;}if dy>32767 {dy=32767;}store64(s+40,dx);store64(s+48,dy);store64(s+80,1);}
            if kind==GUI_MOUSE_DOWN || kind==GUI_MOUSE_UP {let buttons=gui_mouse_buttons(load64(s));store64(s+56,(buttons&1)|((buttons&2)<<1)|((buttons&4)>>1));store64(s+80,1);}
        }
    }
    let sending=1;while sending && load64(s+64)<load64(s+72) {let head=load64(s+64);let key=load64(s+512+(head&255)*8);if pc_window_key(load64(s+24),key&65535,(key>>16)&1) {store64(s+64,head+1);}else {sending=0;}}
    if load64(s+80) && pc_ps2_motion(load64(s+24),load64(s+40),load64(s+48),load64(s+56)) {store64(s+40,0);store64(s+48,0);store64(s+80,0);}
    if !pc_window_draw(s) || !gui_present(load64(s)) {pc_window_error=gui_error;return -1;}return 1;
}
