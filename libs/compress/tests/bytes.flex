// Directed and randomized compiler operation checks, including page boundaries.
import "../../../lib/bytes.flex";
import "../../../scripts/lib/host.flex";
global by_order=0;
fn by_arg(value) {by_order=by_order+1;return value;}
fn by_high(v) {if v<0 {return 63;}let i=-1;while v {v=v>>1;i=i+1;}return i;}
fn main(argc,argv) {
 let a=alloc(12288);let b=alloc(12288);let r=alloc(8192);h_assert(a>0 && b>0 && r>0,"byte buffers");h_assert(syscall(10,a+8192,4096,0,0,0,0)==0 && syscall(10,b+8192,4096,0,0,0,0)==0,"guard pages");
 let i=0;while i<8192 {store8(a+i,(i*13+23)&255);store8(b+i,0x7a);i=i+1;}
 let n=0;while n<=256 {let src=a+8192-n;let dst=b+8192-n;store8(dst-1,0x6d);h_assert(bytes_copy(dst,src,n)==dst,"copy result");h_assert(load8(dst-1)==0x6d,"copy lower guard");i=0;while i<n {h_assert(load8(src+i)==load8(dst+i),"copy bytes");i=i+1;}
  h_assert(bytes_common_prefix(src,dst,n)==n,"equal prefix at page end");i=0;while i<n {let old=load8(dst+i);store8(dst+i,old^1);h_assert(bytes_common_prefix(src,dst,n)==i,"first mismatch at every lane");store8(dst+i,old);i=i+1;}
  h_assert(bytes_fill(dst,0x12345,n)==dst && load8(dst-1)==0x6d,"fill result and lower guard");i=0;while i<n {h_assert(load8(dst+i)==0x45,"fill truncates to byte");i=i+1;}
  if n>=4 {h_assert(bytes_store32(dst+n-4,0x123456789abcdef0)==0x123456789abcdef0,"store32 result");h_assert(bytes_load32(dst+n-4)==0x9abcdef0,"unaligned load32 zero extends");}
  n=n+1;
 }
 // Forward overlap is observable: this is deliberately not memmove semantics.
 n=0;while n<128 {i=0;while i<256 {store8(a+i,i);store8(r+i,i);i=i+1;}bytes_copy(a+1,a,n);i=0;while i<n {store8(r+1+i,load8(r+i));i=i+1;}i=0;while i<256 {h_assert(load8(a+i)==load8(r+i),"forward overlap");i=i+1;}n=n+1;}
 let seed=53;i=0;while i<10000 {seed=seed*6364136223846793005+1442695040888963407;h_assert(word_high_bit(seed)==by_high(seed),"all high bits");i=i+1;}h_assert(word_high_bit(0)==(-1) && word_high_bit(1)==0 && word_high_bit(0x8000000000000000)==63,"bit scan edge cases");
 by_order=0;h_assert(bytes_copy(by_arg(b),by_arg(a),by_arg(0))==b && by_order==3,"arguments evaluated exactly once");h_assert(bytes_common_prefix(a+8192,b+8192,0)==0 && bytes_copy(b+8192,a+8192,0)==b+8192,"zero lengths do not touch guard pages");h_print(1,"Byte lowering: boundaries, overlap, return values, bit scans and argument evaluation pass\n");return 0;
}
