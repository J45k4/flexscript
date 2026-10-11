import "window.flex";
// Desktop core profile or OpenGL ES. Request the version the renderer needs.
fn gui_gl_open(title,width,height,flags,major,minor,es) {
    if major<1 || major>9 || minor<0 || minor>9 {return gui__fail("Invalid OpenGL version");}
    if !gui_init() {return 0;}
    gui__call("SDL_GL_ResetAttributes",0,0,0,0,0,0);
    let profile=1;if es {profile=4;}
    if gui__int("SDL_GL_SetAttribute",17,major,0,0,0,0)<0 || gui__int("SDL_GL_SetAttribute",18,minor,0,0,0,0)<0 || gui__int("SDL_GL_SetAttribute",21,profile,0,0,0,0)<0 || gui__int("SDL_GL_SetAttribute",5,1,0,0,0,0)<0 || gui__int("SDL_GL_SetAttribute",6,24,0,0,0,0)<0 || gui__int("SDL_GL_SetAttribute",7,8,0,0,0,0)<0 {return gui__sdl_error();}
    let window=gui__create(title,width,height,flags,1);if !window {return 0;}
    let p=gui__record(window);let context=gui__call("SDL_GL_CreateContext",load64(p),0,0,0,0,0);
    if !context {gui__sdl_error();gui_close(window);return 0;}
    store64(p+24,context);gui__gl_current=0;
    if !gui_gl_current(window) {gui_close(window);return 0;}
    gui__dimensions(p);return window;
}
fn gui_gl_current(window) {
    let p=gui__record(window);if !p {return 0;}
    if !load64(p+24) {return gui__fail("Window has no OpenGL context");}
    if gui__int("SDL_GL_MakeCurrent",load64(p),load64(p+24),0,0,0,0)<0 {return gui__sdl_error();}gui__gl_current=window;return 1;
}
fn gui_gl_proc(window,name) {
    if !name {return gui__fail("OpenGL symbol name is null");}if !gui_gl_current(window) {return 0;}
    let p=gui__call("SDL_GL_GetProcAddress",name,0,0,0,0,0);
    if !p {gui__sdl_error();}return p;
}
fn gui_gl_swap_interval(window,interval) {
    if interval< -1 || interval>1 {return gui__fail("Invalid OpenGL swap interval");}if !gui_gl_current(window) {return 0;}
    if gui__int("SDL_GL_SetSwapInterval",interval,0,0,0,0,0)<0 {return gui__sdl_error();}return 1;
}
fn gui_gl_swap(window) {
    if !gui_gl_current(window) {return 0;}let p=gui__record(window);
    gui__call("SDL_GL_SwapWindow",load64(p),0,0,0,0,0);return 1;
}
// Cache belongs to the live window generation. Names are copied, so callers may
// reuse their string buffers. Storage is bounded and reused when a slot reopens.
fn gui_gl_cached_proc(window,name) {
    if !name {return gui__fail("OpenGL symbol name is null");}
    let p=gui__record(window);if !p {return 0;}
    if !load64(p+24) {return gui__fail("Window has no OpenGL context");}
    if gui__gl_current!=window && !gui_gl_current(window) {return 0;}
    let cache=load64(p+656);let count=load64(p+664);
    let length=0;while length<64 && load8(name+length) {length=length+1;}
    if !length || length==64 {return gui__fail("OpenGL symbol name must contain 1 to 63 bytes");}
    let i=0;while i<count {
        let entry=cache+i*72;let j=0;
        while j<length && load8(entry+j)==load8(name+j) {j=j+1;}
        if j==length && !load8(entry+j) {return load64(entry+64);}
        i=i+1;
    }
    if count==128 {return gui__fail("OpenGL dispatch limit (128) reached");}
    let function=gui_gl_proc(window,name);if !function {return 0;}
    if !cache {cache=alloc(128*72);store64(p+656,cache);}
    let entry=cache+count*72;i=0;
    while i<=length {store8(entry+i,load8(name+i));i=i+1;}
    store64(entry+64,function);store64(p+664,count+1);return function;
}
// Returns the raw integer/pointer result. Zero can be a successful GL result;
// callers that need to distinguish lookup failure can resolve the pointer first.
fn gui_gl_call(window,name,a,b,c,d,e,f) {
    let function=gui_gl_cached_proc(window,name);if !function {return 0;}
    return ffi_call(function,a,b,c,d,e,f);
}
fn gui__gl_scratch(window) {
    let p=gui__record(window);if !p {return 0;}
    let scratch=load64(p+672);if !scratch {scratch=alloc(8208);store64(p+672,scratch);}
    return scratch;
}
// Compile a NUL-terminated GLSL stage. Failed objects are deleted and the
// driver's diagnostic is exposed through gui_error, without terminating apps.
fn gui_gl_shader(window,kind,source) {
    if !source {return gui__fail("OpenGL shader source is null");}
    if !gui_gl_cached_proc(window,"glCreateShader") || !gui_gl_cached_proc(window,"glShaderSource") || !gui_gl_cached_proc(window,"glCompileShader") || !gui_gl_cached_proc(window,"glGetShaderiv") || !gui_gl_cached_proc(window,"glGetShaderInfoLog") || !gui_gl_cached_proc(window,"glDeleteShader") {return 0;}
    let scratch=gui__gl_scratch(window);
    let shader=gui_gl_call(window,"glCreateShader",kind,0,0,0,0,0);
    if !shader {return gui__fail("OpenGL could not create shader");}
    store64(scratch,source);
    gui_gl_call(window,"glShaderSource",shader,1,scratch,0,0,0);
    gui_gl_call(window,"glCompileShader",shader,0,0,0,0,0);
    gui_gl_call(window,"glGetShaderiv",shader,0x8b81,scratch,0,0,0);
    if !gui__u32(scratch) {
        store8(scratch+16,0);
        gui_gl_call(window,"glGetShaderInfoLog",shader,8192,0,scratch+16,0,0);
        gui_gl_call(window,"glDeleteShader",shader,0,0,0,0,0);
        return gui__fail(scratch+16);
    }
    return shader;
}
// Link vertex/fragment source, releasing temporary stages on every path.
// Programs returned successfully remain owned by the caller/context.
fn gui_gl_program(window,vertex,fragment) {
    if !gui_gl_cached_proc(window,"glCreateProgram") || !gui_gl_cached_proc(window,"glAttachShader") || !gui_gl_cached_proc(window,"glLinkProgram") || !gui_gl_cached_proc(window,"glGetProgramiv") || !gui_gl_cached_proc(window,"glGetProgramInfoLog") || !gui_gl_cached_proc(window,"glDeleteProgram") {return 0;}
    let v=gui_gl_shader(window,0x8b31,vertex);if !v {return 0;}
    let f=gui_gl_shader(window,0x8b30,fragment);
    if !f {gui_gl_call(window,"glDeleteShader",v,0,0,0,0,0);return 0;}
    let program=gui_gl_call(window,"glCreateProgram",0,0,0,0,0,0);
    if program {
        gui_gl_call(window,"glAttachShader",program,v,0,0,0,0);
        gui_gl_call(window,"glAttachShader",program,f,0,0,0,0);
        gui_gl_call(window,"glLinkProgram",program,0,0,0,0,0);
    }
    gui_gl_call(window,"glDeleteShader",v,0,0,0,0,0);
    gui_gl_call(window,"glDeleteShader",f,0,0,0,0,0);
    if !program {return gui__fail("OpenGL could not create program");}
    let scratch=gui__gl_scratch(window);
    gui_gl_call(window,"glGetProgramiv",program,0x8b82,scratch,0,0,0);
    if !gui__u32(scratch) {
        store8(scratch+16,0);
        gui_gl_call(window,"glGetProgramInfoLog",program,8192,0,scratch+16,0,0);
        gui_gl_call(window,"glDeleteProgram",program,0,0,0,0,0);
        return gui__fail(scratch+16);
    }
    return program;
}
