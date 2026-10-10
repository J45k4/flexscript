import "lib/build.flex";
import "../lib/vulkan.flex";
fn ray_check(status) {
    if status {h_print(2,h_cat3("Vulkan: ",vk_error,h_cat3(" (",h_int(status),")\n")));vk_close();syscall(231,1,0,0,0,0,0);}return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==2,"usage: ray-run ray-query.spv");
    if !vk_ray_open(0) {ray_check(vk_status);return 77;}
    h_print(1,h_cat3("Vulkan GPU: ",vk_device_name(),"\n"));ray_check(vk_status);
    let vertices=vk_buffer(36,0x80000|0x20000,1);ray_check(vk_status);let v=load64(vertices+16);
    vk_u32(v,0xbf800000);vk_u32(v+4,0xbf800000);vk_u32(v+8,0);
    vk_u32(v+12,0x3f800000);vk_u32(v+16,0xbf800000);vk_u32(v+20,0);
    vk_u32(v+24,0);vk_u32(v+28,0x3f800000);vk_u32(v+32,0);
    let blas=vk_acceleration(vk_triangle_geometry(vertices,12,3),1,1);ray_check(vk_status);
    let instances=vk_buffer(64,0x80000|0x20000,1);ray_check(vk_status);vk_instance_identity(load64(instances+16),blas);ray_check(vk_status);
    let tlas=vk_acceleration(vk_instance_geometry(instances),0,1);ray_check(vk_status);
    let output=vk_buffer(64*64*4,0x20,1);ray_check(vk_status);
    let code=h_read(load64(argv+8));let pipeline=vk_ray_pipeline(code,h_file_size);ray_check(vk_status);
    ray_check(vk_ray_dispatch(pipeline,tlas,output,8,8,1));
    let pixels=load64(output+16);let hits=0;let i=0;
    while i<4096 {
        let x=i%64;let y=i/64;
        // Coordinates are exact odd multiples of 1/32; no samples hit an edge.
        let xx=2*x-63;let yy=2*y-63;
        let hit=yy> -32 && yy<32 && 2*xx+yy<32 && -2*xx+yy<32;
        let expected=0xff181820;if hit {expected=0xff20c060;hits=hits+1;}
        if vk_get_u32(pixels+i*4)!=expected {h_print(2,h_cat3("Ray mismatch at ",h_int(i),"\n"));vk_close();return 1;}i=i+1;
    }
    h_assert(hits==512,"reference triangle coverage");
    let ppm=alloc(13+4096*3);h_copy(ppm,"P6\n64 64\n255\n",13);let at=13;i=63;
    while i>=0 {let x=0;while x<64 {let color=vk_get_u32(pixels+(i*64+x)*4);store8(ppm+at,color);store8(ppm+at+1,color>>8);store8(ppm+at+2,color>>16);at=at+3;x=x+1;}i=i-1;}
    h_save_bytes("build/ray-query.ppm",ppm,13+4096*3,420);
    vk_close();h_print(1,"Hardware ray-query parity: 4096 pixels passed (512 hits)\n");return 0;
}
