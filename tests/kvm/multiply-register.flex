import "../../emulator/backends/software.flex";
global mul_case=0;
fn expect(ok) {if !ok {let p=alloc(32);let i=31;store8(p+i,10);let n=mul_case;while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,2,p+i,32-i,0,0,0);syscall(1,2,"multiply register assertion failed\n",34,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main(argc,argv) {
 expect(argc==2);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);let row=alloc(64);let before=alloc(128);
 let v=softvm_create(1048576);expect(v);let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);
 x86_jit_min_fuel=0;x86_jit_threshold=1;
 let rows=0;while rows<1156 {expect(syscall(0,fd,row,64,0,0,0)==64);let width=load64(row);let sign=load64(row+8);
  let engine=0;while engine<2 {let variant=0;while variant<2 {
   x86_jit_enabled=engine;expect(x86_start(c,0x1000,32,0,0));let mode=64;if width==4 && !variant {mode=32;}store64(c+144,mode);store64(c+136,0xed7);if variant {store64(c+376,load64(c+376)|3);}
   let i=0;while i<16 {store64(c+i*8,0xfedcba9800000000+i);i=i+1;}
   let source=rows&15;if mode==32 {source=source&7;}if variant {source=2;}
   if source==0 && load64(row+16)!=load64(row+24) {source=1;}
   store64(c,load64(row+16));store64(c+source*8,load64(row+24));i=0;while i<16 {store64(before+i*8,load64(c+i*8));i=i+1;}
   let p=ram+0x1000;if mode==64 {store8(p,0x40+(width==8)*8+(source>=8));p=p+1;}
   store8(p,0xf7);store8(p+1,0xe0+sign*8+(source&7));store8(p+2,0xf4);p=p+2;
   expect(x86_run_slice(c,run,100,1)==10 && load64(c+312)==1 && load64(c+128)==p-ram);
   expect(load64(c)==load64(row+32) && load64(c+16)==load64(row+40) && load64(c+344)==load64(row+40));
   expect(load64(c+136)==((0xed7&~0x801)|(load64(row+48)&0x801)));
   i=0;while i<16 {if i!=0 && i!=2 {expect(load64(c+i*8)==load64(before+i*8));}i=i+1;}
   if engine {expect(load64(c+1008)==1);}mul_case=mul_case+1;variant=variant+1;
  }engine=engine+1;}rows=rows+1;
 }
 expect(syscall(0,fd,row,1,0,0,0)==0);syscall(3,fd,0,0,0,0,0);
 // A memory operand retains the interpreter path and checked access.
 expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c,3);store64(c+24,0x8000);store64(ram+0x8000,7);xf_hex(ram+0x1000,"48f723f4");expect(x86_run_slice(c,run,100,1)==10 && load64(c)==21 && load64(c+16)==0 && load64(c+1008)==0);
 softvm_close(v);syscall(11,row,64,0,0,0,0);syscall(11,before,128,0,0,0,0);
 syscall(1,1,"PASS: native full-width MUL/IMUL hardware results and register aliases\n",71,0,0,0);return 0;
}
