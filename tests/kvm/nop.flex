import "../../emulator/backends/software.flex";
global nop_case=0;
fn expect(ok) {if !ok {let p=alloc(32);let n=nop_case;let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,2,p+i,32-i,0,0,0);syscall(1,2,"NOP assertion failed\n",21,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn byte(p,value) {store8(p,value);return p+1;}
fn reset(c,mode) {expect(x86_start(c,0x1000,32,0,0));store64(c+144,mode);store64(c+136,0xed7);let i=0;while i<16 {store64(c+i*8,0xfedcba9876540000+i);i=i+1;}return 0;}
fn check(c,run,ram,end,native) {
 expect(x86_run_slice(c,run,100,1)==10 && load64(c+312)==1 && load64(c+128)==end-ram && load64(c+136)==0xed7);
 let i=0;while i<16 {expect(load64(c+i*8)==0xfedcba9876540000+i);i=i+1;}
 expect(load64(c+1008)==native);nop_case=nop_case+1;return 0;
}
fn main() {
 let v=softvm_create(1048576);expect(v);let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);x86_jit_min_fuel=0;x86_jit_threshold=1;
 let engine=0;while engine<2 {x86_jit_enabled=engine;let mode=32;while mode<=64 {let variant=0;while variant<256 {
  reset(c,mode);if variant&128 {store64(c+376,load64(c+376)|3);}
  let p=ram+0x1000;let prefixes=(variant>>5)&3;let i=0;while i<prefixes {p=byte(p,0x66);i=i+1;}if variant&16 {p=byte(p,0x2e);}if mode==64 {p=byte(p,0x40+(variant&15));}
  p=byte(p,0x0f);p=byte(p,0x1f);let mod=(variant>>3)&3;let rm=variant&7;p=byte(p,mod*64+rm);let displacement=0;
  if mod<3 {if rm==4 {p=byte(p,0xed);if mod==0 {displacement=4;}}else if mod==0 && rm==5 {displacement=4;}
   if mod==1 {displacement=1;}if mod==2 {displacement=4;}}
  i=0;while i<displacement {p=byte(p,0xff);i=i+1;}store8(p,0xf4);check(c,run,ram,p,engine);variant=variant+1;
 }mode=mode*2;}
 // Every legal instruction length, including fourteen prefixes plus NOP.
 let count=0;while count<=14 {reset(c,64);let p=ram+0x1000;let i=0;while i<count {p=byte(p,0x66);i=i+1;}p=byte(p,0x90);store8(p,0xf4);check(c,run,ram,p,engine);count=count+1;}
 // REX.B changes opcode 90 to XCHG RAX,R8, so it must retain the fallback.
 reset(c,64);xf_hex(ram+0x1000,"4990f4");expect(x86_run_slice(c,run,100,1)==10 && load64(c)==0xfedcba9876540008 && load64(c+64)==0xfedcba9876540000 && load64(c+1008)==0);
 // CS prefix on a non-NOP must not disappear into the NOP recognizer.
 reset(c,64);xf_hex(ram+0x1000,"2e4889c8f4");expect(x86_run_slice(c,run,100,1)==10 && load64(c)==0xfedcba9876540001 && load64(c+1008)==0);
 // Truncated source at a page boundary uses the checked interpreter fetch.
 reset(c,64);store64(c+128,0x1fff);xf_hex(ram+0x1fff,"0f1f00f4");check(c,run,ram,ram+0x2002,0);
 // Invalid /1 and overlong prefix encodings must fault, never retire natively.
 reset(c,64);xf_hex(ram+0x1000,"0f1fc8f4");expect(x86_run_slice(c,run,100,1)==-1 && load64(c+1008)==0);
 reset(c,64);let i=0;while i<15 {store8(ram+0x1000+i,0x66);i=i+1;}store8(ram+0x100f,0x90);expect(x86_run_slice(c,run,100,1)==-1 && load64(c+1008)==0);
 engine=engine+1;}
 softvm_close(v);syscall(1,1,"PASS: native multi-byte NOP lengths, prefixes, operands and faults\n",67,0,0,0);return 0;
}
