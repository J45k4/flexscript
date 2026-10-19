// Copyright 2023 The Go Authors. All rights reserved.
// Zstd decoding algorithms adapted from Go internal/zstd (Go 1.25.3).
// BSD-3-Clause; see licenses/Go-BSD.txt.
// Decoder owns 442624 bytes of scratch plus a frame-bounded history ring.
// 0 error; 8 window limit; 16 stage; 24 buffered input; 32 required input;
// 48 ring; 56 logical window; 64 ring write cursor; 72 ring valid bytes;
// 80 frame size (-1 unknown); 88 decoded total; 96 checksum flag;
// 104 last block; 112 block type; 120 block size; 128 output size; 136 cursor;
// 1648 physical ring capacity (logical window + one 128 KiB block).
// 144/152/160 repeat offsets; 168 Huffman log; 176/184/192 FSE logs.
fn zstd_decoder_open(max_window) {
 if max_window<1024 || max_window>1073741824 {return 0;}let c=alloc(442624);if c<=0 {return 0;}store64(c+8,max_window);fz_baselines(c);fz_state_transforms(c);zstd_decoder_reset(c);fz_native_open(c);return c;
}
fn zstd_decoder_reset(c) {if !c {return -1;}store64(c,0);store64(c+16,0);store64(c+24,0);store64(c+32,4);store64(c+128,0);store64(c+136,0);store64(c+1600,0);store64(c+1616,131072);store64(c+1640,0);return 1;}
fn zstd_decoder_close(c) {if !c {return 0;}fz_native_close(c);if load64(c+48) {syscall(11,load64(c+48),load64(c+1648),0,0,0,0);}syscall(11,c,442624,0,0,0,0);return 1;}
fn fz_seq_table(c,p,n,off,kind,mode) {
 let table=c+4096;let maxsym=35;let maxbits=9;let log=6;
 if kind==1 {table=c+8192;maxsym=31;maxbits=8;log=5;}else if kind==2 {table=c+10240;maxsym=52;}
 let bases=c+512;if kind==1 {bases=c+1224;}else if kind==2 {bases=c+800;}
 if mode==0 {if kind==0 {fz_ll_default(table);}else if kind==1 {fz_of_default(table);}else {fz_ml_default(table);}}
 else if mode==1 {if off>=n || load8(p+off)>maxsym {return fz_fail(c,"invalid sequence RLE symbol");}store64(table,load8(p+off));off=off+1;log=0;}
 else if mode==2 {log=fz_fse_core(c,p,n,off,maxsym,maxbits,table,bases);if log<0 {return -1;}off=load64(c+304);store64(c+176+kind*8,log);return off;}
 else {if load64(c+176+kind*8)<0 {return fz_fail(c,"sequence repeat before table");}return off;}
 // Bake length baselines and bit counts into each state: baseline:32,
 // extra bits:5, state bits:8, state base:9. Repeat mode reuses this table.

 let i=0;while i<(1<<log) {let e=load64(table+i*8);let b=load64(bases+(e&255)*8);store64(table+i*8,b|(((e>>8)&255)<<37)|((e>>16)<<45));i=i+1;}
 store64(c+176+kind*8,log);return off;
}
fn fz_match(c,out,pos,offset,n) {
 if load64(c+1640) {
  if offset<=0 || offset>load64(c+56) || offset>load64(c+1608)+pos || pos+n>load64(c+1616) {return fz_fail(c,"match outside complete-frame output");}
  let source=load64(c+1584)+load64(c+1608)+pos-offset;let available=offset;let left=n;
  while left {let count=fz_min(left,available);fz_copy(out+pos,source,count);pos=pos+count;left=left-count;available=available+count;}return pos;
 }
 if offset<=0 || offset>load64(c+56) || offset>pos+load64(c+72) {return fz_fail(c,"match offset outside history");}
 if pos+n>131072 {return fz_fail(c,"match exceeds block size");}
 let left=n;
 if offset>pos {
  let count=fz_min(offset-pos,left);let cap=load64(c+1648);let src=load64(c+64)-(offset-pos);if src<0 {src=src+cap;}let first=fz_min(count,cap-src);
  fz_copy(out+pos,load64(c+48)+src,first);if count>first {fz_copy(out+pos+first,load64(c+48),count-first);}pos=pos+count;left=left-count;
 }
 // Expand periodic matches geometrically. Every chunk reads only bytes
 // already produced, and source/destination chunks never overlap.
 let source=pos-offset;let available=offset;
 while left {let count=fz_min(left,available);fz_copy(out+pos,out+source,count);pos=pos+count;left=left-count;available=available+count;}return pos;
}
fn fz_compressed(c,p,n) {
 let off=fz_literals(c,p,n);if off<0 {return -1;}let litlen=load64(c+216);let lits=c+172288;let out=load64(c+1600);if !out {out=c+303360;}let limit=load64(c+1616);
 if off>=n {return fz_fail(c,"missing sequence count");}let count=load8(p+off);off=off+1;
 if count==0 {if off!=n || litlen>limit {return fz_fail(c,"invalid zero-sequence literals");}fz_copy(out,lits,litlen);return litlen;}
 if count==255 {if off+2>n {return fz_fail(c,"truncated sequence count");}count=fz_u16(p+off)+32512;off=off+2;}else if count>=128 {if off>=n {return fz_fail(c,"truncated sequence count");}count=((count-128)<<8)+load8(p+off);off=off+1;}
 if off>=n {return fz_fail(c,"missing sequence modes");}let modes=load8(p+off);off=off+1;if modes&3 {return fz_fail(c,"reserved sequence mode bits");}
 off=fz_seq_table(c,p,n,off,0,(modes>>6)&3);if off<0 {return -1;}
 off=fz_seq_table(c,p,n,off,1,(modes>>4)&3);if off<0 {return -1;}
 off=fz_seq_table(c,p,n,off,2,(modes>>2)&3);if off<0 {return -1;}
 // Wide bit peeks may read up to seven bytes past the compressed block.
 // p is owned padded scratch or a borrowed span with seven readable bytes;
 // masked bits never depend on that padding. All logical bit bounds are checked.
 if n<=off || !load8(p+n-1) {return fz_fail(c,"invalid sequence bitstream");}
 let bitpos=(n-off-1)*8+fz_log(load8(p+n-1));let bits=load64(c+176);bitpos=bitpos-bits;if bitpos<0 {return fz_fail(c,"truncated sequence states");}
 let ls=(load64(p+off+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1);
 bits=load64(c+184);bitpos=bitpos-bits;if bitpos<0 {return fz_fail(c,"truncated sequence states");}
 let os=(load64(p+off+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1);
 bits=load64(c+192);bitpos=bitpos-bits;if bitpos<0 {return fz_fail(c,"truncated sequence states");}
 let ms=(load64(p+off+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1);
 let pos=0;let lp=0;let seq=0;let r1=load64(c+144);let r2=load64(c+152);let r3=load64(c+160);let window=load64(c+56);let history=load64(c+72);let direct=load64(c+1640);if direct {history=load64(c+1608);}let history_base=load64(c+1584);let ring=load64(c+48);let ring_pos=load64(c+64);let ring_cap=load64(c+1648);
 let native_seq=load64(c+1768);if count<2048 && load64(c+344) {native_seq=load64(c+344);}
 store64(c+1624,history>=window);store64(c+1632,history-out);store64(c+1656,lits+litlen);
 while seq<count {
 let fast=0;if seq+1<count && bitpos>=64 && native_seq {
  store64(c+1664,ls);store64(c+1672,os);store64(c+1680,ms);store64(c+1688,bitpos);store64(c+1696,count-seq);store64(c+1704,pos);store64(c+1712,lp);store64(c+1720,p+off);store64(c+1728,out);store64(c+1736,lits);store64(c+1744,litlen);store64(c+1752,out+limit);store64(c+144,r1);store64(c+152,r2);store64(c+160,r3);
  fast=native_call1(native_seq,c);if fast<0 {return fz_fail(c,"native sequence rejected");}if fast {ls=load64(c+1664);os=load64(c+1672);ms=load64(c+1680);bitpos=load64(c+1688);pos=load64(c+1704);lp=load64(c+1712);r1=load64(c+144);r2=load64(c+152);r3=load64(c+160);seq=seq+fast;}
 }
 if !fast {

  let le=load64(c+4096+ls*8);let oe=load64(c+8192+os*8);let me=load64(c+10240+ms*8);
  let offset=oe&0xffffffff;let match=me&0xffffffff;let literal=le&0xffffffff;
  let ob=(oe>>32)&31;let mb=(me>>32)&31;let lb=(le>>32)&31;
  let lstate=(le>>37)&255;let mstate=(me>>37)&255;let ostate=(oe>>37)&255;
  let needed=ob+mb+lb;if seq+1<count {needed=needed+lstate+mstate+ostate;}
  if needed<=56 && bitpos>=64 {
   let ready=56+(bitpos&7);if (bitpos&7)==0 {ready=64;}let word=load64(p+off+((bitpos+7)>>3)-8);
   if ob {ready=ready-ob;offset=offset+((word>>ready)&load64(c+2048+ob*8));}
   if mb {ready=ready-mb;match=match+((word>>ready)&load64(c+2048+mb*8));}
   if lb {ready=ready-lb;literal=literal+((word>>ready)&load64(c+2048+lb*8));}
   if seq+1<count {
    ready=ready-lstate;ls=(le>>45)+((word>>ready)&load64(c+2048+lstate*8));
    ready=ready-mstate;ms=(me>>45)+((word>>ready)&load64(c+2048+mstate*8));
    ready=ready-ostate;os=(oe>>45)+((word>>ready)&load64(c+2048+ostate*8));
   }bitpos=bitpos-needed;
  }else {
  bits=(oe>>32)&31;bitpos=bitpos-bits;if bitpos<0 {return fz_fail(c,"short offset bits");}offset=(oe&0xffffffff)+((load64(p+off+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1));
  bits=(me>>32)&31;bitpos=bitpos-bits;if bitpos<0 {return fz_fail(c,"short match bits");}match=(me&0xffffffff)+((load64(p+off+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1));
  bits=(le>>32)&31;bitpos=bitpos-bits;if bitpos<0 {return fz_fail(c,"short literal bits");}literal=(le&0xffffffff)+((load64(p+off+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1));
  if seq+1<count {
   bits=(le>>37)&255;bitpos=bitpos-bits;if bitpos<0 {return fz_fail(c,"short literal state");}ls=(le>>45)+((load64(p+off+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1));
   bits=(me>>37)&255;bitpos=bitpos-bits;if bitpos<0 {return fz_fail(c,"short match state");}ms=(me>>45)+((load64(p+off+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1));
   bits=(oe>>37)&255;bitpos=bitpos-bits;if bitpos<0 {return fz_fail(c,"short offset state");}os=(oe>>45)+((load64(p+off+(bitpos>>3))>>(bitpos&7))&((1<<bits)-1));
  }
  }
  if ((oe>>32)&31)>1 {r3=r2;r2=r1;r1=offset;}
  else {
   if literal==0 {offset=offset+1;}
   if offset==1 {offset=r1;}
   else if offset==2 {offset=r2;r2=r1;r1=offset;}
   else if offset==3 {offset=r3;r3=r2;r2=r1;r1=offset;}
   else if offset==4 {offset=r1-1;r3=r2;r2=r1;r1=offset;}
  }
  seq=seq+1;
  if literal>litlen-lp || pos+literal+match>limit {return fz_fail(c,"sequence literal overflow");}
  if literal {fz_copy(out+pos,lits+lp,literal);pos=pos+literal;lp=lp+literal;}
  if offset<=0 || offset>window || offset>pos+history {return fz_fail(c,"match offset outside history");}let left=match;
  if offset>pos {
   let count=offset-pos;if count>left {count=left;}
   if direct {fz_copy(out+pos,history_base+history+pos-offset,count);}else {let from=ring_pos-(offset-pos);if from<0 {from=from+ring_cap;}let first=ring_cap-from;if first>count {first=count;}fz_copy(out+pos,ring+from,first);if count>first {fz_copy(out+pos+first,ring,count-first);}}
   pos=pos+count;left=left-count;
  }
  let from=out+pos-offset;let available=offset;
  while left {let count=left;if count>available {count=available;}fz_copy(out+pos,from,count);pos=pos+count;left=left-count;available=available+count;}
 }
 }
 if pos+litlen-lp>limit || bitpos!=0 {return fz_fail(c,"invalid sequence stream ending");}
 store64(c+144,r1);store64(c+152,r2);store64(c+160,r3);if litlen>lp {fz_copy(out+pos,lits+lp,litlen-lp);}return pos+litlen-lp;
}
// The extra block of physical capacity is a free gap after the logical window.
// Direct block output and bounded wide stores must stay within that gap;
// advancing by the exact decoded size preserves the gap after short blocks too.
fn fz_history_commit(c,n) {
 let cap=load64(c+1648);let next=load64(c+64)+n;if next>=cap {next=next-cap;}store64(c+64,next);store64(c+72,fz_min(load64(c+56),load64(c+72)+n));return 1;
}
fn fz_history(c,p,n) {
 let cap=load64(c+1648);if !cap || !n {return 1;}let pos=load64(c+64);let first=fz_min(n,cap-pos);fz_copy(load64(c+48)+pos,p,first);fz_copy(load64(c+48),p+first,n-first);return fz_history_commit(c,n);
}
fn fz_frame(c) {
 let p=c+41100;let d=load8(p);let single=(d>>5)&1;let dict=d&3;let ds=0;if dict {ds=1<<(dict-1);}
 let fs=1<<(d>>6);if fs==1 && !single {fs=0;}let off=1;let window=0;
 if !single {let w=load8(p+off);off=off+1;let log=(w>>3)+10;if log>30 {return fz_fail(c,"window exceeds decoder limit");}window=(1<<log)+((1<<log)>>3)*(w&7);}
 let id=0;let i=0;while i<ds {id=id|(load8(p+off+i)<<(i*8));i=i+1;}off=off+ds;if id {return fz_fail(c,"Zstd dictionaries are not supported");}
 let size=-1;if fs {size=0;i=0;while i<fs {size=size|(load8(p+off+i)<<(i*8));i=i+1;}if size<0 {return fz_fail(c,"frame size exceeds signed 64-bit limit");}if fs==2 {size=size+256;}}
 if single {window=size;}if window>load64(c+8) {return fz_fail(c,"window exceeds decoder limit");}
 if load64(c+1640) {if load64(c+48) {syscall(11,load64(c+48),load64(c+1648),0,0,0,0);store64(c+48,0);}store64(c+1648,0);store64(c+56,window);}
 else if window!=load64(c+56) || (window && !load64(c+48)) {if load64(c+48) {syscall(11,load64(c+48),load64(c+1648),0,0,0,0);}store64(c+48,0);store64(c+56,window);store64(c+1648,0);if window {let physical=window+131072;let w=alloc(physical);if w<=0 {return fz_fail(c,"history allocation failed");}store64(c+48,w);store64(c+1648,physical);}}
 store64(c+64,0);store64(c+72,0);store64(c+80,size);store64(c+88,0);store64(c+96,d&4);store64(c+144,1);store64(c+152,4);store64(c+160,8);store64(c+168,0);store64(c+176,-1);store64(c+184,-1);store64(c+192,-1);fz_xreset(c+384);return 1;
}
// Input and output each point to {data, capacity/size, position}, three words.
// Return 0 at one completed frame, 1 when more input/output is needed, -1 on
// sticky error. A frame boundary never consumes bytes of the following frame.
fn zstd_decode(c,out,input) {
 if !c || load64(c) {return -1;}
 if load64(input+16)<0 || load64(input+16)>load64(input+8) || load64(out+16)<0 || load64(out+16)>load64(out+8) {return fz_fail(c,"invalid stream buffer positions");}
 while 1 {
  let stage=load64(c+16);
  if stage==5 {
   let left=load64(c+128)-load64(c+136);let take=fz_min(left,load64(out+8)-load64(out+16));
   if take {fz_copy(load64(out)+load64(out+16),load64(c+1600)+load64(c+136),take);store64(out+16,load64(out+16)+take);store64(c+136,load64(c+136)+take);}
   if take<left {return 1;}
   if load64(c+104) {if load64(c+96) {store64(c+16,6);store64(c+32,4);store64(c+24,0);}else {store64(c+16,0);store64(c+32,4);store64(c+24,0);return 0;}}
   else {store64(c+16,3);store64(c+32,3);store64(c+24,0);}
  }else if stage==8 {
   let take=fz_min(load64(c+32),load64(input+8)-load64(input+16));store64(input+16,load64(input+16)+take);store64(c+32,load64(c+32)-take);
   if load64(c+32) {return 1;}store64(c+16,0);store64(c+32,4);store64(c+24,0);return 0;
  }else {
   let dest=c+41100;if stage==4 {dest=c+41216;}
   let need=load64(c+32);let have=load64(c+24);let take=fz_min(need-have,load64(input+8)-load64(input+16));
   // Borrow an entire contiguous block only when seven readable padding bytes
   // remain in this input span. Kernels never retain its pointer after stage 4.
   // A split block or the final unpadded span still uses owned block scratch.
   if stage==4 && !have && take==need && load64(input+8)-load64(input+16)-take>=7 {dest=load64(input)+load64(input+16);store64(input+16,load64(input+16)+take);have=need;store64(c+24,have);}else if take {fz_copy(dest+have,load64(input)+load64(input+16),take);store64(input+16,load64(input+16)+take);have=have+take;store64(c+24,have);}
   if have<need {return 1;}
   if stage==0 {
    let magic=fz_u32(dest);if magic==0xfd2fb528 {store64(c+16,1);store64(c+32,1);store64(c+24,0);}else if (magic&0xfffffff0)==0x184d2a50 {store64(c+16,7);store64(c+32,4);store64(c+24,0);}else {return fz_fail(c,"invalid Zstd magic");}
   }else if stage==1 {
    let d=load8(dest);if d&8 {return fz_fail(c,"reserved frame descriptor bit");}let single=(d>>5)&1;let ds=0;if d&3 {ds=1<<((d&3)-1);}let fs=1<<(d>>6);if fs==1 && !single {fs=0;}
    store64(c+16,2);store64(c+32,1+(1-single)+ds+fs);
   }else if stage==2 {
    if fz_frame(c)<0 {return -1;}store64(c+16,3);store64(c+32,3);store64(c+24,0);
   }else if stage==3 {
    let h=fz_u24(dest);let kind=(h>>1)&3;let size=h>>3;
    if kind==3 || size>131072 || size>load64(c+56) {return fz_fail(c,"invalid block header");}
    store64(c+104,h&1);store64(c+112,kind);store64(c+120,size);store64(c+16,4);store64(c+24,0);if kind==1 {store64(c+32,1);}else {store64(c+32,size);}
   }else if stage==4 {
    let size=load64(c+120);let kind=load64(c+112);let output=c+303360;let direct_ring=0;let room=fz_min(131072,load64(c+56));if load64(c+48) && load64(c+1648)-load64(c+64)>=room {output=load64(c+48)+load64(c+64);direct_ring=1;}store64(c+1600,output);store64(c+1616,131072);if direct_ring {store64(c+1616,room);store64(c+1584,load64(c+48));}else {store64(c+1584,output);}
    if kind==0 {fz_copy(output,dest,size);}else if kind==1 {fz_fill(output,load8(dest),size);}else {size=fz_compressed(c,dest,size);if size<0 {return -1;}}
    if size>load64(c+56) {return fz_fail(c,"decoded block exceeds window");}
    let total=load64(c+88)+size;let expected=load64(c+80);if total<0 || (expected>=0 && (total>expected || (load64(c+104) && total!=expected))) {return fz_fail(c,"frame content size mismatch");}
    store64(c+88,total);if load64(c+96) {fz_xupdate(c+384,output,size);}if !load64(c+104) {if direct_ring {fz_history_commit(c,size);}else {fz_history(c,output,size);}}
    store64(c+128,size);store64(c+136,0);store64(c+16,5);
   }else if stage==6 {
    if fz_u32(dest)!=(fz_xdigest(c+384)&0xffffffff) {return fz_fail(c,"Zstd checksum mismatch");}
    store64(c+16,0);store64(c+32,4);store64(c+24,0);return 0;
   }else if stage==7 {store64(c+16,8);store64(c+32,fz_u32(dest));store64(c+24,0);}
   else {return fz_fail(c,"invalid decoder state");}
  }
 }
 return -1;
}
// Complete-buffer path decodes directly into caller output. Previous blocks
// already form a contiguous history window, so neither a separate ring nor
// per-block input/output copies are needed. Streaming keeps its bounded ring.
fn zstd_decompress(c,dst,capacity,src,n) {
 if !c {return -1;}zstd_decoder_reset(c);if n<=0 || capacity<0 {return fz_fail(c,"invalid complete-frame buffers");}store64(c+1640,1);
 let at=0;let total=0;
 while at<n {
  if n-at<4 {return fz_fail(c,"truncated frame magic");}let magic=fz_u32(src+at);at=at+4;
  if (magic&0xfffffff0)==0x184d2a50 {if n-at<4 {return fz_fail(c,"truncated skippable size");}let size=fz_u32(src+at);at=at+4;if size>n-at {return fz_fail(c,"truncated skippable frame");}at=at+size;}
  else {
   if magic!=0xfd2fb528 || at>=n {return fz_fail(c,"invalid complete-frame magic");}let descriptor=load8(src+at);if descriptor&8 {return fz_fail(c,"reserved frame descriptor bit");}
   let single=(descriptor>>5)&1;let ds=0;if descriptor&3 {ds=1<<((descriptor&3)-1);}let fs=1<<(descriptor>>6);if fs==1 && !single {fs=0;}let header=1+(1-single)+ds+fs;
   if header>n-at {return fz_fail(c,"truncated frame header");}fz_copy(c+41100,src+at,header);at=at+header;if fz_frame(c)<0 {return -1;}
   let base=total;store64(c+1584,dst+base);let last=0;
   while !last {
    if n-at<3 {return fz_fail(c,"truncated block header");}let block=fz_u24(src+at);at=at+3;last=block&1;let kind=(block>>1)&3;let size=block>>3;let payload=size;if kind==1 {payload=1;}
    if kind==3 || size>131072 || size>load64(c+56) || payload>n-at {return fz_fail(c,"invalid complete block bounds");}
    let remaining=capacity-total;let output=dst+total;store64(c+1600,output);store64(c+1608,total-base);store64(c+1616,fz_min(remaining,131072));
    if kind==0 {if size>remaining {return fz_fail(c,"insufficient output capacity");}fz_copy(output,src+at,size);}
    else if kind==1 {if size>remaining {return fz_fail(c,"insufficient output capacity");}fz_fill(output,load8(src+at),size);}
    else {let input=src+at;
     // The bit peeks need seven accessible padding bytes. Usually these are
     // subsequent block bytes; the final short tail uses our owned scratch.
     if n-at-payload<7 {fz_copy(c+41216,input,payload);input=c+41216;}
     size=fz_compressed(c,input,payload);if size<0 {return -1;}
    }
    at=at+payload;if size>load64(c+56) {return fz_fail(c,"decoded block exceeds window");}total=total+size;let produced=total-base;let expected=load64(c+80);
    if produced<0 || (expected>=0 && produced>expected) {return fz_fail(c,"frame content size mismatch");}store64(c+88,produced);if load64(c+96) {fz_xupdate(c+384,output,size);}
   }
   if load64(c+80)>=0 && total-base!=load64(c+80) {return fz_fail(c,"frame content size mismatch");}
   if load64(c+96) {if n-at<4 || fz_u32(src+at)!=(fz_xdigest(c+384)&0xffffffff) {return fz_fail(c,"Zstd checksum mismatch");}at=at+4;}
  }
 }
 // Leave a fresh streaming boundary; preserve any error until explicit reset.
 store64(c+1640,0);store64(c+1600,0);store64(c+1616,131072);return total;
}
