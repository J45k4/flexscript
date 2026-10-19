// Private arenas and byte containers. Database and query lifetimes are separate.
global fd_last_error=0;
global fd_copy_code=0;
fn fd_panic() {syscall(1,2,"FlexDB: out of memory\n",22,0,0,0);syscall(60,1,0,0,0,0,0);return 0;}
fn fd_alloc(a,n) {
    if n<0 || n>67108864 {fd_panic();}
    n=(n+7)&(-8);
    if !load64(a) || n>load64(a+16)-load64(a+8) {
        let size=65536;if n+16>size {size=(n+4111)&(-4096);}
        let p=alloc(size);if p<=0 {fd_panic();}
        store64(p,load64(a));store64(p+8,size);store64(a,p);store64(a+8,0);store64(a+16,size-16);
    }
    let p=load64(a)+16+load64(a+8);store64(a+8,load64(a+8)+n);return p;
}
fn fd_clear(a) {
    // mmap commonly puts successive arena blocks next to one another. Release
    // an adjacent owned run with one munmap, reading its links beforehand.
    // Exact adjacency is required: gaps and blocks from other arenas survive.
    let p=load64(a);while p {let start=p;let end=p+load64(p+8);let next=load64(p);let joined=1;
        while next && joined {let size=load64(next+8);if next+size==start {start=next;next=load64(next);}else if next==end {end=next+size;next=load64(next);}else {joined=0;}}
        syscall(11,start,end-start,0,0,0,0);p=next;
    }
    store64(a,0);store64(a+8,0);store64(a+16,0);return 0;
}
// Large disjoint copies use a tiny baseline x86-64 entry (System V arguments
// RDI/RSI/RDX). REP MOVSB has exact byte bounds; small/overlapping copies keep
// the original loop. Executable-memory failure keeps the Flexscript fallback.
fn fd_copy_init() {
    if fd_copy_code {return fd_copy_code;}fd_copy_code=-1;let p=alloc(4096);if p<=0 {return -1;}
    store64(p,0xf3fcd18948f88948);store8(p+8,0xa4);store8(p+9,0xc3); // mov rax,rdi; mov rcx,rdx; cld; rep movsb; ret
    if syscall(10,p,4096,5,0,0,0)<0 {syscall(11,p,4096,0,0,0,0);return -1;}fd_copy_code=p;return p;
}
fn fd_copy(to,from,n) {
    if n>=512 && ((to>=from && to-from>=n) || (from>=to && from-to>=n)) {let code=fd_copy_code;if !code {code=fd_copy_init();}if code>0 {return ffi_call(code,to,from,n,0,0,0);}}
    let i=0;while i<=n-32 {store64(to+i,load64(from+i));store64(to+i+8,load64(from+i+8));store64(to+i+16,load64(from+i+16));store64(to+i+24,load64(from+i+24));i=i+32;}while i<=n-8 {store64(to+i,load64(from+i));i=i+8;}while i<n {store8(to+i,load8(from+i));i=i+1;}return to;
}
fn fd_len(s) {let n=0;while (s+n)&7 {if !load8(s+n) {return n;}n=n+1;}while 1 {let w=load64(s+n);if ((w-0x0101010101010101)&(~w)&0x8080808080808080) {let i=0;while i<8 {if !load8(s+n+i) {return n+i;}i=i+1;}}n=n+8;}return n;}
fn fd_bytes(a,b,n) {let i=0;while i<=n-32 {if load64(a+i)!=load64(b+i) || load64(a+i+8)!=load64(b+i+8) || load64(a+i+16)!=load64(b+i+16) || load64(a+i+24)!=load64(b+i+24) {return 0;}i=i+32;}while i<=n-8 {if load64(a+i)!=load64(b+i) {return 0;}i=i+8;}while i<n {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn fd_text(a,s) {let n=fd_len(s);let p=fd_alloc(a,n+1);fd_copy(p,s,n);store8(p+n,0);return p;}
fn fd_same(a,b) {let n=fd_len(a);return n==fd_len(b) && fd_bytes(a,b,n);}
fn fd_error(db,message) {fd_last_error=message;if db {store64(db+32,message);}return 0;}
fn flexdb_error(db) {if db {return load64(db+32);}return fd_last_error;}
// Vector/buffer: length, capacity, data. Old allocations live until arena close.
fn fd_vec(a) {let p=fd_alloc(a,24);store64(p,0);store64(p+8,0);store64(p+16,0);return p;}
fn fd_at(v,i) {return load64(load64(v+16)+i*8);}
fn fd_reserve(a,v,n) {
    if n<0 || n>16777216 {return 0;}
    if n<=load64(v+8) {return 1;}
    let cap=load64(v+8)*2;if cap<64 {cap=64;}if cap<n {cap=n;}if cap>16777216 {cap=16777216;}
    let p=fd_alloc(a,cap);fd_copy(p,load64(v+16),load64(v));store64(v+8,cap);store64(v+16,p);return 1;
}
fn fd_append(a,v,p,n) {if !fd_reserve(a,v,load64(v)+n) {return 0;}fd_copy(load64(v+16)+load64(v),p,n);store64(v,load64(v)+n);return 1;}
fn fd_word(a,v,w) {let n=load64(v);if !fd_reserve(a,v,n+8) {return 0;}store64(load64(v+16)+n,w);store64(v,n+8);return 1;}
fn fd_push(a,v,w) {if !fd_word(a,v,w) {fd_panic();}return 1;}
fn fd_size(v) {return load64(v)/8;}
fn fd_clone_vec(a,v) {let p=fd_vec(a);if !fd_append(a,p,load64(v+16),load64(v)) {fd_panic();}return p;}
fn fd_put(v,i,w) {store64(load64(v+16)+i*8,w);return w;}
// Values: kind (0 null, 1 i64, 2 text, 3 blob, 4 f64 bits), word/data, bytes.
fn fd_value(a,kind,word,n) {let p=fd_alloc(a,24);store64(p,kind);store64(p+8,word);store64(p+16,n);return p;}
fn flexdb_null(a) {return fd_value(a,0,0,0);}
fn flexdb_int(a,n) {return fd_value(a,1,n,0);}
fn flexdb_text(a,s) {let n=fd_len(s);let p=fd_alloc(a,24+n+1);store64(p,2);store64(p+8,p+24);store64(p+16,n);fd_copy(p+24,s,n);store8(p+24+n,0);return p;}
fn flexdb_blob(a,p,n) {if n<0 || n>67108863 {return 0;}let b=fd_alloc(a,n+1);fd_copy(b,p,n);store8(b+n,0);return fd_value(a,3,b,n);}
fn flexdb_real(a,bits) {return fd_value(a,4,bits,0);}
fn flexdb_kind(v) {return load64(v);}
fn flexdb_int_type() {return 1;}
fn flexdb_text_type() {return 2;}
fn flexdb_blob_type() {return 3;}
fn flexdb_real_type() {return 4;}
fn flexdb_word(v) {return load64(v+8);}
fn flexdb_bytes(v) {let n=load64(v+16);if load64(v)==3 && n<0 {return -n-1;}return n;}
fn fd_clone_value(a,v) {
    let kind=load64(v);if kind==3 && load64(v+16)<0 {return fd_value(a,3,load64(v+8),load64(v+16));}if kind==2 || kind==3 {let n=load64(v+16);let p=fd_alloc(a,n+1);fd_copy(p,load64(v+8),n);store8(p+n,0);return fd_value(a,kind,p,n);}
    return fd_value(a,kind,load64(v+8),0);
}
fn flexdb_values(a) {let p=fd_alloc(a,88);store64(p,0);store64(p+8,64);store64(p+16,p+24);return p;}
fn flexdb_add(a,values,v) {if !v || !fd_push(a,values,v) {return 0;}return values;}
fn flexdb_rowid(row) {return load64(row);}
fn flexdb_cell(row,column) {if column<0 || column>=load64(row+8) {return 0;}return load64(row+16+column*8);}
// One allocation owns the row, value descriptors and copied byte payloads.
fn fd_row(a,id,values) {
    let n=fd_size(values);let bytes=16+n*32;let i=0;while i<n {let v=fd_at(values,i);let kind=load64(v);if (kind==2 || kind==3) && load64(v+16)>=0 {bytes=bytes+((load64(v+16)+8)&(-8));}i=i+1;}
    let r=fd_alloc(a,bytes);store64(r,id);store64(r+8,n);let payload=r+16+n*32;i=0;
    while i<n {let v=fd_at(values,i);let copy=r+16+n*8+i*24;let kind=load64(v);store64(r+16+i*8,copy);store64(copy,kind);
        if kind==3 && load64(v+16)<0 {store64(copy+8,load64(v+8));store64(copy+16,load64(v+16));}else if kind==2 || kind==3 {let size=load64(v+16);fd_copy(payload,load64(v+8),size);store8(payload+size,0);store64(copy+8,payload);store64(copy+16,size);payload=payload+((size+8)&(-8));}
        else {store64(copy+8,load64(v+8));store64(copy+16,0);}i=i+1;
    }return r;
}

// Internal schema replacement only: values already belong to the database.
// Public mutation APIs keep copying caller-owned values through fd_row.
fn fd_row_refs(db,id,values) {
    let count=fd_size(values);let row=fd_alloc(db,16+count*8);store64(row,id);store64(row+8,count);fd_copy(row+16,load64(values+16),count*8);return row;
}
fn fd_schema_value(db,v) {
    if !v {return fd_error(db,"schema converter failed");}let kind=load64(v);let bytes=load64(v+16);
    if kind<0 || kind>4 || !fd_blob_value_ok(db,v,kind,bytes) {return fd_error(db,"row value does not match column type/nullability");}
    return fd_clone_value(db,v);
}

fn fd_text_equal_n(word,query,n) {return fd_len(word)==n && fd_bytes(word,query,n);}
