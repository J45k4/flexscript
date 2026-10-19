import "../../lib/bytes.flex";
// Caller supplies two disjoint n+8 byte buffers. No host services are required.
fn kernel(a,b,n) {
 let i=0;while i<n+8 {store8(a+i,i*13);store8(b+i,0x7a);i=i+1;}
 if bytes_copy(b,a,n)!=b {return 1;}
 if bytes_common_prefix(a,b,n)!=n || load8(b+n)!=0x7a {return 2;}
 i=0;while i<n {if load8(b+i)!=((i*13)&255) {return 3;}i=i+1;}
 if n {store8(b+n-1,load8(b+n-1)^1);if bytes_common_prefix(a,b,n)!=n-1 {return 4;}}
 if bytes_fill(b,0x12345,n)!=b || load8(b+n)!=0x7a {return 5;}
 i=0;while i<n {if load8(b+i)!=0x45 {return 6;}i=i+1;}
 if bytes_store32(b+n,0x123456789abcdef0)!=0x123456789abcdef0 || bytes_load32(b+n)!=0x9abcdef0 {return 7;}
 if word_high_bit(0)!=(-1) || word_high_bit(1)!=0 || word_high_bit(0x8000000000000000)!=63 {return 8;}
 if n>1 {i=0;while i<n {store8(a+i,i);i=i+1;}bytes_copy(a+1,a,n-1);i=0;while i<n {if load8(a+i)!=0 {return 9;}i=i+1;}}
 return 0;
}
