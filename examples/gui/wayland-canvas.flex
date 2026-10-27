import "../../libs/gui/renderer/gl.flex";
import "../../scripts/lib/json.flex";
fn main(argc,argv){
    h_environment(argc,argv);let client=wl_client_open(0,"Flexscript native GPU canvas",800,600);h_assert(client,wl_error);let renderer=gr_open(client);h_assert(renderer,gr_error);
    gr_clear(renderer,0xff10151a);gr_fill(renderer,40,40,300,160,0xffc5e3ae);gr_clip(renderer,70,80,200,100);gr_fill(renderer,20,20,400,300,0x806030c0);gr_unclip(renderer);
    let layer=gr_texture(renderer,64,64,0,1,2);h_assert(layer,gr_error);gr_target(renderer,layer);gr_clear(renderer,0);gr_fill(renderer,0,0,64,16,0xffffffff);gr_fill(renderer,0,48,64,16,0xffff0000);gr_target(renderer,0);gr_texture_draw(renderer,layer,400,40,64,64);
    let image=alloc(16);bytes_store32(image,0xff0000ff);bytes_store32(image+4,0xff00ff00);bytes_store32(image+8,0xffff0000);bytes_store32(image+12,0xffffffff);let texture=gr_texture(renderer,2,2,image,0,1);h_assert(texture,gr_error);gr_texture_draw(renderer,texture,500,40,64,64);
    let width=load64(client+72);let height=load64(client+80);let pixels=alloc(width*height*4);h_assert(gr_read(renderer,pixels,width*4,width*height*4),gr_error);
    let at=pixels+(50*width+50)*4;h_assert(load8(at)==197 && load8(at+1)==227 && load8(at+2)==174,"Native GL rectangle pixels differ");
    at=pixels+(90*width+90)*4;h_assert(load8(at)>=146 && load8(at)<=147 && load8(at+1)>=137 && load8(at+1)<=138 && load8(at+2)>=182 && load8(at+2)<=184,"Native GL alpha pixels differ");
    at=pixels+(45*width+405)*4;h_assert(load8(at)==255 && load8(at+1)==255 && load8(at+2)==255,"Render-target texture top is flipped");
    at=pixels+(98*width+405)*4;h_assert(load8(at)==255 && !load8(at+1) && !load8(at+2),"Render-target texture bottom is flipped");
    at=pixels+(42*width+502)*4;h_assert(load8(at)==255 && !load8(at+1) && !load8(at+2),"Uploaded RGBA texture orientation differs");
    if argc>1{h_save_bytes(load64(argv+8),pixels,width*height*4,420);}let result=j_object();let device=gr_gl(renderer,46,0x1f01,0,0,0,0,0);j_set(result,"renderer",j_string(h_slice(device,h_len(device))));j_set(result,"width",j_int(width));j_set(result,"height",j_int(height));j_set(result,"draw_calls",j_int(load64(renderer+240)));j_set(result,"gl_error",j_int(gr_gl(renderer,48,0,0,0,0,0,0)));h_assert(gr_present(renderer),gr_error);wl_client_wait(client,40);gr_close(renderer);wl_client_close(client);syscall(11,image,16,0,0,0,0);syscall(11,pixels,width*height*4,0,0,0,0);h_print(1,h_cat(j_dump(result),"\n"));return 0;
}
