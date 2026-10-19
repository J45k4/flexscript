// FlexDB: embedded relational storage, queried through ordinary function calls.
import "memory.flex";
import "storage.flex";
import "blob.flex";
import "query.flex";
import "reconcile.flex";
import "checkpoint.flex";
import "autoindex.flex";
// DB (256 bytes): arena, fd, error, tables, state, end, sequence,
// transaction arena/buffer/snapshots, original table count, operation count.
// Table (144 bytes): db, name, columns, rows, next ID, active, ordinal;
// checkpoint/index state through +120, conservative blob-schema flag at +128.
fn fd_ready(db) {if !db || load64(db+24)<0 || load64(db+48)==2 {return fd_error(db,"database is unavailable; close and reopen");}return 1;}
fn fd_writing(db) {if !fd_ready(db) {return 0;}if load64(db+48)!=1 {return fd_error(db,"mutation requires flexdb_begin");}return 1;}
fn open_flexdb(path) {
    fd_last_error="";let db=alloc(256);if db<=0 {fd_panic();}
    store64(db+24,-1);store64(db+32,"");store64(db+40,fd_vec(db));store64(db+168,fd_text(db,path));
    if !fd_open_storage(db,path) {store64(db+48,2);close_flexdb(db);return 0;}return db;
}
fn close_flexdb(db) {
    if !db {return 0;}let ok=1;if !load64(db+48) && (load64(db+56)-load64(db+152)>=65536 || load64(db+224)>=2) {ok=flexdb_checkpoint(db);if !ok && !load64(db+48) {ok=1;}}if load64(db+72) {fd_clear(load64(db+72));syscall(11,load64(db+72),32,0,0,0,0);}
    fd_blob_close(db);fd_tx_cache_close(db);fd_query_cache_close(db);fd_cp_cache_close(db);fd_auto_close(db);if load64(db+24)>=0 {syscall(3,load64(db+24),0,0,0,0,0);}if load64(db+128) {syscall(11,load64(db+128),load64(db+136),0,0,0,0);}fd_clear(db);syscall(11,db,256,0,0,0,0);return ok;
}
fn flexdb_begin(db) {
    if !fd_ready(db) {return 0;}if load64(db+48) {return fd_error(db,"transaction already active");}
    store64(db+96,fd_size(load64(db+40)));store64(db+104,0);store64(db+120,0);store64(db+32,"");store64(db+48,1);return 1;
}
// First mutation prepares the log and rollback snapshots. Empty transactions
// require neither a scratch allocation nor table snapshots under the held lock.
fn fd_tx_prepare(db) {
    if load64(db+72) {return 1;}if load64(db+48)!=1 {return fd_error(db,"mutation requires flexdb_begin");}
    let a=load64(db+216);if a {store64(db+216,0);}else {a=alloc(32);if a<=0 {fd_panic();}}store64(db+72,a);store64(db+80,fd_vec(a));fd_word(a,load64(db+80),0);
    let snapshots=fd_vec(a);store64(db+88,snapshots);store64(db+112,fd_vec(a));store64(db+248,fd_vec(a));let tables=load64(db+40);let i=0;
    while i<load64(db+96) {let t=fd_at(tables,i);let s=fd_alloc(a,40);store64(s,t);store64(s+8,load64(t+24));store64(s+16,load64(t+32));store64(s+24,load64(t+16));store64(s+32,load64(load64(t+24)));fd_push(a,snapshots,s);i=i+1;}return 1;
}
fn fd_tx_cache_close(db) {let a=load64(db+216);if a {fd_clear(a);syscall(11,a,32,0,0,0,0);store64(db+216,0);}return 1;}
fn fd_end_transaction(db) {
    fd_blob_rollback(db);
    let a=load64(db+72);if a {let p=load64(a);if p && !load64(p) && load64(p+8)<=65536 && !load64(db+216) {store64(a+8,0);store64(db+216,a);}else {fd_clear(a);syscall(11,a,32,0,0,0,0);}}
    store64(db+72,0);store64(db+80,0);store64(db+88,0);store64(db+112,0);store64(db+120,0);store64(db+248,0);store64(db+48,0);return 1;
}
fn flexdb_rollback(db) {
    if !fd_writing(db) {return 0;}if !load64(db+72) {return fd_end_transaction(db);}let undo=load64(db+112);let i=fd_size(undo)-1;while i>=0 {let entry=fd_at(undo,i);fd_put(load64(entry),load64(entry+8),load64(entry+16));i=i-1;}let snapshots=load64(db+88);i=0;
    while i<fd_size(snapshots) {let s=fd_at(snapshots,i);let t=load64(s);store64(t+24,load64(s+8));store64(t+32,load64(s+16));store64(t+16,load64(s+24));store64(load64(s+8),load64(s+32));i=i+1;}
    let tables=load64(db+40);i=load64(db+96);while i<fd_size(tables) {store64(fd_at(tables,i)+40,0);i=i+1;}store64(tables,load64(db+96)*8);return fd_end_transaction(db);
}
fn flexdb_commit(db) {
    if !fd_writing(db) {return 0;}if !load64(db+104) {return fd_end_transaction(db);}if load64(db+104) {store64(load64(load64(db+80)+16),load64(db+104));if !fd_blob_write_pending(db) || !fd_write_transaction(db) {return 0;}fd_blob_publish(db);}
    if !fd_auto_commit(db) {return 0;}return fd_end_transaction(db);
}
fn flexdb_schema(db) {if !fd_ready(db) {return 0;}return fd_vec(db);}
fn fd_name(name) {let n=fd_len(name);return n>0 && n<=255;}
fn flexdb_column(db,schema,name,kind,nullable) {
    if !fd_ready(db) {return -1;}if !fd_name(name) || kind<1 || kind>4 || (nullable!=0 && nullable!=1) || fd_size(schema)>=64 {fd_error(db,"invalid column definition");return -1;}
    let i=0;while i<fd_size(schema) {if fd_same(load64(fd_at(schema,i)),name) {fd_error(db,"duplicate column name");return -1;}i=i+1;}
    let c=fd_alloc(db,24);store64(c,fd_text(db,name));store64(c+8,kind);store64(c+16,nullable);fd_push(db,schema,c);return fd_size(schema)-1;
}
fn flexdb_table(db,name) {if !fd_ready(db) {return 0;}let v=load64(db+40);let i=0;while i<fd_size(v) {let t=fd_at(v,i);if fd_same(load64(t+8),name) {return t;}i=i+1;}return 0;}
fn fd_table_new(db,name,columns) {
    let t=fd_alloc(db,144);store64(t,db);store64(t+8,fd_text(db,name));let schema=fd_vec(db);let i=0;
    while i<fd_size(columns) {let c=fd_at(columns,i);let copy=fd_alloc(db,24);store64(copy,fd_text(db,load64(c)));store64(copy+8,load64(c+8));store64(copy+16,load64(c+16));fd_push(db,schema,copy);if load64(c+8)==3 {store64(t+128,1);}i=i+1;}
    store64(t+16,schema);store64(t+24,fd_vec(db));store64(t+32,1);store64(t+40,1);store64(t+48,fd_size(load64(db+40)));fd_push(db,load64(db+40),t);return t;
}
fn fd_table_id(t) {return load64(t+48);}
fn fd_command(db,n) {if !fd_tx_prepare(db) {return 0;}let a=load64(db+72);if !fd_reserve(a,load64(db+80),load64(load64(db+80))+n) {return fd_error(db,"transaction exceeds 16 MiB");}return 1;}
fn fd_log_word(db,w) {return fd_word(load64(db+72),load64(db+80),w);}
fn fd_log_bytes(db,p,n) {return fd_append(load64(db+72),load64(db+80),p,n);}
fn fd_logged(db) {store64(db+104,load64(db+104)+1);store64(db+120,0);return 1;}
fn flexdb_create(db,name,columns) {
    if !fd_writing(db) {return 0;}
    if !fd_name(name) || flexdb_table(db,name) || fd_size(columns)<1 || fd_size(columns)>64 || fd_size(load64(db+40))>=1024 {return fd_error(db,"invalid or duplicate table");}
    let n=32+fd_len(name);let i=0;while i<fd_size(columns) {let c=fd_at(columns,i);n=n+24+fd_len(load64(c));i=i+1;}
    if !fd_command(db,n) {return 0;}let t=fd_table_new(db,name,columns);
    fd_log_word(db,1);fd_log_word(db,fd_table_id(t));fd_log_word(db,fd_len(name));fd_log_bytes(db,name,fd_len(name));fd_log_word(db,fd_size(columns));i=0;
    while i<fd_size(columns) {let c=fd_at(columns,i);fd_log_word(db,fd_len(load64(c)));fd_log_bytes(db,load64(c),fd_len(load64(c)));fd_log_word(db,load64(c+8));fd_log_word(db,load64(c+16));i=i+1;}fd_logged(db);return t;
}
fn flexdb_column_index(table,name) {let v=load64(table+16);let i=0;while i<fd_size(v) {if fd_same(load64(fd_at(v,i)),name) {return i;}i=i+1;}return -1;}
fn fd_table_ready(t) {if !t {return fd_error(0,"invalid table");}if !load64(t+40) {return fd_error(load64(t),"inactive table");}return fd_ready(load64(t));}
fn fd_row_index(t,id) {
    if id<=0 || id>=load64(t+32) {return -1;}let rows=load64(t+24);if id>0 && id<=fd_size(rows) {let row=fd_at(rows,id-1);if !row || load64(row)==id {return id-1;}}let lo=0;let hi=fd_size(rows);while lo<hi {let mid=(lo+hi)/2;let row=fd_table_row(t,mid);if !row {return -1;}let found=load64(row);if found<id {lo=mid+1;}else {hi=mid;}}
    if lo<fd_size(rows) {let row=fd_table_row(t,lo);if row && load64(row)==id {return lo;}}return -1;
}
fn flexdb_get(t,id) {
    if !t {fd_table_ready(t);return 0;}let db=load64(t);
    if !load64(t+40) || !db || load64(db+24)<0 || load64(db+48)==2 {fd_table_ready(t);return 0;}
    if id<=0 || id>=load64(t+32) {return 0;}let rows=load64(t+24);
    // Common dense-ID lookup needs no helper calls. Keep the same row-ID,
    // deletion and connection checks, with lazy decoding and the sparse fallback.
    if id<=load64(rows)/8 {let r=load64(load64(rows+16)+(id-1)*8);if !r {r=fd_table_row(t,id-1);if !r {return 0;}}if load64(r)==id {if load64(r+8) {return r;}return 0;}}
    let i=fd_row_index(t,id);if i<0 {return 0;}let r=fd_at(rows,i);if !r {r=fd_table_row(t,i);}if !r || !load64(r+8) {return 0;}return r;
}
fn fd_check_values(t,values) {
    return fd_check_columns(load64(t),load64(t+16),values);
}
fn fd_check_columns(db,columns,values) {
    if fd_size(values)!=fd_size(columns) {return fd_error(db,"row does not match column count");}
    let i=0;while i<fd_size(values) {let v=fd_at(values,i);let c=fd_at(columns,i);if !v {return fd_error(db,"invalid value");}let kind=load64(v);
        if (kind==0 && !load64(c+16)) || (kind!=0 && kind!=load64(c+8)) || ((kind==2 && (load64(v+16)<0 || load64(v+16)>1048576)) || (kind==3 && !fd_blob_value_ok(db,v,kind,load64(v+16)))) {return fd_error(db,"row value does not match column type/nullability");}i=i+1;}return 1;
}
fn fd_row_undo(db,rows,index) {let a=load64(db+72);let entry=fd_alloc(a,24);store64(entry,rows);store64(entry+8,index);store64(entry+16,fd_at(rows,index));fd_push(a,load64(db+112),entry);return 1;}
// Consecutive inserts share a schema-typed batch header instead of repeating
// table/row/column metadata per record. Updates retain the original encoding.
fn fd_upsert(t,id,values,index) {
    let db=load64(t);if load64(t+128) {if !fd_check_values(t,values) {return 0;}values=fd_blob_values(db,values);if !values {return 0;}}let columns=load64(t+16);let count=fd_size(values);if count!=fd_size(columns) {return fd_error(db,"row does not match column count");}
    let batch=0;let tid=fd_table_id(t);let b=load64(db+80);
    if index<0 && load64(db+120) {let at=load64(db+120)-1;let header=load64(b+16)+at;if load64(header)==5 && load64(header+8)==tid && load64(header+16)+load64(header+24)==id {batch=at+1;}}
    let n=32+count*16;let mask=0;if index<0 {n=8;if !batch {n=n+32;}}
    let row_bytes=16+count*32;let i=0;
    while i<count {let v=fd_at(values,i);let c=fd_at(columns,i);if !v {return fd_error(db,"invalid value");}let kind=load64(v);
        if (kind==0 && !load64(c+16)) || (kind!=0 && kind!=load64(c+8)) || ((kind==2 && (load64(v+16)<0 || load64(v+16)>1048576)) || (kind==3 && !fd_blob_value_ok(db,v,kind,load64(v+16)))) {return fd_error(db,"row value does not match column type/nullability");}
        if index<0 {if kind==0 {mask=mask|(1<<i);}else {n=n+8;}}
        if kind==3 && load64(v+16)<0 {n=n+40;}else if kind==2 || kind==3 {let size=load64(v+16);n=n+size;row_bytes=row_bytes+((size+8)&(-8));}i=i+1;
    }
    if !fd_command(db,n) {return 0;}b=load64(db+80);let used=load64(b);let p=load64(b+16)+used;let row=fd_alloc(db,row_bytes);store64(row,id);store64(row+8,count);let payload=row+16+count*32;
    if index<0 {
        if batch {let header=load64(b+16)+batch-1;store64(header+24,load64(header+24)+1);}else {store64(p,5);store64(p+8,tid);store64(p+16,id);store64(p+24,1);p=p+32;}
        store64(p,mask);p=p+8;
    }else {store64(p,2);store64(p+8,tid);store64(p+16,id);store64(p+24,count);p=p+32;}i=0;
    while i<count {let v=fd_at(values,i);let kind=load64(v);let copy=row+16+count*8+i*24;store64(row+16+i*8,copy);store64(copy,kind);
        if index>=0 {store64(p,kind);p=p+8;}
        if kind==3 && load64(v+16)<0 {p=p+fd_blob_encode(p,v);store64(copy+8,load64(v+8));store64(copy+16,load64(v+16));}else if kind==2 || kind==3 {let bytes=load64(v+16);store64(p,bytes);fd_copy(p+8,load64(v+8),bytes);p=p+8+bytes;fd_copy(payload,load64(v+8),bytes);store8(payload+bytes,0);store64(copy+8,payload);store64(copy+16,bytes);payload=payload+((bytes+8)&(-8));}
        else {let word=load64(v+8);if index>=0 || kind {store64(p,word);p=p+8;}store64(copy+8,word);store64(copy+16,0);}i=i+1;
    }
    let before=0;if index>=0 {before=fd_at(load64(t+24),index);}fd_auto_event(t,id,before,row);store64(b,used+n);if index<0 {fd_push(db,load64(t+24),row);store64(t+32,id+1);if !batch {fd_logged(db);batch=used+1;}store64(db+120,batch);}else {fd_row_undo(db,load64(t+24),index);fd_put(load64(t+24),index,row);fd_logged(db);}return id;
}
fn flexdb_insert(t,values) {if !fd_table_ready(t) || !fd_writing(load64(t)) {return 0;}let id=load64(t+32);if id==9223372036854775807 {return fd_error(load64(t),"row ID exhausted");}return fd_upsert(t,id,values,-1);}
fn flexdb_update(t,id,values) {if !fd_table_ready(t) || !fd_writing(load64(t)) {return 0;}if !flexdb_get(t,id) {return fd_error(load64(t),"row not found");}return fd_upsert(t,id,values,fd_row_index(t,id))!=0;}
fn flexdb_delete(t,id) {
    if !fd_table_ready(t) || !fd_writing(load64(t)) {return 0;}let db=load64(t);if !flexdb_get(t,id) {return fd_error(db,"row not found");}if !fd_command(db,24) {return 0;}
    fd_log_word(db,3);fd_log_word(db,fd_table_id(t));fd_log_word(db,id);let row=fd_alloc(db,16);store64(row,id);store64(row+8,0);let index=fd_row_index(t,id);fd_auto_event(t,id,fd_at(load64(t+24),index),row);fd_row_undo(db,load64(t+24),index);fd_put(load64(t+24),index,row);return fd_logged(db);
}
// Bounded decoder used only after the frame checksum and footer validate.
fn fd_read_word(r) {let at=load64(r+8);if at>load64(r+16)-8 {store64(r+24,0);return 0;}store64(r+8,at+8);return load64(load64(r)+at);}
fn fd_read_bytes(db,r,n) {let at=load64(r+8);if n<0 || n>1048576 || n>load64(r+16)-at {store64(r+24,0);return "";}let p=fd_alloc(db,n+1);fd_copy(p,load64(r)+at,n);store8(p+n,0);store64(r+8,at+n);return p;}
fn fd_read_name(db,r) {let n=fd_read_word(r);let p=fd_read_bytes(db,r,n);if n<1 || n>255 || fd_len(p)!=n {store64(r+24,0);}return p;}
// One bounded scratch value set per frame; fd_row copies before it is reused.
fn fd_decode_values(db,r,count,columns,mask) {
    let values=r+40;store64(values,count*8);store64(values+8,512);store64(values+16,r+64);let j=0;
    while j<count && load64(r+24) {
        let kind=0;let word=0;
        if columns {if !(mask&(1<<j)) {kind=load64(fd_at(columns,j)+8);word=fd_read_word(r);}}
        else {kind=fd_read_word(r);word=fd_read_word(r);}
        if kind<0 || kind>4 || (kind==0 && word!=0) {store64(r+24,0);return 0;}
        let v=r+576+j*24;store64(v,kind);store64(v+16,0);
        if kind==3 && word<0 {if !load64(r+32) {store64(r+24,0);return 0;}let d=fd_blob_decode(db,r,word);if !d {store64(r+24,0);return 0;}store64(v+8,d);store64(v+16,word);}else if kind==2 || kind==3 {let at=load64(r+8);if word<0 || word>1048576 || word>load64(r+16)-at {store64(r+24,0);return 0;}store64(v+8,load64(r)+at);store64(v+16,word);store64(r+8,at+word);}
        else {store64(v+8,word);}fd_put(values,j,v);j=j+1;
    }return values;
}
fn fd_replay(db,p,n) {return fd_replay_version(db,p,n,0);}
fn fd_replay_version(db,p,n,external) {
    let r=fd_alloc(db,2112);store64(r,p);store64(r+8,0);store64(r+16,n);store64(r+24,1);store64(r+32,external);let ops=fd_read_word(r);if ops<1 || ops>n/16 {return 0;}
    let i=0;while i<ops && load64(r+24) {
        let op=fd_read_word(r);let tid=fd_read_word(r);let tables=load64(db+40);
        if op==1 {
            if tid!=fd_size(tables) || tid>=1024 {return 0;}let name=fd_read_name(db,r);if flexdb_table(db,name) {return 0;}
            let columns=fd_vec(db);let count=fd_read_word(r);if count<1 || count>64 {return 0;}let j=0;
            while j<count && load64(r+24) {let column=fd_read_name(db,r);let kind=fd_read_word(r);let nullable=fd_read_word(r);if flexdb_column(db,columns,column,kind,nullable)<0 {return 0;}j=j+1;}
            if load64(r+24) {fd_table_new(db,name,columns);}
        }else if op==2 || op==3 {
            if tid<0 || tid>=fd_size(tables) {return 0;}let t=fd_at(tables,tid);let id=fd_read_word(r);if id<=0 || id>=9223372036854775807 {return 0;}let index=fd_row_index(t,id);
            if op==3 {let before=flexdb_get(t,id);if !before {return 0;}let row=fd_alloc(db,16);store64(row,id);store64(row+8,0);fd_put(load64(t+24),index,row);if !fd_auto_change(t,id,before,row) {return 0;}}
            else {
                let count=fd_read_word(r);if count!=fd_size(load64(t+16)) {return 0;}let values=fd_decode_values(db,r,count,0,0);
                if load64(r+24) {if !fd_check_values(t,values) {return 0;}let row=fd_row(db,id,values);let before=0;if index<0 {if id!=load64(t+32) {return 0;}fd_push(db,load64(t+24),row);store64(t+32,id+1);}else {before=flexdb_get(t,id);if !before {return 0;}fd_put(load64(t+24),index,row);}if !fd_auto_change(t,id,before,row) {return 0;}}
            }
        }else if op==5 {
            if tid<0 || tid>=fd_size(tables) {return 0;}let t=fd_at(tables,tid);let first=fd_read_word(r);let count=fd_read_word(r);
            if first!=load64(t+32) || count<1 || count>(load64(r+16)-load64(r+8))/8 || first>9223372036854775807-count {return 0;}
            let columns=load64(t+16);let cells=fd_size(columns);let k=0;while k<count && load64(r+24) {
                let mask=fd_read_word(r);if cells<64 && (mask>>cells)!=0 {return 0;}let values=fd_decode_values(db,r,cells,columns,mask);
                if load64(r+24) {if !fd_check_values(t,values) {return 0;}let row=fd_row(db,first+k,values);fd_push(db,load64(t+24),row);store64(t+32,first+k+1);if !fd_auto_change(t,first+k,0,row) {return 0;}}k=k+1;
            }
        }else if op==4 {
            if tid<0 || tid>=fd_size(tables) || !fd_replay_schema(db,fd_at(tables,tid),r) {return 0;}
        }else {return 0;}
        i=i+1;
    }
    return load64(r+24) && load64(r+8)==n && i==ops;
}
