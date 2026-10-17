import "../../examples/render/scene-content.flex";
global rt_checks=0;
fn rt(ok,message) {h_assert(ok,message);rt_checks=rt_checks+1;return 0;}
fn rt_read() {
    let w=gui_pixel_width(load64(demo_device));let h=gui_pixel_height(load64(demo_device));let pixels=alloc(w*h*3);
    let args=gui__zero(alloc(88),88);store64(args+16,w);store64(args+24,h);store64(args+32,0x1907);store64(args+40,0x1401);store64(args+48,pixels);
    render_gl(demo_device,"glPixelStorei",0x0d05,1,0,0,0,0);ffi_call_words(gui_gl_cached_proc(load64(demo_device),"glReadPixels"),args);syscall(11,args,88,0,0,0,0);return pixels;
}
fn rt_device(directory) {
    demo_init(directory,GUI_HIDDEN);demo_frame(0);let lit=rt_read();demo_frame(1);let shadow=rt_read();
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
    let gpu=0;let i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {gpu=1;}i=i+1;}
    if gpu {rt_device(b_option(argc,argv,"--shaders","build/render"));}
    h_print(1,h_cat(h_int(rt_checks)," renderer checks passed\n"));return 0;
}
