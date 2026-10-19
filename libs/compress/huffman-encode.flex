// Adaptive canonical Huffman literal encoding, length-limited to eleven bits.
// Workspace is inside the reusable encoder context; no per-block allocation.
// Histogram +2240000; ranked leaves +2242048; tree nodes +2244096;
// radix buffer / depth counts +2252288; lengths +2256384;
// reserved +2258560; codes +2258688; weights +2260736;
// weight FSE table +2263000; inverse +2264064; stream scratch +2048000.
fn fz_weight_default(c) {
 store64(c+2263000+0,768);
 store64(c+2263000+8,769);
 store64(c+2263000+16,771);
 store64(c+2263000+24,773);
 store64(c+2263000+32,1288);
 store64(c+2263000+40,525056);
 store64(c+2263000+48,770);
 store64(c+2263000+56,772);
 store64(c+2263000+64,1030);
 store64(c+2263000+72,1291);
 store64(c+2263000+80,525057);
 store64(c+2263000+88,525059);
 store64(c+2263000+96,525061);
 store64(c+2263000+104,1031);
 store64(c+2263000+112,1049344);
 store64(c+2263000+120,525058);
 store64(c+2263000+128,525060);
 store64(c+2263000+136,1049349);
 store64(c+2263000+144,1290);
 store64(c+2263000+152,1049345);
 store64(c+2263000+160,1049347);
 store64(c+2263000+168,1049348);
 store64(c+2263000+176,1049607);
 store64(c+2263000+184,1573632);
 store64(c+2263000+192,1049346);
 store64(c+2263000+200,1573635);
 store64(c+2263000+208,1573637);
 store64(c+2263000+216,1289);
 store64(c+2263000+224,1573633);
 store64(c+2263000+232,1573634);
 store64(c+2263000+240,1573636);
 store64(c+2263000+248,1049606);
 fz_inverse(c+2263000,c+2264064,5);return 1;
}
fn fz_weight_header(out) {
 store8(out+0,80);
 store8(out+1,74);
 store8(out+2,85);
 store8(out+3,213);
 store8(out+4,38);
 store8(out+5,29);
 return 6;
}
fn fz_huff_lengths(c) {
 let hist=c+2240000;let rank=c+2242048;let nodes=c+2244096;let lengths=c+2256384;let counts=c+2252288;let i=0;
 // Sort leaves by integer frequency with stable byte radix passes, then
 // merge two sorted queues. This avoids hundreds of heap calls per block.
 let symbols=0;let highest=0;let maximum_frequency=0;i=0;
 while i<256 {let frequency=load64(hist+i*8);if frequency {store64(nodes+i*16,frequency);store64(nodes+i*16+8,-1);store64(rank+symbols*8,i);symbols=symbols+1;highest=i;if frequency>maximum_frequency {maximum_frequency=frequency;}}i=i+1;}
 store64(c+2258568,highest);if symbols<2 {return 0;}
 let input=rank;let output=counts;let passes=1;if maximum_frequency>=256 {passes=2;}if maximum_frequency>=65536 {passes=3;}let pass=0;
 while pass<passes {let shift=pass*8;let buckets=fz_min(256,(maximum_frequency>>shift)+1);fz_fill(lengths,0,buckets*8);i=0;while i<symbols {let symbol=load64(input+i*8);let bucket=(load64(nodes+symbol*16)>>shift)&255;store64(lengths+bucket*8,load64(lengths+bucket*8)+1);i=i+1;}
  let sum=0;i=0;while i<buckets {let n=load64(lengths+i*8);store64(lengths+i*8,sum);sum=sum+n;i=i+1;}
  i=0;while i<symbols {let symbol=load64(input+i*8);let bucket=(load64(nodes+symbol*16)>>shift)&255;let at=load64(lengths+bucket*8);store64(output+at*8,symbol);store64(lengths+bucket*8,at+1);i=i+1;}let swap=input;input=output;output=swap;pass=pass+1;
 }
 if input!=rank {fz_copy(rank,input,symbols*8);}let leaf=0;let inner=256;let node=256;
 while node<255+symbols {let a=0;let b=0;let k=0;while k<2 {let id=0;if leaf<symbols {let candidate=load64(rank+leaf*8);if inner<node && load64(nodes+inner*16)<load64(nodes+candidate*16) {id=inner;inner=inner+1;}else {id=candidate;leaf=leaf+1;}}else {id=inner;inner=inner+1;}if k==0 {a=id;}else {b=id;}k=k+1;}
  store64(nodes+node*16,load64(nodes+a*16)+load64(nodes+b*16));store64(nodes+node*16+8,-1);store64(nodes+a*16+8,node);store64(nodes+b*16+8,node);node=node+1;
 }
 // Parents have larger node IDs. Compute their depths once in reverse order,
 // reusing frequencies after the tree is complete, then visit each leaf once.
 let root=node-1;store64(nodes+root*16,0);i=root-1;while i>=256 {store64(nodes+i*16,load64(nodes+load64(nodes+i*16+8)*16)+1);i=i-1;}
 fz_fill(counts,0,2048);fz_fill(lengths,0,2048);let maximum=0;i=0;
 while i<symbols {let symbol=load64(rank+i*8);let parent=load64(nodes+symbol*16+8);let depth=load64(nodes+parent*16)+1;store64(counts+depth*8,load64(counts+depth*8)+1);if depth>maximum {maximum=depth;}i=i+1;}
 // Rebalance deepest sibling pairs. Kraft equality and the leaf count remain
 // unchanged; least-frequent leaves receive the resulting longest lengths.
 let depth=maximum;while depth>11 {while load64(counts+depth*8)>0 {let shorter=depth-2;while shorter>0 && !load64(counts+shorter*8) {shorter=shorter-1;}if !shorter {return -1;}
  store64(counts+depth*8,load64(counts+depth*8)-2);store64(counts+(depth-1)*8,load64(counts+(depth-1)*8)+1);store64(counts+shorter*8,load64(counts+shorter*8)-1);store64(counts+(shorter+1)*8,load64(counts+(shorter+1)*8)+2);}depth=depth-1;}
 if maximum>11 {maximum=11;}let at=0;depth=maximum;while depth>0 {let left=load64(counts+depth*8);while left {store64(lengths+load64(rank+at*8)*8,depth);at=at+1;left=left-1;}depth=depth-1;}
 let weights=c+2260736;let codes=c+2258688;fz_fill(counts,0,104);i=0;
 while i<256 {let len=load64(lengths+i*8);let weight=0;if len {weight=maximum+1-len;store64(counts+weight*8,load64(counts+weight*8)+1);}store64(weights+i*8,weight);i=i+1;}
 let next=0;i=0;while i<maximum {let cur=next;next=next+(load64(counts+(i+1)*8)<<i);store64(counts+(i+1)*8,cur);i=i+1;}
 i=0;while i<256 {let weight=load64(weights+i*8);if weight {let first=load64(counts+weight*8);store64(codes+i*8,(first>>(weight-1))|(load64(lengths+i*8)<<16));store64(counts+weight*8,first+(1<<(weight-1)));}else {store64(codes+i*8,0);}i=i+1;}
 return maximum;
}
fn fz_encode_weights(c,out,count) {
 if count<=128 {store8(out,count+127);let i=0;while i<count {let value=load64(c+2260736+i*8)<<4;if i+1<count {value=value|load64(c+2260736+(i+1)*8);}store8(out+1+i/2,value);i=i+2;}return 1+(count+1)/2;}
 let header=fz_weight_header(out+1);let stream=out+1+header;let table=c+2263000;let inverse=c+2264064;let weights=c+2260736;
 let s1=0;let s2=0;if count&1 {s1=fz_first(table,32,load64(weights+(count-1)*8));s2=fz_first(table,32,load64(weights+(count-2)*8));}else {s1=fz_first(table,32,load64(weights+(count-2)*8));s2=fz_first(table,32,load64(weights+(count-1)*8));}
 let i=count-3;let acc=0;let nbits=0;let written=0;
 while i>=0 {let symbol=load64(weights+i*8);let state=s1;if i&1 {state=s2;}let entry=load64(inverse+(symbol*32+state)*8);acc=acc|((entry>>16)<<nbits);nbits=nbits+((entry>>8)&255);if i&1 {s2=entry&255;}else {s1=entry&255;}
  while nbits>=8 {store8(stream+written,acc);written=written+1;acc=acc>>8;nbits=nbits-8;}i=i-1;}
 acc=acc|(s2<<nbits);nbits=nbits+5;acc=acc|(s1<<nbits);nbits=nbits+5;acc=acc|(1<<nbits);nbits=nbits+1;while nbits>0 {store8(stream+written,acc);written=written+1;acc=acc>>8;nbits=nbits-8;}
 let bytes=header+written;if bytes>=128 {return -1;}store8(out,bytes);return bytes+1;
}
fn fz_huff_encode_stream(c,src,n,out) {
 if load64(c+1872) {store64(c+1880,src);store64(c+1888,n);store64(c+1896,out);return native_call1(load64(c+1872),c);}
 let codes=c+2258688;let acc=0;let nbits=0;let written=0;let i=n;
 while i>0 {i=i-1;let code=load64(codes+load8(src+i)*8);acc=acc|((code&65535)<<nbits);nbits=nbits+(code>>16);if nbits>=32 {bytes_store32(out+written,acc);written=written+4;acc=(acc>>32)&0xffffffff;nbits=nbits-32;}}
 acc=acc|(1<<nbits);nbits=nbits+1;while nbits>0 {store8(out+written,acc);written=written+1;acc=acc>>8;nbits=nbits-8;}return written;
}
// Returns complete literals-section bytes, or -1 if Huffman is not worthwhile.
fn fz_huff_encode(c,src,n,out) {
 if n<128 {return -1;}let hist=c+2240000;let i=0;if load64(c+2016) {store64(c+1880,src);store64(c+1888,n);native_call1(load64(c+2016),c);}else {fz_fill(hist,0,2048);while i<n {let symbol=load8(src+i);store64(hist+symbol*8,load64(hist+symbol*8)+1);i=i+1;}}
 let repeat=(load64(c+320)&8)!=0;let bits=0;let ideal=0;let logn=fz_log(n);let correction=((n-(1<<logn))*16)>>logn;
 if repeat {i=0;while i<256 {let frequency=load64(hist+i*8);if frequency {let len=load64(c+2258688+i*8)>>16;if !len {repeat=0;}bits=bits+frequency*len*16;ideal=ideal+frequency*(fz_frequency_cost(frequency,logn)+correction);}i=i+1;}if bits>ideal+n*2+2048 {repeat=0;}}
 let temp=c+2048000;let tree=0;
 if !repeat {store64(c+320,load64(c+320)&(-9));let log=fz_huff_lengths(c);if log<=0 {return -1;}let highest=load64(c+2258568);tree=fz_encode_weights(c,temp+5,highest);if tree<0 {return -1;}}

 let at=5+tree;let streams=1;if n>=1024 {streams=4;}if streams==1 {at=at+fz_huff_encode_stream(c,src,n,temp+at);}else {let each=(n+3)/4;let jump=temp+at;at=at+6;let i=0;while i<4 {let amount=each;if i==3 {amount=n-each*3;}let bytes=fz_huff_encode_stream(c,src+i*each,amount,temp+at);if i<3 {fz_le(jump+i*2,bytes,2);}at=at+bytes;i=i+1;}}
 let compressed=at-5;let header=0;let bytes=0;if streams==1 && compressed<1024 {header=2|(n<<4)|(compressed<<14);bytes=3;}else if streams==4 && n<16384 && compressed<16384 {header=10|(n<<4)|(compressed<<18);bytes=4;}else {header=14|(n<<4)|(compressed<<22);bytes=5;}
 if compressed+bytes>=n {return -1;}if repeat {header=header|1;}else {store64(c+320,load64(c+320)|8);}fz_le(out,header,bytes);fz_copy(out+bytes,temp+5,compressed);return compressed+bytes;
}
