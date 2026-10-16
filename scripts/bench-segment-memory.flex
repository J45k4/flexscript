import "../emulator/backends/software.flex";
// Execution-only nanoseconds for 200,000 TLS loads and additions.
// The measured path is FS-relative ADD/SUB/JNE, not a full-system boot.
fn now(p) {syscall(228,1,p,0,0,0,0);return load64(p)*1000000000+load64(p+8);}
fn num(n) {let p=alloc(32);let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,1,p+i,32-i,0,0,0);return 0;}
fn main() {let v=softvm_create(1048576);let c=load64(v+64);let r=load64(v+24);let run=load64(v+40);let stamp=alloc(16);let j=0;while j<3 {x86_start(c,0x1000,32,0,0);store64(c+144,64);store64(c+464,0x4000);store64(r+0x4000,1);xf_hex(r+0x1000,"b9400d03006448030425000000004883e90175f1f4");let t=now(stamp);if x86_run(c,run,1000000)!=5 || load64(c+312)!=600002 || load64(c)!=200000 || load64(c+8) {return 1;}num(now(stamp)-t);j=j+1;}softvm_close(v);return 0;}
