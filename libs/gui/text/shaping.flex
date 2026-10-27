// Immutable-font run cache: 64 sets x 4 ways, at most 2 MiB of owned runs/text.
// Results are borrowed until the next lookup or cache destruction. Large runs
// use one transient owned result, released on the next lookup.
import "font.flex";
fn ts_context(){let c=alloc(128);let entries=alloc(256*64);if c<0 || entries<0{if c>0{syscall(11,c,128,0,0,0,0);}if entries>0{syscall(11,entries,256*64,0,0,0,0);}return tf_fail("Cannot allocate shape cache");}tf_zero(c,128);tf_zero(entries,256*64);store64(c,entries);return c;}
fn ts_drop(c,e){if load64(e){tf_shape_free(load64(e+32));syscall(11,load64(e+24),load64(e+16)+1,0,0,0,0);store64(c+8,load64(c+8)-load64(e+40));tf_zero(e,64);}return 0;}
fn ts_context_free(c){if !c{return 0;}let i=0;while i<256{ts_drop(c,load64(c)+i*64);i=i+1;}tf_shape_free(load64(c+48));syscall(11,load64(c),256*64,0,0,0,0);syscall(11,c,128,0,0,0,0);return 0;}
fn ts_run(c,font,text){return ts_run_direction(c,font,text,0);}
fn ts_run_direction(c,font,text,direction){
    if direction && direction!=4 && direction!=5{return tf_fail("Invalid cached shape direction");}
    tf_shape_free(load64(c+48));store64(c+48,0);let n=tf_length(text);if n>32768{return tf_fail("Text run exceeds shaping limit");}let hash=0;let i=0;while i<n{hash=(hash*33+load8(text+i))&0x7fffffff;i=i+1;}
    let id=load64(font+80);let base=load64(c)+(((hash^(id*31)^direction)&63)*4)*64;let chosen=base;let oldest=9223372036854775807;store64(c+16,load64(c+16)+1);i=0;
    while i<4{let e=base+i*64;if load64(e)==id && load64(e+8)==hash && load64(e+16)==n && load64(e+56)==direction && bytes_common_prefix(load64(e+24),text,n)==n{store64(e+48,load64(c+16));store64(c+24,load64(c+24)+1);return load64(e+32);}let age=load64(e+48);if !load64(e){age=-1;}if age<oldest{oldest=age;chosen=e;}i=i+1;}
    store64(c+32,load64(c+32)+1);let s=tf_shape(font,text,n,direction);if !s{return 0;}store64(c+40,load64(c+40)+1);let bytes=n+1+load64(s+48);
    if bytes>2097152{store64(c+48,s);return s;}ts_drop(c,chosen);
    while load64(c+8)+bytes>2097152{let victim=0;oldest=9223372036854775807;i=0;while i<256{let e=load64(c)+i*64;if load64(e) && load64(e+48)<oldest{oldest=load64(e+48);victim=e;}i=i+1;}ts_drop(c,victim);}
    let copy=alloc(n+1);if copy<0{tf_shape_free(s);return tf_fail("Cannot retain shape text");}bytes_copy(copy,text,n);store8(copy+n,0);
    store64(chosen,id);store64(chosen+8,hash);store64(chosen+16,n);store64(chosen+24,copy);store64(chosen+32,s);store64(chosen+40,bytes);store64(chosen+48,load64(c+16));store64(chosen+56,direction);store64(c+8,load64(c+8)+bytes);return s;
}
