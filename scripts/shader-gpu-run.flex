// Driver-level execution of SetaScript-generated GLSL, with CPU readback oracles.
import "lib/build.flex";
import "../lib/graphics.flex";
fn sh_source(dir,name) {return h_read(h_join(dir,h_cat(name,".glsl")));}
fn sh_float(n) {
    if !n {return 0;}let exponent=0;while (1<<(exponent+1))<=n {exponent=exponent+1;}
    return ((exponent+127)<<23)|((n-(1<<exponent))<<(23-exponent));
}
fn sh_buffer(binding,target,data,size) {
    let value=alloc(8);gfx_call("glCreateBuffers",1,value,0,0,0,0);let id=gfx_get_u32(value);
    gfx_call("glNamedBufferData",id,size,data,0x88e4,0,0);gfx_call("glBindBufferBase",target,binding,id,0,0,0);return id;
}
fn sh_render(dir,vertex,fragment,textured) {
    let program=gfx_program(sh_source(dir,vertex),sh_source(dir,fragment));h_assert(program,gfx_error);
    let paint=0;let uniform=0;
    if textured {
        paint=gfx_texture(1,1);gfx_texture_clear(paint,0xff4080c0);gfx_call("glBindTextureUnit",0,paint,0,0,0,0);
        let tint=alloc(16);gfx_u32(tint,0x3f000000);gfx_u32(tint+4,0x3f800000);gfx_u32(tint+8,0x3f000000);gfx_u32(tint+12,0x3f800000);
        uniform=sh_buffer(2,0x8a11,tint,16);
    }
    let target=gfx_texture(64,64);gfx_texture_clear(target,0);h_assert(gfx_draw(program,target,64,64,3),gfx_error);
    let pixels=alloc(64*64*4);h_assert(!gfx_read(target,pixels,64*64*4),"GLSL render readback failed");
    let expected=alloc(4);gfx_u32(expected,0xffbf8040);if textured {gfx_u32(expected,0xff208060);}
    let i=0;while i<64*64*4 {let difference=load8(pixels+i)-load8(expected+i%4);h_assert(difference>= -1 && difference<=1,h_cat("GLSL pixel mismatch at byte ",h_int(i)));i=i+1;}
    let ids=alloc(12);gfx_u32(ids,target);gfx_call("glDeleteTextures",1,ids,0,0,0,0);
    if textured {gfx_u32(ids,paint);gfx_call("glDeleteTextures",1,ids,0,0,0,0);gfx_u32(ids,uniform);gfx_call("glDeleteBuffers",1,ids,0,0,0,0);}
    gfx_call("glDeleteProgram",program,0,0,0,0,0);return 0;
}
fn sh_compute(dir) {
    let shader=gfx_shader(0x91b9,sh_source(dir,"vector-compute"));h_assert(shader,gfx_error);
    let program=gfx_int("glCreateProgram",0,0,0,0,0,0);gfx_call("glAttachShader",program,shader,0,0,0,0);gfx_call("glLinkProgram",program,0,0,0,0,0);
    let status=alloc(8);gfx_call("glGetProgramiv",program,0x8b82,status,0,0,0);
    if !gfx_get_u32(status) {let log=alloc(8192);gfx_call("glGetProgramInfoLog",program,8192,0,log,0,0);h_die(log);}
    let count=129;let values=alloc(count*4);let i=0;while i<count {gfx_u32(values+i*4,sh_float(i));i=i+1;}
    let input=sh_buffer(0,0x90d2,values,count*4);let output=sh_buffer(1,0x90d2,0,count*4);
    gfx_call("glUseProgram",program,0,0,0,0,0);gfx_call("glDispatchCompute",3,1,1,0,0,0);gfx_call("glMemoryBarrier",0x200,0,0,0,0,0);
    gfx_call("glGetNamedBufferSubData",output,0,count*4,values,0,0);h_assert(!gfx_int("glGetError",0,0,0,0,0,0),"GLSL compute readback failed");
    i=0;while i<count {h_assert(gfx_get_u32(values+i*4)==sh_float(i*3+7),h_cat("GLSL compute mismatch at ",h_int(i)));i=i+1;}
    let ids=alloc(8);gfx_u32(ids,input);gfx_u32(ids+4,output);gfx_call("glDeleteBuffers",2,ids,0,0,0,0);
    gfx_call("glDeleteShader",shader,0,0,0,0,0);gfx_call("glDeleteProgram",program,0,0,0,0,0);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let dir=b_option(argc,argv,"--dir","build/shaders");
    if !gfx_open(0,64,64) {h_print(2,h_cat3("Graphics unavailable: ",gfx_error,"\n"));gfx_close();return 77;}
    h_print(1,h_cat3("OpenGL renderer: ",gfx_renderer(),"\n"));
    sh_render(dir,"triangle-vertex","triangle-fragment",0);
    sh_render(dir,"textured-vertex","textured-fragment",1);sh_compute(dir);gfx_close();
    h_print(1,"GLSL execution: 8192 rendered pixels and 129 compute results passed\n");return 0;
}
