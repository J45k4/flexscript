import "../../lib/ffi-words.flex";
// Materials own arbitrary shader programs. Pass 0 = opaque, 1 = alpha, 2 =
// depth-only. A depth variant may use its own vertex shader for deformation.
fn render_material(d,vertex,fragment) {
    let program=render_program(d,vertex,fragment);if !program {return 0;}
    let m=gui__zero(alloc(48),48);store64(m,d);store64(m+8,program);store64(m+32,1);return m;
}
fn render_depth_variant(m,vertex,fragment) {
    if !m || !load64(m+8) {return gui__fail("Material is closed");}
    let p=render_program(load64(m),vertex,fragment);if !p {return 0;}
    if load64(m+16) {render_delete(load64(m),1,load64(m+16));}store64(m+16,p);return 1;
}
fn render_material_state(m,alpha,cull) {
    if !m || !load64(m+8) {return 0;}store64(m+24,alpha!=0);store64(m+32,cull!=0);return 1;
}
fn render_material_bind(m,pass) {
    if !m || !load64(m+8) || pass<0 || pass>2 {return gui__fail("Invalid material pass");}
    let d=load64(m);if !render_live(d) {return 0;}
    let p=load64(m+8);if pass==2 {p=load64(m+16);if !p {return gui__fail("Material has no depth shader variant");}}
    render_gl(d,"glUseProgram",p,0,0,0,0,0);render_gl(d,"glEnable",0x0b71,0,0,0,0,0);
    if load64(m+32) {render_gl(d,"glEnable",0x0b44,0,0,0,0,0);}else {render_gl(d,"glDisable",0x0b44,0,0,0,0,0);}
    if pass==1 && load64(m+24) {
        render_gl(d,"glEnable",0x0be2,0,0,0,0,0);render_gl(d,"glBlendFunc",0x0302,0x0303,0,0,0,0);render_gl(d,"glDepthMask",0,0,0,0,0,0);
    }else {render_gl(d,"glDisable",0x0be2,0,0,0,0,0);render_gl(d,"glDepthMask",1,0,0,0,0,0);}return 1;
}
fn render_uniform(m,pass,name) {
    if !m || !load64(m+8) || pass<0 || pass>2 {return -1;}
    let p=load64(m+8);if pass==2 {p=load64(m+16);}if !p {return -1;}
    let result=render_gl(load64(m),"glGetUniformLocation",p,name,0,0,0,0)&4294967295;
    if result==4294967295 {return -1;}return result;
}
fn render_matrix(m,pass,name,matrix) {
    if !matrix || !render_material_bind(m,pass) {return 0;}
    let location=render_uniform(m,pass,name);if location<0 {return gui__fail("Required matrix uniform is missing");}
    render_gl(load64(m),"glUniformMatrix4fv",location,1,0,matrix,0,0);return 1;
}
fn render_texture(m,pass,name,unit,target,texture) {
    if unit<0 || unit>15 || !render_material_bind(m,pass) {return 0;}
    let location=render_uniform(m,pass,name);if location<0 {return gui__fail("Required texture uniform is missing");}
    let d=load64(m);render_gl(d,"glActiveTexture",0x84c0+unit,0,0,0,0,0);
    render_gl(d,"glBindTexture",target,texture,0,0,0,0);render_gl(d,"glUniform1i",location,unit,0,0,0,0);return 1;
}
// Named uniform blocks work with compiler-generated sw_blockN names and with
// caller-written GLSL. Storage is reused by binding across material variants.
fn render_block(m,pass,name,binding,data,bytes) {
    if !data || binding<0 || binding>31 || bytes<1 || bytes>65536 || !render_material_bind(m,pass) {return 0;}
    let d=load64(m);let program=load64(m+8);if pass==2 {program=load64(m+16);}
    let index=render_gl(d,"glGetUniformBlockIndex",program,name,0,0,0,0)&4294967295;
    if index==4294967295 {return gui__fail("Required uniform block is missing");}
    let required=load64(d+24);render_gl(d,"glGetActiveUniformBlockiv",program,index,0x8a40,required,0,0);
    if bytes<gui__u32(required) {return gui__fail("Uniform block data is too small");}
    let block=load64(m+40);while block && load64(block)!=binding {block=load64(block+24);}
    if !block {
        let buffer=render_buffer(d);if !buffer {return 0;}block=alloc(32);
        store64(block,binding);store64(block+8,buffer);store64(block+16,0);store64(block+24,load64(m+40));store64(m+40,block);
    }
    if !render_upload(d,load64(block+8),0x8a11,bytes,data,0x88e8) {return 0;}store64(block+16,bytes);
    render_gl(d,"glUniformBlockBinding",program,index,binding,0,0,0);render_gl(d,"glBindBufferBase",0x8a11,binding,load64(block+8),0,0,0);return 1;
}
fn render_mesh(d,stride,attributes,count) {
    let vao=render_array(d);if !vao {return 0;}let buffer=render_buffer(d);
    if !buffer || !render_layout(d,vao,buffer,stride,attributes,count) {render_delete(d,3,vao);if buffer {render_delete(d,2,buffer);}return 0;}
    let m=gui__zero(alloc(48),48);store64(m,d);store64(m+8,vao);store64(m+16,buffer);store64(m+24,stride);return m;
}
fn render_mesh_upload(mesh,data,vertices,usage) {
    if !mesh || !load64(mesh+8) || vertices<0 || vertices>134217728/load64(mesh+24) || (vertices && !data) {return gui__fail("Invalid mesh upload");}
    if !render_upload(load64(mesh),load64(mesh+16),0x8892,vertices*load64(mesh+24),data,usage) {return 0;}
    store64(mesh+32,vertices);return 1;
}
fn render_mesh_draw(mesh,material,pass,first,count) {
    if !mesh || !material || load64(mesh)!=load64(material) || first<0 || count<0 || first>load64(mesh+32) || count>load64(mesh+32)-first {return gui__fail("Invalid mesh draw range or material device");}
    if !render_material_bind(material,pass) {return 0;}return render_draw(load64(mesh),load64(mesh+8),4,first,count);
}
fn render_mesh_close(mesh) {
    if !mesh || !load64(mesh+8) {return 1;}render_delete(load64(mesh),3,load64(mesh+8));render_delete(load64(mesh),2,load64(mesh+16));store64(mesh+8,0);return 1;
}
fn render_material_close(m) {
    if !m || !load64(m+8) {return 1;}render_delete(load64(m),1,load64(m+8));if load64(m+16) {render_delete(load64(m),1,load64(m+16));}
    let b=load64(m+40);while b {let next=load64(b+24);render_delete(load64(m),2,load64(b+8));syscall(11,b,32,0,0,0,0);b=next;}
    store64(m+8,0);store64(m+16,0);store64(m+40,0);return 1;
}
// Depth target: device, texture, framebuffer, width, height. Uses a regular
// depth sampler, so custom shaders choose comparison and filtering themselves.
fn render_depth_target(d,width,height) {
    if width<1 || height<1 || width>8192 || height>8192 || !render_live(d) {return gui__fail("Invalid depth target dimensions");}
    let p=load64(d+24);gui__put32(p,0);render_gl(d,"glGenTextures",1,p,0,0,0,0);let texture=render_track(d,4,gui__u32(p));if !texture {return 0;}
    render_gl(d,"glBindTexture",0x0de1,texture,0,0,0,0);
    // glTexImage2D has nine arguments, supplied through the portable word FFI.
    let args=gui__zero(alloc(88),88);store64(args,0x0de1);store64(args+16,0x81a6);store64(args+24,width);store64(args+32,height);store64(args+48,0x1902);store64(args+56,0x1405);
    let function=gui_gl_cached_proc(load64(d),"glTexImage2D");let result=ffi_call_words(function,args);syscall(11,args,88,0,0,0,0);
    if result== -10001 || result== -10002 || result== -10003 {render_delete(d,4,texture);return gui__fail("Depth target allocation FFI failed");}
    render_gl(d,"glTexParameteri",0x0de1,0x2801,0x2600,0,0,0);render_gl(d,"glTexParameteri",0x0de1,0x2800,0x2600,0,0,0);
    render_gl(d,"glTexParameteri",0x0de1,0x2802,0x812f,0,0,0);render_gl(d,"glTexParameteri",0x0de1,0x2803,0x812f,0,0,0);
    gui__put32(p,0);render_gl(d,"glGenFramebuffers",1,p,0,0,0,0);let fbo=render_track(d,5,gui__u32(p));
    render_gl(d,"glBindFramebuffer",0x8d40,fbo,0,0,0,0);render_gl(d,"glFramebufferTexture2D",0x8d40,0x8d00,0x0de1,texture,0,0);
    render_gl(d,"glDrawBuffer",0,0,0,0,0,0);render_gl(d,"glReadBuffer",0,0,0,0,0,0);
    let complete=render_gl(d,"glCheckFramebufferStatus",0x8d40,0,0,0,0,0)==0x8cd5;render_gl(d,"glBindFramebuffer",0x8d40,0,0,0,0,0);
    if !complete {render_delete(d,5,fbo);render_delete(d,4,texture);return gui__fail("Depth framebuffer is incomplete");}
    let t=alloc(40);store64(t,d);store64(t+8,texture);store64(t+16,fbo);store64(t+24,width);store64(t+32,height);return t;
}
fn render_begin(d,target,width,height) {
    if !render_live(d) || width<1 || height<1 {return 0;}
    let fbo=0;if target {if load64(target)!=d || !load64(target+16) {return gui__fail("Invalid render target");}fbo=load64(target+16);width=load64(target+24);height=load64(target+32);}
    render_gl(d,"glBindFramebuffer",0x8d40,fbo,0,0,0,0);render_gl(d,"glViewport",0,0,width,height,0,0);
    render_gl(d,"glDepthMask",1,0,0,0,0,0);render_gl(d,"glClear",0x4100,0,0,0,0,0);return 1;
}
fn render_target_close(t) {
    if !t || !load64(t+16) {return 1;}render_delete(load64(t),5,load64(t+16));render_delete(load64(t),4,load64(t+8));store64(t+16,0);store64(t+8,0);return 1;
}
