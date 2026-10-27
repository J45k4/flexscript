// Optional benchmark instrumentation, not application drawing code. GPU query
// intervals include idle gaps while the CPU feeds GL. Their absolute clock is
// unrelated to CLOCK_MONOTONIC / compositor timestamps. Never call glFinish or
// read a result before GL_QUERY_RESULT_AVAILABLE reports it ready.
import "../../libs/gui/draw.flex";
// Header: window0, renderer8, capacity16, bytes24, Gen32, Delete40, Counter48,
// Available56, Result64, GetQuery72, Error80, context88, bits96, failed104,
// result reads112, not-ready polls120, scratch128..159. IDs256, states after IDs.
fn gt_symbol(window,name){if gui__native{return gr_proc(load64(gui__record(window)+8),name);}return gui__call("SDL_GL_GetProcAddress",name,0,0,0,0,0);}
fn gt_valid(t){if !t{return 0;}let p=gui__record(load64(t));if !p || load64(p+8)!=load64(t+8){return 0;}if gui__native{return gr_egl(load64(p+8),"eglGetCurrentContext",0,0,0,0,0,0)==load64(t+88);}return gui__call("SDL_GL_GetCurrentContext",0,0,0,0,0,0)==load64(t+88);}
fn gt_failure(t,message){store64(t+104,1);gui__fail(message);return 0;}
fn gt_error(t){return ffi_call(load64(t+80),0,0,0,0,0,0);}
fn gt_flush(t){let p=gui__record(load64(t));if gui__native{return gr_flush(load64(p+8));}if gui__int("SDL_RenderFlush",load64(p+8),0,0,0,0,0)<0{return gui__sdl_error();}return 1;}
fn gt_close(t){if !t{return 0;}let live=gt_valid(t);if live && load64(t+40){ffi_call(load64(t+40),load64(t+16)*2,t+256,0,0,0,0);}let bytes=load64(t+24);syscall(11,t,bytes,0,0,0,0);return live;}
fn gt_open(window,capacity){
    let p=gui__record(window);if !p || !load64(p+8) || capacity<1 || capacity>10000{return gui__fail("Invalid GPU timing window/capacity");}
    let context=0;if gui__native{context=gr_egl(load64(p+8),"eglGetCurrentContext",0,0,0,0,0,0);}else{let info=gui_renderer_info(window);if !info || !wl_equal(load64(info),"opengl"){return gui__fail("GPU timing requires the desktop OpenGL SDL renderer");}context=gui__call("SDL_GL_GetCurrentContext",0,0,0,0,0,0);}if !context{return gui__fail("GPU timing needs a current OpenGL context");}
    let bytes=256+capacity*16;let t=alloc(bytes);if t<0{return gui__fail("GPU timing allocation failed");}bytes_fill(t,0,bytes);store64(t,window);store64(t+8,load64(p+8));store64(t+16,capacity);store64(t+24,bytes);store64(t+88,context);
    store64(t+32,gt_symbol(window,"glGenQueries"));store64(t+40,gt_symbol(window,"glDeleteQueries"));store64(t+48,gt_symbol(window,"glQueryCounter"));store64(t+56,gt_symbol(window,"glGetQueryObjectuiv"));store64(t+64,gt_symbol(window,"glGetQueryObjectui64v"));store64(t+72,gt_symbol(window,"glGetQueryiv"));store64(t+80,gt_symbol(window,"glGetError"));
    if !load64(t+32) || !load64(t+40) || !load64(t+48) || !load64(t+56) || !load64(t+64) || !load64(t+72) || !load64(t+80){gt_close(t);return gui__fail("OpenGL timestamp queries are unavailable");}
    if gt_error(t){gt_close(t);return gui__fail("Preexisting GL error before GPU timing");}ffi_call(load64(t+72),0x8e28,0x8864,t+128,0,0,0);let bits=bytes_load32(t+128);if gt_error(t) || bits!=64{gt_close(t);return gui__fail("GPU timing requires 64-bit timestamp counters");}store64(t+96,bits);
    ffi_call(load64(t+32),capacity*2,t+256,0,0,0,0);if gt_error(t){gt_close(t);return gui__fail("Cannot allocate GPU timestamp queries");}let i=0;while i<capacity*2{if !bytes_load32(t+256+i*4){gt_close(t);return gui__fail("GPU timestamp query allocation returned zero");}i=i+1;}return t;
}
fn gt_state(t,index){return t+256+load64(t+16)*8+index*8;}
fn gt_begin(t,index){
    if !gt_valid(t) || load64(t+104) || index<0 || index>=load64(t+16){return 0;}let state=gt_state(t,index);if load64(state){return 0;}if !gt_flush(t){return gt_failure(t,"Cannot drain drawing before GPU timestamp");}ffi_call(load64(t+48),bytes_load32(t+256+index*8),0x8e28,0,0,0,0);if gt_error(t){return gt_failure(t,"GPU start timestamp failed");}store64(state,1);return 1;
}
fn gt_end(t,index){
    if !gt_valid(t) || load64(t+104) || index<0 || index>=load64(t+16){return 0;}let state=gt_state(t,index);if load64(state)!=1{return 0;}if !gt_flush(t){return gt_failure(t,"Cannot drain drawing before GPU end timestamp");}ffi_call(load64(t+48),bytes_load32(t+260+index*8),0x8e28,0,0,0,0);if gt_error(t){return gt_failure(t,"GPU end timestamp failed");}store64(state,2);return 1;
}
// 1 = ready (start/end/elapsed in out24), 0 = pending/invalid state, -1 = failed.
fn gt_poll(t,index,out){
    if !gt_valid(t) || !out || index<0 || index>=load64(t+16){return 0;}if load64(t+104){return -1;}let state=gt_state(t,index);if load64(state)!=2{return 0;}bytes_store32(t+128,0);ffi_call(load64(t+56),bytes_load32(t+260+index*8),0x8867,t+128,0,0,0);if gt_error(t){gt_failure(t,"GPU timestamp availability failed");return -1;}if !bytes_load32(t+128){store64(t+120,load64(t+120)+1);return 0;}
    ffi_call(load64(t+64),bytes_load32(t+256+index*8),0x8866,t+136,0,0,0);ffi_call(load64(t+64),bytes_load32(t+260+index*8),0x8866,t+144,0,0,0);store64(t+112,load64(t+112)+2);let start=load64(t+136);let end=load64(t+144);if gt_error(t) || start<0 || end<start{gt_failure(t,"GPU timestamp interval wrapped or failed");return -1;}store64(out,start);store64(out+8,end);store64(out+16,end-start);store64(state,3);return 1;
}
