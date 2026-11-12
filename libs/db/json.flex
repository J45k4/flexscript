// Validated, compact UTF-8 JSON (value kind 5). SQL NULL remains kind 0.
// A cursor is source, length, offset, failed; parsing never allocates a tree.
fn fdj_ws(c) {let p=load64(c);let n=load64(c+8);let i=load64(c+16);while i<n && (load8(p+i)==32 || load8(p+i)==9 || load8(p+i)==10 || load8(p+i)==13) {i=i+1;}store64(c+16,i);return 1;}
fn fdj_hex(c) {if c>=48 && c<=57 {return c-48;}if c>=65 && c<=70 {return c-65+10;}if c>=97 && c<=102 {return c-97+10;}return -1;}
fn fdj_u16(c) {let p=load64(c);let i=load64(c+16);if i+4>load64(c+8) {store64(c+24,1);return 0;}let code=0;let k=0;while k<4 {let v=fdj_hex(load8(p+i+k));if v<0 {store64(c+24,1);return 0;}code=(code<<4)|v;k=k+1;}store64(c+16,i+4);return code;}
fn fdj_utf8(p,n,i) {let c=load8(p+i);let bytes=0;let v=0;let minimum=0;if c>=194 && c<=223 {bytes=2;v=c&31;minimum=128;}else if c>=224 && c<=239 {bytes=3;v=c&15;minimum=2048;}else if c>=240 && c<=244 {bytes=4;v=c&7;minimum=65536;}else {return 0;}if i+bytes>n {return 0;}let k=1;while k<bytes {let next=load8(p+i+k);if next<128 || next>191 {return 0;}v=(v<<6)|(next&63);k=k+1;}if v<minimum || v>1114111 || (v>=55296 && v<=57343) {return 0;}return bytes;}
fn fdj_string(c) {
 let p=load64(c);let n=load64(c+8);let i=load64(c+16);if i>=n || load8(p+i)!=34 {return 0;}i=i+1;
 while i<n {let ch=load8(p+i);i=i+1;if ch==34 {store64(c+16,i);return 1;}if ch<32 {return 0;}if ch==92 {if i>=n {return 0;}ch=load8(p+i);i=i+1;if ch==117 {store64(c+16,i);let code=fdj_u16(c);i=load64(c+16);if load64(c+24) {return 0;}if code>=55296 && code<=56319 {if i+2>n || load8(p+i)!=92 || load8(p+i+1)!=117 {return 0;}store64(c+16,i+2);let low=fdj_u16(c);i=load64(c+16);if load64(c+24) || low<56320 || low>57343 {return 0;}}else if code>=56320 && code<=57343 {return 0;}}else if ch!=34 && ch!=92 && ch!=47 && ch!=98 && ch!=102 && ch!=110 && ch!=114 && ch!=116 {return 0;}}
 else if ch>=128 {let bytes=fdj_utf8(p,n,i-1);if !bytes {return 0;}i=i+bytes-1;}}
 return 0;
}
fn fdj_value(c,depth) {
 if depth>64 {return 0;}fdj_ws(c);let p=load64(c);let n=load64(c+8);let i=load64(c+16);if i>=n {return 0;}let ch=load8(p+i);if ch==34 {return fdj_string(c);}
 if ch==123 || ch==91 {let object=ch==123;let end=93;if object {end=125;}store64(c+16,i+1);fdj_ws(c);i=load64(c+16);if i<n && load8(p+i)==end {store64(c+16,i+1);return 1;}let live=1;while live {if object {if !fdj_string(c) {return 0;}fdj_ws(c);i=load64(c+16);if i>=n || load8(p+i)!=58 {return 0;}store64(c+16,i+1);}if !fdj_value(c,depth+1) {return 0;}fdj_ws(c);i=load64(c+16);if i>=n {return 0;}ch=load8(p+i);store64(c+16,i+1);if ch==end {return 1;}if ch!=44 {return 0;}fdj_ws(c);}return 0;}
 let word=0;let length=0;if ch==116 {word="true";length=4;}if ch==102 {word="false";length=5;}if ch==110 {word="null";length=4;}if word {if i+length>n || !fd_bytes(p+i,word,length) {return 0;}store64(c+16,i+length);return 1;}
 if ch==45 {i=i+1;}if i>=n {return 0;}ch=load8(p+i);if ch==48 {i=i+1;}else {if ch<49 || ch>57 {return 0;}while i<n && load8(p+i)>=48 && load8(p+i)<=57 {i=i+1;}}
 if i<n && load8(p+i)==46 {i=i+1;let start=i;while i<n && load8(p+i)>=48 && load8(p+i)<=57 {i=i+1;}if i==start {return 0;}}
 if i<n && (load8(p+i)==101 || load8(p+i)==69) {i=i+1;if i<n && (load8(p+i)==43 || load8(p+i)==45) {i=i+1;}let start=i;while i<n && load8(p+i)>=48 && load8(p+i)<=57 {i=i+1;}if i==start {return 0;}}
 store64(c+16,i);return 1;
}
fn fdj_valid(p,n) {if !p || n<1 || n>1048576 {return 0;}let c=alloc(32);if c<=0 {return 0;}store64(c,p);store64(c+8,n);let ok=fdj_value(c,0);fdj_ws(c);ok=ok && load64(c+16)==n && !load64(c+24);syscall(11,c,32,0,0,0,0);return ok;}
fn flexdb_json(a,text) {
 if !text {return 0;}let n=fd_len(text);if !fdj_valid(text,n) {return 0;}let out=fd_alloc(a,n+1);let i=0;let at=0;let quoted=0;let escape=0;
 while i<n {let c=load8(text+i);if quoted || (c!=32 && c!=9 && c!=10 && c!=13) {store8(out+at,c);at=at+1;}if escape {escape=0;}else if quoted && c==92 {escape=1;}else if c==34 {quoted=!quoted;}i=i+1;}store8(out+at,0);return fd_value(a,5,out,at);
}
fn flexdb_json_type() {return 5;}
// Unquote a validated JSON string into a length-bearing text value. Embedded
// NUL is representable internally; scalar extraction below declines it.
fn fdj_unquote(a,p,n) {let out=fd_alloc(a,n+1);let at=0;let i=1;let c=fd_alloc(a,32);store64(c,p);store64(c+8,n);
 while i<n-1 {let ch=load8(p+i);i=i+1;if ch==92 {ch=load8(p+i);i=i+1;if ch==117 {store64(c+16,i);ch=fdj_u16(c);i=load64(c+16);if ch>=55296 && ch<=56319 {store64(c+16,i+2);let low=fdj_u16(c);i=load64(c+16);ch=65536+((ch-55296)<<10)+(low-56320);}if ch>=65536 {store8(out+at,240|(ch>>18));at=at+1;store8(out+at,128|((ch>>12)&63));at=at+1;store8(out+at,128|((ch>>6)&63));at=at+1;ch=128|(ch&63);}else if ch>=2048 {store8(out+at,224|(ch>>12));at=at+1;store8(out+at,128|((ch>>6)&63));at=at+1;ch=128|(ch&63);}else if ch>=128 {store8(out+at,192|(ch>>6));at=at+1;ch=128|(ch&63);}}
 else if ch==98 {ch=8;}else if ch==102 {ch=12;}else if ch==110 {ch=10;}else if ch==114 {ch=13;}else if ch==116 {ch=9;}}
 store8(out+at,ch);at=at+1;}store8(out+at,0);return fd_value(a,2,out,at);
}
fn fdj_pointer(a,path) {let out=fd_vec(a);if !path || fd_len(path)>4096 {return 0;}if !load8(path) {return out;}if load8(path)!=47 {return 0;}let i=1;while 1 {let token=fd_alloc(a,fd_len(path+i)+1);let n=0;while load8(path+i) && load8(path+i)!=47 {let ch=load8(path+i);i=i+1;if ch==126 {ch=load8(path+i);i=i+1;if ch==48 {ch=126;}else if ch==49 {ch=47;}else {return 0;}}store8(token+n,ch);n=n+1;}store8(token+n,0);fd_push(a,out,fd_value(a,2,token,n));if !load8(path+i) {return out;}i=i+1;}return 0;}
fn fdj_find(a,value,tokens) {
 let p=flexdb_word(value);let n=flexdb_bytes(value);let start=0;let end=n;let part=0;let c=fd_alloc(a,32);store64(c,p);store64(c+8,n);
 while part<fd_size(tokens) {let token=fd_at(tokens,part);let want=load64(token+8);let want_n=load64(token+16);let object=load8(p+start)==123;let array=load8(p+start)==91;if !object && !array {return flexdb_null(a);}store64(c+16,start+1);fdj_ws(c);let index=0;let found=0;let chosen_start=0;let chosen_end=0;let live=1;
 while live {let i=load64(c+16);if i>=end || load8(p+i)==125 || load8(p+i)==93 {live=0;}else {let match=0;if object {let key=i;if !fdj_string(c) {return 0;}let text=fdj_unquote(a,p+key,load64(c+16)-key);match=load64(text+16)==want_n && fd_bytes(load64(text+8),want,want_n);fdj_ws(c);store64(c+16,load64(c+16)+1);}else {let digits=want_n>0 && !(want_n>1 && load8(want)==48);let number=0;let k=0;while k<want_n {let ch=load8(want+k);if ch<48 || ch>57 || number>214748364 {digits=0;}else {number=number*10+ch-48;}k=k+1;}match=digits && index==number;}
 fdj_ws(c);let lo=load64(c+16);if !fdj_value(c,0) {return 0;}let hi=load64(c+16);if match {found=1;chosen_start=lo;chosen_end=hi;}fdj_ws(c);i=load64(c+16);if i<end && load8(p+i)==44 {store64(c+16,i+1);fdj_ws(c);}else {live=0;}index=index+1;}}
 if !found {return flexdb_null(a);}start=chosen_start;end=chosen_end;part=part+1;}
 let copy=fd_alloc(a,end-start+1);fd_copy(copy,p+start,end-start);store8(copy+end-start,0);return fd_value(a,5,copy,end-start);
}
fn flexdb_json_get(a,value,pointer) {if !value || !pointer {return 0;}let tokens=fdj_pointer(a,pointer);if !tokens {return 0;}if !flexdb_kind(value) {return flexdb_null(a);}if flexdb_kind(value)!=5 {return 0;}return fdj_find(a,value,tokens);}
fn flexdb_json_text(a,value,pointer) {let v=flexdb_json_get(a,value,pointer);if !v {return 0;}if !flexdb_kind(v) || load8(flexdb_word(v))!=34 {return flexdb_null(a);}let out=fdj_unquote(a,flexdb_word(v),flexdb_bytes(v));if fd_len(flexdb_word(out))!=flexdb_bytes(out) {return flexdb_null(a);}return out;}
fn flexdb_json_int(a,value,pointer) {let v=flexdb_json_get(a,value,pointer);if !v {return 0;}if !flexdb_kind(v) {return v;}let p=flexdb_word(v);let n=flexdb_bytes(v);let negative=load8(p)==45;let i=negative;let result=0;if i==n {return flexdb_null(a);}while i<n {let digit=load8(p+i)-48;let last=7;if negative {last=8;}if digit<0 || digit>9 || result<(-922337203685477580) || (result==(-922337203685477580) && digit>last) {return flexdb_null(a);}result=result*10-digit;i=i+1;}if !negative {result=-result;}return flexdb_int(a,result);}
fn flexdb_where_json(q,input,column,pointer,op,value) {
 if !input || !value || column<0 || column>=load64(input) || fd_at(load64(input+16),column)!=5 || op<0 || op>5 {fd_error(load64(q+24),"invalid JSON filter");return 0;}let kind=flexdb_kind(value);if kind!=1 && kind!=2 && kind!=5 {fd_error(load64(q+24),"JSON filter expects integer, text or JSON value");return 0;}if kind==5 && op>1 {fd_error(load64(q+24),"JSON document filters support equality only");return 0;}if !fdj_pointer(q,pointer) {fd_error(load64(q+24),"invalid JSON pointer");return 0;}let result=fd_relation(q,load64(input+16));let i=0;
 while i<flexdb_count(input) {let row=flexdb_at(input,i);let cell=flexdb_cell(row,column);let extracted=0;if kind==1 {extracted=flexdb_json_int(q,cell,pointer);}else if kind==2 {extracted=flexdb_json_text(q,cell,pointer);}else {extracted=flexdb_json_get(q,cell,pointer);}if !extracted {fd_error(load64(q+24),"JSON extraction failed");return 0;}if fd_matches(extracted,op,value) {fd_push(q,load64(result+8),row);}i=i+1;}return result;
}
