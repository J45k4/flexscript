// Native fast Zstd encoder: eight-byte LZ hashing, repeated offsets, adaptive
// FSE and Huffman literals. Raw/RLE fallback guarantees bounded expansion.
// Encoder context owns 2424832 bytes, reusable across independent frames.
// 0 error; 8 bit reservoir; 16 bit count; 24 output pointer; 32 byte count;
// 40 output capacity. Default tables at +4096/+8192/+10240.
// Inverse transitions +16384 LL (36*64), +34816 OF (32*32),
// +43008 ML (53*64). Hash +73728 (65536 u32), literals +598016,
// sequences +729088 (32768 * 16), compressed scratch +1777664 (262144).
// Each sequence stores u32 LL/ML/encoded offset and three byte-sized codes.
// Fingerprinted 1024-entry hash +2404096; total reservation 2424832 bytes.
fn zstd_compress_bound(n) {if n<0 || n>2147483647 {return -1;}return n+((n+131071)/131072)*3+16;}
fn fz_inverse(table,inv,log) {
 let size=1<<log;let i=0;while i<size {let e=load64(table+i*8);let sym=e&255;let bits=(e>>8)&255;let base=e>>16;let j=0;while j<(1<<bits) {store64(inv+(sym*size+base+j)*8,i|(bits<<8)|(j<<16));j=j+1;}i=i+1;}return 1;
}
fn zstd_encoder_open() {
 let c=alloc(2424832);if c<=0 {return 0;}fz_baselines(c);fz_ll_default(c+4096);fz_of_default(c+8192);fz_ml_default(c+10240);fz_inverse(c+4096,c+16384,6);fz_inverse(c+8192,c+34816,5);fz_inverse(c+10240,c+43008,6);fz_weight_default(c);fz_model_defaults(c);let i=0;while i<256 {store8(c+2300000+i,fz_ll_code(i));if i>=3 {store8(c+2300256+i,fz_ml_code(i));}i=i+1;}fz_native_open(c);return c;
}
fn zstd_encoder_close(c) {if !c {return 0;}fz_native_close(c);syscall(11,c,2424832,0,0,0,0);return 1;}
fn fz_wbits(c,v,n) {
 if n<0 || n>31 {return fz_fail(c,"invalid encoder bit count");}
 let bits=load64(c+8)|((v&((1<<n)-1))<<load64(c+16));let count=load64(c+16)+n;let pos=load64(c+32);
 while count>=8 {if pos>=load64(c+40) {return fz_fail(c,"encoder scratch overflow");}store8(load64(c+24)+pos,bits);pos=pos+1;bits=bits>>8;count=count-8;}
 store64(c+8,bits);store64(c+16,count);store64(c+32,pos);return 1;
}
fn fz_wfinish(c) {if fz_wbits(c,1,1)<0 {return -1;}let pos=load64(c+32);if load64(c+16) {if pos>=load64(c+40) {return fz_fail(c,"encoder scratch overflow");}store8(load64(c+24)+pos,load64(c+8));pos=pos+1;}return pos;}
fn fz_ll_code(n) {if n<16 {return n;}if n<24 {return 16+(n-16)/2;}if n<32 {return 20+(n-24)/4;}if n<48 {return 22+(n-32)/8;}if n<64 {return 24+(n-48)/16;}return fz_log(n)+19;}
fn fz_ml_code(n) {if n<35 {return n-3;}if n<43 {return 32+(n-35)/2;}if n<51 {return 36+(n-43)/4;}if n<67 {return 38+(n-51)/8;}if n<99 {return 40+(n-67)/16;}if n<131 {return 42+(n-99)/32;}return fz_log(n-3)+36;}
fn fz_first(table,size,sym) {let i=0;while i<size {if (load64(table+i*8)&255)==sym {return i;}i=i+1;}return -1;}
// Sequence bitstreams are assembled in local registers and flushed four bytes
// at a time. The reservoir stays below 64 bits, including worst-case extras.
fn fz_seq_bits(c,seqs,count,out,capacity) {
 let i=count-1;let seq=seqs+i*16;let code=bytes_load32(seq+12);
 let llog=load64(c+200);let olog=load64(c+208);let mlog=load64(c+216);let linverse=load64(c+224);let oinverse=load64(c+232);let minverse=load64(c+240);
 let ls=fz_first(load64(c+256),1<<llog,code&255);let ms=fz_first(load64(c+272),1<<mlog,(code>>8)&255);let os=fz_first(load64(c+264),1<<olog,(code>>16)&255);
 // A sequence has at most 17 LL + 17 ML + 23 OF extra bits and
 // three six-bit state updates: <=75 bits. Final states/stop fit in 16
 // more bytes. Preflight this bound once; otherwise retain checked fallback.
 if load64(c+1800) && capacity>=count*10+16 {store64(c+1808,seqs);store64(c+1816,count);store64(c+1824,out);store64(c+1832,capacity);store64(c+1840,ls);store64(c+1848,os);store64(c+1856,ms);let result=native_call1(load64(c+1800),c);if result<0 {return fz_fail(c,"native sequence encoding overflow");}return result;}
 let acc=0;let nbits=0;let written=0;
 while i>=0 {
  seq=seqs+i*16;code=bytes_load32(seq+12);let lb=load64(c+512+(code&255)*8);let mb=load64(c+800+((code>>8)&255)*8);let oc=(code>>16)&255;
  acc=acc|((bytes_load32(seq)-(lb&0xffffffff))<<nbits);nbits=nbits+(lb>>32);
  acc=acc|((bytes_load32(seq+4)-(mb&0xffffffff))<<nbits);nbits=nbits+(mb>>32);
  if nbits>=32 {if written+4>capacity {return fz_fail(c,"encoder scratch overflow");}bytes_store32(out+written,acc);written=written+4;acc=(acc>>32)&0xffffffff;nbits=nbits-32;}
  acc=acc|((bytes_load32(seq+8)-(1<<oc))<<nbits);nbits=nbits+oc;
  if nbits>=32 {if written+4>capacity {return fz_fail(c,"encoder scratch overflow");}bytes_store32(out+written,acc);written=written+4;acc=(acc>>32)&0xffffffff;nbits=nbits-32;}
  i=i-1;
  if i>=0 {
   seq=seqs+i*16;code=bytes_load32(seq+12);let oe=load64(oinverse+(((code>>16)&255)*64+os)*8);let me=load64(minverse+(((code>>8)&255)*64+ms)*8);let le=load64(linverse+((code&255)*64+ls)*8);
   acc=acc|((oe>>16)<<nbits);nbits=nbits+((oe>>8)&255);acc=acc|((me>>16)<<nbits);nbits=nbits+((me>>8)&255);acc=acc|((le>>16)<<nbits);nbits=nbits+((le>>8)&255);
   if nbits>=32 {if written+4>capacity {return fz_fail(c,"encoder scratch overflow");}bytes_store32(out+written,acc);written=written+4;acc=(acc>>32)&0xffffffff;nbits=nbits-32;}
   os=oe&255;ms=me&255;ls=le&255;
  }
 }
 acc=acc|(ms<<nbits);nbits=nbits+mlog;acc=acc|(os<<nbits);nbits=nbits+olog;acc=acc|(ls<<nbits);nbits=nbits+llog;
 if nbits>=32 {if written+4>capacity {return fz_fail(c,"encoder scratch overflow");}bytes_store32(out+written,acc);written=written+4;acc=(acc>>32)&0xffffffff;nbits=nbits-32;}
 acc=acc|(1<<nbits);nbits=nbits+1;while nbits>0 {if written>=capacity {return fz_fail(c,"encoder scratch overflow");}store8(out+written,acc);written=written+1;acc=acc>>8;nbits=nbits-8;}
 return written;
}
fn fz_hash(p) {return (((load64(p))*0x1e35a7bd1e35a7bd)>>54)&1023;}
fn fz_encode_block(c,src,start,n,window,out) {
 let pos=start;let end=start+n;let anchor=start;let literals=c+598016;let litbytes=0;let sequences=c+729088;let count=0;let hash=c+2404096;let r1=load64(c+144);let r2=load64(c+152);let r3=load64(c+160);let first_offset=0;fz_fill(c+399360,0,1536);
 if load64(c+1864) {store64(c+1888,src);store64(c+1896,start);store64(c+1904,n);store64(c+1912,window);count=native_call1(load64(c+1864),c);anchor=load64(c+1928);litbytes=load64(c+1936);first_offset=load64(c+1944);r1=load64(c+144);r2=load64(c+152);r3=load64(c+160);}else {
 while pos+8<=end {
  let prev=-1;let minimum=4;let repeated=0;
  if r1>0 && pos+1>=r1 && bytes_load32(src+pos+1-r1)==bytes_load32(src+pos+1) {pos=pos+1;prev=pos-r1;minimum=4;repeated=1;}
  else {let word=load64(src+pos);let h=((word*0x1e35a7bd1e35a7bd)>>54)&1023;let entry=load64(hash+h*8);prev=(entry&0xffffffff)-1;store64(hash+h*8,((word&0xffffffff)<<32)|(pos+1));if prev<0 || pos-prev>window || ((entry>>32)&0xffffffff)!=(word&0xffffffff) {prev=-1;}}
  if prev>=0 {
   let limit=anchor;if repeated {limit=anchor+1;}while pos>limit && prev>0 && load8(src+pos-1)==load8(src+prev-1) {pos=pos-1;prev=prev-1;minimum=minimum+1;}
   let len=minimum+bytes_common_prefix(src+prev+minimum,src+pos+minimum,end-pos-minimum);
   let ll=pos-anchor;fz_copy(literals+litbytes,src+anchor,ll);litbytes=litbytes+ll;
   let distance=pos-prev;if !count {first_offset=distance;}let value=distance+3;
   if ll && distance==r1 {value=1;}else if distance==r2 {if ll {value=2;}else {value=1;}r2=r1;r1=distance;}else if distance==r3 {if ll {value=3;}else {value=2;}r3=r2;r2=r1;r1=distance;}else if !ll && distance==r1-1 {value=3;r3=r2;r2=r1;r1=distance;}else {r3=r2;r2=r1;r1=distance;}
   let lc=0;let mc=0;if ll<256 {lc=load8(c+2300000+ll);}else {lc=fz_ll_code(ll);}if len<256 {mc=load8(c+2300256+len);}else {mc=fz_ml_code(len);}let oc=fz_log(value);
   bytes_store32(sequences+count*16,ll);bytes_store32(sequences+count*16+4,len);bytes_store32(sequences+count*16+8,value);bytes_store32(sequences+count*16+12,lc|(mc<<8)|(oc<<16));count=count+1;store64(c+399360+lc*8,load64(c+399360+lc*8)+1);store64(c+399872+oc*8,load64(c+399872+oc*8)+1);store64(c+400384+mc*8,load64(c+400384+mc*8)+1);
   pos=pos+len;anchor=pos;
   if pos>=2 && pos+6<=end {store64(hash+((((load64(src+pos-2))*0x1e35a7bd1e35a7bd)>>54)&1023)*8,((load64(src+pos-2)&0xffffffff)<<32)|(pos-1));}if pos>=1 && pos+7<=end {store64(hash+((((load64(src+pos-1))*0x1e35a7bd1e35a7bd)>>54)&1023)*8,((load64(src+pos-1)&0xffffffff)<<32)|pos);}
  }else {pos=pos+((pos-anchor)>>6)+2;}
 }
 }
 store64(c+144,r1);store64(c+152,r2);store64(c+160,r3);
 if !count {store64(c+48,0);return n;}
 fz_copy(literals+litbytes,src+anchor,end-anchor);litbytes=litbytes+end-anchor;
 let at=fz_huff_encode(c,literals,litbytes,out);if at<0 {at=0;if litbytes<32 {store8(out,litbytes<<3);at=1;}else if litbytes<4096 {fz_le(out,(litbytes<<4)|4,2);at=2;}else {fz_le(out,(litbytes<<4)|12,3);at=3;}
 fz_copy(out+at,literals,litbytes);at=at+litbytes;}
 if count<128 {store8(out+at,count);at=at+1;}else if count<32512 {store8(out+at,(count>>8)+128);store8(out+at+1,count);at=at+2;}else {store8(out+at,255);fz_le(out+at+1,count-32512,2);at=at+3;}
 if count {if fz_sequence_models(c,sequences,count)<0 {return -1;}store8(out+at,load64(c+312));at=at+1;let kind=0;while kind<3 {let bytes=load64(c+288+kind*8);fz_copy(out+at,c+401920+kind*128,bytes);at=at+bytes;kind=kind+1;}let bits=fz_seq_bits(c,sequences,count,out+at,262144-at);if bits<0 {return -1;}at=at+bits;}
 // RLE whole-block optimization, detected without a second input scan.
 if count==1 && litbytes==1 && bytes_load32(sequences)==1 && bytes_load32(sequences+4)==n-1 && first_offset==1 {store64(c+48,1);store8(out,load8(src+start));return 1;}
 store64(c+48,2);return at;
}
// One-shot encoder, independent frames. Initial fast strategy has no levels.
// Returns encoded byte count or -1; dst_capacity must be >= compress_bound.
fn zstd_compress(c,dst,dst_capacity,src,n) {
 if !c {return -1;}store64(c,0);let bound=zstd_compress_bound(n);if bound<0 || dst_capacity<bound {return fz_fail(c,"compression output buffer too small");}
 store64(c+144,1);store64(c+152,4);store64(c+160,8);store64(c+320,0);fz_fill(c+2404096,0,8192);fz_le(dst,0xfd2fb528,4);store8(dst+4,128);let log=17;while log<23 && (1<<log)<n {log=log+1;}store8(dst+5,(log-10)<<3);fz_le(dst+6,n,4);
 let offset=0;let written=10;let more=1;
 while more {
  let size=fz_min(n-offset,131072);let last=offset+size==n;let old1=load64(c+144);let old2=load64(c+152);let old3=load64(c+160);let encoded=fz_encode_block(c,src,offset,size,1<<log,c+1777664);if encoded<0 {return -1;}
  let kind=load64(c+48);let payload=encoded;if encoded>=size {kind=0;payload=size;}if kind!=2 {store64(c+320,0);store64(c+144,old1);store64(c+152,old2);store64(c+160,old3);}
  let header=(payload<<3)|(kind<<1)|last;if kind==1 {header=(size<<3)|2|last;}
  fz_le(dst+written,header,3);written=written+3;if kind==0 {fz_copy(dst+written,src+offset,size);}else {fz_copy(dst+written,c+1777664,payload);}written=written+payload;
  offset=offset+size;if last {more=0;}
 }
 return written;
}
