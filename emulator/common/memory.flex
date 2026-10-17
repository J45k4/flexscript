// Shared binary/memory primitives for normal-process machine emulators.
// Callers validate guest ranges before exposing a host pointer.
fn em_u32(p){return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn em_put32(p,n){let i=0;while i<4{store8(p+i,n>>(i*8));i=i+1;}return 0;}
fn em_zero(p,n){let i=0;while i<n{store8(p+i,0);i=i+1;}return p;}
fn em_copy(to,from,n){let i=0;while i<n{store8(to+i,load8(from+i));i=i+1;}return 0;}
fn em_range(size,offset,n){return offset>=0 && n>=0 && offset<=size && n<=size-offset;}
