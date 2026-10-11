// Device regression for the AMD host ABI, launch words and graph replay.
import "lib/harness.flex";
import "lib/build.flex";
import "../lib/hip.flex";
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
fn suite(compiler) {
    t_init(compiler);let context=hip_context_device(0);th_check(hip_status);
    h_print(1,h_cat3("HIP device: ",hip_device_name(0),"\n"));
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(index,input,output,count){let v=load64(input+index*8);store64(output+index*8,v*3+gpu_launch_word(0)+gpu_block_x());return 0;}fn main(){return 78;}"));
    let host=hip_host_buffer(4096);th_check(hip_status);let input=hip_buffer(4096);th_check(hip_status);let output=hip_buffer(4096);th_check(hip_status);
    let i=0;while i<512 {store64(host+i*8,i);i=i+1;}th_check(hip_upload(input,host,4096));
    let targets=h_args("hip","rdna-gfx1201",0,0,0,0);let target=0;
    while target<2 {
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
    th_vector("hip");th_vector("rdna-gfx1201");
    th_check(hip_free(input));th_check(hip_free(output));th_check(hip_host_free(host));th_check(hip_close(context));return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
