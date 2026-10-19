// Copyright 2023 The Go Authors. All rights reserved.
// Decoder algorithms adapted from Go internal/zstd (Go 1.25.3).
// BSD-3-Clause; see licenses/Go-BSD.txt.
fn fz_huff(c,p,n,off) {
 if load64(c+2040) {store64(c+1880,p);store64(c+1888,n);store64(c+1896,off);let result=native_call1(load64(c+2040),c);if result==(-1) {return fz_fail(c,"invalid native Huffman weights");}if result>=0 {native_call1(load64(c+2024),c);store64(c+168,11);return result;}}
 if off>=n {return fz_fail(c,"missing Huffman table");}let hdr=load8(p+off);off=off+1;let count=0;let weights=c+38912;
 if hdr<128 {
  if hdr==0 || off+hdr>n {return fz_fail(c,"invalid Huffman table size");}
  let log=fz_fse(c,p,off+hdr,off,255,6,c+14336);if log<0 {return -1;}
  let start=load64(c+304);let end=off+hdr-1;if start>end || !load8(p+end) {return fz_fail(c,"invalid Huffman weight stream");}
  let bitpos=(end-start)*8+fz_log(load8(p+end));if bitpos<log*2 {return fz_fail(c,"truncated Huffman states");}
  bitpos=bitpos-log;let s1=(load64(p+start+(bitpos>>3))>>(bitpos&7))&((1<<log)-1);bitpos=bitpos-log;let s2=(load64(p+start+(bitpos>>3))>>(bitpos&7))&((1<<log)-1);let done=0;
  while !done {
   let e=load64(c+14336+s1*8);let bits=(e>>8)&255;
   if bitpos<bits {
    if count>=254 {return fz_fail(c,"too many Huffman weights");}store64(weights+count*8,e&255);store64(weights+(count+1)*8,load64(c+14336+s2*8)&255);count=count+2;done=1;
   }else {
    bitpos=bitpos-bits;s1=(e>>16)+((load64(p+start+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1));if count>=255 {return fz_fail(c,"too many Huffman weights");}store64(weights+count*8,e&255);count=count+1;
    e=load64(c+14336+s2*8);bits=(e>>8)&255;
    if bitpos<bits {
     if count>=254 {return fz_fail(c,"too many Huffman weights");}store64(weights+count*8,e&255);store64(weights+(count+1)*8,load64(c+14336+s1*8)&255);count=count+2;done=1;
    }else {bitpos=bitpos-bits;s2=(e>>16)+((load64(p+start+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1));if count>=255 {return fz_fail(c,"too many Huffman weights");}store64(weights+count*8,e&255);count=count+1;}
   }
  }
  off=off+hdr;
 }else {
  count=hdr-127;if off+(count+1)/2>n {return fz_fail(c,"truncated Huffman weights");}let i=0;
  while i<count {let w=load8(p+off);off=off+1;store64(weights+i*8,w>>4);if i+1<count {store64(weights+(i+1)*8,w&15);}i=i+2;}
 }
 let hist=c+40960;fz_fill(hist,0,104);let sum=0;let i=0;
 while i<count {let w=load64(weights+i*8);if w>12 {return fz_fail(c,"Huffman weight exceeds limit");}store64(hist+w*8,load64(hist+w*8)+1);if w {sum=sum+(1<<(w-1));}i=i+1;}
 if !sum {return fz_fail(c,"empty Huffman table");}let log=fz_log(sum)+1;if log>11 {return fz_fail(c,"Huffman tree exceeds limit");}
 let left=(1<<log)-sum;if !left || (left&(left-1)) {return fz_fail(c,"invalid final Huffman weight");}let last=fz_log(left)+1;
 if count>=256 {return fz_fail(c,"Huffman alphabet overflow");}store64(weights+count*8,last);count=count+1;store64(hist+last*8,load64(hist+last*8)+1);
 if load64(hist+8)<2 || (load64(hist+8)&1) {return fz_fail(c,"invalid Huffman rank one");}
 let next=0;i=0;while i<log {let cur=next;next=next+(load64(hist+(i+1)*8)<<i);store64(hist+(i+1)*8,cur);i=i+1;}
 store64(c+168,log);if load64(c+2024) {store64(c+2032,count);native_call1(load64(c+2024),c);}else {fz_huff_base_table(c,count,log);fz_huff_dual_table(c,11);}
 store64(c+168,11);return off;
}
fn fz_huff_stream(c,p,start,size,out,n) {
 if size<=0 || !load8(p+start+size-1) {return fz_fail(c,"invalid Huffman literal stream");}
 return fz_huff_tail(c,p,start,out,n,(size-1)*8+fz_log(load8(p+start+size-1)));
}
fn fz_huff_tail(c,p,start,out,n,bitpos) {
 let log=load64(c+168);let mask=(1<<log)-1;let table=c+22528;let i=0;
 while i<n {
  let index=0;let at=bitpos-log;
  if at>=0 {index=(load64(p+start+(at>>3))>>(at&7))&mask;}else {index=(load64(p+start)<<(-at))&mask;}
  let entry=bytes_load32(table+index*4);let bits=entry&255;if at<0 && bits>bitpos {return fz_fail(c,"truncated Huffman literals");}
  store8(out+i,entry>>8);bitpos=bitpos-bits;i=i+1;
 }
 if bitpos {return fz_fail(c,"extra bits after Huffman literals");}return n;
}

fn fz_huff_four(c,p,off,size,out,n) {
 if size<6 {return fz_fail(c,"short Huffman jump table");}let s1=fz_u16(p+off);let s2=fz_u16(p+off+2);let s3=fz_u16(p+off+4);let s4=size-6-s1-s2-s3;let each=(n+3)/4;let last=n-3*each;
 if s1<=0 || s2<=0 || s3<=0 || s4<=0 || last<0 {return fz_fail(c,"invalid Huffman jump lengths");}
 let p1=p+off+6;let p2=p1+s1;let p3=p2+s2;let p4=p3+s3;
 if !load8(p1+s1-1) || !load8(p2+s2-1) || !load8(p3+s3-1) || !load8(p4+s4-1) {return fz_fail(c,"invalid Huffman stop bit");}
 let b1=(s1-1)*8+fz_log(load8(p1+s1-1));let b2=(s2-1)*8+fz_log(load8(p2+s2-1));let b3=(s3-1)*8+fz_log(load8(p3+s3-1));let b4=(s4-1)*8+fz_log(load8(p4+s4-1));
 let log=load64(c+168);let mask=(1<<log)-1;let table=c+30720;let d1=out;let d2=out+each;let d3=out+each*2;let d4=out+each*3;let e1=d2;let e2=d3;let e3=d4;let e4=d4+last;let more=1;
 while more {
  let run=(e1-d1)/2;let safe=(e2-d2)/2;if run>safe {run=safe;}safe=(e3-d3)/2;if run>safe {run=safe;}safe=(e4-d4)/2;if run>safe {run=safe;}
  safe=b1/log;if run>safe {run=safe;}safe=b2/log;if run>safe {run=safe;}safe=b3/log;if run>safe {run=safe;}safe=b4/log;if run>safe {run=safe;}
  if !run {more=0;}else {if load64(c+1776) {
   let v=c+1800;store64(v,p1);store64(v+8,p2);store64(v+16,p3);store64(v+24,p4);store64(v+32,b1);store64(v+40,b2);store64(v+48,b3);store64(v+56,b4);store64(v+64,d1);store64(v+72,d2);store64(v+80,d3);store64(v+88,d4);store64(v+96,table);store64(v+104,log);store64(v+112,mask);store64(v+120,run);store64(v+128,e1);store64(v+136,e2);store64(v+144,e3);store64(v+152,e4);let result=native_call1(load64(c+1776),v);if result<0 {return fz_fail(c,"invalid native Huffman stream");}return n;
  }else {let i=0;while i<run {
   let v1=bytes_load32(table+((load64(p1+((b1-log)>>3))>>((b1-log)&7))&mask)*4);
   let v2=bytes_load32(table+((load64(p2+((b2-log)>>3))>>((b2-log)&7))&mask)*4);
   let v3=bytes_load32(table+((load64(p3+((b3-log)>>3))>>((b3-log)&7))&mask)*4);
   let v4=bytes_load32(table+((load64(p4+((b4-log)>>3))>>((b4-log)&7))&mask)*4);
   store8(d1,v1>>8);store8(d1+1,v1>>16);b1=b1-(v1&255);d1=d1+1+(v1>>24);
   store8(d2,v2>>8);store8(d2+1,v2>>16);b2=b2-(v2&255);d2=d2+1+(v2>>24);
   store8(d3,v3>>8);store8(d3+1,v3>>16);b3=b3-(v3&255);d3=d3+1+(v3>>24);
   store8(d4,v4>>8);store8(d4+1,v4>>16);b4=b4-(v4&255);d4=d4+1+(v4>>24);i=i+1;}}
  }
 }
 if fz_huff_tail(c,p1,0,d1,e1-d1,b1)<0 || fz_huff_tail(c,p2,0,d2,e2-d2,b2)<0 || fz_huff_tail(c,p3,0,d3,e3-d3,b3)<0 || fz_huff_tail(c,p4,0,d4,e4-d4,b4)<0 {return -1;}return n;
}

fn fz_literals(c,p,n) {
 if !n {return fz_fail(c,"missing literals header");}let hdr=load8(p);let kind=hdr&3;let fmt=(hdr>>2)&3;let off=1;let raw=0;let size=0;let streams=1;let out=c+172288;
 if kind<2 {
  if fmt==0 || fmt==2 {raw=hdr>>3;}else if fmt==1 {if n<2 {return fz_fail(c,"short literal header");}raw=(hdr>>4)|(load8(p+1)<<4);off=2;}else {if n<3 {return fz_fail(c,"short literal header");}raw=(hdr>>4)|(fz_u16(p+1)<<4);off=3;}
  if raw>131072 {return fz_fail(c,"literal size exceeds block");}
  if kind==0 {if off+raw>n {return fz_fail(c,"truncated raw literals");}fz_copy(out,p+off,raw);off=off+raw;}else {if off>=n {return fz_fail(c,"missing RLE literal");}fz_fill(out,load8(p+off),raw);off=off+1;}
 }else {
  if fmt<2 {if n<3 {return fz_fail(c,"short Huffman header");}raw=(hdr>>4)|((load8(p+1)&63)<<4);size=(load8(p+1)>>6)|(load8(p+2)<<2);off=3;if fmt==1 {streams=4;}}
  else if fmt==2 {if n<4 {return fz_fail(c,"short Huffman header");}raw=(hdr>>4)|(load8(p+1)<<4)|((load8(p+2)&3)<<12);size=(load8(p+2)>>2)|(load8(p+3)<<6);off=4;streams=4;}
  else {if n<5 {return fz_fail(c,"short Huffman header");}raw=(hdr>>4)|(load8(p+1)<<4)|((load8(p+2)&63)<<12);size=(load8(p+2)>>6)|(load8(p+3)<<2)|(load8(p+4)<<10);off=5;streams=4;}
  if raw>131072 || off+size>n {return fz_fail(c,"Huffman literal sizes exceed block");}let end=off+size;
  if kind==2 {let next=fz_huff(c,p,end,off);if next<0 {return -1;}size=size-(next-off);off=next;}else if !load64(c+168) {return fz_fail(c,"Huffman repeat before table");}
  if streams==1 {if fz_huff_stream(c,p,off,size,out,raw)<0 {return -1;}}
  else {if fz_huff_four(c,p,off,size,out,raw)<0 {return -1;}}
  off=end;
 }
 store64(c+216,raw);return off;
}

fn fz_huff_base_table(c,count,log) {let weights=c+38912;let hist=c+40960; let i=0;while i<count {let w=load64(weights+i*8);if w {let start=load64(hist+w*8);let len=1<<(w-1);let expanded=start<<(11-log);let copies=len<<(11-log);let v=(i<<8)|(log+1-w);let j=0;while j<copies {bytes_store32(c+22528+(expanded+j)*4,v);j=j+1;}store64(hist+w*8,start+len);}i=i+1;}
return 1;}

fn fz_huff_dual_table(c,log) {let d=0;let mask=(1<<log)-1;while d<(1<<log) {let first=bytes_load32(c+22528+d*4);let bits=first&255;let second=bytes_load32(c+22528+((d<<bits)&mask)*4);let total=bits+(second&255);let value=first;if total<=log {value=total|(first&0xff00)|((second&0xff00)<<8)|0x1000000;}bytes_store32(c+30720+d*4,value);d=d+1;}
return 1;}
