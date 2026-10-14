// Adaptive equality indexes are derived caches, never logical schema rules.
// Table+120: candidate vector. DB+200: policy; +224: tuning dirty (1 stats,
// 2 topology); +248: transaction change events. Hash buckets are (hash,row ID).
fn fd_auto_policy(db) {
    let p=load64(db+200);if p {return p;}p=fd_alloc(db,128);store64(p,0);store64(p+8,8388608);store64(p+16,0);store64(p+24,4);store64(p+32,0);store64(p+40,262144);store64(p+48,100000000);store64(p+56,256);store64(p+64,4);store64(p+72,8);store64(p+80,32768);store64(p+88,64);store64(p+104,1024);store64(db+200,p);return p;
}
fn fd_auto_clock(clock) {if syscall(228,1,clock,0,0,0,0)<0 {return 0;}return load64(clock)*1000000000+load64(clock+8);}
// Candidate (184 bytes): name,col,kind,calls,scanned,matches,data,capacity,
// live,last use,hits,source buckets,owned arena,cooldown,page CRCs,page flags,count arena,
// count data,owner table,count capacity,min,max,bounds-known.
// Mapped buckets remain read-only; writable pages are copied on demand.
fn fd_auto_find(t,col) {let v=load64(t+120);if !v {return 0;}let i=0;while i<fd_size(v) {let x=fd_at(v,i);if load64(x+8)==col {return x;}i=i+1;}return 0;}
fn fd_auto_new(t,col,kind) {
    let db=load64(t);if !load64(t+120) {store64(t+120,fd_vec(db));}let x=fd_alloc(db,184);store64(x,fd_text(db,load64(fd_at(load64(t+16),col))));store64(x+8,col);store64(x+16,kind);store64(x+144,t);fd_push(db,load64(t+120),x);return x;
}
fn fd_auto_drop(x,cooldown) {
    store64(x+176,0);fd_auto_count_clear(x);if !load64(x+48) {return 1;}let db=load64(load64(x+144));let p=fd_auto_policy(db);store64(p+16,load64(p+16)-load64(x+56)*16);store64(p+32,load64(p+32)-1);
    let a=load64(x+96);if a<0 {a=-a;}if a {fd_clear(a);syscall(11,a,32,0,0,0,0);}store64(x+48,0);store64(x+56,0);store64(x+64,0);store64(x+88,0);store64(x+96,0);store64(x+112,0);store64(x+120,0);store64(x+104,load64(p)+cooldown);store64(db+224,2);return 1;
}
fn fd_auto_clear(t) {let v=load64(t+120);if v {let i=0;while i<fd_size(v) {fd_auto_drop(fd_at(v,i),0);i=i+1;}store64(t+120,0);store64(load64(t)+224,2);}return 1;}
fn fd_auto_hash(kind,word) {
    if kind==1 {let h=word^((word>>33)&0x7fffffff);h=h*(-49064778989728563);h=h^((h>>33)&0x7fffffff);h=h*(-4265267296055464877);return h^((h>>33)&0x7fffffff);}
    return fd_hash_bytes(word,fd_len(word));
}
fn fd_hash_bytes(word,n) {
    let h=1469598103934665603^n;let i=0;
    while i<=n-32 {h=(h^load64(word+i))*1099511628211;h=(h^load64(word+i+8))*1099511628211;h=(h^load64(word+i+16))*1099511628211;h=(h^load64(word+i+24))*1099511628211;i=i+32;}
    while i<=n-8 {h=(h^load64(word+i))*1099511628211;i=i+8;}while i<n {h=(h^load8(word+i))*1099511628211;i=i+1;}
    h=h^((h>>33)&0x7fffffff);h=h*(-49064778989728563);return h^((h>>33)&0x7fffffff);
}
// A negative owner marks a sparse writable copy of mapped buckets. Flags:
// 0 = unchecked source page, 1 = checked source, 2 = copied writable page.
fn fd_auto_page(x,page) {
    let owner=load64(x+96);if owner>0 || !load64(x+112) {return 1;}let flags=load64(x+120);let state=load8(flags+page);if state==2 || (state==1 && !owner) {return 1;}
    let bytes=load64(x+56)*16-page*4096;if bytes>4096 {bytes=4096;}let source=load64(x+48);if owner<0 {source=load64(x+88);}
    if !state && (fd_crc(4294967295,source+page*4096,bytes)^4294967295)!=load64(load64(x+112)+page*8) {return fd_corrupt(load64(load64(x+144)),"automatic index checksum mismatch");}
    if owner<0 {fd_copy(load64(x+48)+page*4096,source+page*4096,bytes);store8(flags+page,2);}else {store8(flags+page,1);}return 1;
}
fn fd_auto_bucket(x,slot,hash) {
    if !fd_auto_page(x,slot/256) {return -2;}let entry=load64(x+48)+slot*16;let id=load64(entry+8);let t=load64(x+144);
    if id<(-1) || id>=load64(t+32) || (id==0 && load64(entry)!=0) {fd_corrupt(load64(t),"invalid automatic index bucket");return -2;}
    if id<=0 {return id;}if load64(entry)!=hash {return -1;}return id;
}
fn fd_auto_insert_bucket(x,hash,id) {
    let capacity=load64(x+56);let slot=hash&(capacity-1);let left=capacity;let tomb=-1;let checked=load64(x+96)<=0 && load64(x+112);
    while left {if checked && !fd_auto_page(x,slot/256) {return 0;}let entry=load64(x+48)+slot*16;let found=load64(entry+8);if found==0 {if tomb>=0 {entry=load64(x+48)+tomb*16;}store64(entry,hash);store64(entry+8,id);store64(x+64,load64(x+64)+1);return 1;}
        if found==(-1) && tomb<0 {tomb=slot;}if found==id && load64(entry)==hash {return 1;}slot=(slot+1)&(capacity-1);left=left-1;}
    if tomb>=0 {let entry=load64(x+48)+tomb*16;store64(entry,hash);store64(entry+8,id);store64(x+64,load64(x+64)+1);return 1;}return 0;
}
// Backward-shift deletion keeps the probing chain intact without tombstones.
fn fd_auto_remove_bucket(x,hash,id) {
    let capacity=load64(x+56);let mask=capacity-1;let data=load64(x+48);let slot=hash&mask;let left=capacity;let checked=load64(x+96)<=0 && load64(x+112);
    while left {if checked && !fd_auto_page(x,slot/256) {return 0;}let entry=data+slot*16;let found=load64(entry+8);if !found {return 0;}if found==id && load64(entry)==hash {
        let hole=slot;let next=(hole+1)&mask;let remain=capacity;let stop=0;
        while remain && !stop {if checked && !fd_auto_page(x,next/256) {return 0;}let p=data+next*16;if !load64(p+8) {stop=1;}else {let home=load64(p)&mask;if ((next-home)&mask)>((hole-home)&mask) {store64(data+hole*16,load64(p));store64(data+hole*16+8,load64(p+8));hole=next;}next=(next+1)&mask;}remain=remain-1;}
        store64(data+hole*16,0);store64(data+hole*16+8,0);store64(x+64,load64(x+64)-1);return 1;
    }slot=(slot+1)&mask;left=left-1;}return 0;
}
fn fd_auto_own(x) {
    if load64(x+96) {return 1;}let bytes=load64(x+56)*16;let a=alloc(32);if a<=0 {fd_panic();}
    // Align the data to an OS page so copying one logical page does not fault
    // in two writable pages. Anonymous untouched pages occupy no physical RAM.
    let data=(fd_alloc(a,bytes+4095)+4095)&(-4096);let source=load64(x+48);
    if load64(x+112) {store64(x+88,source);store64(x+48,data);store64(x+96,-a);}
    else {fd_copy(data,source,bytes);store64(x+48,data);store64(x+96,a);}return 1;
}
fn fd_auto_materialized(x) {let owner=load64(x+96);if owner<0 {store64(x+96,-owner);store64(x+88,0);store64(x+112,0);store64(x+120,0);}return 1;}
fn fd_auto_room(db,bytes,keep) {
    let p=fd_auto_policy(db);if bytes>load64(p+8) {return 0;}
    while load64(p+16)+bytes>load64(p+8) || load64(p+32)>=load64(p+24) {
        let oldest=0;let tables=load64(db+40);let i=0;while i<fd_size(tables) {let v=load64(fd_at(tables,i)+120);if v {let j=0;while j<fd_size(v) {let x=fd_at(v,j);if x!=keep && load64(x+48) && (!oldest || load64(x+72)<load64(oldest+72)) {oldest=x;}j=j+1;}}i=i+1;}
        if !oldest {return 0;}fd_auto_drop(oldest,load64(p+88));
    }return 1;
}
// During a fresh build every bucket is either unused or permanently consumed.
// Path compression finds the first unused linear-probing slot without repeatedly
// scanning duplicate clusters. At most half the buckets are filled, so wrapping
// successor links cannot form a full-table cycle. This scratch is never cached.
fn fd_auto_free_slot(parents,slot) {
    let next=load64(parents+slot*8);while next!=slot {let after=load64(parents+next*8);store64(parents+slot*8,after);slot=next;next=after;}return slot;
}
fn fd_auto_build_insert(x,parents,hash,id) {
    let mask=load64(x+56)-1;let slot=fd_auto_free_slot(parents,hash&mask);let entry=load64(x+48)+slot*16;store64(entry,hash);store64(entry+8,id);
    store64(parents+slot*8,fd_auto_free_slot(parents,(slot+1)&mask));store64(x+64,load64(x+64)+1);return 1;
}
fn fd_auto_build(x) {
    let t=load64(x+144);let db=load64(t);let p=fd_auto_policy(db);let rows=fd_size(load64(t+24));let capacity=32;while capacity<rows*2 {capacity=capacity*2;}
    let bytes=capacity*16;if rows>load64(p+40) || !fd_auto_room(db,bytes,x) {store64(x+104,load64(p)+load64(p+88));return 0;}
    let a=alloc(32);if a<=0 {fd_panic();}let data=fd_alloc(a,bytes);store64(x+176,0);let clock=fd_alloc(a,16);let start=fd_auto_clock(clock);store64(x+48,data);store64(x+56,capacity);store64(x+64,0);store64(x+96,a);store64(x+112,0);store64(x+120,0);let i=0;let ok=1;let scratch=0;let parents=0;
    // Observed duplicate cardinality selects this build strategy. Unique builds
    // retain the smaller direct path; both produce identical bucket contents.
    if load64(x+40)>=load64(x+24)*4 {scratch=alloc(32);if scratch<=0 {fd_panic();}parents=fd_alloc(scratch,capacity*8);while i<capacity && ok {store64(parents+i*8,i);if (i&1023)==0 {let time=fd_auto_clock(clock);if !start || !time || time-start>load64(p+48) {ok=0;}}i=i+1;}i=0;}
    while i<rows && ok {let row=fd_table_row(t,i);if !row {ok=0;}else if load64(row+8) {let value=flexdb_cell(row,load64(x+8));let inserted=0;let hash=fd_auto_hash(load64(x+16),flexdb_word(value));if parents {inserted=fd_auto_build_insert(x,parents,hash,load64(row));}else {inserted=fd_auto_insert_bucket(x,hash,load64(row));}if !inserted {ok=0;}else if load64(x+16)==1 {fd_auto_bounds_add(x,flexdb_word(value));}}
        if (i&63)==0 || (load64(x+16)==2 && row && load64(row+8) && flexdb_bytes(flexdb_cell(row,load64(x+8)))>1024) {let time=fd_auto_clock(clock);if !start || !time || time-start>load64(p+48) {ok=0;}}i=i+1;
    }
    if scratch {fd_clear(scratch);syscall(11,scratch,32,0,0,0,0);}
    if !ok {fd_clear(a);syscall(11,a,32,0,0,0,0);store64(x+48,0);store64(x+56,0);store64(x+64,0);store64(x+96,0);store64(x+104,load64(p)+load64(p+88));return 0;}
    store64(p+16,load64(p+16)+bytes);store64(p+32,load64(p+32)+1);store64(x+88,0);store64(db+224,2);return 1;
}
fn fd_auto_prepare(t,col,kind,word) {
    let db=load64(t);if load64(db+48) {return 0;}let columns=load64(t+16);if col<0 || col>=fd_size(columns) {return 0;}let c=fd_at(columns,col);
    if load64(c+8)!=kind || load64(c+16) || (kind!=1 && kind!=2) {return 0;}if kind==2 && !word {fd_error(db,"text lookup requires a valid string");return -1;}
    let p=fd_auto_policy(db);store64(p,load64(p)+1);if (load64(p)&63)==0 {fd_auto_expire(db);}if !load64(p+8) {return 0;}let x=fd_auto_find(t,col);if !x {x=fd_auto_new(t,col,kind);}store64(x+24,load64(x+24)+1);store64(x+72,load64(p));store64(db+224,1+(load64(db+224)>1));
    if !load64(x+48) && load64(p)>=load64(x+104) && fd_size(load64(t+24))>=load64(p+56) && load64(x+24)>load64(p+64) && load64(x+32)>=load64(p+80) && load64(x+40)*load64(p+72)<load64(x+32) {fd_auto_build(x);if load64(db+48)==2 {return -1;}}
    if load64(x+48) {store64(x+80,load64(x+80)+1);return x;}return 0;
}
fn fd_auto_done(t,col,matches,scan) {
    let x=fd_auto_find(t,col);if !x {return 1;}if scan {store64(x+40,load64(x+40)+matches);store64(x+32,load64(x+32)+fd_size(load64(t+24)));}return 1;
}
fn fd_auto_event(t,id,before,after) {
    if !load64(t+120) {return 1;}let db=load64(t);let a=load64(db+72);let e=fd_alloc(a,40);store64(e,t);store64(e+8,id);store64(e+16,before);store64(e+24,after);store64(e+32,load64(t+16));fd_push(a,load64(db+248),e);return 1;
}
// One maintenance path for successful commits and validated recovery frames.
fn fd_auto_change(t,id,before,after) {
    let v=load64(t+120);if !v {return 1;}let db=load64(t);let j=0;
    while j<fd_size(v) {let x=fd_at(v,j);if load64(x+48) {let col=load64(x+8);let same=0;
        if before && after && load64(before+8) && load64(after+8) {same=fd_same_value(flexdb_cell(before,col),flexdb_cell(after,col));}
        if !same {fd_auto_count_clear(x);if !fd_auto_own(x) {return 0;}
            if before && load64(before+8) && !fd_auto_remove_bucket(x,fd_auto_hash(load64(x+16),flexdb_word(flexdb_cell(before,col))),id) {if load64(db+48)==2 {return 0;}fd_auto_drop(x,8);}
            if load64(x+48) && after && load64(after+8) {
                if load64(x+64)*4>=load64(x+56)*3 {fd_auto_drop(x,8);}
                else if !fd_auto_insert_bucket(x,fd_auto_hash(load64(x+16),flexdb_word(flexdb_cell(after,col))),id) {if load64(db+48)==2 {return 0;}fd_auto_drop(x,8);}
            }
            if load64(x+48) && load64(x+176) && load64(x+16)==1 && after && load64(after+8) {fd_auto_bounds_add(x,flexdb_word(flexdb_cell(after,col)));}store64(db+224,2);
        }
    }j=j+1;}return 1;
}
fn fd_auto_commit(db) {
    let events=load64(db+248);let i=0;
    while i<fd_size(events) {let e=fd_at(events,i);let t=load64(e);if load64(e+32)==load64(t+16) && !fd_auto_change(t,load64(e+8),load64(e+16),load64(e+24)) {return 0;}i=i+1;}return 1;
}
fn fd_same_value(a,b) {if flexdb_kind(a)!=flexdb_kind(b) {return 0;}if flexdb_kind(a)==2 {return fd_same(flexdb_word(a),flexdb_word(b));}return flexdb_word(a)==flexdb_word(b);}
fn fd_auto_close(db) {let tables=load64(db+40);let i=0;while i<fd_size(tables) {fd_auto_clear(fd_at(tables,i));i=i+1;}return 1;}
fn flexdb_auto_budget(db,bytes) {if !fd_ready(db) {return 0;}if load64(db+48) || bytes<0 || bytes>67108864 {return fd_error(db,"invalid automatic-index budget or active transaction");}let p=fd_auto_policy(db);store64(p+8,bytes);fd_auto_close(db);return 1;}
fn flexdb_index_state(t,col) {if !fd_table_ready(t) {return -1;}let x=fd_auto_find(t,col);if !x {return 0;}if load64(x+48) {return 2;}return 1;}
fn flexdb_index_queries(t,col) {let x=fd_auto_find(t,col);if !x {return 0;}return load64(x+24);}
fn flexdb_index_hits(t,col) {let x=fd_auto_find(t,col);if !x {return 0;}return load64(x+80);}
fn flexdb_index_bytes(db) {if !fd_ready(db) {return -1;}return load64(fd_auto_policy(db)+16);}
fn fd_rows_order(q,result) {
    let v=load64(result+8);let n=fd_size(v);if n<2 {return 1;}let temporary=fd_alloc(q,n*8);let data=load64(v+16);let width=1;
    while width<n {let at=0;while at<n {let middle=at+width;if middle>n {middle=n;}let end=middle+width;if end>n {end=n;}let left=at;let right=middle;let out=at;
        while out<end {let row=0;if left<middle && (right>=end || load64(load64(data+left*8))<=load64(load64(data+right*8))) {row=load64(data+left*8);left=left+1;}else {row=load64(data+right*8);right=right+1;}store64(temporary+out*8,row);out=out+1;}at=end;}
        fd_copy(data,temporary,n*8);width=width*2;
    }return 1;
}
// Checkpoint metadata stores usage and optional derived buckets. CRC slots may
// be reserved even when a large cache is omitted to keep the data file bounded.
fn fd_auto_meta_bytes(db) {
 let bytes=16;let tables=load64(db+40);let i=0;while i<fd_size(tables) {let v=load64(fd_at(tables,i)+120);if v {let j=0;while j<fd_size(v) {let x=fd_at(v,j);bytes=bytes+104+((load64(x+56)*16+4095)/4096)*8;j=j+1;}}i=i+1;}return bytes;
}
fn fd_auto_cp_meta(db,a,b) {
 let info=fd_vec(a);let p=fd_auto_policy(db);fd_word(a,b,load64(p));let count_at=load64(b);fd_word(a,b,0);let count=0;let tables=load64(db+40);let i=0;
 while i<fd_size(tables) {let t=fd_at(tables,i);let v=load64(t+120);if v {let j=0;while j<fd_size(v) {let x=fd_at(v,j);let at=load64(b);let pages=(load64(x+56)*16+4095)/4096;let record=fd_alloc(a,24);store64(record,x);store64(record+8,at);store64(record+16,pages);fd_push(a,info,record);
 fd_word(a,b,i);fd_word(a,b,load64(x+8));fd_word(a,b,load64(x+16));fd_word(a,b,load64(x+24));fd_word(a,b,load64(x+32));fd_word(a,b,load64(x+40));fd_word(a,b,load64(x+80));fd_word(a,b,load64(x+72));fd_word(a,b,load64(x+104));fd_word(a,b,0);fd_word(a,b,0);fd_word(a,b,0);fd_word(a,b,pages);let k=0;while k<pages {fd_word(a,b,0);k=k+1;}count=count+1;j=j+1;}}i=i+1;}
 store64(load64(b+16)+count_at,count);return info;
}
fn fd_auto_cp_data(a,b,info) {
 let i=0;while i<fd_size(info) {let record=fd_at(info,i);let x=load64(record);let at=load64(record+8);let capacity=load64(x+56);let bytes=capacity*16;let offset=load64(b);
 if bytes && offset<=16777216-bytes {let pages=load64(record+16);let j=0;while j<pages {if !fd_auto_page(x,j) {return 0;}j=j+1;}fd_auto_materialized(x);if !fd_append(a,b,load64(x+48),bytes) {return 0;}let base=load64(b+16);store64(base+at+72,capacity);store64(base+at+80,load64(x+64));store64(base+at+88,offset);j=0;
 while j<pages {let n=bytes-j*4096;if n>4096 {n=4096;}store64(base+at+104+j*8,fd_crc(4294967295,base+offset+j*4096,n)^4294967295);j=j+1;}}
 i=i+1;}return 1;
}
fn fd_auto_cp_load(db,r,body,n,meta,restore) {
 let p=fd_auto_policy(db);let tick=fd_read_word(r);let count=fd_read_word(r);let tables=load64(db+40);if tick<0 || count<0 || count>fd_size(tables)*64 {return fd_error(db,"invalid automatic-index metadata");}store64(p,tick);let i=0;
 while i<count && load64(r+24) {
 let tid=fd_read_word(r);let col=fd_read_word(r);let kind=fd_read_word(r);if tid<0 || tid>=fd_size(tables) {return fd_error(db,"invalid automatic-index table");}let t=fd_at(tables,tid);let columns=load64(t+16);
 if col<0 || col>=fd_size(columns) || fd_auto_find(t,col) {return fd_error(db,"invalid automatic-index column");}let c=fd_at(columns,col);if (kind!=1 && kind!=2) || load64(c+8)!=kind || load64(c+16) {return fd_error(db,"invalid automatic-index type");}let x=fd_auto_new(t,col,kind);
 store64(x+24,fd_read_word(r));store64(x+32,fd_read_word(r));store64(x+40,fd_read_word(r));store64(x+80,fd_read_word(r));store64(x+72,fd_read_word(r));store64(x+104,fd_read_word(r));
 if load64(x+24)<0 || load64(x+32)<0 || load64(x+40)<0 || load64(x+80)<0 || load64(x+72)<0 || load64(x+72)>tick || load64(x+104)<0 {return fd_error(db,"invalid automatic-index statistics");}
 let capacity=fd_read_word(r);let live=fd_read_word(r);let offset=fd_read_word(r);let pages=fd_read_word(r);
 if capacity<0 || live<0 || pages<0 || pages>4096 || pages>(meta-load64(r+8))/8 {return fd_error(db,"invalid automatic-index bounds");}
 if capacity {if capacity<32 || capacity>1048576 || (capacity&(capacity-1)) || live>fd_size(load64(t+24)) || live>capacity || offset<meta || offset>n || capacity*16>n-offset || pages!=(capacity*16+4095)/4096 {return fd_error(db,"invalid automatic-index buckets");}}
 else if live || offset {return fd_error(db,"invalid omitted automatic index");}
 let checks=body+load64(r+8);let j=0;while j<pages {let crc=fd_read_word(r);if crc<0 || crc>4294967295 {return fd_error(db,"invalid automatic-index checksum");}j=j+1;}
 if restore && capacity && load64(p+16)+capacity*16<=load64(p+8) && load64(p+32)<load64(p+24) {store64(x+48,body+offset);store64(x+56,capacity);store64(x+64,live);store64(x+112,checks);store64(x+120,fd_alloc(db,pages));store64(p+16,load64(p+16)+capacity*16);store64(p+32,load64(p+32)+1);}i=i+1;
 }return load64(r+24) && i==count;
}
fn fd_auto_integrity(t) {
 let v=load64(t+120);if !v {return 1;}let a=alloc(32);if a<=0 {fd_panic();}let rows=fd_size(load64(t+24));let seen=fd_alloc(a,rows);let i=0;let ok=1;
 while i<fd_size(v) && ok {let x=fd_at(v,i);if load64(x+48) {let capacity=load64(x+56);let j=0;while j<rows {store8(seen+j,0);j=j+1;}let live=0;j=0;
 while j<capacity && ok {if !fd_auto_page(x,j/256) {ok=0;}else {let entry=load64(x+48)+j*16;let hash=load64(entry);let id=load64(entry+8);
 if id<(-1) || id>rows || (id==0 && hash!=0) {ok=0;}else if id>0 {let row=fd_table_row(t,id-1);if load8(seen+id-1) || !row || !load64(row+8) || fd_auto_hash(load64(x+16),flexdb_word(flexdb_cell(row,load64(x+8))))!=hash {ok=0;}else {store8(seen+id-1,1);live=live+1;let slot=hash&(capacity-1);let left=capacity;let found=0;while left && !found && ok {if !fd_auto_page(x,slot/256) {ok=0;}else {let other=load64(x+48)+slot*16;if !load64(other+8) {left=1;}else if load64(other+8)==id && load64(other)==hash {found=1;}}slot=(slot+1)&(capacity-1);left=left-1;}if !found {ok=0;}}}}
 j=j+1;}
 if ok {fd_auto_materialized(x);}if live!=load64(x+64) {ok=0;}j=0;while j<rows && ok {let row=fd_table_row(t,j);if !row || (load64(row+8)!=0)!=load8(seen+j) {ok=0;}j=j+1;}}
 i=i+1;}fd_clear(a);syscall(11,a,32,0,0,0,0);if !ok {return fd_corrupt(load64(t),"automatic-index integrity failed");}return 1;
}

fn fd_auto_expire(db) {let p=fd_auto_policy(db);let tables=load64(db+40);let i=0;while i<fd_size(tables) {let v=load64(fd_at(tables,i)+120);if v {let j=0;while j<fd_size(v) {let x=fd_at(v,j);if load64(x+48) && load64(p)-load64(x+72)>load64(p+104) {fd_auto_drop(x,load64(p+88));}j=j+1;}}i=i+1;}return 1;}

// Optional numeric count memo: exact keys, bounded storage, no borrowed strings.
// It is discarded whenever the indexed field changes, and is never persisted.
// +128 arena, +136 entries, +152 capacity; entry=(key,count,occupied).
fn fd_auto_count_clear(x) {let a=load64(x+128);if a {let db=load64(load64(x+144));let p=fd_auto_policy(db);store64(p+16,load64(p+16)-load64(x+152)*24);fd_clear(a);syscall(11,a,32,0,0,0,0);store64(x+128,0);store64(x+136,0);store64(x+152,0);}return 1;}
fn fd_auto_count_cached(x,hash,key) {if !load64(x+128) {return -1;}let p=load64(x+136)+(hash&(load64(x+152)-1))*24;if load64(p+16) && load64(p)==key {return load64(p+8);}return -1;}
fn fd_auto_count_store(x,hash,key,count) {
 if !load64(x+128) {if count<2 {return 1;}let db=load64(load64(x+144));let policy=fd_auto_policy(db);let cap=4096;let rows=fd_size(load64(load64(x+144)+24));while cap>rows && cap>16 {cap=cap/2;}while cap*24>load64(policy+8)-load64(policy+16) && cap>=16 {cap=cap/2;}if cap<16 {return 1;}let a=alloc(32);if a<=0 {fd_panic();}store64(x+128,a);store64(x+136,fd_alloc(a,cap*24));store64(x+152,cap);store64(policy+16,load64(policy+16)+cap*24);}
 let p=load64(x+136)+(hash&(load64(x+152)-1))*24;store64(p,key);store64(p+8,count);store64(p+16,1);return 1;
}

// Conservative integer bounds eliminate out-of-range misses, including large
// duplicate clusters. Deletes never tighten them; inserts/updates widen them.
// Bounds are private derived state, rebuilt with RAM indexes, not persisted.
fn fd_auto_bounds_add(x,key) {
 if !load64(x+176) {store64(x+160,key);store64(x+168,key);store64(x+176,1);}else {if key<load64(x+160) {store64(x+160,key);}if key>load64(x+168) {store64(x+168,key);}}return 1;
}
