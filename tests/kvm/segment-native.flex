import "../../lib/softvm.flex";
global sn_case=0;
fn expect(v) {if !v {let p=alloc(32);let n=sn_case;let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,2,p+i,32-i,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn program(k) {
 if k==0 {return "488b00";}if k==1 {return "488900";}if k==2 {return "480300";}if k==3 {return "482b00";}
 if k==4 {return "483b00";}if k==5 {return "488500";}if k==6 {return "48f700ffffffff";}if k==7 {return "0fb600";}
 if k==8 {return "0f1000";}if k==9 {return "0f2800";}if k==10 {return "668b00";}if k==11 {return "8a20";}
 if k==12 {return "8820";}if k==13 {return "0f9400";}if k==14 {return "480f4500";}if k==15 {return "480fbc00";}
 if k==16 {return "488d00";}if k==17 {return "4889c8";}if k==18 {return "50";}if k==19 {return "58";}
 if k==20 {return "e800000000";}if k==21 {return "483dffffffff";}if k==22 {return "0f1100";}if k==23 {return "0f2900";}if k==24 {return "488b05f8f0ffff";}if k==25 {return "488b042500010000";}return "488b448808";
}
fn reset(c,r,segment,base,kind) {
 expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c+168,512);store64(c+136,0xed7);store64(c+464,0x7000);store64(c+472,0x8000);store64(c+segment,base);
 let i=0;while i<16 {store64(c+i*8,0x12345678fedcba98+i*71);store64(c+1184+i*16,0xabcdef0123456789+i);store64(c+1192+i*16,0x87654321fedcba98+i);i=i+1;}
 store64(c,0x100);store64(c+8,2);store64(c+32,0x6000);i=0x100;while i<0x9000 {store64(r+i,0x123456789abcdef0+i);i=i+8;}
 store8(r+0x1000,0x64+(segment==472));let text=program(kind);let n=0;while load8(text+n) {n=n+1;}xf_hex(r+0x1001,text);store8(r+0x1001+n/2,0xf4);return 0;
}
fn paging(c,r,flags) {
 store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,544);store64(c+176,1281);store64(c+376,3);
 store64(r+0x10000,0x11007);store64(r+0x11000,0x12007);store64(r+0x12000,0x13007);let i=0;while i<256 {store64(r+0x13000+i*8,i*4096+7);i=i+1;}store64(r+0x13000+4*8,0x4000+flags);return 0;
}
fn compare(a,b,ra,rb,ua,ub) {
 x86_jit_enabled=0;let expected=x86_run_slice(a,ua,100,1);let error=x86_error;x86_jit_enabled=1;let actual=x86_run_slice(b,ub,100,1);expect(actual==expected && error==x86_error);
 let i=0;while i<208 {expect(load64(a+i)==load64(b+i));i=i+8;}expect(load64(a+288)==load64(b+288) && load64(a+312)==load64(b+312));expect(load64(a+352)==load64(b+352) && load64(a+360)==load64(b+360) && load64(a+392)==load64(b+392));
 i=1024;while i<1536 {expect(load64(a+i)==load64(b+i));i=i+8;}i=0x100;while i<0x9000 {expect(load64(ra+i)==load64(rb+i));i=i+8;}return actual;
}
fn main() {
 let va=softvm_create(1048576);let vb=softvm_create(1048576);expect(va && vb);let a=load64(va+64);let b=load64(vb+64);let ra=load64(va+24);let rb=load64(vb+24);let ua=load64(va+40);let ub=load64(vb+40);x86_jit_min_fuel=0;x86_jit_threshold=1;
 let seg=464;while seg<=472 {let k=0;while k<27 {let variant=0;while variant<6 {
  let base=0x4000;if variant==1 {base=base+1;}if variant==5 {base=0x100000-0x104;}
  reset(a,ra,seg,base,k);reset(b,rb,seg,base,k);if variant>=2 && variant<=4 {let flags=7;if variant==3 {flags=0;}if variant==4 {flags=5;}paging(a,ra,flags);paging(b,rb,flags);}
  let reason=compare(a,b,ra,rb,ua,ub);if variant==0 {expect(reason==10 && load64(b+1008)==1);}sn_case=sn_case+1;variant=variant+1;
 }k=k+1;}seg=seg+8;}
 // A cached block must read changed FS/GS bases, rather than bake in TLS state.
 seg=464;while seg<=472 {reset(b,rb,seg,0x4000,0);x86_jit_enabled=1;expect(x86_run_slice(b,ub,100,1)==10 && load64(b)==load64(rb+0x4100));let before=load64(b+448);store64(b+128,0x1000);store64(b,0x100);store64(b+seg,0x5000);expect(x86_run_slice(b,ub,100,2)==10 && load64(b)==load64(rb+0x5100) && load64(b+1008)==2 && load64(b+448)==before);seg=seg+8;}
 seg=464;while seg<=472 {reset(a,ra,seg,0x4000,0);reset(b,rb,seg,0x4000,0);store64(a+144,32);store64(b+144,32);expect(compare(a,b,ra,rb,ua,ub)==-1 && !load64(b+1008));seg=seg+8;}
 softvm_close(va);softvm_close(vb);let text="PASS: native FS/GS memory, TLS changes, ignored prefixes and precise faults\n";syscall(1,1,text,76,0,0,0);return 0;
}
