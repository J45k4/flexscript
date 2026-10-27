// Flexscript-owned premultiplied-alpha 2D renderer. EGL/OpenGL are driver APIs;
// there is no SDL window, renderer, texture, text surface or C application shim.
import "../backends/wayland/client.flex";
import "../../../lib/ffi-words.flex";
import "../metrics.flex";
global gr_error=0;
// Context +424 tracks scissor enable; +432 is known opacity of this window
// backbuffer. FBO clears do not affect it; swap/resize/surface changes reset it.
// +440..464 cache the physical scissor rectangle; +472/480 cache the shader's
// logical viewport. The canvas owns its context/program/VAO/VBO/texture unit.
fn gr_fail(text){gr_error=text;return 0;}
fn gr_egl(g,name,a,b,c,d,e,f){return ffi_call(ffi_symbol(load64(g),name),a,b,c,d,e,f);}
fn gr_egli(g,name,a,b,c,d,e,f){return ffi_call_i32(ffi_symbol(load64(g),name),a,b,c,d,e,f);}
fn gr_proc(g,name){let p=ffi_symbol(load64(g+8),name);if !p{p=gr_egl(g,"eglGetProcAddress",name,0,0,0,0,0);}return p;}
fn gr_gl(g,index,a,b,c,d,e,f){return ffi_call(load64(g+512+index*8),a,b,c,d,e,f);}
fn gr_words(g,index,count){return ffi_words_call(load64(g+56),load64(g+512+index*8),g+320,count);}
fn gr_arg(g,index,value){store64(g+320+index*8,value);return 0;}
fn gr_functions(g){
    let names="glCreateShader;glShaderSource;glCompileShader;glGetShaderiv;glGetShaderInfoLog;glDeleteShader;glCreateProgram;glAttachShader;glLinkProgram;glGetProgramiv;glGetProgramInfoLog;glDeleteProgram;glUseProgram;glGetUniformLocation;glUniform2i;glUniform1i;glGenVertexArrays;glBindVertexArray;glDeleteVertexArrays;glGenBuffers;glBindBuffer;glBufferData;glDeleteBuffers;glEnableVertexAttribArray;glVertexAttribIPointer;glGenTextures;glBindTexture;glTexParameteri;glTexImage2D;glTexSubImage2D;glDeleteTextures;glActiveTexture;glGenFramebuffers;glBindFramebuffer;glFramebufferTexture2D;glCheckFramebufferStatus;glDeleteFramebuffers;glViewport;glEnable;glDisable;glScissor;glBlendFuncSeparate;glDrawArrays;glClearBufferfv;glPixelStorei;glReadPixels;glGetString;glGetIntegerv;glGetError;";
    let at=0;let index=0;while load8(names+at){let n=0;while load8(names+at)!=59{store8(g+1024+n,load8(names+at));n=n+1;at=at+1;}store8(g+1024+n,0);at=at+1;let p=gr_proc(g,g+1024);if !p{return gr_fail("Required OpenGL 3.3 entry point is unavailable");}store64(g+512+index*8,p);index=index+1;}return 1;
}
fn gr_shader(g,type,source){
    let shader=gr_gl(g,0,type,0,0,0,0,0);if !shader{return gr_fail("Cannot create native UI shader");}store64(g+416,source);gr_gl(g,1,shader,1,g+416,0,0,0);gr_gl(g,2,shader,0,0,0,0,0);bytes_store32(g+280,0);gr_gl(g,3,shader,0x8b81,g+280,0,0,0);
    if !bytes_load32(g+280){gr_gl(g,4,shader,1024,0,g+1024,0,0);gr_gl(g,5,shader,0,0,0,0,0);return gr_fail("Native UI shader compilation failed");}return shader;
}
fn gr_program(g){
    let vertex="#version 330 core\nlayout(location=0) in ivec2 aPos;layout(location=1) in ivec2 aUV;layout(location=2) in uint aColor;layout(location=3) in int aMode;uniform ivec2 uViewport;out vec2 vUV;flat out vec4 vColor;flat out int vMode;void main(){vec2 p=vec2(aPos)/vec2(uViewport);gl_Position=vec4(p.x*2.0-1.0,1.0-p.y*2.0,0,1);vUV=vec2(aUV);vColor=vec4(float((aColor>>16u)&255u),float((aColor>>8u)&255u),float(aColor&255u),float((aColor>>24u)&255u))/255.0;vMode=aMode;}\n";
    let fragment="#version 330 core\nin vec2 vUV;flat in vec4 vColor;flat in int vMode;uniform sampler2D uTexture;out vec4 result;void main(){if(vMode==0){result=vec4(vColor.rgb*vColor.a,vColor.a);}else{vec2 uv=vUV;if(vMode==2){uv.y=float(textureSize(uTexture,0).y)-uv.y;}vec4 t=texture(uTexture,uv/vec2(textureSize(uTexture,0)));if(vMode==1){t.rgb*=t.a;}if(vMode==3){t=vec4(t.rrr,t.r);}result=vec4(t.rgb*vColor.rgb*vColor.a,t.a*vColor.a);}}\n";
    let v=gr_shader(g,0x8b31,vertex);if !v{return 0;}let f=gr_shader(g,0x8b30,fragment);if !f{gr_gl(g,5,v,0,0,0,0,0);return 0;}
    let program=gr_gl(g,6,0,0,0,0,0,0);gr_gl(g,7,program,v,0,0,0,0);gr_gl(g,7,program,f,0,0,0,0);gr_gl(g,8,program,0,0,0,0,0);gr_gl(g,5,v,0,0,0,0,0);gr_gl(g,5,f,0,0,0,0,0);bytes_store32(g+280,0);gr_gl(g,9,program,0x8b82,g+280,0,0,0);
    if !bytes_load32(g+280){gr_gl(g,11,program,0,0,0,0,0);return gr_fail("Native UI shader linking failed");}store64(g+80,program);store64(g+176,gr_gl(g,13,program,"uViewport",0,0,0,0));store64(g+184,gr_gl(g,13,program,"uTexture",0,0,0,0));return 1;
}
fn gr_flush(g){
    let count=load64(g+208);if !count{return 1;}let width=load64(g+112);let height=load64(g+120);if width!=load64(g+472) || height!=load64(g+480){gr_gl(g,14,load64(g+176),width,height,0,0,0);store64(g+472,width);store64(g+480,height);}
    gr_gl(g,21,0x8892,count*24,load64(g+200),0x88e0,0,0);gr_gl(g,26,0x0de1,load64(g+216),0,0,0,0);gr_gl(g,42,4,0,count,0,0,0);store64(g+208,0);store64(g+240,load64(g+240)+1);return 1;
}
fn gr_size(g,width,height){
    if width<=0 || height<=0{width=load64(g+144);height=load64(g+152);}if width==load64(g+112) && height==load64(g+120){return 1;}gr_flush(g);store64(g+112,width);store64(g+120,height);return 1;
}
fn gr_target(g,texture){
    if texture && load64(texture+56)!=g{return gr_fail("Texture belongs to another renderer");}let fbo=0;let width=load64(g+128);let height=load64(g+136);
    if texture{fbo=load64(texture+40);if !fbo{return gr_fail("Texture is not a render target");}width=load64(texture+8);height=load64(texture+16);}
    gr_flush(g);store64(g+104,texture);store64(g+144,width);store64(g+152,height);gr_gl(g,33,0x8d40,fbo,0,0,0,0);gr_gl(g,37,0,0,width,height,0,0);if load64(g+424){gr_gl(g,39,0x0c11,0,0,0,0,0);}store64(g+424,0);if !texture{let client=load64(g+72);width=load64(client+72);height=load64(client+80);}return gr_size(g,width,height);
}
fn gr_clip(g,x,y,width,height){
    let pw=load64(g+144);let ph=load64(g+152);let vw=load64(g+112);let vh=load64(g+120);
    let left=x*pw/vw;let top=y*ph/vh;let right=(x+width)*pw/vw;let bottom=(y+height)*ph/vh;
    if left<0{left=0;}if top<0{top=0;}if right>pw{right=pw;}if bottom>ph{bottom=ph;}if right<left{right=left;}if bottom<top{bottom=top;}
    let sy=ph-bottom;let sw=right-left;let sh=bottom-top;if load64(g+424) && left==load64(g+440) && sy==load64(g+448) && sw==load64(g+456) && sh==load64(g+464){return 1;}gr_flush(g);if !load64(g+424){gr_gl(g,38,0x0c11,0,0,0,0,0);}store64(g+424,1);store64(g+440,left);store64(g+448,sy);store64(g+456,sw);store64(g+464,sh);gr_gl(g,40,left,sy,sw,sh,0,0);return 1;
}
fn gr_unclip(g){if !load64(g+424){return 1;}gr_flush(g);gr_gl(g,39,0x0c11,0,0,0,0,0);store64(g+424,0);return 1;}
fn gr_channel(value){
    if !value{return 0;}let exponent=0;while value<255{value=value*2;exponent=exponent-1;}
    return ((127+exponent)<<23)|(((value-255)*8388608+127)/255);
}
fn gr_clear_to(g,color,whole){
    if !load64(g+104) && !gr_resize(g){return 0;}
    gr_flush(g);let clipped=whole && load64(g+424);if clipped{gr_gl(g,39,0x0c11,0,0,0,0,0);}let alpha=(color>>24)&255;if !load64(g+104){if alpha!=255{store64(g+432,0);}else if whole || !load64(g+424){store64(g+432,1);}}bytes_store32(g+256,gr_channel(((color>>16)&255)*alpha/255));bytes_store32(g+260,gr_channel(((color>>8)&255)*alpha/255));bytes_store32(g+264,gr_channel((color&255)*alpha/255));bytes_store32(g+268,gr_channel(alpha));gr_gl(g,43,0x1800,0,g+256,0,0,0);if clipped{gr_gl(g,38,0x0c11,0,0,0,0,0);}return 1;
}
// Raw renderer clears may be clipped (including transparent opacity probes).
// Public canvas clears match SDL_RenderClear: ignore viewport/clip for this
// operation only. The cached scissor rectangle and following draws stay intact.
fn gr_clear(g,color){return gr_clear_to(g,color,0);}
fn gr_clear_all(g,color){return gr_clear_to(g,color,1);}
// The Linux x86-64 GL vertex ABI is six little-endian 32-bit words. Pack pairs
// directly rather than making six bytewise store calls per vertex. Mask the
// low member so negative/high-word inputs cannot overwrite its neighbor.
fn gr_vertex(p,x,y,u,v,color,mode){store64(p,(x&0xffffffff)|(y<<32));store64(p+8,(u&0xffffffff)|(v<<32));store64(p+16,(color&0xffffffff)|(mode<<32));return 0;}
fn gr_quad(g,texture,x,y,width,height,u,v,uw,vh,color,mode){
    if width<=0 || height<=0{return 1;}if load64(g+208)>4090 || load64(g+216)!=texture{gr_flush(g);}store64(g+216,texture);
    let p=load64(g+200)+load64(g+208)*24;let right=x+width;let bottom=y+height;
    gr_vertex(p,x,y,u,v,color,mode);gr_vertex(p+24,right,y,u+uw,v,color,mode);gr_vertex(p+48,x,bottom,u,v+vh,color,mode);
    gr_vertex(p+72,x,bottom,u,v+vh,color,mode);gr_vertex(p+96,right,y,u+uw,v,color,mode);gr_vertex(p+120,right,bottom,u+uw,v+vh,color,mode);store64(g+208,load64(g+208)+6);return 1;
}
fn gr_fill(g,x,y,width,height,color){return gr_quad(g,0,x,y,width,height,0,0,0,0,color,0);}
fn gr_texture(g,width,height,pixels,layer,mode){
    if width<1 || height<1 || width>16384 || height>16384 || width>24000000/height{return gr_fail("Invalid native texture size");}
    let t=alloc(64);if t<0{return gr_fail("Texture allocation failed");}wl_zero(t,64);store64(t+8,width);store64(t+16,height);store64(t+24,255);store64(t+32,mode);store64(t+56,g);gui_metrics_add(2,1);let upload_start=gui_metrics_start();
    gr_gl(g,25,1,g+280,0,0,0,0);store64(t,bytes_load32(g+280));gr_gl(g,26,0x0de1,load64(t),0,0,0,0);gr_gl(g,27,0x0de1,0x2801,0x2601,0,0,0);gr_gl(g,27,0x0de1,0x2800,0x2601,0,0,0);gr_gl(g,27,0x0de1,0x2802,0x812f,0,0,0);gr_gl(g,27,0x0de1,0x2803,0x812f,0,0,0);gr_gl(g,44,0x0cf5,1,0,0,0,0);
    let format=0x1908;let internal=0x8058;let channels=4;if mode==3{format=0x1903;internal=0x8229;channels=1;}
    gr_arg(g,0,0x0de1);gr_arg(g,1,0);gr_arg(g,2,internal);gr_arg(g,3,width);gr_arg(g,4,height);gr_arg(g,5,0);gr_arg(g,6,format);gr_arg(g,7,0x1401);gr_arg(g,8,pixels);gr_words(g,28,9);
    if layer{
        gr_gl(g,32,1,g+280,0,0,0,0);store64(t+40,bytes_load32(g+280));gr_gl(g,33,0x8d40,load64(t+40),0,0,0,0);gr_gl(g,34,0x8d40,0x8ce0,0x0de1,load64(t),0,0);
        let ok=gr_gl(g,35,0x8d40,0,0,0,0,0)==0x8cd5;let previous=load64(g+104);let fbo=0;if previous{fbo=load64(previous+40);}gr_gl(g,33,0x8d40,fbo,0,0,0,0);
        if !ok{bytes_store32(g+280,load64(t+40));gr_gl(g,36,1,g+280,0,0,0,0);bytes_store32(g+280,load64(t));gr_gl(g,30,1,g+280,0,0,0,0);syscall(11,t,64,0,0,0,0);return gr_fail("Native texture framebuffer is incomplete");}
    }
    store64(t+48,load64(g+232));store64(g+232,t);if pixels{store64(g+248,load64(g+248)+width*height*channels);gui_metrics_add(3,1);gui_metrics_add(4,width*height*channels);}gui_metrics_end(9,upload_start);return t;
}
// Tightly packed pixel updates. R8 is used for coverage; mode 4 is uploaded
// premultiplied RGBA (color glyphs), without render-target vertical inversion.
fn gr_texture_patch(g,t,x,y,width,height,pixels){
    if !t || load64(t+56)!=g || !pixels || x<0 || y<0 || width<1 || height<1 || x+width>load64(t+8) || y+height>load64(t+16){return gr_fail("Invalid native texture update");}
    gr_flush(g);let upload_start=gui_metrics_start();gr_gl(g,26,0x0de1,load64(t),0,0,0,0);gr_gl(g,44,0x0cf5,1,0,0,0,0);let format=0x1908;let channels=4;if load64(t+32)==3{format=0x1903;channels=1;}
    gr_arg(g,0,0x0de1);gr_arg(g,1,0);gr_arg(g,2,x);gr_arg(g,3,y);gr_arg(g,4,width);gr_arg(g,5,height);gr_arg(g,6,format);gr_arg(g,7,0x1401);gr_arg(g,8,pixels);gr_words(g,29,9);
    store64(g+248,load64(g+248)+width*height*channels);gui_metrics_add(3,1);gui_metrics_add(4,width*height*channels);gui_metrics_end(9,upload_start);return 1;
}
fn gr_texture_free(texture){
    if !texture{return 0;}let g=load64(texture+56);gr_flush(g);if load64(g+104)==texture{gr_target(g,0);}let previous=0;let t=load64(g+232);while t && t!=texture{previous=t;t=load64(t+48);}if !t{return 0;}
    if previous{store64(previous+48,load64(t+48));}else{store64(g+232,load64(t+48));}
    if load64(t+40){bytes_store32(g+280,load64(t+40));gr_gl(g,36,1,g+280,0,0,0,0);}bytes_store32(g+280,load64(t));gr_gl(g,30,1,g+280,0,0,0,0);syscall(11,t,64,0,0,0,0);return 0;
}
fn gr_texture_draw(g,t,x,y,width,height){
    if !t || load64(t+56)!=g{return gr_fail("Invalid native texture");}let color=0xffffff|(load64(t+24)<<24);return gr_quad(g,load64(t),x,y,width,height,0,0,load64(t+8),load64(t+16),color,load64(t+32));
}
fn gr_resize(g){
    let c=load64(g+72);if load64(c+112){return gr_fail(wl_error);}let w=ws_width(c);let h=ws_height(c);let lw=load64(c+72);let lh=load64(c+80);let vw=load64(g+112);let vh=load64(g+120);let automatic=vw==load64(g+160) && vh==load64(g+168);
    let hidden=!wt_ready(c);let changed=hidden!=load64(g+304);if w==load64(g+128) && h==load64(g+136) && !changed{if !load64(g+104) && automatic && (lw!=load64(g+160) || lh!=load64(g+168)){gr_size(g,lw,lh);}store64(g+160,lw);store64(g+168,lh);return 1;}gr_flush(g);
    ffi_call(ffi_symbol(load64(g+40),"wl_egl_window_resize"),load64(g+48),w,h,0,0,0);if changed || hidden{if !gr_surface(g,hidden,w,h){return 0;}}store64(g+128,w);store64(g+136,h);store64(g+432,0);store64(g+160,lw);store64(g+168,lh);if !load64(g+104){gr_target(g,0);if !automatic{gr_size(g,vw,vh);}}return 1;
}
// Rebind only the EGL surface. Context, GL objects, glyph atlases and layers
// survive unmapping. The old window surface's driver-owned frame/FIFO protocol
// objects are released before the xdg role is destroyed and remapped.
fn gr_surface(g,hidden,width,height){
    let display=load64(g+16);let surface=0;if hidden{let attrs=g+2048;bytes_store32(attrs,0x3057);bytes_store32(attrs+4,width);bytes_store32(attrs+8,0x3056);bytes_store32(attrs+12,height);bytes_store32(attrs+16,0x3038);surface=gr_egl(g,"eglCreatePbufferSurface",display,load64(g+64),attrs,0,0,0);}else{surface=gr_egl(g,"eglCreateWindowSurface",display,load64(g+64),load64(g+48),0,0,0);}if !surface{return gr_fail("Cannot create the native window/offscreen EGL surface");}
    if gr_egli(g,"eglMakeCurrent",display,surface,surface,load64(g+32),0,0)!=1{gr_egl(g,"eglDestroySurface",display,surface,0,0,0,0);return gr_fail("Cannot switch the native window/offscreen EGL surface");}let old=load64(g+24);store64(g+24,surface);store64(g+304,hidden);store64(g+432,0);if old{gr_egl(g,"eglDestroySurface",display,old,0,0,0,0);}gr_egli(g,"eglSwapInterval",display,0,0,0,0,0);return 1;
}
fn gr_suspend(g){if load64(g+304){return 1;}gr_flush(g);if !gr_surface(g,1,load64(g+128),load64(g+136)){return 0;}return gr_target(g,load64(g+104));}
fn gr_present(g){
    let c=load64(g+72);if load64(c+112){return gr_fail(wl_error);}if !wt_ready(c){store64(g+208,0);return 1;}if !gr_resize(g){return 0;}gr_flush(g);if !ws_apply(c) || !wt_geometry(c) || !wt_opaque(c,load64(g+432)){return gr_fail(wl_error);}let previous_frame=load64(c+168);let measurement=load64(load64(c+464)+40);if !wpd_submit(c){return gr_fail(wl_error);}if !load64(c+168){let callback=wl_req(c,load64(c+48),3,ffi_symbol(load64(c),"wl_callback_interface"),wl_args(c,0,0,0,0,0,0),0);store64(c+168,wl_watch(c,callback,8,0));if !load64(c+168){return gr_fail(wl_error);}}if gr_egli(g,"eglSwapBuffers",load64(g+16),load64(g+24),0,0,0,0)!=1{if !previous_frame && load64(c+168){wl_destroy(c,load64(c+168),-1);store64(c+168,0);}wpd_cancel_slot(c,measurement);return gr_fail("Native EGL presentation failed");}store64(g+432,0);if !wt_flush(c){if load64(c+168){wl_destroy(c,load64(c+168),-1);store64(c+168,0);}wpd_cancel(c);return gr_fail(wl_error);}return wt_presented(c);
}
fn gr_read(g,pixels,pitch,bytes){
    let width=load64(g+144);let height=load64(g+152);if pitch<width*4 || bytes<(height-1)*pitch+width*4{return gr_fail("Invalid native readback buffer");}gr_flush(g);let n=width*height*4;let raw=alloc(n);if raw<0{return gr_fail("Readback allocation failed");}
    gr_gl(g,44,0x0d05,1,0,0,0,0);gr_arg(g,0,0);gr_arg(g,1,0);gr_arg(g,2,width);gr_arg(g,3,height);gr_arg(g,4,0x1908);gr_arg(g,5,0x1401);gr_arg(g,6,raw);gr_words(g,45,7);
    let y=0;while y<height{bytes_copy(pixels+y*pitch,raw+(height-y-1)*width*4,width*4);y=y+1;}syscall(11,raw,n,0,0,0,0);return 1;
}
fn gr_close(g){
    if !g{return 0;}if load64(g+80){while load64(g+232){gr_texture_free(load64(g+232));}gr_gl(g,11,load64(g+80),0,0,0,0,0);}
    if load64(g+96){bytes_store32(g+280,load64(g+96));gr_gl(g,22,1,g+280,0,0,0,0);}if load64(g+88){bytes_store32(g+280,load64(g+88));gr_gl(g,18,1,g+280,0,0,0,0);}if load64(g+200){syscall(11,load64(g+200),4096*24,0,0,0,0);}
    if load64(g+16){gr_egl(g,"eglMakeCurrent",load64(g+16),0,0,0,0,0);if load64(g+24){gr_egl(g,"eglDestroySurface",load64(g+16),load64(g+24),0,0,0,0);}if load64(g+32){gr_egl(g,"eglDestroyContext",load64(g+16),load64(g+32),0,0,0,0);}gr_egl(g,"eglTerminate",load64(g+16),0,0,0,0,0);}
    if load64(g+48){ffi_call(ffi_symbol(load64(g+40),"wl_egl_window_destroy"),load64(g+48),0,0,0,0,0);}ffi_words_free(load64(g+56));if load64(g+8){ffi_close(load64(g+8));}if load64(g+40){ffi_close(load64(g+40));}if load64(g){ffi_close(load64(g));}syscall(11,g,4096,0,0,0,0);return 0;
}
fn gr_open(client){
    gr_error=0;let g=alloc(4096);if g<0{return gr_fail("Renderer allocation failed");}wl_zero(g,4096);store64(g+72,client);store64(g,ffi_open("libEGL.so.1"));store64(g+8,ffi_open("libGL.so.1"));store64(g+40,ffi_open("libwayland-egl.so.1"));store64(g+56,ffi_words_context());
    if !load64(g) || !load64(g+8) || !load64(g+40) || !load64(g+56){gr_close(g);return gr_fail("EGL, OpenGL and Wayland EGL runtimes are required");}
    let display=gr_egl(g,"eglGetPlatformDisplay",0x31d8,load64(client+8),0,0,0,0);store64(g+16,display);
    if !display || gr_egli(g,"eglInitialize",display,0,0,0,0,0)!=1 || gr_egli(g,"eglBindAPI",0x30a2,0,0,0,0,0)!=1{gr_close(g);return gr_fail("Cannot initialize native Wayland EGL");}
    let attrs=g+2048;let options="12324,8,12323,8,12322,8,12321,8,12339,5,12352,8,12344;";let at=0;let i=0;let value=0;
    while load8(options+at){let ch=load8(options+at);if ch==44 || ch==59{bytes_store32(attrs+i*4,value);value=0;i=i+1;}else{value=value*10+ch-48;}at=at+1;}
    if gr_egli(g,"eglChooseConfig",display,attrs,g+280,1,g+288,0)!=1 || !bytes_load32(g+288){gr_close(g);return gr_fail("No EGL window configuration");}let config=load64(g+280);store64(g+64,config);
    bytes_store32(attrs,0x3098);bytes_store32(attrs+4,3);bytes_store32(attrs+8,0x30fb);bytes_store32(attrs+12,3);bytes_store32(attrs+16,0x30fd);bytes_store32(attrs+20,1);bytes_store32(attrs+24,0x3038);
    let context=gr_egl(g,"eglCreateContext",display,config,0,attrs,0,0);store64(g+32,context);if !context{gr_close(g);return gr_fail("OpenGL 3.3 core is required");}
    let width=ws_width(client);let height=ws_height(client);let window=ffi_call(ffi_symbol(load64(g+40),"wl_egl_window_create"),load64(client+48),width,height,0,0,0);store64(g+48,window);
    if !window || !gr_surface(g,!wt_ready(client),width,height){gr_close(g);return gr_fail("Cannot activate native Wayland GL surface");}
    if !gr_functions(g) || !gr_program(g){gr_close(g);return 0;}
    gr_gl(g,16,1,g+280,0,0,0,0);store64(g+88,bytes_load32(g+280));gr_gl(g,17,load64(g+88),0,0,0,0,0);gr_gl(g,19,1,g+280,0,0,0,0);store64(g+96,bytes_load32(g+280));gr_gl(g,20,0x8892,load64(g+96),0,0,0,0);
    i=0;while i<4{gr_gl(g,23,i,0,0,0,0,0);let size=2;let type=0x1404;if i>=2{size=1;}if i==2{type=0x1405;}let offset=i*8;if i==3{offset=20;}gr_gl(g,24,i,size,type,24,offset,0);i=i+1;}
    // No canvas operation changes these bindings. Texture upload/target work
    // may change the texture/FBO, which each draw/target still binds explicitly.
    gr_gl(g,12,load64(g+80),0,0,0,0,0);gr_gl(g,15,load64(g+184),0,0,0,0,0);gr_gl(g,31,0x84c0,0,0,0,0,0);
    let vertices=alloc(4096*24);if vertices<0{gr_close(g);return gr_fail("Draw buffer allocation failed");}store64(g+200,vertices);store64(g+128,width);store64(g+136,height);store64(g+160,load64(client+72));store64(g+168,load64(client+80));gr_gl(g,38,0x0be2,0,0,0,0,0);gr_gl(g,41,1,0x0303,1,0x0303,0,0);gr_target(g,0);return g;
}
