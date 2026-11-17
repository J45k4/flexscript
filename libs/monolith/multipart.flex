// Bounded multipart/form-data parser. Parts reference the caller-owned input
// bytes; only the small boundary and header values are copied into the arena.
// mono_mp_next returns 1 for a part, 0 at the final delimiter, and -1 on error.
// The caller owns transport limits, input lifetime, authentication and storage.
import "support.flex";
fn mono_mp_lower(c) {if c>=65 && c<=90 {return c+32;}return c;}
fn mono_mp_equal_ci(a,b) {let n=m_len(a);if n!=m_len(b) {return 0;}let i=0;while i<n {if mono_mp_lower(load8(a+i))!=mono_mp_lower(load8(b+i)) {return 0;}i=i+1;}return 1;}
fn mono_mp_token(c) {if (c>=65 && c<=90)||(c>=97 && c<=122)||(c>=48 && c<=57) {return 1;}let p="!#$%&'*+-.^_`|~";let i=0;while load8(p+i) {if load8(p+i)==c {return 1;}i=i+1;}return 0;}
fn mono_mp_trim(p,n) {while n>0 && (load8(p)==32 || load8(p)==9) {p=p+1;n=n-1;}while n>0 && (load8(p+n-1)==32 || load8(p+n-1)==9) {n=n-1;}return m_slice(p,n);}
// Parses a semicolon parameter list. Duplicate requested parameters fail.
// result: 0 absent, -1 invalid, otherwise arena-owned unescaped text.
fn mono_mp_parameter(text,key) {
    let n=m_len(text);let i=0;while i<n && load8(text+i)!=59 {i=i+1;}let result=0;
    while i<n {if load8(text+i)!=59 {return -1;}i=i+1;while i<n && (load8(text+i)==32 || load8(text+i)==9) {i=i+1;}let start=i;while i<n && mono_mp_token(load8(text+i)) {i=i+1;}if i==start {return -1;}let name=m_slice(text+start,i-start);while i<n && (load8(text+i)==32 || load8(text+i)==9) {i=i+1;}if i>=n || load8(text+i)!=61 {return -1;}i=i+1;while i<n && (load8(text+i)==32 || load8(text+i)==9) {i=i+1;}let out=m_buffer();
        if i<n && load8(text+i)==34 {i=i+1;let closed=0;while i<n && !closed {let c=load8(text+i);i=i+1;if c==34 {closed=1;}else {if c==92 {if i>=n {return -1;}c=load8(text+i);i=i+1;}if c<32 || c==127 {return -1;}let one=m_take(1);store8(one,c);m_append(out,one,1);}}if !closed {return -1;}}
        else {start=i;while i<n && mono_mp_token(load8(text+i)) {i=i+1;}if start==i {return -1;}m_append(out,text+start,i-start);}
        while i<n && (load8(text+i)==32 || load8(text+i)==9) {i=i+1;}if i<n && load8(text+i)!=59 {return -1;}if mono_mp_equal_ci(name,key) {if result {return -1;}result=m_data(out);}
    }return result;
}
fn mono_mp_prefix_type(type,wanted) {if !type {return 0;}let n=0;while load8(type+n) && load8(type+n)!=59 {n=n+1;}return mono_mp_equal_ci(mono_mp_trim(type,n),wanted);}
fn mono_mp_boundary(type) {if !mono_mp_prefix_type(type,"multipart/form-data") {return 0;}let b=mono_mp_parameter(type,"boundary");if b<=0 {return 0;}let n=m_len(b);if n<1 || n>70 {return 0;}let i=0;while i<n {let c=load8(b+i);if !(mono_mp_token(c) || c==40 || c==41 || c==44 || c==47 || c==58 || c==61 || c==63 || (c==32 && i<n-1)) {return 0;}i=i+1;}return b;}
fn mono_mp_match(p,n,s) {let k=m_len(s);if k>n {return 0;}let i=0;while i<k {if load8(p+i)!=load8(s+i) {return 0;}i=i+1;}return 1;}
fn mono_mp_open(type,bytes,size,limit) {
    let boundary=mono_mp_boundary(type);if !boundary || size<0 || limit<1 || limit>64 {return 0;}let first=m_cat("--",boundary);let n=m_len(first);if size<n+2 || !mono_mp_match(bytes,size,first) {return 0;}let state=m_take(128);let i=0;while i<128 {store8(state+i,0);i=i+1;}store64(state,bytes);store64(state+8,size);store64(state+16,n+2);store64(state+24,limit);let pattern=m_cat("\r\n--",boundary);store64(state+32,pattern);let plen=m_len(pattern);store64(state+40,plen);
    let table=m_take(plen*8);store64(state+48,table);store64(table,0);i=1;let matched=0;while i<plen {while matched>0 && load8(pattern+i)!=load8(pattern+matched) {matched=load64(table+(matched-1)*8);}if load8(pattern+i)==load8(pattern+matched) {matched=matched+1;}store64(table+i*8,matched);i=i+1;}
    if load8(bytes+n)==45 && load8(bytes+n+1)==45 {let at=n+2;if at==size || (at+2==size && load8(bytes+at)==13 && load8(bytes+at+1)==10) {store64(state+56,1);return state;}return 0;}
    if load8(bytes+n)!=13 || load8(bytes+n+1)!=10 {return 0;}return state;
}
// Scan the binary input once using a KMP failure table. A boundary-like byte
// sequence without a delimiter suffix remains part of the binary payload.
fn mono_mp_delimiter(state,start) {
    let bytes=load64(state);let size=load64(state+8);let pattern=load64(state+32);let plen=load64(state+40);let table=load64(state+48);let i=start;let matched=0;
    while i<size {let c=load8(bytes+i);while matched>0 && c!=load8(pattern+matched) {matched=load64(table+(matched-1)*8);}if c==load8(pattern+matched) {matched=matched+1;}i=i+1;if matched==plen {let at=i-plen;if i+2<=size && load8(bytes+i)==13 && load8(bytes+i+1)==10 {return at;}if i+2<=size && load8(bytes+i)==45 && load8(bytes+i+1)==45 && (i+2==size || (i+4==size && load8(bytes+i+2)==13 && load8(bytes+i+3)==10)) {return at;}matched=load64(table+(matched-1)*8);}}
    return -1;
}
fn mono_mp_next(state) {
    if !state || load64(state+56)==2 {return -1;}if load64(state+56)==1 {return 0;}let count=load64(state+64);if count>=load64(state+24) {store64(state+56,2);return -1;}
    let bytes=load64(state);let size=load64(state+8);let at=load64(state+16);let header_start=at;let disposition=0;let content_type="";let headers=0;
    let header_done=0;while !header_done {if at+2>size || at-header_start>8192 {store64(state+56,2);return -1;}if load8(bytes+at)==13 && load8(bytes+at+1)==10 {at=at+2;header_done=1;}else {let start=at;while at+1<size && !(load8(bytes+at)==13 && load8(bytes+at+1)==10) {let c=load8(bytes+at);if (c<32 && c!=9) || c==127 {store64(state+56,2);return -1;}at=at+1;}if at+1>=size || at-header_start>8192 {store64(state+56,2);return -1;}let colon=start;while colon<at && mono_mp_token(load8(bytes+colon)) {colon=colon+1;}if colon==start || colon==at || load8(bytes+colon)!=58 {store64(state+56,2);return -1;}let name=m_slice(bytes+start,colon-start);let value=mono_mp_trim(bytes+colon+1,at-colon-1);if mono_mp_equal_ci(name,"content-disposition") {if disposition {store64(state+56,2);return -1;}disposition=value;}else if mono_mp_equal_ci(name,"content-type") {if m_len(content_type) {store64(state+56,2);return -1;}content_type=value;}headers=headers+1;if headers>32 {store64(state+56,2);return -1;}at=at+2;}}
    if !disposition || !mono_mp_prefix_type(disposition,"form-data") {store64(state+56,2);return -1;}let name=mono_mp_parameter(disposition,"name");let filename=mono_mp_parameter(disposition,"filename");if name<=0 || filename==(-1) || m_len(name)>255 || (filename && m_len(filename)>255) || !m_utf8(name) || (filename && !m_utf8(filename)) {store64(state+56,2);return -1;}
    let end=mono_mp_delimiter(state,at);if end<0 {store64(state+56,2);return -1;}let after=end+load64(state+40);let final=load8(bytes+after)==45;after=after+2;if final {if after!=size && !(after+2==size && load8(bytes+after)==13 && load8(bytes+after+1)==10) {store64(state+56,2);return -1;}store64(state+56,1);}store64(state+16,after);store64(state+64,count+1);store64(state+72,name);store64(state+80,filename);store64(state+88,content_type);store64(state+96,bytes+at);store64(state+104,end-at);return 1;
}
fn mono_mp_name(state) {return load64(state+72);}
fn mono_mp_filename(state) {return load64(state+80);}
fn mono_mp_type(state) {return load64(state+88);}
fn mono_mp_data(state) {return load64(state+96);}
fn mono_mp_size(state) {return load64(state+104);}
