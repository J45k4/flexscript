// Small resident-kernel experiment: HIP graphs avoid host launch overhead.
// Model throughput must still be measured with bench-llm.flex.
import "../libs/ml/llm/pup.flex";
fn bk_buffer(bytes,fill) {let p=device_buffer(bytes);lm_check(device_status);lm_check(hip_call("hipMemset",p,fill,bytes,0,0,0));return p;}
fn main(argc,argv) {
    h_environment(argc,argv);lm_select_backend("rdna");let context=device_context_device(0);lm_check(device_status);
    let image=b_option(argc,argv,"--image",0);h_assert(image,"provide --image");let kind=b_option(argc,argv,"--kernel","gemv-wide");
    let rows=lw_int(b_option(argc,argv,"--rows","8192"));let width=lw_int(b_option(argc,argv,"--width","2048"));let block=lw_int(b_option(argc,argv,"--block","256"));
    h_assert(rows>0 && rows<=1048576 && width>0 && width<=32768 && rows*width*2<=2147483647 && !(width&3) && block>=32 && block<=1024 && !(block&31),"invalid kernel dimensions");
    let w=bk_buffer(rows*width*2,60);let u=bk_buffer(rows*width*2,56);let x=bk_buffer(width*4,0);let y=bk_buffer(rows*16+width*16,0);
    let host=alloc(width*4);let i=0;while i<width {gpu_store_u32(host+i*4,1065353216);i=i+1;}lm_check(device_upload(x,host,width*4));
    let words=h_take(64);store64(words,w);store64(words+8,x);store64(words+16,y);store64(words+24,width);let threads=rows*32;let shared=0;let first=0;let second=0;
    if h_equal(kind,"mlp-pair") {store64(words+8,u);store64(words+16,x);store64(words+32,y);store64(words+40,y+rows*4);store64(words+48,y+rows*8);store64(words+56,y+rows*12);}
    else if h_equal(kind,"gemv-three") {first=rows;second=rows;threads=rows*96;store64(words,x);store64(words+8,w);store64(words+16,u);store64(words+24,w);store64(words+32,y);store64(words+40,y+rows*4);store64(words+48,y+rows*8);store64(words+56,width);}
    else if h_equal(kind,"rms-add") || h_equal(kind,"rms-wide") {threads=128;shared=32;store64(words,x);store64(words+8,w);store64(words+32,gpu_f32_div(1065353216,gpu_f32_from_i64(width)));store64(words+40,0x358637bd);
        if h_equal(kind,"rms-add") {store64(words+8,x);store64(words+48,w);store64(words+56,y+width*4);}}
    else {h_assert(h_equal(kind,"gemv-wide"),"unsupported benchmark kernel");}
    let module=device_module(h_read(image));lm_check(device_status);let function=device_function(module,"flex_kernel");lm_check(device_status);let stream=device_stream();lm_check(device_status);
    let values=h_take(24);store64(values,first);store64(values+8,second);store64(values+16,threads);let args=h_take(88);i=0;while i<3 {store64(args+i*8,values+i*8);i=i+1;}i=0;while i<8 {store64(args+24+i*8,words+i*8);i=i+1;}
    let config=device_config((threads+block-1)/block,1,1,block,1,1,shared,stream);lm_check(device_status);
    lm_check(device_capture_begin(stream));i=0;while i<100 {lm_check(device_dispatch(function,config,args));i=i+1;}let graph=device_capture_end(stream);lm_check(device_status);let instance=device_graph_instance(graph);lm_check(device_status);
    lm_check(device_graph_launch(instance,stream));lm_check(device_stream_wait(stream));let start=device_event();let end=device_event();let samples=j_array();i=0;
    while i<5 {lm_check(device_event_record(start,stream));lm_check(device_graph_launch(instance,stream));lm_check(device_event_record(end,stream));lm_check(device_stream_wait(stream));let ns=f64_to_i64_trunc(f64_mul(gpu_f32_unpack(device_event_elapsed_f32(start,end)),f64_from_i64(10000)));lm_check(device_status);j_push(samples,j_int(ns));i=i+1;}
    let report=j_object();j_set(report,"kernel",j_string(kind));j_set(report,"image",j_string(image));j_set(report,"rows",j_int(rows));j_set(report,"width",j_int(width));j_set(report,"block",j_int(block));j_set(report,"kernel_ns",samples);h_print(1,h_cat(j_dump(report),"\n"));
    lm_check(device_event_close(start));lm_check(device_event_close(end));lm_check(device_graph_instance_close(instance));lm_check(device_graph_close(graph));lm_check(device_stream_close(stream));lm_check(device_unload(module));lm_check(device_free(w));lm_check(device_free(u));lm_check(device_free(x));lm_check(device_free(y));lm_check(device_close(context));return 0;
}
