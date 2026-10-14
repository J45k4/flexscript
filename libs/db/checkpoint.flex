import "scan-native.flex";
import "pack-native.flex";
// Append-only checkpoints. Metadata is checked on open; directory pages and
// individual rows are checked before use. Everything stays in the same file.
fn fd_footer(a,magic,sequence,start,checkpoint) {
    let p=fd_alloc(a,48);fd_copy(p,magic,8);store64(p+8,sequence);store64(p+16,start);store64(p+24,checkpoint);
    let crc=fd_crc(4294967295,p,32)^4294967295;store64(p+32,crc);store64(p+40,crc^4294967295);return p;
}
fn fd_footer_ok(p) {let crc=fd_crc(4294967295,p,32)^4294967295;return load64(p+32)==crc && load64(p+40)==(crc^4294967295);}
fn fd_map(db,size) {
    if load64(db+128) {return 1;}let p=syscall(9,0,size,1,2,load64(db+24),0);if p<0 {return fd_error(db,"cannot map checkpoint file");}store64(db+128,p);store64(db+136,size);return 1;
}
fn fd_corrupt(db,message) {store64(db+48,2);return fd_error(db,message);}
fn fd_base_header(a) {let p=fd_header(a);fd_copy(p,"FLEXDB02",8);store64(p+8,2);store64(p+24,1);return p;}
fn fd_cp_header_ok(h) {return (fd_bytes(h,"FLEXCP01",8) || fd_bytes(h,"FLEXCP02",8) || fd_bytes(h,"FLEXCP03",8)) && load64(h+8)>=16 && load64(h+8)<=16777216 && load64(h+16)>=0 && ((load64(h+24)>>32)&4294967295)==(fd_crc(4294967295,h,24)^4294967295);}
fn fd_cp_load(db,offset,size) {
    if offset<32 || offset>size-80 || !fd_map(db,size) {return fd_error(db,"invalid checkpoint location");}
    let h=load64(db+128)+offset;if !fd_cp_header_ok(h) {return fd_error(db,"invalid checkpoint header");}let n=load64(h+8);let sequence=load64(h+16);
    if n>size-offset-80 {return fd_error(db,"incomplete referenced checkpoint");}let body=h+32;let end=body+n;
    if !fd_bytes(end,"FLEXCPE1",8) || !fd_footer_ok(end) || load64(end+8)!=sequence || load64(end+16)!=offset || load64(end+24)!=offset {return fd_error(db,"invalid checkpoint footer");}
    let meta=load64(body);if meta<16 || meta>n || (fd_crc(fd_crc(4294967295,h,24),body,meta)^4294967295)!=(load64(h+24)&4294967295) {return fd_error(db,"checkpoint metadata checksum mismatch");}
    let r=fd_alloc(db,2112);store64(r,body);store64(r+8,8);store64(r+16,meta);store64(r+24,1);let tables=fd_read_word(r);if tables<0 || tables>1024 {return fd_error(db,"invalid checkpoint table count");}
    fd_cp_cache_close(db);fd_auto_close(db);store64(load64(db+40),0);let i=0;
    while i<tables && load64(r+24) {
        let name=fd_read_name(db,r);if flexdb_table(db,name) {return fd_error(db,"duplicate checkpoint table");}let columns=fd_vec(db);let count=fd_read_word(r);if count<1 || count>64 {return fd_error(db,"invalid checkpoint columns");}let j=0;
        while j<count && load64(r+24) {let column=fd_read_name(db,r);let kind=fd_read_word(r);let nullable=fd_read_word(r);if flexdb_column(db,columns,column,kind,nullable)<0 {return 0;}j=j+1;}
        let rows=fd_read_word(r);let directory=fd_read_word(r);let pages=fd_read_word(r);
        if rows<0 || rows>2097152 || directory<meta || directory>n || rows*16>n-directory || pages!=(rows*16+4095)/4096 || pages>(meta-load64(r+8))/8 {return fd_error(db,"invalid checkpoint row directory");}
        let checks=body+load64(r+8);j=0;while j<pages {let crc=fd_read_word(r);if crc<0 || crc>4294967295 {return fd_error(db,"invalid checkpoint page checksum");}j=j+1;}
        if !load64(r+24) {return fd_error(db,"truncated checkpoint schema");}let t=fd_table_new(db,name,columns);let v=load64(t+24);store64(v,rows*8);store64(v+8,rows*8);if rows {store64(v+16,fd_alloc(db,rows*8));}
        store64(t+32,rows+1);store64(t+64,body+directory);store64(t+72,body);store64(t+80,rows);store64(t+88,checks);store64(t+96,fd_alloc(db,pages));store64(t+104,n);store64(t+112,meta);i=i+1;
    }
    if (fd_bytes(h,"FLEXCP02",8) || fd_bytes(h,"FLEXCP03",8)) && !fd_auto_cp_load(db,r,body,n,meta,fd_bytes(h,"FLEXCP03",8)) {return 0;}
    if !load64(r+24) || load64(r+8)!=meta || i!=tables {return fd_error(db,"invalid checkpoint metadata");}
    store64(db+144,offset);store64(db+152,offset+n+80);store64(db+160,sequence);store64(db+224,0);return 1;
}
// Parse a checked checkpoint row once, then construct its owned immutable
// representation directly. Scratch descriptors never escape this function.
// A private scalar view avoids hydrating unrelated text/blob fields for a
// proven integer COUNT predicate. Every referenced row still has its directory,
// CRC, null mask, lengths and complete encoding checked before the view is used.
// Current RAM rows override the immutable checkpoint view after edits/rollback.
fn fd_cp_cache_clear(t) {
    let view=load64(t+56);if view {let a=load64(view);fd_clear(a);syscall(11,a,64,0,0,0,0);store64(t+56,0);}return 1;
}
fn fd_cp_cache_close(db) {let tables=load64(db+40);let i=0;while i<fd_size(tables) {fd_cp_cache_clear(fd_at(tables,i));i=i+1;}return 1;}
fn fd_cp_scalar_cache(t,col) {
    if !load64(t+64) {return 0;}let columns=load64(t+16);if col<0 || col>=fd_size(columns) || load64(fd_at(columns,col)+8)!=1 {return 0;}
    let view=load64(t+56);if view && load64(view+8)==col {return view;}fd_cp_cache_clear(t);let db=load64(t);let count=fd_size(columns);let rows=load64(t+80);let a=alloc(64);if a<=0 {fd_panic();}
    view=a+32;store64(view,a);store64(view+8,col);store64(view+16,rows);let data=fd_alloc(a,rows*16);store64(view+24,data);store64(t+56,view);let native=fd_scan_fill(t,col,view);if native>0 {return view;}if native<0 {return -1;}let i=0;
    while i<rows {
        if !fd_at(load64(t+24),i) {let page=i/256;let flags=load64(t+96);
            if !load8(flags+page) {let length=rows*16-page*4096;if length>4096 {length=4096;}if (fd_crc(4294967295,load64(t+64)+page*4096,length)^4294967295)!=load64(load64(t+88)+page*8) {fd_corrupt(db,"checkpoint directory checksum mismatch");return -1;}store8(flags+page,1);}
            let entry=load64(t+64)+i*16;let offset=load64(entry);let packed=load64(entry+8);let bytes=packed&4294967295;
            if offset || packed {if bytes<8 || offset<load64(t+112) || offset>load64(t+104) || bytes>load64(t+104)-offset {fd_corrupt(db,"invalid checkpoint row bounds");return -1;}
                let p=load64(t+72)+offset;if (fd_crc(4294967295,p,bytes)^4294967295)!=((packed>>32)&4294967295) {fd_corrupt(db,"checkpoint row checksum mismatch");return -1;}
                let mask=load64(p);if count<64 && (mask>>count)!=0 {fd_corrupt(db,"invalid checkpoint null mask");return -1;}let at=8;let j=0;let value=0;
                while j<count {let c=fd_at(columns,j);let kind=load64(c+8);let word=0;
                    if mask&(1<<j) {if !load64(c+16) {fd_corrupt(db,"invalid checkpoint row values");return -1;}}
                    else {if at>bytes-8 {fd_corrupt(db,"invalid checkpoint row values");return -1;}word=load64(p+at);at=at+8;if kind==2 || kind==3 {if word<0 || word>1048576 || word>bytes-at {fd_corrupt(db,"invalid checkpoint row values");return -1;}at=at+word;}}
                    if j==col {value=word;}j=j+1;
                }if at!=bytes {fd_corrupt(db,"invalid checkpoint row values");return -1;}store64(data+i*16,value);store64(data+i*16+8,1);
            }
        }i=i+1;
    }return view;
}
fn fd_cp_decode(db,id,columns,p,bytes) {
    let count=fd_size(columns);let mask=load64(p);if count<64 && (mask>>count)!=0 {return fd_corrupt(db,"invalid checkpoint null mask");}
    let scratch=load64(db+176);if !scratch {scratch=fd_alloc(db,2112);store64(db+176,scratch);}let at=8;let needed=16+count*32;let i=0;
    while i<count {let c=fd_at(columns,i);let kind=load64(c+8);let word=0;let length=0;
        if mask&(1<<i) {if !load64(c+16) {return fd_corrupt(db,"invalid checkpoint row values");}kind=0;}
        else {if at>bytes-8 {return fd_corrupt(db,"invalid checkpoint row values");}word=load64(p+at);at=at+8;
            if kind==2 || kind==3 {length=word;if length<0 || length>1048576 || length>bytes-at {return fd_corrupt(db,"invalid checkpoint row values");}word=p+at;at=at+length;needed=needed+((length+8)&(-8));}}
        let v=scratch+576+i*24;store64(v,kind);store64(v+8,word);store64(v+16,length);i=i+1;
    }if at!=bytes {return fd_corrupt(db,"invalid checkpoint row values");}
    let row=fd_alloc(db,needed);store64(row,id);store64(row+8,count);let payload=row+16+count*32;i=0;
    while i<count {let v=scratch+576+i*24;let copy=row+16+count*8+i*24;let kind=load64(v);store64(row+16+i*8,copy);store64(copy,kind);store64(copy+16,load64(v+16));
        if kind==2 || kind==3 {let length=load64(v+16);fd_copy(payload,load64(v+8),length);store8(payload+length,0);store64(copy+8,payload);payload=payload+((length+8)&(-8));}else {store64(copy+8,load64(v+8));}i=i+1;
    }return row;
}
fn fd_table_row(t,index) {
    let rows=load64(t+24);let row=fd_at(rows,index);if row {return row;}let db=load64(t);
    if index<0 || index>=load64(t+80) || !load64(t+64) {return fd_corrupt(db,"missing checkpoint row");}
    let page=index/256;let checked=load64(t+96);
    if !load8(checked+page) {let bytes=load64(t+80)*16-page*4096;if bytes>4096 {bytes=4096;}if (fd_crc(4294967295,load64(t+64)+page*4096,bytes)^4294967295)!=load64(load64(t+88)+page*8) {return fd_corrupt(db,"checkpoint directory checksum mismatch");}store8(checked+page,1);}
    let entry=load64(t+64)+index*16;let offset=load64(entry);let packed=load64(entry+8);let bytes=packed&4294967295;
    if offset==0 && packed==0 {row=fd_alloc(db,16);store64(row,index+1);store64(row+8,0);}
    else {
        if bytes<8 || offset<load64(t+112) || offset>load64(t+104) || bytes>load64(t+104)-offset {return fd_corrupt(db,"invalid checkpoint row bounds");}let p=load64(t+72)+offset;
        if (fd_crc(4294967295,p,bytes)^4294967295)!=((packed>>32)&4294967295) {return fd_corrupt(db,"checkpoint row checksum mismatch");}
        row=fd_cp_decode(db,index+1,load64(t+16),p,bytes);if !row {return 0;}
    }
    fd_put(rows,index,row);store64(db+184,load64(db+184)+1);return row;
}
fn fd_cp_word(a,b,w) {if !fd_word(a,b,w) {return 0;}return 1;}
fn fd_cp_row(a,b,row) {
    let cells=load64(row+8);let size=8;let mask=0;let i=0;while i<cells {let v=load64(row+16+i*8);let kind=load64(v);if !kind {mask=mask|(1<<i);}else {size=size+8;if kind==2 || kind==3 {size=size+load64(v+16);}}i=i+1;}
    let used=load64(b);if !fd_reserve(a,b,used+size) {return 0;}let p=load64(b+16)+used;store64(p,mask);p=p+8;i=0;
    while i<cells {let v=load64(row+16+i*8);let kind=load64(v);if kind==2 || kind==3 {let bytes=load64(v+16);store64(p,bytes);fd_copy(p+8,load64(v+8),bytes);p=p+8+bytes;}else if kind {store64(p,load64(v+8));p=p+8;}i=i+1;}store64(b,used+size);return size;
}
// Reserve the complete checkpoint before emitting rows. Include all caches in
// the bound; the writer still omits those that do not fit the 16 MiB limit.
fn fd_cp_capacity(db,meta) {
    let bytes=meta;let tables=load64(db+40);let i=0;
    while i<fd_size(tables) {let t=fd_at(tables,i);let rows=load64(t+24);bytes=bytes+fd_size(rows)*16;let j=0;
        // RAM tables need no lazy decode pass. Checkpoint-backed tables must
        // validate/hydrate remaining rows before trusted owned-row packing.
        if load64(t+64) {while j<fd_size(rows) {if !fd_at(rows,j) && !fd_table_row(t,j) {return 0;}j=j+1;}}
        let payload=-2;if fd_size(rows)>=128 {payload=fd_pack_size(t);}if payload==-1 {return 0;}
        if payload>=0 {bytes=bytes+payload;}else {j=0;while j<fd_size(rows) {let row=fd_at(rows,j);if !row {return 0;}let count=load64(row+8);if count {bytes=bytes+8;let c=0;while c<count {let v=load64(row+16+c*8);let kind=load64(v);if kind {bytes=bytes+8;if kind==2 || kind==3 {bytes=bytes+load64(v+16);}}c=c+1;}}j=j+1;}}
        let indexes=load64(t+120);if indexes {let k=0;while k<fd_size(indexes) {bytes=bytes+load64(fd_at(indexes,k)+56)*16;k=k+1;}}i=i+1;
    }if bytes>16777216 {bytes=16777216;}return bytes;
}
fn fd_cp_build(db,a) {
    fd_cp_cache_close(db);
    let b=fd_vec(a);let info=fd_vec(a);let tables=load64(db+40);let meta_bytes=16+fd_auto_meta_bytes(db);let ti=0;
    while ti<fd_size(tables) {let t=fd_at(tables,ti);meta_bytes=meta_bytes+40+fd_len(load64(t+8))+((fd_size(load64(t+24))*16+4095)/4096)*8;let columns=load64(t+16);let ci=0;while ci<fd_size(columns) {meta_bytes=meta_bytes+24+fd_len(load64(fd_at(columns,ci)));ci=ci+1;}ti=ti+1;}if meta_bytes>16777216 {return 0;}let capacity=fd_cp_capacity(db,meta_bytes);if !capacity || !fd_reserve(a,b,capacity) {return 0;}
    fd_word(a,b,0);fd_word(a,b,fd_size(tables));let i=0;
    while i<fd_size(tables) {
        let t=fd_at(tables,i);let name=load64(t+8);let columns=load64(t+16);fd_word(a,b,fd_len(name));fd_append(a,b,name,fd_len(name));fd_word(a,b,fd_size(columns));let j=0;
        while j<fd_size(columns) {let c=fd_at(columns,j);let field=load64(c);fd_word(a,b,fd_len(field));fd_append(a,b,field,fd_len(field));fd_word(a,b,load64(c+8));fd_word(a,b,load64(c+16));j=j+1;}
        let rows=fd_size(load64(t+24));let pages=(rows*16+4095)/4096;let record=fd_alloc(a,32);store64(record,t);store64(record+8,load64(b)+8);store64(record+16,load64(b)+24);store64(record+24,rows);fd_push(a,info,record);
        fd_word(a,b,rows);fd_word(a,b,0);fd_word(a,b,pages);j=0;while j<pages {if !fd_cp_word(a,b,0) {return 0;}j=j+1;}i=i+1;
    }
    let indexes=fd_auto_cp_meta(db,a,b);let meta=load64(b);store64(load64(b+16),meta);i=0;
    while i<fd_size(info) {
        let record=fd_at(info,i);let t=load64(record);let rows=load64(record+24);let directory=load64(b);let bytes=rows*16;
        if !fd_reserve(a,b,directory+bytes) {return 0;}store64(load64(b+16)+load64(record+8),directory);store64(b,directory+bytes);let j=0;
        let packed=0;if rows>=128 {packed=fd_pack_rows(t,b,directory);}if packed<0 {return 0;}
        if !packed {while j<rows {let row=fd_at(load64(t+24),j);if !row {return 0;}if !load64(row+8) {let entry=load64(b+16)+directory+j*16;store64(entry,0);store64(entry+8,0);}else {let offset=load64(b);let size=fd_cp_row(a,b,row);if !size {return 0;}let base=load64(b+16);let entry=base+directory+j*16;store64(entry,offset);store64(entry+8,size|((fd_crc(4294967295,base+offset,size)^4294967295)<<32));}j=j+1;}}
        let pages=(bytes+4095)/4096;j=0;while j<pages {let count=bytes-j*4096;if count>4096 {count=4096;}let base=load64(b+16);store64(base+load64(record+16)+j*8,fd_crc(4294967295,base+directory+j*4096,count)^4294967295);j=j+1;}i=i+1;
    }if !fd_auto_cp_data(a,b,indexes) {return 0;}return b;
}
fn fd_cp_write(db,fd,offset,a,b) {
    let h=fd_alloc(a,32);fd_copy(h,"FLEXCP03",8);store64(h+8,load64(b));store64(h+16,load64(db+64));let p=load64(b+16);let crc=fd_crc(fd_crc(4294967295,h,24),p,load64(p))^4294967295;store64(h+24,crc|((fd_crc(4294967295,h,24)^4294967295)<<32));
    let footer=fd_footer(a,"FLEXCPE1",load64(db+64),offset,offset);
    return fd_io(fd,h,32,offset,1) && fd_io(fd,p,load64(b),offset+32,1) && fd_io(fd,footer,48,offset+32+load64(b),1) && fd_sync(fd);
}
fn flexdb_checkpoint(db) {
    if !fd_ready(db) {return 0;}if load64(db+48) {return fd_error(db,"checkpoint requires no active transaction");}if load64(db+144) && load64(db+160)==load64(db+64) && !load64(db+224) {return 1;}
    let a=alloc(32);if a<=0 {fd_panic();}let b=fd_cp_build(db,a);let ok=0;
    if !b {fd_error(db,"checkpoint exceeds 16 MiB or has invalid rows");}
    else {let offset=load64(db+56);if fd_cp_write(db,load64(db+24),offset,a,b) {store64(db+144,offset);store64(db+152,offset+load64(b)+80);store64(db+160,load64(db+64));store64(db+56,load64(db+152));store64(db+224,0);ok=1;}else {fd_corrupt(db,"checkpoint I/O failed; close and reopen");}}
    fd_clear(a);syscall(11,a,32,0,0,0,0);return ok;
}
fn flexdb_integrity(db) {if !fd_ready(db) {return 0;}let tables=load64(db+40);let i=0;while i<fd_size(tables) {let t=fd_at(tables,i);let rows=fd_size(load64(t+24));let j=0;while j<rows {if !fd_table_row(t,j) {return 0;}j=j+1;}if !fd_auto_integrity(t) {return 0;}i=i+1;}return 1;}
fn fd_sync_directory(path,arena) {
    let n=fd_len(path);let i=n-1;while i>=0 && load8(path+i)!=47 {i=i-1;}let parent=".";
    if i>=0 {let bytes=i;if !bytes {bytes=1;}parent=fd_alloc(arena,bytes+1);fd_copy(parent,path,bytes);store8(parent+bytes,0);}
    let fd=syscall(2,parent,0x90000,0,0,0,0);if fd<0 {return 0;}let ok=fd_sync(fd);syscall(3,fd,0,0,0,0,0);return ok;
}
// Publish a compacted checkpoint through atomic rename. Hold both inode locks
// across publication; captured rows and the old mapping remain valid until close.
fn flexdb_compact(db) {
    if !fd_ready(db) {return 0;}if load64(db+48) {return fd_error(db,"compaction requires no active transaction");}
    let a=alloc(32);if a<=0 {fd_panic();}let path=load64(db+168);let st=fd_alloc(a,144);let named=fd_alloc(a,144);let fd=load64(db+24);
    if syscall(5,fd,st,0,0,0,0)<0 || syscall(4,path,named,0,0,0,0)<0 || load64(st)!=load64(named) || load64(st+8)!=load64(named+8) {fd_clear(a);syscall(11,a,32,0,0,0,0);return fd_error(db,"database path was replaced; reopen before compaction");}
    let b=fd_cp_build(db,a);if !b {fd_clear(a);syscall(11,a,32,0,0,0,0);return fd_error(db,"compaction checkpoint exceeds 16 MiB or has invalid rows");}
    let n=fd_len(path);let temp=fd_alloc(a,n+34);fd_copy(temp,path,n);fd_copy(temp+n,".compact-",9);let random=fd_alloc(a,8);
    if syscall(318,random,8,0,0,0,0)!=8 {fd_clear(a);syscall(11,a,32,0,0,0,0);return fd_error(db,"cannot create compaction name");}
    let hex="0123456789abcdef";let i=0;while i<8 {let byte=load8(random+i);store8(temp+n+9+i*2,load8(hex+byte/16));store8(temp+n+10+i*2,load8(hex+(byte&15)));i=i+1;}store8(temp+n+25,0);
    let output=syscall(2,temp,0xa00c2,384,0,0,0);let ok=output>=0;
    if ok {ok=syscall(73,output,6,0,0,0,0)==0 && fd_io(output,fd_base_header(a),32,0,1) && fd_cp_write(db,output,32,a,b);}
    if !ok || syscall(82,temp,path,0,0,0,0)<0 {
        if output>=0 {syscall(3,output,0,0,0,0,0);syscall(87,temp,0,0,0,0,0);}fd_clear(a);syscall(11,a,32,0,0,0,0);return fd_error(db,"cannot write/publish compacted database");
    }
    store64(db+24,output);store64(db+144,32);store64(db+152,32+load64(b)+80);store64(db+56,load64(db+152));store64(db+160,load64(db+64));store64(db+224,0);syscall(3,fd,0,0,0,0,0);
    ok=fd_sync_directory(path,a);fd_clear(a);syscall(11,a,32,0,0,0,0);if !ok {return fd_corrupt(db,"compaction directory sync failed; close and reopen");}return 1;
}
