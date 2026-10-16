import "../emulator/backends/software.flex";
// Execution-only padded full-width MUL loop; not a whole-boot benchmark.
fn now(p) {syscall(228,1,p,0,0,0,0);return load64(p)*1000000000+load64(p+8);}
fn num(n) {let p=alloc(32);let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,1,p+i,32-i,0,0,0);syscall(11,p,32,0,0,0,0);return 0;}
fn main() {
 let v=softvm_create(1048576);let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);let stamp=alloc(16);let sample=0;
 let expected=1;let i=0;while i<200000 {expected=expected*3;i=i+1;}
 while sample<3 {
  x86_start(c,0x1000,32,0,0);store64(c+144,64);store64(c,1);store64(c+8,3);store64(c+24,200000);
  xf_hex(ram+0x1000,"0f1f84000000000048f7e14883eb0175eff4");
  let t=now(stamp);let reason=x86_run(c,run,1000000);let elapsed=now(stamp)-t;
  if reason!=5 || load64(c+312)!=800001 || load64(c)!=expected || load64(c+24) {return 1;}
  num(elapsed);sample=sample+1;
 }
 softvm_close(v);return 0;
}
