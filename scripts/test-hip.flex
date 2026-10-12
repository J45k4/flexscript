// Device regression for the AMD host ABI, launch words and graph replay.
import "lib/harness.flex";
import "lib/build.flex";
import "../lib/hip.flex";
import "../lib/gpu.flex";
import "../examples/gpu/vector.flex";
fn th_check(status) {h_assert(!status,hip_error());return 0;}
fn th_value(i) {
    if i==0 {return 0;}if i==1 {return -1;}if i==2 {return 0x8000000000000000;}if i==3 {return 0x7fffffffffffffff;}
    return i*0x9e3779b97f4a7c15;
}
fn th_vector(target) {
    let count=4099;let bytes=count*8+16;let host=alloc(bytes);let input=hip_buffer(bytes);th_check(hip_status);let output=hip_buffer(bytes);th_check(hip_status);
    let i=0;while i<count {store64(host+1+i*8,th_value(i));i=i+1;}th_check(hip_upload(input,host,bytes));
    store64(host+1+count*8,0x123456789abcdef0);th_check(hip_upload(output,host,bytes));
    let image=h_join(t_work,"vector");h_ok(h_args(t_compiler,"--target",target,"examples/gpu/vector.flex","-o",image));
    let module=hip_module(h_read(image));th_check(hip_status);th_check(hip_launch(module,input+1,output+1,count));th_check(hip_download(host,output,bytes));
    i=0;while i<count {t_assert(load64(host+1+i*8)==transform(th_value(i)),"HIP wrapping arithmetic, signed shift or unaligned word mismatch");i=i+1;}
    t_assert(load64(host+1+count*8)==0x123456789abcdef0,"HIP incomplete block wrote beyond count");
    th_check(hip_unload(module));th_check(hip_free(input));th_check(hip_free(output));syscall(11,host,bytes,0,0,0,0);return 0;
}
fn th_collectives(target,host,input,output) {
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(index,input,output,count){let sum=gpu_warp_sum_f32(gpu_load_u32(input+index*4));let warp=index>>5;if !gpu_lane(){gpu_shared_store64(warp*8,sum);}gpu_shared_barrier();gpu_store_u32(output+index*8,sum);gpu_store_u32(output+index*8+4,gpu_shared_load64(((warp+1)&3)*8));return 0;}fn main(){return 78;}"));
    let i=0;while i<128 {let warp=i>>5;let lane=i&31;let bits=1065353216;
        // Cancellation distinguishes a broadcast tree from a rotating sum:
        // every lane must see 16, including lanes next to a huge operand.
        if warp==1 {let group=lane>>2;if !(group&3) {bits=0x60ad78ec;}else if (group&3)==1 {bits=0xe0ad78ec;}}
        else if warp==2 {bits=gpu_f32_from_i64(lane-16);}else if warp==3 {bits=0;}
        gpu_store_u32(host+i*4,bits);i=i+1;
    }
    th_check(hip_upload(input,host,512));let image=h_join(t_work,"collectives");h_ok(h_args(t_compiler,"--target",target,t_fixture,"-o",image));
    let module=hip_module(h_read(image));th_check(hip_status);let words=h_take(64);let config=hip_config(1,1,1,128,1,1,32,0);th_check(hip_status);
    th_check(hip_launch_words(module,input,output,128,config,words));th_check(hip_synchronize());th_check(hip_download(host,output,1024));
    let expected=h_take(32);store64(expected,0x42000000);store64(expected+8,0x41800000);store64(expected+16,0xc1800000);
    i=0;while i<128 {let warp=i>>5;t_assert(gpu_load_u32(host+i*8)==load64(expected+warp*8),"HIP warp sum did not broadcast the same finite result");t_assert(gpu_load_u32(host+i*8+4)==load64(expected+((warp+1)&3)*8),"HIP shared-only barrier did not publish another wave's result");i=i+1;}
    th_check(hip_unload(module));return 0;
}
fn th_direct_flow() {
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(index,input,output,count){let v=load64(input+index*8);let n=index&7;let a=0;while a<n{a=a+1;}let b=0;while b<(index&3){b=b+1;}let q=v/7;let r=v%-31;if (index&1) && a>2 {q=q+a;}else{q=q-b;}store64(output+index*16,q);store64(output+index*16+8,r);return 0;}fn main(){return 78;}"));
    let count=257;let host=alloc(count*16+16);let input=hip_buffer(count*8);th_check(hip_status);let output=hip_buffer(count*16+16);th_check(hip_status);
    let i=0;while i<count {store64(host+i*8,th_value(i));i=i+1;}th_check(hip_upload(input,host,count*8));
    store64(host+count*16,0x123456789abcdef0);store64(host+count*16+8,0xfedcba9876543210);th_check(hip_upload(output,host,count*16+16));
    let image=h_join(t_work,"direct-flow");h_ok(h_args(t_compiler,"--target","rdna-direct-gfx1201",t_fixture,"-o",image));let module=hip_module(h_read(image));th_check(hip_status);
    th_check(hip_launch(module,input,output,count));th_check(hip_download(host,output,count*16+16));i=0;
    while i<count {let v=th_value(i);let q=v/7;if (i&1) && (i&7)>2 {q=q+(i&7);}else {q=q-(i&3);}
        t_assert(load64(host+i*16)==q,h_cat3("direct RDNA flow/division mismatch at ",h_int(i),h_cat3(": ",h_int(load64(host+i*16)),h_cat(" expected ",h_int(q)))));
        t_assert(load64(host+i*16+8)==v%-31,h_cat3("direct RDNA signed remainder mismatch at ",h_int(i),h_cat3(": ",h_int(load64(host+i*16+8)),h_cat(" expected ",h_int(v%-31)))));i=i+1;}
    t_assert(load64(host+count*16)==0x123456789abcdef0 && load64(host+count*16+8)==0xfedcba9876543210,"direct RDNA flow wrote beyond count");
    th_check(hip_unload(module));th_check(hip_free(input));th_check(hip_free(output));return 0;
}
fn suite(compiler) {
    t_init(compiler);let context=hip_context_device(0);th_check(hip_status);
    h_print(1,h_cat3("HIP device: ",hip_device_name(0),"\n"));
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(index,input,output,count){let v=load64(input+index*8);store64(output+index*8,v*3+gpu_launch_word(0)+gpu_block_x());return 0;}fn main(){return 78;}"));
    let host=hip_host_buffer(4096);th_check(hip_status);let input=hip_buffer(4096);th_check(hip_status);let output=hip_buffer(4096);th_check(hip_status);
    let i=0;while i<512 {store64(host+i*8,i);i=i+1;}th_check(hip_upload(input,host,4096));
    let targets=h_args("hip","rdna-gfx1201","rdna-direct-gfx1201",0,0,0);let target=0;
    while target<3 {
        let image=h_join(t_work,"kernel");h_ok(h_args(t_compiler,"--target",h_at(targets,target),t_fixture,"-o",image));
        let module=hip_module(h_read(image));th_check(hip_status);let function=hip_function(module,"flex_kernel");th_check(hip_status);
        let stream=hip_stream();th_check(hip_status);let config=hip_config(4,1,1,128,1,1,0,stream);th_check(hip_status);
        let values=h_take(88);store64(values,input);store64(values+8,output);store64(values+16,512);store64(values+24,7);
        let args=h_take(88);i=0;while i<11 {store64(args+i*8,values+i*8);i=i+1;}
        th_check(hip_dispatch(function,config,args));th_check(hip_stream_wait(stream));th_check(hip_download(host,output,4096));
        i=0;while i<512 {t_assert(load64(host+i*8)==i*3+7+i/128,"HIP launch argument or geometry mismatch");i=i+1;}
        th_check(hip_capture_begin(stream));th_check(hip_dispatch(function,config,args));let graph=hip_capture_end(stream);th_check(hip_status);
        let instance=hip_graph_instance(graph);th_check(hip_status);th_check(hip_graph_close(graph));th_check(hip_graph_upload(instance,stream));
        th_check(hip_graph_launch(instance,stream));th_check(hip_stream_wait(stream));th_check(hip_download(host,output,4096));
        i=0;while i<512 {t_assert(load64(host+i*8)==i*3+7+i/128,"HIP graph replay changed launch arguments");i=i+1;}
        th_check(hip_graph_instance_close(instance));th_check(hip_stream_close(stream));th_check(hip_unload(module));target=target+1;
    }
    th_vector("hip");th_vector("rdna-gfx1201");th_vector("rdna-direct-gfx1201");
    th_collectives("hip",host,input,output);th_collectives("rdna-gfx1201",host,input,output);th_collectives("rdna-direct-gfx1201",host,input,output);
    th_direct_flow();
    th_check(hip_free(input));th_check(hip_free(output));th_check(hip_host_free(host));th_check(hip_close(context));return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
