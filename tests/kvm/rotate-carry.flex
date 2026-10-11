import "../../lib/softvm.flex";
global rc_case=0;
fn expect(ok) {if !ok {let p=alloc(32);let n=rc_case;let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,2,p+i,32-i,0,0,0);syscall(1,2,"carry rotate assertion failed\n",30,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn emit(p,v) {store8(p,v);return p+1;}
fn main(argc,argv) {
 expect(argc==2);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);let row=alloc(64);let before=alloc(128);
 let v=softvm_create(1048576);expect(v);let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);x86_jit_min_fuel=0;x86_jit_threshold=1;
 let rows=0;while rows<2304 {expect(syscall(0,fd,row,64,0,0,0)==64);let width=load64(row);let right=load64(row+8);let count=load64(row+16);let input=load64(row+24);let flags=load64(row+32);
  let engine=0;while engine<2 {x86_jit_enabled=engine;let variant=0;while variant<3 {
   expect(x86_start(c,0x1000,32,0,0));let mode=64;if width<8 && !variant {mode=32;}store64(c+144,mode);store64(c+136,flags);if variant==2 {store64(c+376,load64(c+376)|3);}
   let reg=0;if variant==2 {reg=rows&15;if reg==1 && count!=(input&255) {reg=9;}if width==1 {reg=4;}}
   let i=0;while i<16 {store64(c+i*8,0x123456789abcdef0+i);i=i+1;}
   let destination=reg;if width==1 && reg==4 {destination=0;store64(c,(input&~0xff00)|((input&255)<<8));}else {store64(c+destination*8,input);}
   if reg!=1 {store64(c+8,count);}store64(ram+0x8000,input);i=0;while i<16 {store64(before+i*8,load64(c+i*8));i=i+1;}
   let immediate=rows&1;let implicit=count==1 && rows%3==0;
   let p=ram+0x1000;if width==2 {p=emit(p,0x66);}if width==8 || reg>=8 {p=emit(p,0x40+(width==8)*8+(reg>=8));}
   let op=0xd2;if width!=1 {op=op+1;}if immediate {op=op-18;}if implicit {op=op-2;if immediate {op=op+18;}}
   p=emit(p,op);let group=2+right;if variant==1 {p=emit(p,group*8+4);p=emit(p,0x25);store64(p,0x8000);p=p+4;}else {p=emit(p,0xc0+group*8+(reg&7));}
   if immediate && !implicit {p=emit(p,count);}store8(p,0xf4);
   expect(x86_run_slice(c,run,100,1)==10 && load64(c+312)==1 && load64(c+128)==p-ram);
   let expected=load64(row+40);if width==1 && reg==4 {expected=(input&~0xff00)|((expected&255)<<8);}
   if variant==1 {expect(load64(ram+0x8000)==((input&~x86_mask(width))|(expected&x86_mask(width))));}else {expect(load64(c+destination*8)==expected);}
   let masked=count&31;if width==8 {masked=count&63;}let change=1;if masked==1 {change=0x801;}
   expect(load64(c+136)==((flags&~change)|(load64(row+48)&change)));
   i=0;while i<16 {if variant==1 || i!=destination {expect(load64(c+i*8)==load64(before+i*8));}i=i+1;}
   let native=engine && width>=4 && variant!=1;expect(load64(c+1008)==native);rc_case=rc_case+1;variant=variant+1;
  }engine=engine+1;}rows=rows+1;
 }
 // CPL3 memory RMW faults must retain the operand and flags, including zero
 // counts and a transfer crossing into an absent or read-only second page.
 let engine=0;while engine<2 {x86_jit_enabled=engine;let fault=0;while fault<6 {
  expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c+136,0xad7);store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,32);store64(c+176,1281);store64(c+376,3);
  store64(ram+0x10000,0x11007);store64(ram+0x11000,0x12007);store64(ram+0x12000,0x13007);let i=0;while i<256 {store64(ram+0x13000+i*8,i*4096+7);i=i+1;}
  let address=0x4000;if fault>=3 {address=0x4ffc;}store64(c+24,address);store64(c+8,fault%3);store64(ram+0x4000,7);store64(ram+0x4ff8,0x123456789abcdef0);store64(ram+0x5000,0xfedcba9876543210);
  let flags=5;if fault==2 || fault==5 {flags=0;}let page=4;if fault>=3 {page=5;}store64(ram+0x13000+page*8,page*4096+flags);
  xf_hex(ram+0x1000,"48d31bf4");expect(x86_run_slice(c,run,100,1)==-1 && load64(c+1008)==0 && load64(c+136)==0xad7);
  expect(load64(c+352)==page*4096 && load64(c+360)==6+(flags!=0));expect(load64(ram+0x4000)==7 && load64(ram+0x4ff8)==0x123456789abcdef0 && load64(ram+0x5000)==0xfedcba9876543210);rc_case=rc_case+1;fault=fault+1;
 }engine=engine+1;}
 expect(syscall(0,fd,row,1,0,0,0)==0);syscall(3,fd,0,0,0,0,0);softvm_close(v);
 syscall(1,1,"PASS: RCL/RCR hardware results, counts, carry, widths and aliases\n",66,0,0,0);return 0;
}
