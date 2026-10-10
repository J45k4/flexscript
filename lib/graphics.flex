// Headless OpenGL 4.5 through EGL device displays, Linux x86-64 integer FFI.
// GLSL stages use the graphics driver's shader compiler; this is separate from
// the direct Flexscript -> SASS compute backend.
import "ffi.flex";
global gfx_egl=0;
global gfx_gl=0;
global gfx_display=0;
global gfx_context=0;
global gfx_surface=0;
global gfx_error=0;
fn gfx_u32(p,v) {let i=0;while i<4 {store8(p+i,v>>(i*8));i=i+1;}return 0;}
fn gfx_get_u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn gfx_symbol(name) {
    if !gfx_egl {gfx_egl=ffi_open("libEGL.so.1");}if !gfx_egl {gfx_error="EGL loader unavailable";return 0;}
    let p=ffi_symbol(gfx_egl,name);if p {return p;}
    let get=ffi_symbol(gfx_egl,"eglGetProcAddress");if get {p=ffi_call(get,name,0,0,0,0,0);if p {return p;}}
    if !gfx_gl {gfx_gl=ffi_open("libGL.so.1");}if gfx_gl {p=ffi_symbol(gfx_gl,name);if p {return p;}}
    gfx_error=name;return 0;
}
fn gfx_call(name,a,b,c,d,e,f) {let p=gfx_symbol(name);if !p {return 0;}return ffi_call(p,a,b,c,d,e,f);}
fn gfx_int(name,a,b,c,d,e,f) {let p=gfx_symbol(name);if !p {return 0;}return ffi_call_i32(p,a,b,c,d,e,f);}
fn gfx_open(ordinal,width,height) {
    if gfx_display {gfx_error="Graphics context already open; close it before reopening";return 0;}
    if ordinal<0 || width<1 || height<1 {gfx_error="Invalid device or surface dimensions";return 0;}
    let devices=alloc(32*8);let count=alloc(8);
    if !gfx_int("eglQueryDevicesEXT",32,devices,count,0,0,0) {gfx_error="Cannot enumerate EGL devices";return 0;}
    if ordinal>=(load64(count)&4294967295) {gfx_error="EGL device ordinal unavailable";return 0;}
    gfx_display=gfx_call("eglGetPlatformDisplayEXT",0x313f,load64(devices+ordinal*8),0,0,0,0);
    if !gfx_display {gfx_error="Cannot create EGL device display";return 0;}
    if !gfx_int("eglInitialize",gfx_display,0,0,0,0,0) {gfx_error="Cannot initialize EGL device";return 0;}
    if !gfx_int("eglBindAPI",0x30a2,0,0,0,0,0) {gfx_error="Cannot bind OpenGL API";return 0;}
    let attrs=alloc(60);gfx_u32(attrs,0x3033);gfx_u32(attrs+4,1);gfx_u32(attrs+8,0x3040);gfx_u32(attrs+12,8);
    gfx_u32(attrs+16,0x3024);gfx_u32(attrs+20,8);gfx_u32(attrs+24,0x3023);gfx_u32(attrs+28,8);
    gfx_u32(attrs+32,0x3022);gfx_u32(attrs+36,8);gfx_u32(attrs+40,0x3021);gfx_u32(attrs+44,8);gfx_u32(attrs+48,0x3038);
    let value=alloc(8);if !gfx_int("eglChooseConfig",gfx_display,attrs,value,1,count,0) || !load64(count) {gfx_error="No OpenGL pbuffer config";return 0;}
    let config=load64(value);let surface=alloc(20);gfx_u32(surface,0x3057);gfx_u32(surface+4,width);gfx_u32(surface+8,0x3056);gfx_u32(surface+12,height);gfx_u32(surface+16,0x3038);
    gfx_surface=gfx_call("eglCreatePbufferSurface",gfx_display,config,surface,0,0,0);
    if !gfx_surface {gfx_error="Cannot create EGL pbuffer";return 0;}
    let context=alloc(28);gfx_u32(context,0x3098);gfx_u32(context+4,4);gfx_u32(context+8,0x30fb);gfx_u32(context+12,5);
    gfx_u32(context+16,0x30fd);gfx_u32(context+20,1);gfx_u32(context+24,0x3038);
    gfx_context=gfx_call("eglCreateContext",gfx_display,config,0,context,0,0);
    if !gfx_context {gfx_error="OpenGL 4.5 context unavailable";return 0;}
    if !gfx_int("eglMakeCurrent",gfx_display,gfx_surface,gfx_surface,gfx_context,0,0) {gfx_error="Cannot activate EGL context";return 0;}
    gfx_error=0;return gfx_context;
}
fn gfx_renderer() {return gfx_call("glGetString",0x1f01,0,0,0,0,0);}
fn gfx_shader(kind,source) {
    let shader=gfx_int("glCreateShader",kind,0,0,0,0,0);if !shader {gfx_error="Cannot create shader";return 0;}
    let text=alloc(8);store64(text,source);gfx_call("glShaderSource",shader,1,text,0,0,0);gfx_call("glCompileShader",shader,0,0,0,0,0);
    let value=alloc(8);gfx_call("glGetShaderiv",shader,0x8b81,value,0,0,0);
    if !(load64(value)&4294967295) {
        let log=alloc(8192);gfx_call("glGetShaderInfoLog",shader,8192,0,log,0,0);gfx_error=log;gfx_call("glDeleteShader",shader,0,0,0,0,0);return 0;
    }return shader;
}
fn gfx_program(vertex,fragment) {
    let vs=gfx_shader(0x8b31,vertex);if !vs {return 0;}let fs=gfx_shader(0x8b30,fragment);if !fs {gfx_call("glDeleteShader",vs,0,0,0,0,0);return 0;}
    let program=gfx_int("glCreateProgram",0,0,0,0,0,0);gfx_call("glAttachShader",program,vs,0,0,0,0);gfx_call("glAttachShader",program,fs,0,0,0,0);
    gfx_call("glLinkProgram",program,0,0,0,0,0);gfx_call("glDeleteShader",vs,0,0,0,0,0);gfx_call("glDeleteShader",fs,0,0,0,0,0);
    let value=alloc(8);gfx_call("glGetProgramiv",program,0x8b82,value,0,0,0);
    if !(load64(value)&4294967295) {let log=alloc(8192);gfx_call("glGetProgramInfoLog",program,8192,0,log,0,0);gfx_error=log;gfx_call("glDeleteProgram",program,0,0,0,0,0);return 0;}return program;
}
fn gfx_texture(width,height) {
    let value=alloc(8);gfx_call("glCreateTextures",0x0de1,1,value,0,0,0);let texture=load64(value)&4294967295;
    gfx_call("glTextureStorage2D",texture,1,0x8058,width,height,0);
    gfx_call("glTextureParameteri",texture,0x2801,0x2600,0,0,0);gfx_call("glTextureParameteri",texture,0x2800,0x2600,0,0,0);return texture;
}
fn gfx_texture_clear(texture,rgba) {let value=alloc(4);gfx_u32(value,rgba);gfx_call("glClearTexImage",texture,0,0x1908,0x1401,value,0);return 0;}
fn gfx_read(texture,pixels,bytes) {gfx_call("glGetTextureImage",texture,0,0x1908,0x1401,bytes,pixels);return gfx_int("glGetError",0,0,0,0,0,0);}
fn gfx_draw(program,target,width,height,vertices) {
    let value=alloc(8);gfx_call("glCreateFramebuffers",1,value,0,0,0,0);let framebuffer=load64(value)&4294967295;
    gfx_call("glNamedFramebufferTexture",framebuffer,0x8ce0,target,0,0,0);
    if gfx_int("glCheckNamedFramebufferStatus",framebuffer,0x8d40,0,0,0,0)!=0x8cd5 {
        gfx_error="Incomplete framebuffer";gfx_call("glDeleteFramebuffers",1,value,0,0,0,0);return 0;
    }
    let vao=alloc(8);gfx_call("glCreateVertexArrays",1,vao,0,0,0,0);
    gfx_call("glBindFramebuffer",0x8d40,framebuffer,0,0,0,0);gfx_call("glViewport",0,0,width,height,0,0);
    gfx_call("glUseProgram",program,0,0,0,0,0);gfx_call("glBindVertexArray",load64(vao)&4294967295,0,0,0,0,0);
    gfx_call("glDrawArrays",4,0,vertices,0,0,0);gfx_call("glFinish",0,0,0,0,0,0);
    gfx_call("glDeleteVertexArrays",1,vao,0,0,0,0);gfx_call("glBindFramebuffer",0x8d40,0,0,0,0,0);
    gfx_call("glDeleteFramebuffers",1,value,0,0,0,0);if gfx_int("glGetError",0,0,0,0,0,0) {gfx_error="OpenGL drawing failed";return 0;}return 1;
}
fn gfx_close() {
    if gfx_display {
        gfx_int("eglMakeCurrent",gfx_display,0,0,0,0,0);
        if gfx_context {gfx_int("eglDestroyContext",gfx_display,gfx_context,0,0,0,0);}
        if gfx_surface {gfx_int("eglDestroySurface",gfx_display,gfx_surface,0,0,0,0);}
        gfx_int("eglTerminate",gfx_display,0,0,0,0,0);
    }
    gfx_display=0;gfx_context=0;gfx_surface=0;return 0;
}
