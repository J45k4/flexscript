import "../../emulator/backends/software.flex";
fn expect(v) {if !v {let text="Accumulator immediate assertion failed\n";syscall(1,2,text,38,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn value(i) {if i==0 {return 0;}if i==1 {return 1;}if i==2 {return -1;}if i==3 {return 0x7fffffff;}if i==4 {return 0x80000000;}if i==5 {return 0x7fffffffffffffff;}if i==6 {return 0x8000000000000000;}return 0xfeedface87654321;}
fn main() {
 let v=softvm_create(1048576);expect(v);let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);
 x86_jit_min_fuel=0;x86_jit_threshold=1;
 let engine=0;while engine<2 {x86_jit_enabled=engine;let mode=32;while mode<=64 {let width=4;while width<=8 {
  if width==4 || mode==64 {let op=0;while op<8 {let a=0;while a<8 {let b=0;while b<8 {let carry=0;while carry<2 {let cpl=0;while cpl<=3 {
   x86_start(c,0x1000,32,0,0);store64(c+144,mode);store64(c+376,cpl);let flags=0xad6|carry;store64(c+136,flags);
   let r=0;while r<16 {store64(c+r*8,0x123456789abcdef0+r);r=r+1;}store64(c,value(a));
   let immediate=x86_signed(value(b)&0xffffffff,4);let result=x86_alu(c,op,value(a)&x86_mask(width),immediate,width);let answer_flags=load64(c+136);store64(c+136,flags);
   let p=ram+0x1000;if width==8 {store8(p,0x48);p=p+1;}store8(p,op*8+5);p=p+1;
   let j=0;while j<4 {store8(p+j,immediate>>(j*8));j=j+1;}p=p+4;store8(p,0xf4);
   expect(x86_run_slice(c,run,10,1)==10 && !load64(c+288));expect(load64(c+128)==p-ram && load64(c+312)==1);
   let wanted=result&x86_mask(width);if op==7 {wanted=value(a);}expect(load64(c)==wanted && load64(c+136)==answer_flags);
   r=1;while r<16 {expect(load64(c+r*8)==0x123456789abcdef0+r);r=r+1;}
   if engine {expect(load64(c+1008)==1);}cpl=cpl+3;
  }carry=carry+1;}b=b+1;}a=a+1;}op=op+1;}}
 width=width*2;}mode=mode*2;}engine=engine+1;}
 softvm_close(v);let text="PASS: accumulator immediates, sign extension, carry, flags and native execution\n";syscall(1,1,text,80,0,0,0);return 0;
}
