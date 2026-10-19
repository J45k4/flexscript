// Per-block sequence models. The match finder and length/offset code selection
// stay independent of entropy modeling. Six-bit tables balance build cost and
// precision; estimated total bit cost includes table headers and final states.
// Adaptive inverses: LL +335872, OF +354304, ML +370688 (stride 64).
// Decode tables +397824; normalized histograms +399360; headers +401920.
// Default estimated bit costs +402432; stride-64 default OF inverse +403968.
// Cached prior-table costs +2400000 (three 64-word lanes).
// Context +200..216 logs; +224..240 inverses; +256..272 tables;
// +288..304 header lengths; +312 sequence mode byte.
fn fz_inverse_stride(table,inv,log,stride) {
 let size=1<<log;let i=0;while i<size {let e=load64(table+i*8);let sym=e&255;let bits=(e>>8)&255;let base=e>>16;let j=0;while j<(1<<bits) {store64(inv+(sym*stride+base+j)*8,i|(bits<<8)|(j<<16));j=j+1;}i=i+1;}return 1;
}
fn fz_model_defaults(c) {
 fz_fill(c+402432,0,1536);let kind=0;while kind<3 {let table=c+4096;let size=64;if kind==1 {table=c+8192;size=32;}else if kind==2 {table=c+10240;}let i=0;while i<size {let sym=load64(table+i*8)&255;let at=c+402432+kind*512+sym*8;store64(at,load64(at)+1);i=i+1;}kind=kind+1;}
 kind=0;while kind<3 {let log=6;if kind==1 {log=5;}let i=0;while i<64 {let at=c+402432+kind*512+i*8;let n=load64(at);let cost=99999;if n {cost=fz_frequency_cost(n,log);}store64(at,cost);i=i+1;}kind=kind+1;}
 fz_inverse_stride(c+8192,c+403968,5,64);return 1;
}
fn fz_model_default(c,kind) {
 let table=c+4096;let inverse=c+16384;let log=6;if kind==1 {table=c+8192;inverse=c+403968;log=5;}else if kind==2 {table=c+10240;inverse=c+43008;}
 fz_copy(c+2400000+kind*512,c+402432+kind*512,512);store64(c+200+kind*8,log);store64(c+224+kind*8,inverse);store64(c+256+kind*8,table);store64(c+288+kind*8,0);store64(c+320,load64(c+320)|(1<<kind));return 0;
}
fn fz_normalize(hist,norm,highest,count) {
 let sum=0;let i=0;while i<=highest {let frequency=load64(hist+i*8);let n=0;if frequency {n=(frequency*64+count/2)/count;if !n {n=1;}}store64(norm+i*8,n);sum=sum+n;i=i+1;}
 while sum!=64 {let best=-1;let error=-9223372036854775807;i=0;while i<=highest {let n=load64(norm+i*8);let frequency=load64(hist+i*8);let score=0;let valid=frequency>0;
  if sum>64 {score=n*count-frequency*64;valid=n>1;}else {score=frequency*64-n*count;}
  if valid && score>error {best=i;error=score;}i=i+1;}
  if best<0 {return 0;}if sum>64 {store64(norm+best*8,load64(norm+best*8)-1);sum=sum-1;}else {store64(norm+best*8,load64(norm+best*8)+1);sum=sum+1;}
 }return 1;
}
fn fz_ncount(c,norm,highest,out) {
 store64(c+8,0);store64(c+16,0);store64(c+24,out);store64(c+32,0);store64(c+40,128);fz_wbits(c,1,4);let remaining=65;let threshold=64;let needed=7;let sym=0;let prevzero=0;
 while remaining>1 {
  if prevzero {let zeros=0;while sym<=highest && !load64(norm+sym*8) {zeros=zeros+1;sym=sym+1;}while zeros>=18 {fz_wbits(c,4095,12);zeros=zeros-18;}while zeros>=3 {fz_wbits(c,3,2);zeros=zeros-3;}fz_wbits(c,zeros,2);prevzero=0;}
  else {if sym>highest {return -1;}let n=load64(norm+sym*8);let value=n+1;let maximum=2*threshold-1-remaining;if value<maximum {fz_wbits(c,value,needed-1);}else {if value>=threshold {value=value+maximum;}fz_wbits(c,value,needed);}remaining=remaining-n;prevzero=n==0;sym=sym+1;while remaining<threshold {threshold=threshold>>1;needed=needed-1;}}
 }
 if load64(c) {return -1;}let bytes=load64(c+32);if load64(c+16) {store8(out+bytes,load64(c+8));bytes=bytes+1;}return bytes;
}
fn fz_model_build(c,norm,highest,table,inverse) {
 let next=c+420864;let i=0;let pos=0;while i<=highest {let count=load64(norm+i*8);store64(next+i*8,count);let j=0;while j<count {store64(table+pos*8,i);pos=(pos+43)&63;j=j+1;}i=i+1;}
 if pos {return 0;}i=0;while i<64 {let sym=load64(table+i*8);let t=load64(next+sym*8);store64(next+sym*8,t+1);let bits=6-fz_log(t);store64(table+i*8,sym|(bits<<8)|(((t<<bits)-64)<<16));i=i+1;}
 fz_inverse_stride(table,inverse,6,64);return 1;
}
// Cost in sixteenths of a bit. Linear interpolation between powers of two is
// sufficient for choosing a table; actual emitted bytes remain the final test.
fn fz_frequency_cost(n,log) {let b=fz_log(n);return (log-b)*16-(((n-(1<<b))*16)>>b);}
fn fz_sequence_model(c,sequences,count,kind) {
 let hist=c+399360+kind*512;let norm=c+420352;let table=c+397824+kind*512;let inverse=c+335872;if kind==1 {inverse=c+354304;}else if kind==2 {inverse=c+370688;}
 let i=0;let highest=0;while i<64 {if load64(hist+i*8) {highest=i;}i=i+1;}
 let distinct=0;let only=0;i=0;while i<=highest {if load64(hist+i*8) {distinct=distinct+1;only=i;}i=i+1;}
 // A previously emitted table can be reused without another normalized
 // histogram/header/inverse build when its measured cost stays close to the
 // current histogram's entropy estimate. Missing symbols always force a rebuild.
 if load64(c+320)&(1<<kind) {
  let plog=load64(c+200+kind*8);let freq=c+2400000+kind*512;
  let feasible=1;let repeatcost=0;let ideal=0;let clog=fz_log(count);let correction=((count-(1<<clog))*16)>>clog;i=0;
  while i<=highest {let n=load64(hist+i*8);if n {let pf=load64(freq+i*8);if pf<0 {feasible=0;}else {repeatcost=repeatcost+n*pf;}ideal=ideal+n*(fz_frequency_cost(n,clog)+correction);}i=i+1;}
  repeatcost=repeatcost*(count-1)/count+plog*16;ideal=ideal*(count-1)/count;
  if feasible && repeatcost<=ideal+count*2+1024 {store64(c+288+kind*8,0);return 3;}
 }
 let oldlog=6;if kind==1 {oldlog=5;}let oldcost=0;i=0;while i<=highest {let frequency=load64(hist+i*8);if frequency {oldcost=oldcost+frequency*load64(c+402432+kind*512+i*8);}i=i+1;}oldcost=oldcost*(count-1)/count+oldlog*16;
 let header=c+401920+kind*128;let headerbytes=0;let log=6;let mode=2;let cost=0;
 if distinct==1 {fz_fill(c+2400000+kind*512,255,512);store64(c+2400000+kind*512+only*8,0);headerbytes=1;store8(header,only);log=0;mode=1;cost=128;}
 else {if count<96 {return fz_model_default(c,kind);}if !fz_normalize(hist,norm,highest,count) {return fz_model_default(c,kind);}headerbytes=fz_ncount(c,norm,highest,header);if headerbytes<0 {return -1;}fz_fill(c+2400000+kind*512,255,512);i=0;while i<=highest {let frequency=load64(hist+i*8);if frequency {let perbit=fz_frequency_cost(load64(norm+i*8),6);store64(c+2400000+kind*512+i*8,perbit);cost=cost+frequency*perbit;}i=i+1;}cost=cost*(count-1)/count+6*16+headerbytes*128;}
 if cost>=oldcost {return fz_model_default(c,kind);}
 if mode==1 {store64(table,only);store64(inverse+only*64*8,0);}else if !fz_model_build(c,norm,highest,table,inverse) {return -1;}
 store64(c+200+kind*8,log);store64(c+224+kind*8,inverse);store64(c+256+kind*8,table);store64(c+288+kind*8,headerbytes);store64(c+320,load64(c+320)|(1<<kind));return mode;
}
fn fz_sequence_models(c,sequences,count) {
 let ll=fz_sequence_model(c,sequences,count,0);let of=fz_sequence_model(c,sequences,count,1);let ml=fz_sequence_model(c,sequences,count,2);if ll<0 || of<0 || ml<0 {return fz_fail(c,"cannot encode sequence models");}store64(c+312,(ll<<6)|(of<<4)|(ml<<2));return 1;
}
