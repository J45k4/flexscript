import "../lib/softvm.flex";
// Three execution-only wall-time samples (nanoseconds), each running the same
// 200,000-iteration TEST/SUB/JNE loop. Not a full-system or KVM benchmark.
fn now(p) {syscall(228,1,p,0,0,0,0);return load64(p)*1000000000+load64(p+8);}
fn num(n) {let p=alloc(32);let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,1,p+i,32-i,0,0,0);return 0;}
fn main() {let v=softvm_create(1048576);let c=load64(v+64);let r=load64(v+24);let run=load64(v+40);let stamp=alloc(16);let j=0;while j<3 {x86_start(c,0x1000,32,0,0);store64(c+144,64);xf_hex(r+0x1000,"b9400d030048f7c09fffffff4883e90175f3f4");store64(c,0x12345678abcdef01);let t=now(stamp);if x86_run(c,run,1000000)!=5 || load64(c+312)!=600002 || load64(c)!=0x12345678abcdef01 || load64(c+8) {return 1;}num(now(stamp)-t);j=j+1;}return 0;}
