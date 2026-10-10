// Linux x86-64 CUDA Driver API adapter. CUDA 12+ provides the four-argument
// cuLaunchKernelEx interface, which fits Flexscript's existing integer FFI.
import "ffi.flex";
global cuda_library=0;
global cuda_status=0;
global cuda_log=0;
fn cuda_call(name,a,b,c,d,e,f) {
    if !cuda_library {cuda_library=ffi_open("libcuda.so.1");}
    if !cuda_library {cuda_status=-10001;return cuda_status;}
    let symbol=ffi_symbol(cuda_library,name);
    if !symbol {cuda_status=-10002;return cuda_status;}
    cuda_status=ffi_call_i32(symbol,a,b,c,d,e,f);return cuda_status;
}
fn cuda_error() {
    if cuda_status==-10001 {return "libcuda.so.1 unavailable";}
    if cuda_status==-10002 {return "required CUDA driver symbol unavailable (launch needs CUDA 12+)";}
    let result=alloc(8);let status=cuda_status;
    cuda_call("cuGetErrorName",status,result,0,0,0,0);cuda_status=status;
    if load64(result) {return load64(result);}return "unknown CUDA driver error";
}
fn cuda_device_count() {
    if cuda_call("cuInit",0,0,0,0,0,0) {return -1;}
    let value=alloc(8);if cuda_call("cuDeviceGetCount",value,0,0,0,0,0) {return -1;}
    return load64(value)&4294967295;
}
fn cuda_device(ordinal) {
    let value=alloc(8);if cuda_call("cuDeviceGet",value,ordinal,0,0,0,0) {return -1;}
    return load64(value)&4294967295;
}
fn cuda_device_attribute(device,attribute) {
    let value=alloc(8);if cuda_call("cuDeviceGetAttribute",value,attribute,device,0,0,0) {return -1;}
    return load64(value)&4294967295;
}
fn cuda_device_name(device) {
    let value=alloc(256);if cuda_call("cuDeviceGetName",value,256,device,0,0,0) {return 0;}return value;
}
fn cuda_device_memory(device) {
    let value=alloc(8);if cuda_call("cuDeviceTotalMem_v2",value,device,0,0,0,0) {return -1;}return load64(value);
}
// Device-info record: name pointer, ordinal, SM count, warp width, maximum
// threads/block, threads/SM, shared bytes/block, registers/block, VRAM bytes,
// compute-capability major, minor. Integer fields occupy eight bytes each.
fn cuda_device_info(ordinal) {
    if cuda_call("cuInit",0,0,0,0,0,0) {return 0;}
    let device=cuda_device(ordinal);if cuda_status {return 0;}let info=alloc(88);
    store64(info,cuda_device_name(device));if cuda_status {return 0;}store64(info+8,ordinal);
    store64(info+16,cuda_device_attribute(device,16));if cuda_status {return 0;}
    store64(info+24,cuda_device_attribute(device,10));if cuda_status {return 0;}
    store64(info+32,cuda_device_attribute(device,1));if cuda_status {return 0;}
    store64(info+40,cuda_device_attribute(device,39));if cuda_status {return 0;}
    store64(info+48,cuda_device_attribute(device,8));if cuda_status {return 0;}
    store64(info+56,cuda_device_attribute(device,12));if cuda_status {return 0;}
    store64(info+64,cuda_device_memory(device));if cuda_status {return 0;}
    store64(info+72,cuda_device_attribute(device,75));if cuda_status {return 0;}
    store64(info+80,cuda_device_attribute(device,76));if cuda_status {return 0;}return info;
}
fn cuda_context_device(ordinal) {
    if cuda_call("cuInit",0,0,0,0,0,0) {return 0;}
    let device=alloc(8);let context=alloc(8);
    if cuda_call("cuDeviceGet",device,ordinal,0,0,0,0) {return 0;}
    if cuda_call("cuCtxCreate_v2",context,0,load64(device),0,0,0) {return 0;}
    return load64(context);
}
fn cuda_context() {return cuda_context_device(0);}
fn cuda_context_set(context) {return cuda_call("cuCtxSetCurrent",context,0,0,0,0,0);}
fn cuda_synchronize() {return cuda_call("cuCtxSynchronize",0,0,0,0,0,0);}
fn cuda_module(image) {
    let module=alloc(8);let options=alloc(8);let values=alloc(16);
    cuda_log=alloc(8192);
    store8(options,5);store8(options+4,6);
    store64(values,cuda_log);store64(values+8,8192);
    if cuda_call("cuModuleLoadDataEx",module,image,2,options,values,0) {return 0;}
    return load64(module);
}
fn cuda_buffer(size) {
    let pointer=alloc(8);
    if cuda_call("cuMemAlloc_v2",pointer,size,0,0,0,0) {return 0;}return load64(pointer);
}
fn cuda_upload(device,host,size) {return cuda_call("cuMemcpyHtoD_v2",device,host,size,0,0,0);}
fn cuda_download(host,device,size) {return cuda_call("cuMemcpyDtoH_v2",host,device,size,0,0,0);}
fn cuda_u32(pointer,value) {let i=0;while i<4 {store8(pointer+i,value>>(i*8));i=i+1;}return 0;}
fn cuda_function(module,name) {
    let function=alloc(8);
    if cuda_call("cuModuleGetFunction",function,module,name,0,0,0) {return 0;}return load64(function);
}
fn cuda_function_attribute(function,attribute) {
    let value=alloc(8);if cuda_call("cuFuncGetAttribute",value,attribute,function,0,0,0) {return -1;}
    return load64(value)&4294967295;
}
fn cuda_function_set_attribute(function,attribute,value) {return cuda_call("cuFuncSetAttribute",function,attribute,value,0,0,0);}
fn cuda_occupancy(function,threads,shared) {
    let value=alloc(8);if cuda_call("cuOccupancyMaxActiveBlocksPerMultiprocessor",value,function,threads,shared,0,0) {return -1;}
    return load64(value)&4294967295;
}
fn cuda_config(gx,gy,gz,bx,by,bz,shared,stream) {
    if gx<1 || gx>2147483647 || gy<1 || gy>65535 || gz<1 || gz>65535
       || bx<1 || by<1 || bz<1 || bx>1024 || by>1024 || bz>64 || bx*by*bz>1024
       || shared<0 || shared>4294967295 {cuda_status=1;return 0;}
    if gx*gy*gz>0x7fffffffffffffff/(bx*by*bz) {cuda_status=1;return 0;}
    // CUlaunchConfig: seven u32 fields, padding, stream, attrs, numAttrs.
    let config=alloc(56);cuda_u32(config,gx);cuda_u32(config+4,gy);cuda_u32(config+8,gz);
    cuda_u32(config+12,bx);cuda_u32(config+16,by);cuda_u32(config+20,bz);cuda_u32(config+24,shared);
    store64(config+32,stream);cuda_status=0;return config;
}
// Low-level dispatch accepts any named CUDA function and its parameter pointers.
// It enqueues work; synchronize the stream before reading results or freeing data.
fn cuda_dispatch(function,config,arguments) {
    if !function || !config {cuda_status=1;return 1;}
    return cuda_call("cuLaunchKernelEx",config,function,arguments,0,0,0);
}
fn cuda_launch_config(module,input,output,count,config) {
    if count<0 || count>2147483647 || !config {cuda_status=1;return 1;}
    if count==0 {cuda_status=0;return 0;}
    let function=cuda_function(module,"flex_kernel");if !function {return cuda_status;}
    let arguments=alloc(24);let values=alloc(24);
    store64(values,input);store64(values+8,output);store64(values+16,count);
    store64(arguments,values);store64(arguments+8,values+8);store64(arguments+16,values+16);
    return cuda_dispatch(function,config,arguments);
}
fn cuda_launch_threads(module,input,output,count,threads) {
    if count<0 || count>2147483647 || threads<1 || threads>1024 {cuda_status=1;return 1;}
    if count==0 {cuda_status=0;return 0;}
    let config=cuda_config((count+threads-1)/threads,1,1,threads,1,1,0,0);
    if cuda_launch_config(module,input,output,count,config) {return cuda_status;}return cuda_synchronize();
}
fn cuda_launch(module,input,output,count) {return cuda_launch_threads(module,input,output,count,128);}
fn cuda_stream() {
    let value=alloc(8);if cuda_call("cuStreamCreate",value,1,0,0,0,0) {return 0;}return load64(value);
}
fn cuda_stream_wait(stream) {return cuda_call("cuStreamSynchronize",stream,0,0,0,0,0);}
fn cuda_stream_close(stream) {return cuda_call("cuStreamDestroy_v2",stream,0,0,0,0,0);}
fn cuda_host_buffer(bytes) {
    let value=alloc(8);if cuda_call("cuMemHostAlloc",value,bytes,0,0,0,0) {return 0;}return load64(value);
}
fn cuda_host_free(pointer) {return cuda_call("cuMemFreeHost",pointer,0,0,0,0,0);}
fn cuda_upload_async(device,host,bytes,stream) {return cuda_call("cuMemcpyHtoDAsync_v2",device,host,bytes,stream,0,0);}
fn cuda_download_async(host,device,bytes,stream) {return cuda_call("cuMemcpyDtoHAsync_v2",host,device,bytes,stream,0,0);}
fn cuda_copy_async(to,from,bytes,stream) {return cuda_call("cuMemcpyDtoDAsync_v2",to,from,bytes,stream,0,0);}
fn cuda_event() {
    let value=alloc(8);if cuda_call("cuEventCreate",value,0,0,0,0,0) {return 0;}return load64(value);
}
fn cuda_event_record(event,stream) {return cuda_call("cuEventRecord",event,stream,0,0,0,0);}
fn cuda_event_wait(event) {return cuda_call("cuEventSynchronize",event,0,0,0,0,0);}
fn cuda_stream_wait_event(stream,event) {return cuda_call("cuStreamWaitEvent",stream,event,0,0,0,0);}
fn cuda_event_close(event) {return cuda_call("cuEventDestroy_v2",event,0,0,0,0,0);}
fn cuda_event_elapsed_f32(start,end) {
    let value=alloc(8);if cuda_call("cuEventElapsedTime",value,start,end,0,0,0) {return -1;}return load64(value)&4294967295;
}
// One-channel float texture over an existing linear device allocation.
// The allocation must outlive the object; coordinates are integer texel indices.
fn cuda_texture_f32(pointer,bytes) {
    let resource=alloc(144);cuda_u32(resource,2);store64(resource+8,pointer);
    cuda_u32(resource+16,32);cuda_u32(resource+20,1);store64(resource+24,bytes);
    let texture=alloc(104);cuda_u32(texture,1);cuda_u32(texture+4,1);cuda_u32(texture+8,1);
    let value=alloc(8);if cuda_call("cuTexObjectCreate",value,resource,texture,0,0,0) {return 0;}return load64(value);
}
fn cuda_texture_close(texture) {return cuda_call("cuTexObjectDestroy",texture,0,0,0,0,0);}
fn cuda_free(pointer) {return cuda_call("cuMemFree_v2",pointer,0,0,0,0,0);}
fn cuda_unload(module) {return cuda_call("cuModuleUnload",module,0,0,0,0,0);}
fn cuda_close(context) {return cuda_call("cuCtxDestroy_v2",context,0,0,0,0,0);}
