// Diagnostic bootstrap only: the Mesa probe runs on the matching real kernel.
fn length(s) {let n=0;while load8(s+n) {n=n+1;}return n;}
fn print(s) {syscall(1,1,s,length(s),0,0,0);return 0;}
fn stop() {while 1 {syscall(34,0,0,0,0,0,0);}return 0;}
fn check(code) {if code<0 {print("FAIL: Mesa init bootstrap syscall\n");stop();}return code;}
fn module(path) {let fd=check(syscall(2,path,0,0,0,0,0));let result=syscall(313,fd,"",0,0,0,0);syscall(3,fd,0,0,0,0,0);return check(result);}
fn option(wanted) {
    let fd=check(syscall(2,"/proc/cmdline",0,0,0,0,0));let text=check(alloc(4096));let n=check(syscall(0,fd,text,4095,0,0,0));syscall(3,fd,0,0,0,0,0);
    let i=0;let found=0;let size=length(wanted);while i<n {while i<n && load8(text+i)<=32 {i=i+1;}let start=i;while i<n && load8(text+i)>32 {i=i+1;}if i-start==size {let j=0;while j<size && load8(text+start+j)==load8(wanted+j) {j=j+1;}if j==size {found=1;}}}
    syscall(11,text,4096,0,0,0,0);return found;
}
fn main() {
    print("Loading official Linux GPU modules for Mesa diagnostic\n");
    check(syscall(165,"devtmpfs","/dev","devtmpfs",0,"",0));check(syscall(165,"sysfs","/sys","sysfs",0,"",0));check(syscall(165,"proc","/proc","proc",0,"",0));
    module("/virtio_dma_buf.ko");module("/virtio-gpu.ko");
    let args=alloc(24);store64(args,"/mesa-probe");if option("flexvirt.mesa_scanout=1") {store64(args+8,"--scanout");}let env=alloc(56);
    store64(env,"LIBGL_ALWAYS_SOFTWARE=1");store64(env+8,"LP_NUM_THREADS=1");store64(env+16,"GALLIUM_OVERRIDE_CPU_CAPS=sse2");store64(env+24,"EGL_LOG_LEVEL=debug");store64(env+32,"HOME=/tmp");store64(env+40,"PATH=/usr/bin");
    check(syscall(59,"/mesa-probe",args,env,0,0,0));return stop();
}
