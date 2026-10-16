import "../gui.flex";
// Device: window, closed, dispatch table, scratch, resource list, owned window.
// Resource records: next, GL kind (1 program, 2 buffer, 3 VAO, 4 texture,
// 5 framebuffer), name. All owned objects are released before the context.
fn render_attach(window) {
    if !gui_gl_current(window) {return 0;}
    let d=gui__zero(alloc(48),48);
    store64(d,window);store64(d+16,gui__zero(alloc(8192),8192));
    store64(d+24,alloc(16));return d;
}
fn render_open(title,width,height,flags) {
    let w=gui_gl_open(title,width,height,flags,4,5,0);if !w {return 0;}
    let d=render_attach(w);if !d {gui_close(w);return 0;}
    store64(d+40,1);return d;
}
fn render_live(d) {
    if !d || load64(d+8) {return gui__fail("Renderer is closed");}
    let w=load64(d);if !gui__record(w) {return 0;}
    if gui__gl_current!=w && !gui_gl_current(w) {return 0;}
    return 1;
}
// Literal-name cache extracted from Setaworld's hot GL dispatch. Keys must be
// immutable strings for the lifetime of the device. Cache misses are bounded.
fn render_gl(d,name,a,b,c,e,f,g) {
    if !render_live(d) || !name {return 0;}
    let table=load64(d+16);let slot=((name>>3)^(name>>12))&511;let probes=0;
    while probes<512 {
        let entry=table+slot*16;let key=load64(entry);
        if key==name {return ffi_call(load64(entry+8),a,b,c,e,f,g);}
        if !key {
            let function=gui_gl_cached_proc(load64(d),name);if !function {return 0;}
            store64(entry,name);store64(entry+8,function);return ffi_call(function,a,b,c,e,f,g);
        }
        slot=(slot+1)&511;probes=probes+1;
    }
    return gui__fail("Renderer dispatch cache is full");
}
fn render_track(d,kind,id) {
    if !id {return 0;}
    let r=alloc(24);store64(r,load64(d+32));store64(r+8,kind);store64(r+16,id);store64(d+32,r);return id;
}
fn render_program(d,vertex,fragment) {
    if !render_live(d) {return 0;}
    return render_track(d,1,gui_gl_program(load64(d),vertex,fragment));
}
fn render_buffer(d) {
    if !render_live(d) {return 0;}
    let p=load64(d+24);gui__put32(p,0);render_gl(d,"glGenBuffers",1,p,0,0,0,0);
    return render_track(d,2,gui__u32(p));
}
fn render_array(d) {
    if !render_live(d) {return 0;}
    let p=load64(d+24);gui__put32(p,0);render_gl(d,"glGenVertexArrays",1,p,0,0,0,0);
    return render_track(d,3,gui__u32(p));
}
fn render_delete(d,kind,id) {
    if !id || !render_live(d) {return 0;}
    let r=load64(d+32);let found=0;
    while r {if load64(r+8)==kind && load64(r+16)==id {store64(r+16,0);found=1;}r=load64(r);}
    if !found {return gui__fail("Renderer does not own this resource");}
    let p=load64(d+24);gui__put32(p,id);
    if kind==1 {render_gl(d,"glDeleteProgram",id,0,0,0,0,0);}
    if kind==2 {render_gl(d,"glDeleteBuffers",1,p,0,0,0,0);}
    if kind==3 {render_gl(d,"glDeleteVertexArrays",1,p,0,0,0,0);}
    if kind==4 {render_gl(d,"glDeleteTextures",1,p,0,0,0,0);}
    if kind==5 {render_gl(d,"glDeleteFramebuffers",1,p,0,0,0,0);}
    return 1;
}
fn render_upload(d,buffer,target,bytes,data,usage) {
    if !buffer || bytes<0 || bytes>134217728 || !render_live(d) {return gui__fail("Invalid renderer upload");}
    render_gl(d,"glBindBuffer",target,buffer,0,0,0,0);
    render_gl(d,"glBufferData",target,bytes,data,usage,0,0);return 1;
}
// Attribute records: location, components, GL type, normalized, byte offset,
// integer input. Both floating and integer custom shader inputs are supported.
fn render_layout(d,vao,buffer,stride,attributes,count) {
    if !vao || !buffer || stride<1 || stride>4096 || count<1 || count>16 || !attributes || !render_live(d) {return gui__fail("Invalid renderer vertex layout");}
    let i=0;while i<count {
        let a=attributes+i*48;let type=load64(a+16);let bytes=0;
        if type==0x1406 || type==0x1404 || type==0x1405 {bytes=4;}
        if type==0x1402 || type==0x1403 {bytes=2;}
        if type==0x1400 || type==0x1401 {bytes=1;}
        if load64(a)<0 || load64(a)>15 || load64(a+8)<1 || load64(a+8)>4 || !bytes || load64(a+32)<0 || load64(a+32)+load64(a+8)*bytes>stride || (load64(a+40) && type==0x1406) {return gui__fail("Invalid renderer vertex attribute");}
        let j=0;while j<i {if load64(attributes+j*48)==load64(a) {return gui__fail("Duplicate renderer vertex attribute");}j=j+1;}i=i+1;
    }
    render_gl(d,"glBindVertexArray",vao,0,0,0,0,0);render_gl(d,"glBindBuffer",0x8892,buffer,0,0,0,0);
    i=0;while i<count {
        let a=attributes+i*48;render_gl(d,"glEnableVertexAttribArray",load64(a),0,0,0,0,0);
        if load64(a+40) {render_gl(d,"glVertexAttribIPointer",load64(a),load64(a+8),load64(a+16),stride,load64(a+32),0);}
        else {render_gl(d,"glVertexAttribPointer",load64(a),load64(a+8),load64(a+16),load64(a+24),stride,load64(a+32));}i=i+1;
    }return 1;
}
fn render_draw(d,vao,mode,first,count) {
    if !vao || first<0 || count<0 || !render_live(d) {return gui__fail("Invalid renderer draw");}
    render_gl(d,"glBindVertexArray",vao,0,0,0,0,0);render_gl(d,"glDrawArrays",mode,first,count,0,0,0);return 1;
}
fn render_close(d) {
    if !d || load64(d+8) {return 1;}
    // An externally closed context already released its GL objects. Never use
    // cached entry points against a later window generation.
    if render_live(d) {
        let r=load64(d+32);while r {if load64(r+16) {render_delete(d,load64(r+8),load64(r+16));}r=load64(r);}
        if load64(d+40) {gui_close(load64(d));}
    }
    let r=load64(d+32);while r {let next=load64(r);syscall(11,r,24,0,0,0,0);r=next;}
    syscall(11,load64(d+16),8192,0,0,0,0);syscall(11,load64(d+24),16,0,0,0,0);
    store64(d+8,1);store64(d+32,0);return 1;
}
