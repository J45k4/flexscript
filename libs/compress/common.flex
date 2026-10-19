// Byte operations shared by the native codec. No compression FFI.
import "../../lib/bytes.flex";
lowering fz_copy "memory.copy" "native-x86_64";
lowering fz_fill "memory.fill" "native-x86_64";
lowering fz_u32 "word.load32" "native-x86_64";
lowering fz_log "word.high_bit" "native-x86_64";
fn fz_copy(d,s,n) {let i=0;while i+32<=n {store64(d+i,load64(s+i));store64(d+i+8,load64(s+i+8));store64(d+i+16,load64(s+i+16));store64(d+i+24,load64(s+i+24));i=i+32;}while i+8<=n {store64(d+i,load64(s+i));i=i+8;}while i<n {store8(d+i,load8(s+i));i=i+1;}return d;}
fn fz_fill(d,v,n) {let w=(v&255)*0x0101010101010101;let i=0;while i+8<=n {store64(d+i,w);i=i+8;}while i<n {store8(d+i,v);i=i+1;}return d;}
fn fz_u16(p) {return load8(p)|(load8(p+1)<<8);}
fn fz_u24(p) {return fz_u16(p)|(load8(p+2)<<16);}
fn fz_u32(p) {return fz_u16(p)|(fz_u16(p+2)<<16);}
fn fz_le(p,v,n) {let i=0;while i<n {store8(p+i,v);v=v>>8;i=i+1;}return p;}
fn fz_log(v) {if v<0 {return 63;}if !v {return -1;}let n=0;if v>=4294967296 {v=v>>32;n=n+32;}if v>=65536 {v=v>>16;n=n+16;}if v>=256 {v=v>>8;n=n+8;}if v>=16 {v=v>>4;n=n+4;}if v>=4 {v=v>>2;n=n+2;}if v>=2 {n=n+1;}return n;}
fn fz_min(a,b) {if a<b {return a;}return b;}
fn fz_fail(c,s) {if !load64(c) {store64(c,s);}return -1;}
fn zstd_error(c) {if !c {return "Zstd allocation failed";}return load64(c);}
// Forward bit reader: data, size, next byte, bit reservoir, valid bits.
fn fz_fmore(b) {while load64(b+32)<16 {let off=load64(b+16);if off>=load64(b+8) {return 0;}store64(b+24,load64(b+24)|(load8(load64(b)+off)<<load64(b+32)));store64(b+16,off+1);store64(b+32,load64(b+32)+8);}return 1;}
fn fz_fval(b,n) {let v=load64(b+24)&((1<<n)-1);store64(b+24,load64(b+24)>>n);store64(b+32,load64(b+32)-n);return v;}
// Reverse bit reader: data, first byte, current byte, reservoir, valid bits.
fn fz_rinit(b,p,start,end) {if end<start || !load8(p+end) {return 0;}store64(b,p);store64(b+8,start);store64(b+16,end);store64(b+24,load8(p+end));store64(b+32,fz_log(load8(p+end)));return 1;}
fn fz_rfetch(b,n) {while load64(b+32)<n {let off=load64(b+16);if off<=load64(b+8) {return 0;}off=off-1;store64(b+16,off);store64(b+24,(load64(b+24)<<8)|load8(load64(b)+off));store64(b+32,load64(b+32)+8);}return 1;}
fn fz_rval(b,n) {if !fz_rfetch(b,n) {return -1;}let cnt=load64(b+32)-n;store64(b+32,cnt);return (load64(b+24)>>cnt)&((1<<n)-1);}
fn fz_remain(b) {return (load64(b+16)-load64(b+8))*8+load64(b+32);}
