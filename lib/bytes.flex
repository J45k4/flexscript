// Exact-bound byte primitives, with portable bodies for interpreter/JIT/Wasm
// and native instruction selection through the public lowering mechanism.
lowering bytes_copy "memory.copy" "native-x86_64";
lowering bytes_fill "memory.fill" "native-x86_64";
lowering bytes_load32 "word.load32" "native-x86_64";
lowering bytes_store32 "word.store32" "native-x86_64";
lowering word_high_bit "word.high_bit" "native-x86_64";
lowering bytes_common_prefix "memory.common_prefix" "native-x86_64";
// Valid readable/writable ranges and nonnegative sizes are caller preconditions.
// Copy proceeds forward byte by byte, including overlapping ranges.
fn bytes_copy(dst,src,n) {let i=0;while i<n {store8(dst+i,load8(src+i));i=i+1;}return dst;}
fn bytes_fill(dst,value,n) {let i=0;while i<n {store8(dst+i,value);i=i+1;}return dst;}
fn bytes_load32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn bytes_store32(p,v) {store8(p,v);store8(p+1,v>>8);store8(p+2,v>>16);store8(p+3,v>>24);return v;}
fn word_high_bit(v) {if v<0 {return 63;}let bit=-1;while v {v=v>>1;bit=bit+1;}return bit;}
fn bytes_common_prefix(a,b,n) {let i=0;while i<n && load8(a+i)==load8(b+i) {i=i+1;}return i;}
