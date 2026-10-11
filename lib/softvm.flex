import "kvm.flex";
// Shares the monitor handle's RAM and exit-buffer layout, with CPU at offset 64.
fn softvm_create(bytes) {
    if bytes<1048576 || bytes>3221225472 || bytes%4096 {return kvm_fail("Invalid software VM RAM size.",-22);}
    let v=alloc(80);if v<0 {return kvm_fail("Cannot allocate software VM.",v);}
    let ram=alloc(bytes);let run=alloc(4096);
    if ram<0 || run<0 {if ram>=0 {syscall(11,ram,bytes,0,0,0,0);}if run>=0 {syscall(11,run,4096,0,0,0,0);}syscall(11,v,80,0,0,0,0);return kvm_fail("Cannot allocate software VM memory.",-12);}
    let cpu=x86_create(ram,bytes);
    if !cpu {syscall(11,ram,bytes,0,0,0,0);syscall(11,run,4096,0,0,0,0);syscall(11,v,80,0,0,0,0);return kvm_fail(x86_message,x86_error);}
    store64(v,-1);store64(v+8,-1);store64(v+16,-1);store64(v+24,ram);store64(v+32,bytes);store64(v+40,run);store64(v+48,4096);store64(v+64,cpu);return v;
}
fn softvm_start(v,entry,bits,a,b) {if !x86_start(load64(v+64),entry,bits,a,b) {return kvm_fail(x86_message,x86_error);}return 1;}
fn softvm_run(v,fuel) {let reason=x86_run(load64(v+64),load64(v+40),fuel);if reason<0 {kvm_fail(x86_message,x86_error);}return reason;}
fn softvm_close(v) {if !v {return 0;}x86_close(load64(v+64));kvm_close(v);return 0;}
