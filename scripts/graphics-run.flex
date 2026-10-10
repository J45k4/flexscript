import "lib/build.flex";
import "../lib/graphics.flex";
fn main(argc,argv) {
    h_environment(argc,argv);
    if !gfx_open(0,64,64) {h_print(2,h_cat3("Graphics: ",gfx_error,"\n"));gfx_close();return 77;}
    let renderer=gfx_renderer();h_print(1,h_cat3("OpenGL renderer: ",renderer,"\n"));
    let program=gfx_program(h_read("examples/gpu/shaders/triangle.vert"),h_read("examples/gpu/shaders/triangle.frag"));
    if !program {h_print(2,gfx_error);gfx_close();return 1;}
    let paint=gfx_texture(1,1);gfx_texture_clear(paint,0xff20c060);gfx_call("glBindTextureUnit",0,paint,0,0,0,0);
    let target=gfx_texture(64,64);gfx_texture_clear(target,0xff181820);
    if !gfx_draw(program,target,64,64,3) {h_print(2,gfx_error);gfx_close();return 1;}
    let pixels=alloc(4096*4);h_assert(!gfx_read(target,pixels,4096*4),"graphics readback");
    let i=0;let hits=0;while i<4096 {
        let x=i%64;let y=i/64;let xx=2*x-63;let yy=2*y-63;
        let hit=yy> -32 && yy<32 && 2*xx+yy<32 && -2*xx+yy<32;
        let expected=0xff181820;if hit {expected=0xff20c060;hits=hits+1;}
        if gfx_get_u32(pixels+i*4)!=expected {h_print(2,h_cat3("Raster mismatch at ",h_int(i),"\n"));gfx_close();return 1;}i=i+1;
    }
    h_assert(hits==512,"triangle raster coverage");
    let ids=alloc(8);gfx_u32(ids,paint);gfx_u32(ids+4,target);gfx_call("glDeleteTextures",2,ids,0,0,0,0);gfx_call("glDeleteProgram",program,0,0,0,0,0);
    gfx_close();h_print(1,"Textured raster parity: 4096 pixels passed (512 covered)\n");return 0;
}
