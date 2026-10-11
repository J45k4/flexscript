// Offline HIP -> AMD HSA code-object compilation. No GPU context is needed.
// ROCm's LLVM compiler handles register allocation and RDNA instruction encoding.
import "ffi.flex";
global hiprtc_library=0;
global hiprtc_status=0;
global hiprtc_log=0;
global hiprtc_bytes=0;
fn hiprtc_call(name,a,b,c,d,e,f) {
    if !hiprtc_library {hiprtc_library=ffi_open("libhiprtc.so");}
    if !hiprtc_library {hiprtc_status=-10001;return hiprtc_status;}
    let symbol=ffi_symbol(hiprtc_library,name);
    if !symbol {hiprtc_status=-10002;return hiprtc_status;}
    hiprtc_status=ffi_call_i32(symbol,a,b,c,d,e,f);return hiprtc_status;
}
fn hiprtc_compile(source,architecture) {
    hiprtc_log=0;hiprtc_bytes=0;let holder=alloc(8);
    if hiprtc_call("hiprtcCreateProgram",holder,source,"flex_kernel.hip",0,0,0) {return 0;}
    let program=load64(holder);let options=alloc(40);
    store64(options,architecture);store64(options+8,"--std=c++17");store64(options+16,"-O3");
    store64(options+24,"-ffp-contract=off");store64(options+32,"-I/opt/rocm/include");
    let status=hiprtc_call("hiprtcCompileProgram",program,5,options,0,0,0);
    let size=alloc(8);hiprtc_call("hiprtcGetProgramLogSize",program,size,0,0,0,0);
    if load64(size)>0 {hiprtc_log=alloc(load64(size));hiprtc_call("hiprtcGetProgramLog",program,hiprtc_log,0,0,0,0);}
    let code=0;
    if !status {
        status=hiprtc_call("hiprtcGetCodeSize",program,size,0,0,0,0);
        if !status {hiprtc_bytes=load64(size);code=alloc(hiprtc_bytes);if code<0 {status=-10003;code=0;}
            else {status=hiprtc_call("hiprtcGetCode",program,code,0,0,0,0);}}
    }
    hiprtc_call("hiprtcDestroyProgram",holder,0,0,0,0,0);hiprtc_status=status;
    syscall(11,holder,8,0,0,0,0);syscall(11,options,40,0,0,0,0);syscall(11,size,8,0,0,0,0);
    if status {return 0;}return code;
}
