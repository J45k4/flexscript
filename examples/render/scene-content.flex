// Standalone consumer: no Setaworld imports or assets. Shader source is supplied
// by the app; the renderer owns its GPU resources, bindings and draw passes.
import "../../libs/render.flex";
import "../../scripts/lib/build.flex";
global demo_device=0;global demo_material=0;global demo_mesh=0;
global demo_shadow=0;global demo_camera=0;global demo_light=0;
global demo_models=0;global demo_tints=0;global demo_eye=0;global demo_target=0;global demo_up=0;
fn demo_choose(c,a,b) {if c {return a;}return b;}
fn demo_require(ok) {if !ok {h_die(h_cat("Render demo: ",gui_error));}return 0;}
fn demo_vector(x,y,z) {let p=alloc(24);store64(p,x);store64(p+8,y);store64(p+16,z);return p;}
fn demo_model(p,x,y,z,sx,sy,sz) {
    render_identity(p);render_float(p,sx,1000);render_float(p+20,sy,1000);render_float(p+40,sz,1000);
    render_float(p+48,x,1000);render_float(p+52,y,1000);render_float(p+56,z,1000);return p;
}
fn demo_init(directory,flags) {
    demo_device=render_open("Flexscript Shared Renderer - custom SetaScript shaders",960,640,flags|GUI_RESIZABLE|GUI_HIGH_DPI);demo_require(demo_device);
    gui_gl_swap_interval(load64(demo_device),1);
    demo_material=render_material(demo_device,h_read(h_join(directory,"custom-vertex.glsl")),h_read(h_join(directory,"custom-fragment.glsl")));demo_require(demo_material);
    demo_require(render_depth_variant(demo_material,h_read(h_join(directory,"depth-vertex.glsl")),h_read(h_join(directory,"depth-fragment.glsl"))));
    let attributes=gui__zero(alloc(96),96);store64(attributes+8,3);store64(attributes+16,0x1406);
    store64(attributes+48,1);store64(attributes+56,3);store64(attributes+64,0x1406);store64(attributes+80,12);
    demo_mesh=render_mesh(demo_device,24,attributes,2);demo_require(demo_mesh);
    let data=alloc(36*24);let face=0;
    while face<6 {
        let axis=face/2;let sign=1;if face%2==1 {sign=-1;}
        let i=0;while i<6 {
            let corner=i;if i==3 {corner=0;}if i==4 {corner=2;}if i==5 {corner=3;}
            let u=-500;if corner==1 || corner==2 {u=500;}let v=-500;if corner>=2 {v=500;}
            let p=data+(face*6+i)*24;let k=0;while k<3 {render_float(p+k*4,0,1);render_float(p+12+k*4,demo_choose(k==axis,sign,0),1);k=k+1;}
            render_float(p+axis*4,sign*500,1000);render_float(p+((axis+1)%3)*4,u*sign,1000);render_float(p+((axis+2)%3)*4,v,1000);i=i+1;
        }face=face+1;
    }
    demo_require(render_mesh_upload(demo_mesh,data,36,0x88e4));syscall(11,data,36*24,0,0,0,0);
    demo_shadow=render_depth_target(demo_device,1024,1024);demo_require(demo_shadow);
    demo_camera=alloc(64);demo_light=alloc(64);demo_models=alloc(256);demo_tints=alloc(64);
    demo_model(demo_models,0,-150,0,8000,300,8000);
    demo_model(demo_models+64,0,600,0,1200,1200,1200);
    demo_model(demo_models+128,1600,350,1000,700,700,700);
    demo_model(demo_models+192,-1600,900,-600,700,1800,700);
    let i=0;while i<4 {let p=demo_tints+i*16;render_float(p,demo_choose(i==0,35,demo_choose(i==1,25,90)),100);render_float(p+4,demo_choose(i==0,45,demo_choose(i==1,75,45)),100);render_float(p+8,demo_choose(i==0,50,demo_choose(i==1,90,25)),100);render_float(p+12,1,1);i=i+1;}
    demo_eye=demo_vector(5500,4000,6500);demo_target=demo_vector(0,350,0);demo_up=demo_vector(0,1000000,0);
    let light_eye=demo_vector(-3000,6000,4000);let light_target=demo_vector(0,0,0);
    demo_require(render_camera(demo_light,light_eye,light_target,demo_up,1024,1024,1732051,100,20000));
    h_print(1,"OpenGL device: ");h_print(1,render_gl(demo_device,"glGetString",0x1f01,0,0,0,0,0));h_print(1,"\n");
    h_print(1,"Shared renderer ready: custom SetaScript material, four meshes, depth shadows.\n");return 0;
}
fn demo_frame(shadows) {
    let w=load64(demo_device);let width=gui_pixel_width(w);let height=gui_pixel_height(w);if width<1 || height<1 {return 0;}
    demo_require(render_camera(demo_camera,demo_eye,demo_target,demo_up,width,height,1732051,100,30000));
    demo_require(render_begin(demo_device,demo_shadow,width,height));
    if shadows {
        demo_require(render_block(demo_material,2,"sw_block0",0,demo_light,64));
        let i=0;while i<4 {demo_require(render_block(demo_material,2,"sw_block1",1,demo_models+i*64,64));demo_require(render_mesh_draw(demo_mesh,demo_material,2,0,36));i=i+1;}
    }
    demo_require(render_begin(demo_device,0,width,height));
    demo_require(render_block(demo_material,0,"sw_block0",0,demo_camera,64));demo_require(render_block(demo_material,0,"sw_block2",2,demo_light,64));
    demo_require(render_texture(demo_material,0,"sw_r4003",3,0x0de1,load64(demo_shadow+8)));
    let i=0;while i<4 {
        demo_require(render_block(demo_material,0,"sw_block1",1,demo_models+i*64,64));demo_require(render_block(demo_material,0,"sw_block5",5,demo_tints+i*16,16));
        demo_require(render_mesh_draw(demo_mesh,demo_material,0,0,36));i=i+1;
    }
    demo_require(!render_gl(demo_device,"glGetError",0,0,0,0,0,0));return 1;
}
fn demo_capture(path) {
    let w=gui_pixel_width(load64(demo_device));let h=gui_pixel_height(load64(demo_device));let data=alloc(w*h*3);let row=alloc(w*3);
    render_gl(demo_device,"glPixelStorei",0x0d05,1,0,0,0,0);
    // ReadPixels has seven arguments, including the destination buffer.
    let args=gui__zero(alloc(88),88);store64(args+16,w);store64(args+24,h);store64(args+32,0x1907);store64(args+40,0x1401);store64(args+48,data);
    ffi_call_words(gui_gl_cached_proc(load64(demo_device),"glReadPixels"),args);
    let y=0;while y<h/2 {h_copy(row,data+y*w*3,w*3);h_copy(data+y*w*3,data+(h-y-1)*w*3,w*3);h_copy(data+(h-y-1)*w*3,row,w*3);y=y+1;}
    let header=h_cat("P6\n",h_cat(h_int(w),h_cat(" ",h_cat(h_int(h),"\n255\n"))));let fd=syscall(2,path,577,420,0,0,0);h_assert(fd>=0,"Capture file creation");h_assert(h_write(fd,header,h_len(header))==h_len(header) && h_write(fd,data,w*h*3)==w*h*3,"Capture write");h_close(fd);
    syscall(11,data,w*h*3,0,0,0,0);syscall(11,row,w*3,0,0,0,0);syscall(11,args,88,0,0,0,0);return 0;
}
