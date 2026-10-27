// Unicode 17 UAX #9 revision 51. P1..I2 resolve logical paragraphs; L1/L2
// are applied separately to each wrapped line. Shapers retain logical text.
import "utf8.flex";
import "bidi-properties.flex";
// Class numbers: L0 R1 AL2 EN3 ES4 ET5 AN6 CS7 NSM8 BN9 B10 S11
// WS12 ON13 LRE14 LRO15 RLE16 RLO17 PDF18 LRI19 RLI20 FSI21 PDI22.
fn ub_unpack(p,n){let v=0;let i=0;while i<n{v=(v<<6)|(load8(p+i)-63);i=i+1;}return v;}
fn unicode_bidi_class(cp){
    if cp<0 || cp>1114111{return 0;}let data=unicode_bidi_class_data();let low=0;let high=unicode_bidi_class_count();while low<high{let mid=(low+high)/2;let p=data+mid*9;if cp<ub_unpack(p,4){high=mid;}else if cp>ub_unpack(p+4,4){low=mid+1;}else{return load8(p+8)-63;}}return 0;
}
// (paired_scalar<<2)|type (opening1/closing2), or 0.
fn unicode_bidi_bracket(cp){let data=unicode_bidi_bracket_data();let low=0;let high=unicode_bidi_bracket_count();while low<high{let mid=(low+high)/2;let p=data+mid*9;let key=ub_unpack(p,4);if cp<key{high=mid;}else if cp>key{low=mid+1;}else{return (ub_unpack(p+4,4)<<2)|(load8(p+8)-63);}}return 0;}
// Scalar fallback for a renderer without OpenType mirroring. HarfBuzz performs
// its own L4 mirroring: do not apply this mapping a second time before shaping.
fn unicode_bidi_mirror(cp){let data=unicode_bidi_mirror_data();let low=0;let high=unicode_bidi_mirror_count();while low<high{let mid=(low+high)/2;let p=data+mid*8;let key=ub_unpack(p,4);if cp<key{high=mid;}else if cp>key{low=mid+1;}else{return ub_unpack(p+4,4);}}return cp;}
fn ub_removed(t){return t==9 || (t>=14 && t<=18);}
fn ub_isolate(t){return t>=19 && t<=21;}
fn ub_strong(t){if t==3 || t==6{return 1;}return t;}
fn ub_neutral(t){return (t>=10 && t<=13) || t>=19;}
fn ub_ws(t){return t==12 || t>=19;}
fn ub_record(map,i){return map+64+i*32;}
fn ub_seq_type(seq,i){return load8(load64(seq+i*8)+17);}
fn ub_set_type(seq,i,t){store8(load64(seq+i*8)+17,t);return 0;}

// N0 / BD16. At most 63 unmatched openings, with canonical equivalents.
// pair[i] stores the closing sequence index for opening i, or -1. Processing
// that array in ascending order implements the required opening-position sort.
fn ub_brackets(seq,n,pair,stack,embedding,sos){
    let depth=0;let i=0;let overflow=0;while i<n{store64(pair+i*8,-1);i=i+1;}i=0;
    while i<n && !overflow{let p=load64(seq+i*8);if load8(p+17)==13{let cp=load64(p);let bracket=unicode_bidi_bracket(cp);let kind=bracket&3;let value=bracket>>2;if kind==1{if depth==63{overflow=1;}else{if value==0x232a{value=0x3009;}store64(stack+depth*16,value);store64(stack+depth*16+8,i);depth=depth+1;}}else if kind==2{if cp==0x232a{cp=0x3009;}let j=depth-1;while j>=0{if cp==load64(stack+j*16){store64(pair+load64(stack+j*16+8)*8,i);depth=j;j=-1;}else{j=j-1;}}}}i=i+1;}
    if overflow{return 0;}i=0;while i<n{let close=load64(pair+i*8);if close>=0{let found=0;let matching=0;let j=i+1;while j<close && !matching{let t=ub_strong(ub_seq_type(seq,j));if t<=1{found=1;if t==embedding{matching=1;}}j=j+1;}if found{let t=embedding;if !matching{t=sos;j=i-1;while j>=0{let previous=ub_strong(ub_seq_type(seq,j));if previous<=1{t=previous;j=-1;}else{j=j-1;}}}
                ub_set_type(seq,i,t);ub_set_type(seq,close,t);j=i+1;while j<n && load8(load64(seq+j*8)+16)==8{ub_set_type(seq,j,t);j=j+1;}j=close+1;while j<n && load8(load64(seq+j*8)+16)==8{ub_set_type(seq,j,t);j=j+1;}
            }}i=i+1;}return 1;
}
fn ub_implicit(seq,n,pair,stack,level,sos,eos){
    // W1.
    let i=0;let previous=sos;while i<n{let t=ub_seq_type(seq,i);if t==8{t=previous;ub_set_type(seq,i,t);}if t>=19{previous=13;}else{previous=t;}i=i+1;}
    // W2 (before AL is changed by W3).
    i=0;let strong=sos;while i<n{let t=ub_seq_type(seq,i);if t<=2{strong=t;}else if t==3 && strong==2{ub_set_type(seq,i,6);}i=i+1;}
    i=0;while i<n{if ub_seq_type(seq,i)==2{ub_set_type(seq,i,1);}i=i+1;}
    // W4.
    i=1;while i+1<n{let t=ub_seq_type(seq,i);let left=ub_seq_type(seq,i-1);let right=ub_seq_type(seq,i+1);if left==right && ((t==4 && left==3) || (t==7 && (left==3 || left==6))){ub_set_type(seq,i,left);}i=i+1;}
    // W5, then W6.
    i=0;while i<n{if ub_seq_type(seq,i)==5{let first=i;while i<n && ub_seq_type(seq,i)==5{i=i+1;}let left=sos;if first{left=ub_seq_type(seq,first-1);}let right=eos;if i<n{right=ub_seq_type(seq,i);}if left==3 || right==3{let j=first;while j<i{ub_set_type(seq,j,3);j=j+1;}}}else{i=i+1;}}
    i=0;while i<n{let t=ub_seq_type(seq,i);if t==4 || t==5 || t==7{ub_set_type(seq,i,13);}i=i+1;}
    // W7.
    i=0;strong=sos;while i<n{let t=ub_seq_type(seq,i);if t<=1{strong=t;}else if t==3 && strong==0{ub_set_type(seq,i,0);}i=i+1;}
    ub_brackets(seq,n,pair,stack,level&1,sos);
    // N1/N2. Numbers establish R context, but retain their numeric type.
    i=0;previous=sos;while i<n{let t=ub_seq_type(seq,i);if ub_neutral(t){let first=i;while i<n && ub_neutral(ub_seq_type(seq,i)){i=i+1;}let right=eos;if i<n{right=ub_strong(ub_seq_type(seq,i));}let value=level&1;if previous==right{value=previous;}let j=first;while j<i{ub_set_type(seq,j,value);j=j+1;}}else{previous=ub_strong(t);i=i+1;}}
    // I1/I2; preserve the original explicit level for every other sequence's
    // sos/eos computation. Resolved levels are stored in a separate byte.
    i=0;while i<n{let p=load64(seq+i*8);let t=load8(p+17);let value=level;if level&1{if t!=1{value=value+1;}}else if t==1{value=value+1;}else if t==3 || t==6{value=value+2;}store8(p+19,value);i=i+1;}return 1;
}

// Process exactly one P1 paragraph [first,end), including a terminal B.
// scratch: active indices8n, run map8n, runs24n, sequence8n, bracket pairs8n,
// matching-isolate stack8n; fixed explicit-status and bracket stacks follow.
fn ub_paragraph(map,first,end,mode,scratch,capacity){
    let active=scratch;let runmap=active+capacity*8;let runs=runmap+capacity*8;let seq=runs+capacity*24;let pair=seq+capacity*8;let matching=pair+capacity*8;let status=matching+capacity*8;let brackets=status+3072;
    // BD9 matching and P2/P3. Strong text inside nested isolates contributes
    // only to that isolate's FSI direction, never to its parent or paragraph.
    let depth=0;let base=-1;let i=first;while i<end{let p=ub_record(map,i);let t=load8(p+16);if ub_isolate(t){store64(matching+depth*8,i);depth=depth+1;}else if t==22{if depth{depth=depth-1;let open=load64(matching+depth*8);store64(ub_record(map,open)+24,i);store64(p+24,open);}}else if t<=2{let dir=t!=0;if depth{let open=ub_record(map,load64(matching+(depth-1)*8));if !load8(open+22){store8(open+21,dir);store8(open+22,1);}}else if base<0{base=dir;}}i=i+1;}
    if mode<=1{base=mode;}else if base<0{base=mode==3;}if first==0{store64(map+24,base);}
    // X1..X8. Entries are level, override (ON13 means neutral), isolate.
    store64(status,base);store64(status+8,13);store64(status+16,0);depth=1;let overflow_isolate=0;let overflow_embedding=0;let valid_isolate=0;i=first;
    while i<end{let p=ub_record(map,i);let t=load8(p+16);let top=status+(depth-1)*24;let level=load64(top);let override=load64(top+8);store8(p+18,level);store8(p+20,base);
        if (t>=14 && t<=17) || ub_isolate(t){let isolate=ub_isolate(t);let rtl=t==16 || t==17 || t==20;if t==21{rtl=load8(p+21);}if isolate && override!=13{store8(p+17,override);}let next=(level+2)&~1;if rtl{next=(level+1)|1;}
            if next<=125 && !overflow_isolate && !overflow_embedding{let entry=status+depth*24;store64(entry,next);let value=13;if t==15{value=0;}else if t==17{value=1;}store64(entry+8,value);store64(entry+16,isolate);depth=depth+1;if isolate{valid_isolate=valid_isolate+1;}}
            else if isolate{overflow_isolate=overflow_isolate+1;}else if !overflow_isolate{overflow_embedding=overflow_embedding+1;}
        }else if t==22{if overflow_isolate{overflow_isolate=overflow_isolate-1;}else if valid_isolate{overflow_embedding=0;while !load64(status+(depth-1)*24+16){depth=depth-1;}depth=depth-1;valid_isolate=valid_isolate-1;}top=status+(depth-1)*24;store8(p+18,load64(top));override=load64(top+8);if override!=13{store8(p+17,override);}}
        else if t==18{if !overflow_isolate{if overflow_embedding{overflow_embedding=overflow_embedding-1;}else if depth>1 && !load64(top+16){depth=depth-1;}}}
        else if t==10{store8(p+18,base);}else if t!=9 && override!=13{store8(p+17,override);}
        if ub_removed(t){store8(p+19,255);}else{store8(p+19,load8(p+18));}i=i+1;
    }
    // X9 and the explicit level runs used by X10. Each run stores [a,b)
    // positions into active[] and its linked next run, initially -1.
    let count=0;i=first;while i<end{if !ub_removed(load8(ub_record(map,i)+16)){store64(active+count*8,i);count=count+1;}i=i+1;}
    let run_count=0;i=0;while i<count{let begin=i;let level=load8(ub_record(map,load64(active+i*8))+18);while i<count && load8(ub_record(map,load64(active+i*8))+18)==level{store64(runmap+load64(active+i*8)*8,run_count);i=i+1;}let r=runs+run_count*24;store64(r,begin);store64(r+8,i);store64(r+16,-1);run_count=run_count+1;}
    let r=0;while r<run_count{let p=ub_record(map,load64(active+(load64(runs+r*24+8)-1)*8));let match=load64(p+24);if ub_isolate(load8(p+16)) && match>=0{let next=load64(runmap+match*8);if next!=r{store64(runs+r*24+16,next);}}r=r+1;}
    r=0;while r<run_count{let begin=load64(runs+r*24);let p=ub_record(map,load64(active+begin*8));let match=load64(p+24);let linked=0;if load8(p+16)==22 && match>=0{let prev=load64(runmap+match*8);linked=prev!=r && load64(runs+prev*24+16)==r;}
        if !linked{let length=0;let current=r;let last_end=0;while current>=0{let entry=runs+current*24;let j=load64(entry);last_end=load64(entry+8);while j<last_end{store64(seq+length*8,ub_record(map,load64(active+j*8)));length=length+1;j=j+1;}current=load64(entry+16);}
            let level=load8(p+18);let before=base;if begin{before=load8(ub_record(map,load64(active+(begin-1)*8))+18);}let after=base;let last=load64(seq+(length-1)*8);if last_end<count && !ub_isolate(load8(last+16)){after=load8(ub_record(map,load64(active+last_end*8))+18);}if before<level{before=level;}if after<level{after=level;}ub_implicit(seq,length,pair,brackets,level,before&1,after&1);
        }r=r+1;
    }return 1;
}

// Owned result. Header: scalar count0, UTF-8 byte length8, allocation bytes16,
// first paragraph base24. Records start64, stride32: scalar0, byte offset8,
// original class16, work class17, explicit level18, resolved level19 (255=X9),
// paragraph base20, FSI direction21/known22, matching isolate/PDI index24.
// mode: 0=LTR, 1=RTL, 2=first-strong/default LTR, 3=first-strong/default RTL.
// At most 1 MiB UTF-8 / 262144 scalars; no borrowed data after this returns.
fn unicode_bidi(text,n,mode){
    if !text || n<0 || n>1048576 || mode<0 || mode>3{return unicode_fail("Invalid bidi input or direction");}let at=0;let count=0;while at<n{let value=unicode_utf8_read(text,n,at);if value<0{return unicode_fail("Invalid UTF-8 bidi input");}at=at+(value&7);count=count+1;if count>262144{return unicode_fail("Bidi scalar limit exceeded");}}
    let bytes=64+count*32;let map=alloc(bytes);if map<=0{return unicode_fail("Cannot allocate bidi result");}store64(map,count);store64(map+8,n);store64(map+16,bytes);store64(map+24,mode&1);let i=0;at=0;while i<count{let value=unicode_utf8_read(text,n,at);let p=ub_record(map,i);store64(p,value>>3);store64(p+8,at);store64(p+16,0);store8(p+16,unicode_bidi_class(value>>3));store8(p+17,load8(p+16));store64(p+24,-1);at=at+(value&7);i=i+1;}
    let temporary=4096+count*64;let scratch=alloc(temporary);if scratch<=0{syscall(11,map,bytes,0,0,0,0);return unicode_fail("Cannot allocate bidi scratch");}let first=0;while first<count{let end=first+1;while end<count && load8(ub_record(map,end-1)+16)!=10{end=end+1;}ub_paragraph(map,first,end,mode,scratch,count);first=end;}syscall(11,scratch,temporary,0,0,0,0);return map;
}
fn unicode_bidi_free(map){if map{syscall(11,map,load64(map+16),0,0,0,0);}return 0;}
fn unicode_bidi_level(map,i){if !map || i<0 || i>=load64(map){return -1;}let level=load8(ub_record(map,i)+19);if level==255{return -1;}return level;}
fn unicode_bidi_offset(map,i){if !map || i<0 || i>load64(map){return -1;}if i==load64(map){return load64(map+8);}return load64(ub_record(map,i)+8);}
// First scalar starting at/after byte offset, or count at the end.
fn unicode_bidi_index(map,offset){if !map || offset<0 || offset>load64(map+8){return -1;}let low=0;let high=load64(map);while low<high{let mid=(low+high)/2;if load64(ub_record(map,mid)+8)<offset{low=mid+1;}else{high=mid;}}return low;}

// L1/L2 for a single wrapped line [first,end), in scalar indices. Caller's
// levels[] has end-first bytes, order[] has end-first 64-bit scalar indices.
// Result is order count (X9 entries omitted), or -1 on invalid bounds. It does
// not mutate paragraph levels, so another wrapping can reuse the same map.
fn unicode_bidi_line(map,first,end,levels,order,capacity){
    if !map || first<0 || end<first || end>load64(map) || capacity<end-first || (!levels && end>first) || (!order && end>first){unicode_fail("Invalid bidi line output");return -1;}if first==end{return 0;}let base=load8(ub_record(map,first)+20);let i=first;while i<end{let p=ub_record(map,i);if load8(p+20)!=base || (load8(p+16)==10 && i!=end-1){unicode_fail("Bidi line crosses a paragraph");return -1;}store8(levels+i-first,load8(p+19));i=i+1;}
    // X9 controls do not interrupt the whitespace sequence considered by L1.
    let trailing=1;i=end-1;while i>=first{let p=ub_record(map,i);let t=load8(p+16);if !ub_removed(t){if t==10 || t==11{store8(levels+i-first,base);trailing=1;}else if trailing && ub_ws(t){store8(levels+i-first,base);}else{trailing=0;}}i=i-1;}
    let count=0;let maximum=0;let minimum_odd=127;i=first;while i<end{let level=load8(levels+i-first);if level!=255{store64(order+count*8,i);count=count+1;if level>maximum{maximum=level;}if level&1 && level<minimum_odd{minimum_odd=level;}}i=i+1;}
    let threshold=maximum;while threshold>=minimum_odd{let j=0;while j<count{if load8(levels+load64(order+j*8)-first)>=threshold{let a=j;while j<count && load8(levels+load64(order+j*8)-first)>=threshold{j=j+1;}let b=j-1;while a<b{let value=load64(order+a*8);store64(order+a*8,load64(order+b*8));store64(order+b*8,value);a=a+1;b=b-1;}}else{j=j+1;}}threshold=threshold-1;}return count;
}
