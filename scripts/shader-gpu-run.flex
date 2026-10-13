// Driver-level execution of SetaScript-generated GLSL, with CPU readback oracles.
import "lib/build.flex";
import "../lib/graphics.flex";
import "../lib/ffi-words.flex";
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
// Struct layout oracle: the host writes bytes at the offsets documented in the
// generated layout comment (Light 32 bytes, Particle 128 bytes).
fn sh_particle(p,i) {
    gfx_u32(p,sh_float(i));gfx_u32(p+16,sh_float(i));gfx_u32(p+20,sh_float(1));gfx_u32(p+24,sh_float(2));gfx_u32(p+28,sh_float(1));
    gfx_u32(p+32,sh_float(5));gfx_u32(p+36,sh_float(6));gfx_u32(p+48,sh_float(2));gfx_u32(p+68,sh_float(2));gfx_u32(p+88,sh_float(2));gfx_u32(p+108,sh_float(1));
    gfx_u32(p+112,i);return 0;
}
fn sh_expect(p,offset,value,i) {h_assert(gfx_get_u32(p+offset)==value,h_cat3("GLSL struct mismatch at particle ",h_int(i),h_cat(" offset ",h_int(offset))));return 0;}
fn sh_structs(dir) {
    let shader=gfx_shader(0x91b9,sh_source(dir,"structs-compute"));h_assert(shader,gfx_error);
    let program=gfx_int("glCreateProgram",0,0,0,0,0,0);gfx_call("glAttachShader",program,shader,0,0,0,0);gfx_call("glLinkProgram",program,0,0,0,0,0);
    let status=alloc(8);gfx_call("glGetProgramiv",program,0x8b82,status,0,0,0);
    if !gfx_get_u32(status) {let log=alloc(8192);gfx_call("glGetProgramInfoLog",program,8192,0,log,0,0);h_die(log);}
    let count=129;let size=count*128;let values=alloc(size);let i=0;while i<count {sh_particle(values+i*128,i);i=i+1;}
    let tint=alloc(32);gfx_u32(tint,sh_float(1));gfx_u32(tint+4,sh_float(2));gfx_u32(tint+8,sh_float(3));gfx_u32(tint+12,sh_float(4));
    let uniform=sh_buffer(0,0x8a11,tint,32);let input=sh_buffer(1,0x90d2,values,size);let output=sh_buffer(2,0x90d2,0,size);
    gfx_call("glUseProgram",program,0,0,0,0,0);gfx_call("glDispatchCompute",3,1,1,0,0,0);gfx_call("glMemoryBarrier",0x200,0,0,0,0,0);
    gfx_call("glGetNamedBufferSubData",output,0,size,values,0,0);h_assert(!gfx_int("glGetError",0,0,0,0,0,0),"GLSL struct readback failed");
    i=0;while i<count {let p=values+i*128;let intensity=2;if !i {intensity=1;}
        sh_expect(p,0,sh_float(i*2+5),i);sh_expect(p,4,sh_float(6),i);sh_expect(p,8,0,i);
        sh_expect(p,16,sh_float(i+4),i);sh_expect(p,20,sh_float(6),i);sh_expect(p,24,sh_float(10),i);sh_expect(p,28,sh_float(intensity),i);
        sh_expect(p,32,sh_float(5),i);sh_expect(p,36,sh_float(6),i);sh_expect(p,48,sh_float(2),i);sh_expect(p,108,sh_float(1),i);sh_expect(p,112,i+1,i);i=i+1;
    }
    let ids=alloc(12);gfx_u32(ids,uniform);gfx_u32(ids+4,input);gfx_u32(ids+8,output);gfx_call("glDeleteBuffers",3,ids,0,0,0,0);
    gfx_call("glDeleteShader",shader,0,0,0,0,0);gfx_call("glDeleteProgram",program,0,0,0,0,0);return 0;
}
// Shadow-map comparison: a 2x1 depth texture (0.25 | 0.75) sampled with
// reference 0.5 under LEQUAL must be shadowed on the left, lit on the right.
fn sh_shadow(dir) {
    let program=gfx_program(sh_source(dir,"textured-vertex"),sh_source(dir,"shadow-fragment"));h_assert(program,gfx_error);
    let value=alloc(8);gfx_call("glCreateTextures",0x0de1,1,value,0,0,0);let depth=gfx_get_u32(value);
    gfx_call("glTextureStorage2D",depth,1,0x8cac,2,1,0);let texels=alloc(8);gfx_u32(texels,0x3e800000);gfx_u32(texels+4,0x3f400000);
    // glTextureSubImage2D(depth, 0, 0, 0, 2, 1, GL_DEPTH_COMPONENT, GL_FLOAT, texels): nine arguments.
    let words=alloc(88);store64(words,depth);store64(words+8,0);store64(words+16,0);store64(words+24,0);store64(words+32,2);store64(words+40,1);
    store64(words+48,0x1902);store64(words+56,0x1406);store64(words+64,texels);store64(words+72,0);store64(words+80,0);
    ffi_call_words(gfx_symbol("glTextureSubImage2D"),words);
    gfx_call("glTextureParameteri",depth,0x2801,0x2600,0,0,0);gfx_call("glTextureParameteri",depth,0x2800,0x2600,0,0,0);
    gfx_call("glTextureParameteri",depth,0x884c,0x884e,0,0,0);gfx_call("glTextureParameteri",depth,0x884d,0x0203,0,0,0);
    gfx_call("glBindTextureUnit",0,depth,0,0,0,0);h_assert(!gfx_int("glGetError",0,0,0,0,0,0),"GLSL depth texture setup failed");
    let target=gfx_texture(64,64);gfx_texture_clear(target,0);h_assert(gfx_draw(program,target,64,64,3),gfx_error);
    let pixels=alloc(64*64*4);h_assert(!gfx_read(target,pixels,64*64*4),"GLSL shadow readback failed");
    let y=0;while y<64 {let x=0;while x<64 {let at=pixels+(y*64+x)*4;let lit=x>=32;let r=load8(at);let g=load8(at+1);let b=load8(at+2);
        h_assert((lit && r>=254 && g<=1) || (!lit && r<=1 && g>=254),h_cat("GLSL shadow comparison mismatch at x ",h_int(x)));h_assert(b>=63 && b<=65,"GLSL shadow blue channel");x=x+1;}y=y+1;}
    let ids=alloc(8);gfx_u32(ids,target);gfx_u32(ids+4,depth);gfx_call("glDeleteTextures",2,ids,0,0,0,0);gfx_call("glDeleteProgram",program,0,0,0,0,0);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let dir=b_option(argc,argv,"--dir","build/shaders");
    if !gfx_open(0,64,64) {h_print(2,h_cat3("Graphics unavailable: ",gfx_error,"\n"));gfx_close();return 77;}
    h_print(1,h_cat3("OpenGL renderer: ",gfx_renderer(),"\n"));
    sh_render(dir,"triangle-vertex","triangle-fragment",0);
    sh_render(dir,"textured-vertex","textured-fragment",1);sh_compute(dir);sh_structs(dir);sh_shadow(dir);gfx_close();
    h_print(1,"GLSL execution: 8192 rendered pixels, 129 compute results, 129 struct records and 4096 shadow comparisons passed\n");return 0;
}
