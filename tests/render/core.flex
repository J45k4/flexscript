import "../../examples/render/scene-content.flex";
global rt_checks=0;
fn rt(ok,message) {h_assert(ok,message);rt_checks=rt_checks+1;return 0;}
fn rt_read() {
    let w=gui_pixel_width(load64(demo_device));let h=gui_pixel_height(load64(demo_device));let pixels=alloc(w*h*3);
    rt(render_read_rgb8(demo_device,0,0,w,h,pixels,w*h*3),"Framebuffer RGB readback");
    return pixels;
}
fn rt_rgb_texture(d) {
    let pixels = alloc(18);
    let output = alloc(18);
    let i = 0;
    while i < 18 { store8(pixels + i, 17 + i * 11); i = i + 1; }
    rt(!render_texture_rgb8(d,3,2,pixels,17,0),"Short RGB texture buffer rejected");
    rt(!render_read_rgb8(d,0,0,3,2,output,17),"Short RGB readback buffer rejected");

    let buffer = render_buffer(d);
    render_gl(d,"glBindBuffer",0x88ec,buffer,0,0,0,0);
    render_gl(d,"glPixelStorei",0x0cf2,8,0,0,0,0);
    let texture = render_texture_rgb8(d,3,2,pixels,18,1);
    rt(texture,"RGB texture upload with mipmaps");
    let word = alloc(8);
    render_gl(d,"glGetIntegerv",0x88ef,word,0,0,0,0);
    rt(gui__u32(word)==buffer,"Unpack buffer binding restored");
    render_gl(d,"glGetIntegerv",0x0cf2,word,0,0,0,0);
    rt(gui__u32(word)==8,"Unpack row length restored");
    render_gl(d,"glBindBuffer",0x88ec,0,0,0,0,0);
    render_gl(d,"glPixelStorei",0x0cf2,0,0,0,0,0);

    render_gl(d,"glGenFramebuffers",1,word,0,0,0,0);
    let framebuffer = render_track(d,5,gui__u32(word));
    render_gl(d,"glBindFramebuffer",0x8d40,framebuffer,0,0,0,0);
    render_gl(d,"glFramebufferTexture2D",0x8d40,0x8ce0,0x0de1,texture,0,0);
    rt(render_gl(d,"glCheckFramebufferStatus",0x8d40,0,0,0,0,0)==0x8cd5,"RGB texture is framebuffer-complete");
    render_gl(d,"glBindBuffer",0x88eb,buffer,0,0,0,0);
    render_gl(d,"glPixelStorei",0x0d05,8,0,0,0,0);
    rt(render_read_rgb8(d,0,0,3,2,output,18),"Read RGB with independent pack state");
    rt(h_equal(h_sha_bytes(pixels,18),h_sha_bytes(output,18)),"Odd-width RGB rows round-trip exactly");
    render_gl(d,"glGetIntegerv",0x88ed,word,0,0,0,0);
    rt(gui__u32(word)==buffer,"Pack buffer binding restored");
    render_gl(d,"glGetIntegerv",0x0d05,word,0,0,0,0);
    rt(gui__u32(word)==8,"Pack alignment restored");
    render_gl(d,"glBindBuffer",0x88eb,0,0,0,0,0);
    render_gl(d,"glPixelStorei",0x0d05,4,0,0,0,0);
    render_gl(d,"glBindFramebuffer",0x8d40,0,0,0,0,0);
    render_delete(d,5,framebuffer);
    render_delete(d,4,texture);
    render_delete(d,2,buffer);
    syscall(11,pixels,18,0,0,0,0);
    syscall(11,output,18,0,0,0,0);
    syscall(11,word,8,0,0,0,0);
    return 0;
}
fn rt_device(directory) {
    demo_init(directory,GUI_HIDDEN);rt_rgb_texture(demo_device);demo_frame(0);let lit=rt_read();demo_frame(1);let shadow=rt_read();
    let n=gui_pixel_width(load64(demo_device))*gui_pixel_height(load64(demo_device));let differences=0;let darker=0;let colored=0;let i=0;
    while i<n {
        let a=lit+i*3;let b=shadow+i*3;if load8(b)+load8(b+1)+load8(b+2)>30 {colored=colored+1;}
        if load8(a)!=load8(b) || load8(a+1)!=load8(b+1) || load8(a+2)!=load8(b+2) {differences=differences+1;if load8(a)+load8(a+1)+load8(a+2)>load8(b)+load8(b+1)+load8(b+2) {darker=darker+1;}}i=i+1;
    }
    rt(colored>50000,"Custom material draws visible geometry");rt(differences>200 && darker*10>differences*9,"Depth pass produces visible physical shadows");
    let old=load64(demo_eye);store64(demo_eye,old+2000);demo_frame(1);let moved=rt_read();
    rt(!h_equal(h_sha_bytes(shadow,n*3),h_sha_bytes(moved,n*3)),"Moving camera changes rendered pixels");store64(demo_eye,old);
    rt(!render_mesh_draw(demo_mesh,demo_material,0,35,2),"Out-of-bounds draw rejected");
    rt(!render_mesh_upload(demo_mesh,0,36,0x88e4),"Null vertex upload rejected");
    rt(!render_depth_target(demo_device,0,1),"Invalid render target rejected");
    rt(!render_block(demo_material,0,"sw_block0",0,demo_camera,16),"Undersized uniform block rejected");
    let invalid_layout=gui__zero(alloc(48),48);store64(invalid_layout+8,3);store64(invalid_layout+16,0x1406);store64(invalid_layout+32,20);
    rt(!render_layout(demo_device,load64(demo_mesh+8),load64(demo_mesh+16),24,invalid_layout,1),"Attribute extending past its vertex rejected");
    let bad=render_material(demo_device,"#version 330 core\nthis is not GLSL", "#version 330 core\nout vec4 c;void main(){c=vec4(1);}");rt(!bad && h_len(gui_error)>0,"Shader diagnostic returned to caller");
    demo_frame(1);rt(!render_gl(demo_device,"glGetError",0,0,0,0,0,0),"Shader failure leaves renderer usable");
    let second=render_open("Renderer lifecycle test",64,64,GUI_HIDDEN);rt(second,"Second independent renderer");
    rt(!render_mesh_draw(demo_mesh,render_material(second,"#version 330 core\nvoid main(){gl_Position=vec4(0);}","#version 330 core\nout vec4 c;void main(){c=vec4(1);}"),0,0,3),"Cross-device material rejected");
    render_close(second);demo_frame(1);rt(!render_gl(demo_device,"glGetError",0,0,0,0,0,0),"Dispatch cache restores the original context");
    render_mesh_close(demo_mesh);render_mesh_close(demo_mesh);rt(!render_mesh_draw(demo_mesh,demo_material,0,0,3),"Closed mesh rejected");
    render_material_close(demo_material);render_target_close(demo_shadow);render_close(demo_device);render_close(demo_device);rt(!render_live(demo_device),"Closed device rejected");
    let external=gui_gl_open("External renderer context",64,64,GUI_HIDDEN,4,5,0);let attached=render_attach(external);rt(attached,"Attach caller-owned context");
    render_close(attached);rt(gui_gl_current(external),"Renderer leaves caller-owned window alive");gui_close(external);
    external=gui_gl_open("Stale renderer context",64,64,GUI_HIDDEN,4,5,0);attached=render_attach(external);gui_close(external);
    let replacement=render_open("Replacement context",64,64,GUI_HIDDEN);rt(!render_live(attached),"Window generation prevents stale renderer reuse");render_close(attached);rt(render_live(replacement),"Closing stale renderer preserves replacement");render_close(replacement);
    syscall(11,lit,n*3,0,0,0,0);syscall(11,shadow,n*3,0,0,0,0);syscall(11,moved,n*3,0,0,0,0);gui_quit();return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);rt(render_f32(1,1)==1065353216 && render_f32(-1,1)==3212836864,"Signed float conversion");
    rt(render_f32(32000000000000,1000000000)==1190789120,"Wide-coordinate float conversion");rt(render_f32(16777217,1)==1266679809,"Original half-up rounding");
    let matrix=alloc(64);let eye=demo_vector(0,0,5000);let target=demo_vector(0,0,0);let up=demo_vector(0,1000000,0);
    rt(render_camera(matrix,eye,target,up,800,600,1000000,100,10000),"Camera matrix construction");
    rt(gui__u32(matrix+48)==0 && gui__u32(matrix+52)==0 && gui__u32(matrix+60)==render_f32(5,1),"Target projects to screen center with positive clip W");
    rt(!render_camera(matrix,eye,eye,up,800,600,1000000,100,10000),"Degenerate camera rejected");
    let basis=gui__zero(alloc(72),72);
    store64(basis,1000000);store64(basis+32,1000000);store64(basis+64,1000000);
    rt(render_orthographic_view(matrix,demo_vector(500,-1000,3000),basis,5000,2000,10000),"Orthographic transform");
    rt(gui__u32(matrix)==render_f32(1,5) && gui__u32(matrix+20)==render_f32(1,2) &&
       gui__u32(matrix+48)==render_f32(-1,10) && gui__u32(matrix+52)==render_f32(1,2),
       "Orthographic scale and translation");
    rt(!render_orthographic_view(matrix,eye,basis,0,2000,10000),"Invalid orthographic extent rejected");
    let packed=alloc(36*36);
    rt(render_packed_box(packed,0,0,0,0,2000,1000,1000,0xf1e2d3c4)==36,"Packed box emits twelve triangles");
    rt(gui__u32(packed)==render_f32(-1,1) && gui__u32(packed+4)==render_f32(1,2) &&
       gui__u32(packed+16)==render_f32(1,1) && gui__u32(packed+32)==0xf1e2d3c4,
       "Packed attributes match the documented layout");
    let gpu=0;let i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {gpu=1;}i=i+1;}
    if gpu {rt_device(b_option(argc,argv,"--shaders","build/render"));}
    h_print(1,h_cat(h_int(rt_checks)," renderer checks passed\n"));return 0;
}
