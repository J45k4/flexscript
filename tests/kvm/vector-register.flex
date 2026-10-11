import "../../lib/softvm.flex";
global vr_case=0;global vr_point=0;
fn number(n) {let p=alloc(32);let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,2,p+i,32-i,0,0,0);return 0;}
fn expect(ok) {if !ok {number(vr_case);number(vr_point);syscall(1,2,"vector register assertion failed\n",33,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn emit(p,value) {store8(p,value);return p+1;}
fn reset(c,mode) {
 expect(x86_start(c,0x1000,32,0,0));store64(c+144,mode);store64(c+168,512);store64(c+136,0xed7);
 let i=0;while i<16 {store64(c+i*8,0x12345678abcdef01+i);store64(c+1184+i*16,i+17);store64(c+1192+i*16,~i);i=i+1;}return 0;
}
fn main(argc,argv) {
 expect(argc==2);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);let row=alloc(72);let before=alloc(512);
 let v=softvm_create(1048576);expect(v);let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);
 x86_jit_min_fuel=0;x86_jit_threshold=1;
 let rows=0;while rows<4352 {let got=syscall(0,fd,row,72,0,0,0);expect(got==72);let op=load64(row);let immediate=load64(row+8);let opcode=0xef;if op==1 {opcode=0x74;}if op==2 {opcode=0xd7;}if op==3 {opcode=0x70;}if op==4 {opcode=0xd4;}if op==5 {opcode=0x73;}
  let engine=0;while engine<2 {x86_jit_enabled=engine;let mode=32;while mode<=64 {let variant=0;while variant<3 {
   reset(c,mode);let reg=rows&7;let rm=(rows>>3)&7;if mode==64 && variant==1 {reg=reg+8;rm=rm+8;}if variant==2 {rm=reg;}if op==5 {reg=rm;}
   if reg!=rm || op==2 {store64(c+1184+reg*16,load64(row+16));store64(c+1192+reg*16,load64(row+24));}
   store64(c+1184+rm*16,load64(row+32));store64(c+1192+rm*16,load64(row+40));
   let i=0;while i<512 {store64(before+i,load64(c+1024+i));i=i+8;}
   let p=ram+0x1000;p=emit(p,0x66);if mode==64 {p=emit(p,0x40+(reg>=8 && op!=5)*4+(rm>=8)+(variant==1)*8);}p=emit(p,0x0f);p=emit(p,opcode);let modrm=0xc0+(reg&7)*8+(rm&7);if op==5 {modrm=0xd8+(rm&7);}p=emit(p,modrm);if op==3 || op==5 {p=emit(p,immediate);}store8(p,0xf4);
   vr_point=1;expect(x86_run_slice(c,run,100,1)==10 && load64(c+312)==1 && load64(c+128)==p-ram && load64(c+136)==0xed7);
   let lo=load64(row+48);let hi=load64(row+56);if reg==rm && op==0 {lo=0;hi=0;}if reg==rm && op==1 {lo=-1;hi=-1;}if reg==rm && op==4 {lo=load64(row+32)*2;hi=load64(row+40)*2;}
   vr_point=2;if op==2 {expect(load64(c+reg*8)==load64(row+64));}else {expect(load64(c+1184+reg*16)==lo && load64(c+1192+reg*16)==hi);}
   i=0;while i<16 {vr_point=3;if op!=2 || i!=reg {expect(load64(c+i*8)==0x12345678abcdef01+i);}i=i+1;}
   i=0;while i<512 {vr_point=4;if op==2 || i!=160+reg*16 && i!=168+reg*16 {expect(load64(c+1024+i)==load64(before+i));}i=i+8;}
   vr_point=5;if engine {expect(load64(c+1008)==1);}vr_case=vr_case+1;variant=variant+1;
  }mode=mode*2;}engine=engine+1;}rows=rows+1;
 }
 expect(rows==4352 && syscall(0,fd,row,1,0,0,0)==0);syscall(3,fd,0,0,0,0,0);syscall(11,before,512,0,0,0,0);
 // Warm compiled code must reject denied SSE even with unchanged generation.
 let op=0;while op<6 {let control=0;while control<3 {reset(c,64);let opcode=0xef;if op==1 {opcode=0x74;}if op==2 {opcode=0xd7;}if op==3 {opcode=0x70;}if op==4 {opcode=0xd4;}if op==5 {opcode=0x73;}
  xf_hex(ram+0x1000,"66450fefcaf4");store8(ram+0x1003,opcode);if op==3 {store8(ram+0x1005,0x1b);store8(ram+0x1006,0xf4);}if op==5 {store8(ram+0x1001,0x41);store8(ram+0x1004,0xd9);store8(ram+0x1005,8);store8(ram+0x1006,0xf4);}
  x86_jit_enabled=1;expect(x86_run_slice(c,run,100,1)==10 && load64(c+1008)==1);store64(c+128,0x1000);
  if control==0 {store64(c+152,load64(c+152)|4);}else if control==1 {store64(c+152,load64(c+152)|8);}else {store64(c+168,0);}
  vr_point=6;expect(xj_run(c,100)==0 && load64(c+1008)==1);expect(x86_run(c,run,100)==-1 && load64(c+1008)==1);control=control+1;
 }op=op+1;}
 // Call one compiled instruction through a trusted adapter that places
 // sentinels in host XMM0/1 and captures them immediately after its return.
 let wrapper=alloc(4096);let sentinels=alloc(64);
 xf_hex(wrapper,"5341544883ec084889d34989f4f30f6f03f30f6f4b1041ffd4f30f7f4320f30f7f4b304883c408415c5bc3");expect(syscall(10,wrapper,4096,5,0,0,0)==0);
 op=0;while op<6 {reset(c,64);xf_hex(ram+0x1000,"660fefc1f4");let opcode=0xef;if op==1 {opcode=0x74;}if op==2 {opcode=0xd7;}if op==3 {opcode=0x70;}if op==4 {opcode=0xd4;}if op==5 {opcode=0x73;}store8(ram+0x1002,opcode);if op==3 {store8(ram+0x1004,0x93);store8(ram+0x1005,0xf4);}if op==5 {store8(ram+0x1003,0xd8);store8(ram+0x1004,8);store8(ram+0x1005,0xf4);}
  expect(x86_run_slice(c,run,100,1)==10);store64(c+128,0x1000);store64(c+312,0);store64(c+768,1);
  let i=0;while i<32 {store8(sentinels+i,i*17+op);i=i+1;}
  let key=0x1000^(0x1000>>17);let slot=((key*0x9e3779b97f4a7c15)>>32)&32767;let state=xj_state(c);expect(load64(state+64+slot*256+56)==3);
  vr_point=7;expect(ffi_call(wrapper,c,load64(state)+slot*4096,sentinels,0,0,0)==1);i=0;while i<32 {expect(load8(sentinels+i)==load8(sentinels+32+i));i=i+1;}op=op+1;
 }
 syscall(11,wrapper,4096,0,0,0,0);syscall(11,sentinels,64,0,0,0,0);softvm_close(v);
 syscall(1,1,"PASS: native SSE string primitives, hardware results and host XMM state\n",72,0,0,0);return 0;
}
