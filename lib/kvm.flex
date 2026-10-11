// Linux x86-64 KVM API v12. No QEMU, libc or external runtime.
// Handle: system/vm/vcpu fds, RAM/size, kvm_run/size, last exit.
import "kvm-emulator.flex";
// Opt-in API transport for testing. Never an automatic fallback from real KVM.
global kvm_emulated_api=0;
global kvm_error=0;
global kvm_message=0;
fn kvm_fail(message,code) {kvm_message=message;kvm_error=code;return 0;}
fn kvm_u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn kvm_put32(p,n) {let i=0;while i<4 {store8(p+i,n>>(i*8));i=i+1;}return 0;}
fn kvm_zero(p,n) {let i=0;while i<n {store8(p+i,0);i=i+1;}return p;}
fn kvm_copy(to,from,n) {let i=0;while i<n {store8(to+i,load8(from+i));i=i+1;}return 0;}
fn kvm_ioctl(fd,request,arg) {if kvm_emulated_api {return kvme_ioctl(fd,request,arg);}return syscall(16,fd,request,arg,0,0,0);}
fn kvm_device_open() {if kvm_emulated_api {return kvme_open();}return syscall(2,"/dev/kvm",0x80002,0,0,0,0);}
fn kvm_fd_close(fd) {if kvm_emulated_api {return kvme_close(fd);}return syscall(3,fd,0,0,0,0,0);}
fn kvm_map_run(fd,size) {if kvm_emulated_api {return kvme_map(fd,size);}return syscall(9,0,size,3,1,fd,0);}
fn kvm_close(v) {
    if !v {return 0;}
    // Close the vCPU/VM before releasing their backing memory.
    let i=16;while i>=0 {let fd=load64(v+i);if fd>=0 {kvm_fd_close(fd);}i=i-8;}
    if load64(v+40) {syscall(11,load64(v+40),load64(v+48),0,0,0,0);}
    if load64(v+24) {syscall(11,load64(v+24),load64(v+32),0,0,0,0);}
    syscall(11,v,64,0,0,0,0);return 0;
}
fn kvm_abort(v,message,code) {kvm_close(v);return kvm_fail(message,code);}
fn kvm_create(bytes) {
    kvm_error=0;kvm_message=0;
    if bytes<1048576 || bytes>3221225472 || bytes%4096 {return kvm_fail("Guest RAM must be page aligned, between 1 MiB and 3 GiB.",-22);}
    let v=alloc(64);if v<0 {return kvm_fail("Cannot allocate VM handle.",v);}
    store64(v,-1);store64(v+8,-1);store64(v+16,-1);
    let fd=kvm_device_open();
    if fd<0 {return kvm_abort(v,"Cannot open /dev/kvm; a KVM-enabled Linux host and device access are required.",fd);}store64(v,fd);
    let code=kvm_ioctl(fd,0xae00,0);
    if code!=12 {return kvm_abort(v,"Unsupported KVM API version (expected 12).",code);}
    let vm=kvm_ioctl(fd,0xae01,0);if vm<0 {return kvm_abort(v,"KVM_CREATE_VM failed.",vm);}store64(v+8,vm);
    // Intel's three-page TSS region is outside our RAM slot.
    code=kvm_ioctl(vm,0xae47,0xfffbd000);if code<0 {return kvm_abort(v,"KVM_SET_TSS_ADDR failed.",code);}
    let ram=syscall(9,0,bytes,3,0x22,-1,0);
    if ram<0 {return kvm_abort(v,"Cannot map guest RAM.",ram);}store64(v+24,ram);store64(v+32,bytes);
    let region=alloc(32);if region<0 {return kvm_abort(v,"Cannot allocate memory slot descriptor.",region);}
    store64(region+16,bytes);store64(region+24,ram);
    code=kvm_ioctl(vm,0x4020ae46,region);syscall(11,region,32,0,0,0,0);
    if code<0 {return kvm_abort(v,"KVM_SET_USER_MEMORY_REGION failed.",code);}
    let cpu=kvm_ioctl(vm,0xae41,0);if cpu<0 {return kvm_abort(v,"KVM_CREATE_VCPU failed.",cpu);}store64(v+16,cpu);
    let size=kvm_ioctl(fd,0xae04,0);if size<4096 {return kvm_abort(v,"Invalid KVM vCPU mapping size.",size);}store64(v+48,size);
    let run=kvm_map_run(cpu,size);if run<0 {return kvm_abort(v,"Cannot map KVM run state.",run);}store64(v+40,run);
    // Host-supported CPUID includes the long-mode/SSE capabilities needed by FlexOS.
    let cpuid=alloc(8+256*40);if cpuid<0 {return kvm_abort(v,"Cannot allocate CPUID buffer.",cpuid);}
    kvm_put32(cpuid,256);code=kvm_ioctl(fd,0xc008ae05,cpuid);
    if code>=0 {code=kvm_ioctl(cpu,0x4008ae90,cpuid);}
    syscall(11,cpuid,8+256*40,0,0,0,0);
    if code<0 {return kvm_abort(v,"KVM CPUID setup failed.",code);}return v;
}
// Flat real-mode (bits=16) or protected-mode (bits=32) boot. Interrupts masked.
fn kvm_start(v,entry,bits,a,b) {
    if (bits!=16 && bits!=32) || entry<0 || entry>=load64(v+32) || (bits==16 && entry>=65536) {return kvm_fail("Invalid guest entry or CPU mode.",-22);}
    let s=alloc(312);let r=alloc(144);
    if s<0 || r<0 {if s>=0 {syscall(11,s,312,0,0,0,0);}if r>=0 {syscall(11,r,144,0,0,0,0);}return kvm_fail("Cannot allocate CPU state.",-12);}
    let cpu=load64(v+16);let code=kvm_ioctl(cpu,0x8138ae83,s);
    if code>=0 {
        let i=0;while i<6 {
            let seg=s+i*24;kvm_zero(seg,24);kvm_put32(seg+8,65535);
            store8(seg+14,3);store8(seg+15,1);store8(seg+18,1);
            if bits==32 {kvm_put32(seg+8,0xffffffff);store8(seg+12,16);store8(seg+17,1);store8(seg+20,1);}
            if i==0 {store8(seg+14,11);if bits==32 {store8(seg+12,8);}}
            i=i+1;
        }
        store64(s+224,0);store64(s+232,0);store64(s+240,0);store64(s+248,0);store64(s+256,0);store64(s+264,0);
        if bits==32 {store64(s+224,1);}
        code=kvm_ioctl(cpu,0x4138ae84,s);
    }
    if code>=0 {store64(r,a);store64(r+8,b);store64(r+48,0x8000);store64(r+128,entry);store64(r+136,2);code=kvm_ioctl(cpu,0x4090ae82,r);}
    syscall(11,s,312,0,0,0,0);syscall(11,r,144,0,0,0,0);
    if code<0 {return kvm_fail("KVM CPU setup failed.",code);}return 1;
}
// Returns a KVM_EXIT_* reason, or -1 on syscall failure. Caller owns exit handling.
fn kvm_run(v) {
    let code=kvm_ioctl(load64(v+16),0xae80,0);
    if code<0 {if kvm_emulated_api && x86_message {kvm_fail(x86_message,code);}else {kvm_fail("KVM_RUN failed or was interrupted.",code);}return -1;}
    let reason=kvm_u32(load64(v+40)+8);store64(v+56,reason);return reason;
}
// Bounds-check KVM's packed port-I/O transfer before exposing a host pointer.
fn kvm_io_data(v) {
    let run=load64(v+40);let size=load64(v+48);
    if size<48 || kvm_u32(run+8)!=2 {return kvm_fail("Expected KVM_EXIT_IO.",-22);}
    let width=load8(run+33);let count=kvm_u32(run+36);let offset=load64(run+40);
    if load8(run+32)>1 || (width!=1 && width!=2 && width!=4) || count==0 || offset<48 || offset>size || count>(size-offset)/width {return kvm_fail("Invalid KVM I/O transfer.",-22);}
    return run+offset;
}
