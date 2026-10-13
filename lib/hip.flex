// Linux HIP runtime adapter. Kernel arguments are pointer descriptors, matching
// the PTX/SASS launch ABI; code objects contain ordinary AMD HSA machine code.
import "ffi.flex";
import "ffi-words.flex";
import "hip-rtc.flex";
global hip_library=0;
global hip_status=0;
global hip_launch_symbol=0;
fn hip_call(name,a,b,c,d,e,f) {
    if !hip_library {hip_library=ffi_open("libamdhip64.so");}
    if !hip_library {hip_status=-10001;return hip_status;}
    let symbol=ffi_symbol(hip_library,name);if !symbol {hip_status=-10002;return hip_status;}
    hip_status=ffi_call_i32(symbol,a,b,c,d,e,f);return hip_status;
}
fn hip_error() {
    if hip_status==-10001 {return "libamdhip64.so unavailable";}
    if hip_status==-10002 {return "required HIP runtime symbol unavailable";}
    if hip_status==-10003 {return "HIP host allocation or FFI bridge failed";}
    if hip_status==-10004 {if hiprtc_log {return hiprtc_log;}return "HIPRTC kernel compilation failed";}
    let symbol=ffi_symbol(hip_library,"hipGetErrorName");if !symbol {return "unknown HIP error";}
    return ffi_call(symbol,hip_status,0,0,0,0,0);
}
fn hip_device_count() {let p=alloc(8);if hip_call("hipGetDeviceCount",p,0,0,0,0,0) {return -1;}let n=load64(p)&4294967295;syscall(11,p,8,0,0,0,0);return n;}
fn hip_device(ordinal) {return ordinal;}
// Map the CUDA-compatible host adapter's attribute identifiers explicitly.
fn hip_device_attribute(device,attribute) {
    let a=-1;if attribute==1 {a=56;}else if attribute==16 {a=63;}else if attribute==10 {a=87;}
    else if attribute==39 {a=57;}else if attribute==8 {a=74;}else if attribute==12 {a=71;}
    else if attribute==75 {a=23;}else if attribute==76 {a=61;}
    if a<0 {hip_status=1;return -1;}let p=alloc(8);
    if hip_call("hipDeviceGetAttribute",p,a,device,0,0,0) {return -1;}let v=load64(p)&4294967295;syscall(11,p,8,0,0,0,0);return v;
}
fn hip_device_name(device) {let p=alloc(256);if hip_call("hipDeviceGetName",p,256,device,0,0,0) {return 0;}return p;}
// Versioned ROCm 6 device-properties ABI on Linux x86-64: 1472 bytes,
// gcnArchName[256] at 1160. Keep the versioned symbol rather than a moving ABI.
fn hip_device_arch(device) {
    let p=alloc(1472);if hip_call("hipGetDevicePropertiesR0600",p,device,0,0,0,0) {syscall(11,p,1472,0,0,0,0);return 0;}
    let name=alloc(256);let i=0;while i<255 {store8(name+i,load8(p+1160+i));i=i+1;}store8(name+255,0);syscall(11,p,1472,0,0,0,0);return name;
}
fn hip_memory_info() {let p=alloc(16);if hip_call("hipMemGetInfo",p,p+8,0,0,0,0) {return 0;}return p;}
fn hip_context_device(ordinal) {if hip_call("hipInit",0,0,0,0,0,0) {return 0;}let p=alloc(8);if hip_call("hipCtxCreate",p,0,ordinal,0,0,0) {return 0;}let v=load64(p);syscall(11,p,8,0,0,0,0);return v;}
fn hip_close(context) {return hip_call("hipCtxDestroy",context,0,0,0,0,0);}
fn hip_synchronize() {return hip_call("hipDeviceSynchronize",0,0,0,0,0,0);}
fn hip_module(image) {
    let code=image;
    if (load64(image)&4294967295)!=0x464c457f {code=hiprtc_compile(image,"--gpu-architecture=gfx1201");if !code {hip_status=-10004;return 0;}}
    let p=alloc(8);let status=hip_call("hipModuleLoadData",p,code,0,0,0,0);
    if code!=image {syscall(11,code,hiprtc_bytes,0,0,0,0);}if status {return 0;}
    let v=load64(p);syscall(11,p,8,0,0,0,0);return v;
}
fn hip_unload(module) {return hip_call("hipModuleUnload",module,0,0,0,0,0);}
fn hip_buffer(bytes) {let p=alloc(8);if hip_call("hipMalloc",p,bytes,0,0,0,0) {return 0;}let v=load64(p);syscall(11,p,8,0,0,0,0);return v;}
fn hip_free(pointer) {return hip_call("hipFree",pointer,0,0,0,0,0);}
fn hip_upload(device,host,bytes) {return hip_call("hipMemcpy",device,host,bytes,1,0,0);}
fn hip_download(host,device,bytes) {return hip_call("hipMemcpy",host,device,bytes,2,0,0);}
fn hip_copy(to,from,bytes) {return hip_call("hipMemcpy",to,from,bytes,3,0,0);}
fn hip_upload_async(device,host,bytes,stream) {return hip_call("hipMemcpyAsync",device,host,bytes,1,stream,0);}
fn hip_download_async(host,device,bytes,stream) {return hip_call("hipMemcpyAsync",host,device,bytes,2,stream,0);}
fn hip_copy_async(to,from,bytes,stream) {return hip_call("hipMemcpyAsync",to,from,bytes,3,stream,0);}
fn hip_host_buffer(bytes) {let p=alloc(8);if hip_call("hipHostMalloc",p,bytes,0,0,0,0) {return 0;}let v=load64(p);syscall(11,p,8,0,0,0,0);return v;}
fn hip_host_free(pointer) {return hip_call("hipHostFree",pointer,0,0,0,0,0);}
fn hip_function(module,name) {let p=alloc(8);if hip_call("hipModuleGetFunction",p,module,name,0,0,0) {return 0;}let v=load64(p);syscall(11,p,8,0,0,0,0);return v;}
fn hip_function_attribute(function,attribute) {let p=alloc(8);if hip_call("hipFuncGetAttribute",p,attribute,function,0,0,0) {return -1;}let v=load64(p)&4294967295;syscall(11,p,8,0,0,0,0);return v;}
fn hip_occupancy(function,threads,shared) {let p=alloc(8);if hip_call("hipModuleOccupancyMaxActiveBlocksPerMultiprocessor",p,function,threads,shared,0,0) {return -1;}let v=load64(p)&4294967295;syscall(11,p,8,0,0,0,0);return v;}
fn hip_config(gx,gy,gz,bx,by,bz,shared,stream) {
    if gx<1 || gx>2147483647 || gy<1 || gy>65535 || gz<1 || gz>65535 || bx<1 || by<1 || bz<1 || bx>1024 || by>1024 || bz>64 || bx*by*bz>1024 || shared<0 || shared>4294967295 {hip_status=1;return 0;}
    if gx*gy*gz>0x7fffffffffffffff/(bx*by*bz) {hip_status=1;return 0;}
    let p=alloc(88);store64(p+8,gx);store64(p+16,gy);store64(p+24,gz);store64(p+32,bx);store64(p+40,by);store64(p+48,bz);store64(p+56,shared);store64(p+64,stream);hip_status=0;return p;
}
fn hip_dispatch(function,config,arguments) {
    if !function || !config {hip_status=1;return 1;}
    if !hip_launch_symbol {hip_launch_symbol=ffi_symbol(hip_library,"hipModuleLaunchKernel");}
    if !hip_launch_symbol {hip_status=-10002;return hip_status;}
    store64(config,function);store64(config+72,arguments);
    let result=ffi_call_words(hip_launch_symbol,config);hip_status=(result<<32)>>32;return hip_status;
}
fn hip_launch_words(module,input,output,count,config,words) {
    if count<0 || count>2147483647 || !config || !words {hip_status=1;return 1;}if !count {hip_status=0;return 0;}
    let function=hip_function(module,"flex_kernel");if hip_status {return hip_status;}
    let values=alloc(24);store64(values,input);store64(values+8,output);store64(values+16,count);let args=alloc(88);let i=0;
    while i<3 {store64(args+i*8,values+i*8);i=i+1;}i=0;while i<8 {store64(args+24+i*8,words+i*8);i=i+1;}
    let result=hip_dispatch(function,config,args);syscall(11,values,24,0,0,0,0);syscall(11,args,88,0,0,0,0);return result;
}
fn hip_launch(module,input,output,count) {
    if count<0 || count>2147483647 {hip_status=1;return 1;}if !count {hip_status=0;return 0;}
    let words=alloc(64);let config=hip_config((count+127)/128,1,1,128,1,1,0,0);
    let result=hip_launch_words(module,input,output,count,config,words);if !result {result=hip_synchronize();}
    syscall(11,words,64,0,0,0,0);syscall(11,config,88,0,0,0,0);return result;
}
fn hip_stream() {let p=alloc(8);if hip_call("hipStreamCreateWithFlags",p,1,0,0,0,0) {return 0;}let v=load64(p);syscall(11,p,8,0,0,0,0);return v;}
fn hip_stream_wait(stream) {return hip_call("hipStreamSynchronize",stream,0,0,0,0,0);}
fn hip_stream_close(stream) {return hip_call("hipStreamDestroy",stream,0,0,0,0,0);}
fn hip_capture_begin(stream) {return hip_call("hipStreamBeginCapture",stream,0,0,0,0,0);}
fn hip_capture_end(stream) {let p=alloc(8);if hip_call("hipStreamEndCapture",stream,p,0,0,0,0) {return 0;}let v=load64(p);syscall(11,p,8,0,0,0,0);return v;}
fn hip_graph_instance(graph) {let p=alloc(8);if hip_call("hipGraphInstantiateWithFlags",p,graph,0,0,0,0) {return 0;}let v=load64(p);syscall(11,p,8,0,0,0,0);return v;}
fn hip_graph_launch(graph,stream) {return hip_call("hipGraphLaunch",graph,stream,0,0,0,0);}
fn hip_graph_upload(graph,stream) {return hip_call("hipGraphUpload",graph,stream,0,0,0,0);}
fn hip_graph_close(graph) {return hip_call("hipGraphDestroy",graph,0,0,0,0,0);}
fn hip_graph_instance_close(graph) {return hip_call("hipGraphExecDestroy",graph,0,0,0,0,0);}
fn hip_event() {let p=alloc(8);if hip_call("hipEventCreate",p,0,0,0,0,0) {return 0;}let v=load64(p);syscall(11,p,8,0,0,0,0);return v;}
fn hip_event_record(event,stream) {return hip_call("hipEventRecord",event,stream,0,0,0,0);}
fn hip_event_wait(event) {return hip_call("hipEventSynchronize",event,0,0,0,0,0);}
fn hip_stream_wait_event(stream,event) {return hip_call("hipStreamWaitEvent",stream,event,0,0,0,0);}
fn hip_event_close(event) {return hip_call("hipEventDestroy",event,0,0,0,0,0);}
fn hip_event_elapsed_f32(start,end) {let p=alloc(8);if hip_call("hipEventElapsedTime",p,start,end,0,0,0) {return -1;}let v=load64(p)&4294967295;syscall(11,p,8,0,0,0,0);return v;}
