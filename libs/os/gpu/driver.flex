// Host transport is independent of the worker compiler: HIP loads either
// direct AMD code or HIP-compiled code; CUDA loads PTX or native cubins.
import "../../../lib/hip.flex";
import "../../../lib/cuda.flex";
global go_driver=0; // 0 HIP, 1 CUDA. Select before opening model allocations.
fn gd_check(status) {if status {let error=0;if go_driver {error=cuda_error();}else {error=hip_error();}h_die(h_cat3("GPU OS: ",error,"\n"));}return 0;}
fn gd_attribute(attribute,device) {
    if !go_driver {let p=h_take(8);if hip_call("hipDeviceGetAttribute",p,attribute,device,0,0,0) {return -1;}return load64(p)&4294967295;}
    if cuda_call("cuInit",0,0,0,0,0,0) {return -1;}
    // CUDA globaltimer is nanoseconds, independent of the SM clock.
    if attribute==10017 {return 1000000;}
    let kind=0;if attribute==10 {kind=95;}else if attribute==15 {kind=86;}else if attribute==87 {kind=10;}else if attribute==63 {kind=16;}else {return -1;}
    return cuda_device_attribute(cuda_device(device),kind);
}
fn gd_module(image) {if go_driver {let v=cuda_module(image);gd_check(cuda_status);return v;}let v=hip_module(image);gd_check(hip_status);return v;}
fn gd_function(module,name) {if go_driver {let v=cuda_function(module,name);gd_check(cuda_status);return v;}let v=hip_function(module,name);gd_check(hip_status);return v;}
fn gd_occupancy(function) {if go_driver {let n=cuda_occupancy(function,512,17664);gd_check(cuda_status);return n;}let n=hip_occupancy(function,512,17664);gd_check(hip_status);return n;}
fn gd_buffer(bytes) {if go_driver {let p=cuda_buffer(bytes);gd_check(cuda_status);return p;}let p=hip_buffer(bytes);gd_check(hip_status);return p;}
fn gd_upload(device,host,bytes) {if go_driver {return gd_check(cuda_upload(device,host,bytes));}return gd_check(hip_upload(device,host,bytes));}
fn gd_free(pointer) {if go_driver {return gd_check(cuda_free(pointer));}return gd_check(hip_free(pointer));}
fn gd_unload(module) {if go_driver {return gd_check(cuda_unload(module));}return gd_check(hip_unload(module));}
fn gd_host(bytes) {let p=h_take(8);if go_driver {gd_check(cuda_call("cuMemHostAlloc",p,bytes,2,0,0,0));}else {gd_check(hip_call("hipHostMalloc",p,bytes,0x40000002,0,0,0));}return load64(p);}
fn gd_mapped(host) {let p=h_take(8);if go_driver {gd_check(cuda_call("cuMemHostGetDevicePointer_v2",p,host,0,0,0,0));}else {gd_check(hip_call("hipHostGetDevicePointer",p,host,0,0,0,0));}return load64(p);}
fn gd_host_free(pointer) {if go_driver {return gd_check(cuda_host_free(pointer));}return gd_check(hip_host_free(pointer));}
fn gd_stream() {if go_driver {let p=cuda_stream();gd_check(cuda_status);return p;}let p=hip_stream();gd_check(hip_status);return p;}
fn gd_wait(stream) {if go_driver {return gd_check(cuda_stream_wait(stream));}return gd_check(hip_stream_wait(stream));}
fn gd_stream_close(stream) {if go_driver {return gd_check(cuda_stream_close(stream));}return gd_check(hip_stream_close(stream));}
fn gd_launch(function,workers,stream,args) {
    let config=h_zero(h_take(88),88);store64(config,function);store64(config+8,workers);store64(config+16,1);store64(config+24,1);store64(config+32,512);store64(config+40,1);store64(config+48,1);store64(config+56,17664);store64(config+64,stream);store64(config+72,args);
    let symbol=0;if go_driver {symbol=ffi_symbol(cuda_library,"cuLaunchCooperativeKernel");}else {symbol=ffi_symbol(hip_library,"hipModuleLaunchCooperativeKernel");}
    h_assert(symbol,"cooperative launch API unavailable");let status=ffi_call_words(symbol,config);return gd_check((status<<32)>>32);
}
