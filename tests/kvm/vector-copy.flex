import "../../emulator/backends/software.flex";
global vc_case=0;global vc_point=0;
fn number(n) {let p=alloc(32);let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,2,p+i,32-i,0,0,0);return 0;}
fn expect(ok) {if !ok {number(vc_case);number(vc_point);syscall(1,2,"vector copy assertion failed\n",29,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn emit(p,v,n) {let i=0;while i<n {store8(p+i,v>>(i*8));i=i+1;}return p+n;}
fn reset(c,r,mode) {
 expect(x86_start(c,0x1000,32,0,0));store64(c+144,mode);store64(c+168,512);store64(c+136,0xed7);
 let i=0;while i<16 {store64(c+i*8,0x12345678fedcba98+i*71);store64(c+1184+i*16,0x7ff8000012345678+i*17);store64(c+1192+i*16,0x80000000abcdef01+i*31);i=i+1;}
 i=0x1000;while i<0x7000 {store64(r+i,0xa5a5a5a5a5a5a5a5);i=i+8;}return 0;
}
fn compare(a,b,ra,rb,ua,ub,limit) {
 x86_jit_enabled=0;let expected=x86_run_slice(a,ua,100,limit);let error=x86_error;
 x86_jit_enabled=1;let actual=x86_run_slice(b,ub,100,limit);vc_point=1;expect(actual==expected && error==x86_error);
 let i=0;while i<208 {vc_point=100+i;expect(load64(a+i)==load64(b+i));i=i+8;}
 vc_point=2;expect(load64(a+288)==load64(b+288) && load64(a+312)==load64(b+312));
 expect(load64(a+352)==load64(b+352) && load64(a+360)==load64(b+360) && load64(a+392)==load64(b+392));
 i=1024;while i<1536 {vc_point=200+i;expect(load64(a+i)==load64(b+i));i=i+8;}
 i=0x1000;while i<0x7000 {vc_point=300+i;expect(load64(ra+i)==load64(rb+i));i=i+8;}return actual;
}
fn paging(c,r,denied,flags) {
 store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,544);store64(c+176,1281);store64(c+376,3);
 store64(r+0x10000,0x11007);store64(r+0x11000,0x12007);store64(r+0x12000,0x13007);
 let i=0;while i<256 {store64(r+0x13000+i*8,i*4096+7);i=i+1;}store64(r+0x13000+denied*8,denied*4096+flags);return 0;
}
fn main() {
 let va=softvm_create(1048576);let vb=softvm_create(1048576);expect(va && vb);
 let a=load64(va+64);let b=load64(vb+64);let ra=load64(va+24);let rb=load64(vb+24);let ua=load64(va+40);let ub=load64(vb+40);
 x86_jit_min_fuel=0;x86_jit_threshold=1;
 // Every register pair, including aliases, both directions and REX.W ignored.
 let kind=0;while kind<12 {
  let op=0x10;let prefix=0;let aligned=0;if kind<8 {let which=kind&3;if which==1 {op=0x11;}else if which==2 {op=0x28;aligned=1;}else if which==3 {op=0x29;aligned=1;}if kind>=4 {prefix=0x66;}}
  else {op=0x6f;if kind&1 {op=0x7f;}prefix=0x66;aligned=1;if kind>=10 {prefix=0xf3;aligned=0;}}
  let mode=32;while mode<=64 {let registers=8;if mode==64 {registers=16;}let reg=0;while reg<registers {let rm=0;while rm<registers {
   reset(a,ra,mode);reset(b,rb,mode);let p=ra+0x1000;if prefix {p=emit(p,prefix,1);}if mode==64 {p=emit(p,0x40+(reg>=8)*4+(rm>=8)+((reg+rm)&1)*8,1);}
   p=emit(p,0x0f,1);p=emit(p,op,1);p=emit(p,0xc0+(reg&7)*8+(rm&7),1);store8(p,0xf4);
   let j=0;while j<16 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}
   expect(compare(a,b,ra,rb,ua,ub,1)==10);vc_point=3;expect(load64(b+1008)==1);vc_case=vc_case+1;rm=rm+1;
  }reg=reg+1;}
  // Absolute SIB and RIP-relative operands; unaligned and cross-page copies.
  let variant=0;while variant<6 {reset(a,ra,mode);reset(b,rb,mode);let address=0x4000;if variant&1 {address=address+1;}if variant>=4 {address=0x4ff8;}
   let p=ra+0x1000;if prefix {p=emit(p,prefix,1);}if mode==64 {p=emit(p,0x44,1);}p=emit(p,0x0f,1);p=emit(p,op,1);
   if mode==64 && variant>=2 {p=emit(p,5,1);p=emit(p,address-(p-ra+4),4);}else {p=emit(p,4,1);p=emit(p,0x25,1);p=emit(p,address,4);}
   store8(p,0xf4);let j=0;while j<16 {store8(rb+0x1000+j,load8(ra+0x1000+j));j=j+1;}
   let reason=compare(a,b,ra,rb,ua,ub,1);vc_point=4;if aligned && (address&15) {expect(reason==-1 && load64(b+392)==2);}else {expect(reason==10);if variant<4 {expect(load64(b+1008)==1);}}vc_case=vc_case+1;variant=variant+1;
  }mode=mode*2;
 }kind=kind+1;}
 // Successful CPL3 loads/stores use the native page walker; exact RAM-end
 // transfers must copy sixteen bytes without touching adjacent memory.
 let direction=0;while direction<2 {let boundary=0;while boundary<2 {
  reset(a,ra,64);reset(b,rb,64);let address=0x4000;if boundary {address=0xffff0;}
  xf_hex(ra+0x1000,"0f1000f4");xf_hex(rb+0x1000,"0f1000f4");if direction {store8(ra+0x1001,0x11);store8(rb+0x1001,0x11);}
  store64(a,address);store64(b,address);store64(ra+address,0x123456789abcdef0);store64(rb+address,0x123456789abcdef0);store64(ra+address+8,0xfedcba9876543210);store64(rb+address+8,0xfedcba9876543210);
  paging(a,ra,5,7);paging(b,rb,5,7);expect(compare(a,b,ra,rb,ua,ub,1)==10 && load64(b+1008)==1);
  if direction {expect(load64(rb+address)==load64(b+1184) && load64(rb+address+8)==load64(b+1192));}else {expect(load64(b+1184)==0x123456789abcdef0 && load64(b+1192)==0xfedcba9876543210);}
  boundary=boundary+1;vc_case=vc_case+1;
 }direction=direction+1;}
 // Faulting stores must not modify either half; include CPL3 page permissions.
 let fault=0;while fault<9 {reset(a,ra,64);reset(b,rb,64);let address=0xffff8;if fault>=1 {address=0x4ff8;}
  xf_hex(ra+0x1000,"b9070000000f1100f4");xf_hex(rb+0x1000,"b9070000000f1100f4");store64(a,address);store64(b,address);
  if fault>=1 {let flags=0;if fault==2 {flags=3;}if fault==3 {flags=5;}if fault>=4 {flags=7;}paging(a,ra,5,flags);paging(b,rb,5,flags);}
  if fault==4 {store64(a,0x800000000000);store64(b,0x800000000000);}
  if fault==5 {store64(a+152,load64(a+152)|4);store64(b+152,load64(b+152)|4);}
  if fault==6 {store64(a+152,load64(a+152)|8);store64(b+152,load64(b+152)|8);}
  if fault==7 {store64(a+168,32);store64(b+168,32);}
  if fault==8 {store64(a+152,load64(a+152)|12);store64(b+152,load64(b+152)|12);}
  let result=compare(a,b,ra,rb,ua,ub,100);vc_point=5;expect(result==-1 && load64(b+312)==2 && load64(b+8)==7);vc_case=vc_case+1;fault=fault+1;
 }
 // A cached block must still reject SSE after CR0/CR4 changes without relying
 // on a generation change to invalidate the compiled record.
 let control=0;while control<3 {reset(b,rb,64);xf_hex(rb+0x1000,"0f10c1f4");x86_jit_enabled=1;expect(x86_run_slice(b,ub,100,1)==10 && load64(b+1008)==1);
  store64(b+128,0x1000);store64(b+1184,0x76543210);if control==0 {store64(b+152,load64(b+152)|4);}else if control==1 {store64(b+152,load64(b+152)|8);}else {store64(b+168,0);}
  expect(xj_run(b,100)==0 && load64(b+1184)==0x76543210 && load64(b+1008)==1);
  expect(x86_run(b,ub,100)==-1 && load64(b+1184)==0x76543210 && load64(b+1008)==1);control=control+1;vc_case=vc_case+1;
 }
 // A watched-code store must return before executing stale following bytes.
 reset(a,ra,64);reset(b,rb,64);xf_hex(ra+0x1000,"0f1100b801000000f4");xf_hex(rb+0x1000,"0f1100b801000000f4");store64(a,0x1003);store64(b,0x1003);store64(a+1184,0x0000f400000007b8);store64(b+1184,0x0000f400000007b8);store64(a+1192,0);store64(b+1192,0);
 expect(compare(a,b,ra,rb,ua,ub,100)==5 && load64(b)==7);softvm_close(va);softvm_close(vb);
 syscall(1,1,"PASS: native vector copies, FP state, faults, controls and code writes\n",71,0,0,0);return 0;
}
