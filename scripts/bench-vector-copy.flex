import "../lib/softvm.flex";
// Execution-only samples for an SSE load/store loop; not a whole-boot benchmark.
fn now(p) {syscall(228,1,p,0,0,0,0);return load64(p)*1000000000+load64(p+8);}
fn num(n) {let p=alloc(32);let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,1,p+i,32-i,0,0,0);syscall(11,p,32,0,0,0,0);return 0;}
fn main() {
 let v=softvm_create(1048576);let c=load64(v+64);let r=load64(v+24);let run=load64(v+40);let stamp=alloc(16);let j=0;
 while j<3 {
  x86_start(c,0x1000,32,0,0);store64(c+144,64);store64(c+168,512);
  xf_hex(r+0x1000,"b9400d03000f10060f29074883e90175f4f4");
  store64(c+48,0x4000);store64(c+56,0x5000);store64(r+0x4000,0x12345678abcdef01);store64(r+0x4008,0xfedcba9876543210);
  let t=now(stamp);let reason=x86_run(c,run,1000000);let elapsed=now(stamp)-t;
  if reason!=5 || load64(c+312)!=800002 || load64(c+8) || load64(r+0x5000)!=0x12345678abcdef01 || load64(r+0x5008)!=0xfedcba9876543210 {return 1;}
  num(elapsed);j=j+1;
 }
 softvm_close(v);return 0;
}
