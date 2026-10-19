// Copyright 2023 The Go Authors. All rights reserved.
// XXH64 adapted from Go internal/zstd; BSD-3-Clause, licenses/Go-BSD.txt.
fn fz_rot(v,n) {return (v<<n)|((v>>(64-n))&((1<<n)-1));}
fn fz_xround(v,n) {return fz_rot(v+n*0xc2b2ae3d27d4eb4f,31)*0x9e3779b185ebca87;}
fn fz_xmerge(v,n) {return (v^fz_xround(0,n))*0x9e3779b185ebca87+0x85ebca77c2b2ae63;}
// length, four accumulators, tail count, tail bytes (32).
fn fz_xreset(x) {store64(x,0);store64(x+8,0x9e3779b185ebca87+0xc2b2ae3d27d4eb4f);store64(x+16,0xc2b2ae3d27d4eb4f);store64(x+24,0);store64(x+32,-0x9e3779b185ebca87);store64(x+40,0);return 1;}
fn fz_xstripe(x,p) {let i=0;while i<4 {store64(x+8+i*8,fz_xround(load64(x+8+i*8),load64(p+i*8)));i=i+1;}return 1;}
fn fz_xupdate(x,p,n) {
 store64(x,load64(x)+n);let count=load64(x+40);let off=0;
 if count {let take=fz_min(n,32-count);fz_copy(x+48+count,p,take);count=count+take;off=take;if count==32 {fz_xstripe(x,x+48);count=0;}}
 while off+32<=n {fz_xstripe(x,p+off);off=off+32;}
 if off<n {fz_copy(x+48,p+off,n-off);count=n-off;}store64(x+40,count);return 1;
}
fn fz_xdigest(x) {
 let h=0;if load64(x)<32 {h=0x27d4eb2f165667c5;}else {h=fz_rot(load64(x+8),1)+fz_rot(load64(x+16),7)+fz_rot(load64(x+24),12)+fz_rot(load64(x+32),18);let j=0;while j<4 {h=fz_xmerge(h,load64(x+8+j*8));j=j+1;}}
 h=h+load64(x);let p=x+48;let n=load64(x+40);let i=0;
 while i+8<=n {h=h^fz_xround(0,load64(p+i));h=fz_rot(h,27)*0x9e3779b185ebca87+0x85ebca77c2b2ae63;i=i+8;}
 if i+4<=n {h=h^(fz_u32(p+i)*0x9e3779b185ebca87);h=fz_rot(h,23)*0xc2b2ae3d27d4eb4f+0x165667b19e3779f9;i=i+4;}
 while i<n {h=h^(load8(p+i)*0x27d4eb2f165667c5);h=fz_rot(h,11)*0x9e3779b185ebca87;i=i+1;}
 h=h^((h>>33)&0x7fffffff);h=h*0xc2b2ae3d27d4eb4f;h=h^((h>>29)&0x7ffffffff);h=h*0x165667b19e3779f9;return h^((h>>32)&0xffffffff);
}
