import "../../lib/softvm.flex";
global ts_case=0;global ts_point=0;
fn diagnostic(n) {let p=alloc(32);let i=31;store8(p+i,10);while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,2,p+i,32-i,0,0,0);return 0;}
fn expect(ok) {if !ok {diagnostic(ts_case);diagnostic(ts_point);syscall(1,2,"TEST/SETcc assertion failed\n",27,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn emit(p,v,n) {let i=0;while i<n {store8(p+i,v>>(i*8));i=i+1;}return p+n;}
fn pair(a,b,ra,rb,ua,ub,text) {
 x86_start(a,0x1000,32,0,0);x86_start(b,0x1000,32,0,0);store64(a+144,64);store64(b+144,64);xf_hex(ra+0x1000,text);xf_hex(rb+0x1000,text);
 store64(a,0x200000);store64(b,0x200000);store64(a+136,0xad7);store64(b+136,0xad7);
 x86_jit_enabled=0;let reason=x86_run(a,ua,100);let error=x86_error;x86_jit_enabled=1;let actual=x86_run(b,ub,100);if actual!=reason || x86_error!=error {diagnostic(reason);diagnostic(actual);}expect(actual==reason && x86_error==error);
 let i=0;while i<208 {if load64(a+i)!=load64(b+i) {diagnostic(i);diagnostic(load64(a+i));diagnostic(load64(b+i));}expect(load64(a+i)==load64(b+i));i=i+8;}expect(load64(a+288)==load64(b+288) && load64(a+312)==load64(b+312));
 expect(load64(a+352)==load64(b+352) && load64(a+360)==load64(b+360));i=0x1000;while i<0x1100 {expect(load64(ra+i)==load64(rb+i));i=i+8;}return reason;
}
fn main(argc,argv) {
 expect(argc==2);let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);let data=alloc(262144);let bytes=0;let got=1;
 while got>0 {got=syscall(0,fd,data+bytes,262144-bytes,0,0,0);expect(got>=0);bytes=bytes+got;}syscall(3,fd,0,0,0,0,0);expect(bytes>0 && !(bytes%48));
 let va=softvm_create(1048576);let vb=softvm_create(1048576);expect(va && vb);let a=load64(va+64);let b=load64(vb+64);let ra=load64(va+24);let rb=load64(vb+24);let ua=load64(va+40);let ub=load64(vb+40);
 x86_jit_min_fuel=0;x86_jit_threshold=1;
 let engine=0;while engine<2 {x86_jit_enabled=engine;let mode=32;while mode<=64 {let at=0;while at<bytes {
  let row=data+at;let width=load64(row);let form=load64(row+8);let immediate=load64(row+16);let value=load64(row+24);let flags=load64(row+32);let answer=load64(row+40);
  if width!=8 || mode==64 {
   let variant=0;while variant<3 {
    x86_start(a,0x1000,32,0,0);store64(a+144,mode);store64(a+136,flags);store64(a+376,(at/48&1)*3);let r=0;
    while r<16 {store64(a+r*8,0xfeedface87654321+r*0x1234567);r=r+1;}
    let memory=variant==1 && form!=0;let destination=0;let rex=0;if width==8 {rex=0x48;}
    if form!=0 && !memory {destination=(at/48)%8;if mode==64 && variant==2 {destination=destination+8;rex=rex|0x41;}}
    let shift=0;let reg=destination;if width==1 && !rex && destination>=4 && destination<8 {reg=destination-4;shift=8;}
    if form!=2 {if memory {store64(ra+0x4000,value);}else {if width==1 && shift {store64(a+reg*8,(value&255)<<shift);}else {store64(a+reg*8,value);}}}
    let old=load64(a+reg*8);let p=ra+0x1000;if width==2 {p=emit(p,0x66,1);}if rex {p=emit(p,rex,1);}
    let immediate_size=width;if width==8 {immediate_size=4;}
    if form==2 {p=emit(p,0x0f,1);p=emit(p,0x90+immediate,1);immediate_size=0;}
    else {let op=0xa9;if width==1 {op=0xa8;}if form==1 {op=0xf7;if width==1 {op=0xf6;}}p=emit(p,op,1);}
    if form!=0 {if memory {if mode==64 {p=emit(p,5,1);p=emit(p,0x4000-(p-ra+4+immediate_size),4);}else {p=emit(p,5,1);p=emit(p,0x4000,4);}}else {p=emit(p,0xc0+(destination&7),1);}}
    if immediate_size {p=emit(p,immediate,immediate_size);}store8(p,0xf4);
    ts_point=1;expect(x86_run_slice(a,ua,10,1)==10 && !load64(a+288));ts_point=2;expect(load64(a+128)==p-ra && load64(a+312)==1);
    let expected=flags;if form!=2 {expected=(flags&~0x8d5)|answer;}ts_point=3;expect(load64(a+136)==expected);
    ts_point=4;if form==2 {if memory {expect(load8(ra+0x4000)==answer);}else {expect(load64(a+reg*8)==((old&~(255<<shift))|(answer<<shift)));}}
    else {if memory {expect(load64(ra+0x4000)==value);}else {expect(load64(a+reg*8)==old);}}
    ts_point=5;r=0;while r<16 {if r!=reg || memory {expect(load64(a+r*8)==0xfeedface87654321+r*0x1234567);}r=r+1;}
    ts_point=6;if engine && width!=2 {expect(load64(a+1008)==1);}variant=variant+1;
   }
  }at=at+48;ts_case=ts_case+1;
 }mode=mode*2;}engine=engine+1;}
 // Faults must precede changes to flags or destination; earlier MOV retires.
 ts_point=7;expect(pair(a,b,ra,rb,ua,ub,"b90100000048f70425ffff0f009ffffffff4")==-1);
 ts_point=8;expect(pair(a,b,ra,rb,ua,ub,"b9010000000f94042500001000f4")==-1);
 // SETcc into watched code must stop the native block before stale following bytes.
 ts_point=9;expect(pair(a,b,ra,rb,ua,ub,"0f940500000000b801000000f4")==-1);
 softvm_close(va);softvm_close(vb);syscall(1,1,"PASS: native TEST/SETcc flags, registers, memory, faults and code writes\n",73,0,0,0);return 0;
}
