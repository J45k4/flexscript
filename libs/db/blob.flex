// External immutable blobs in the same file. Inline values retain their old
// layout; an external blob has kind 3, descriptor pointer, -(logical bytes+1).
// Disk references occupy 48 bytes: negative length, ID, offset, stored length,
// codec and stored CRC. Blob frames are 64-byte header + payload + 48-byte footer.
// State (db+232): threshold, level, next ID, descriptors, mappings, pending,
// pending bytes, file size, hash capacity, hash slots, enabled, compacting,
// reserved, epoch.
// Descriptor: db, ID, offset, logical/stored bytes, codec, CRC, stored pointer,
// materialized pointer, verified, pending state, staging resource, relocation,
// epoch, active reader pins (128 bytes total).
import "compression.flex";
fn fd_blob_state(db) {
 let s=load64(db+232);if s {return s;}s=fd_alloc(db,112);store64(db+232,s);store64(s,4096);store64(s+8,1);store64(s+16,1);store64(s+24,fd_vec(db));store64(s+32,fd_vec(db));store64(s+40,fd_vec(db));let st=fd_alloc(db,144);if syscall(5,load64(db+24),st,0,0,0,0)==0 {store64(s+56,load64(st+48));}return s;
}
fn flexdb_blob_options(db,threshold,level) {if !fd_ready(db) || load64(db+48) {return fd_error(db,"blob options require an idle database");}if threshold<0 || threshold>1048576 || level<1 || level>19 {return fd_error(db,"invalid blob threshold or compression level");}let s=fd_blob_state(db);if threshold!=load64(s) || level!=load64(s+8) {store64(s,threshold);store64(s+8,level);store64(s+80,1);store64(db+224,2);}return 1;}
fn flexdb_blob_external(v) {return v && load64(v)==3 && load64(v+16)<0;}
fn flexdb_blob_id(v) {if flexdb_blob_external(v) {return load64(load64(v+8)+8);}return 0;}
fn flexdb_blob_stored_bytes(v) {if flexdb_blob_external(v) {return load64(load64(v+8)+32);}return flexdb_bytes(v);}
fn flexdb_blob_codec(v) {if flexdb_blob_external(v) {return load64(load64(v+8)+40);}return 0;}
fn fd_blob_track(db,p,n) {let r=fd_alloc(db,16);store64(r,p);store64(r+8,n);fd_push(db,load64(fd_blob_state(db)+32),r);return r;}
fn fd_blob_find(s,id) {let cap=load64(s+64);if !cap {return 0;}let slot=fd_auto_hash(1,id)&(cap-1);let base=load64(s+72);while load64(base+slot*16) {if load64(base+slot*16)==id {return load64(base+slot*16+8);}slot=(slot+1)&(cap-1);}return 0;}
fn fd_blob_register(db,d) {
 let s=fd_blob_state(db);let v=load64(s+24);let cap=load64(s+64);if !cap || (fd_size(v)+1)*2>=cap {cap=cap*2;if cap<32 {cap=32;}let slots=fd_alloc(db,cap*16);let i=0;while i<fd_size(v) {let old=fd_at(v,i);let slot=fd_auto_hash(1,load64(old+8))&(cap-1);while load64(slots+slot*16) {slot=(slot+1)&(cap-1);}store64(slots+slot*16,load64(old+8));store64(slots+slot*16+8,old);i=i+1;}store64(s+64,cap);store64(s+72,slots);}
 let slot=fd_auto_hash(1,load64(d+8))&(cap-1);let slots=load64(s+72);while load64(slots+slot*16) {slot=(slot+1)&(cap-1);}store64(slots+slot*16,load64(d+8));store64(slots+slot*16+8,d);fd_push(db,v,d);store64(s+80,1);return d;
}
fn fd_blob_header(a,d,offset) {
 let h=fd_alloc(a,64);fd_copy(h,"FLEXBL01",8);store64(h+8,load64(d+32));store64(h+16,load64(d+8));store64(h+24,load64(d+24));store64(h+32,load64(d+40));store64(h+40,load64(d+48));let crc=fd_crc(4294967295,h,48)^4294967295;store64(h+48,crc|((crc^4294967295)<<32));store64(h+56,0);return h;
}
fn fd_blob_header_ok(h) {
 let n=load64(h+8);let raw=load64(h+24);let codec=load64(h+32);let crc=fd_crc(4294967295,h,48)^4294967295;
 return fd_bytes(h,"FLEXBL01",8) && n>0 && n<=67108863 && raw>0 && raw<=67108863 && load64(h+16)>0 && load64(h+16)<9223372036854775807 && (codec==0 || codec==1) && ((codec==0 && n==raw) || (codec==1 && n<raw)) && load64(h+40)>=0 && load64(h+40)<=4294967295 && load64(h+48)==(crc|((crc^4294967295)<<32)) && !load64(h+56);
}
fn fd_blob_ref(db,raw,id,offset,stored,codec,crc) {
 let s=fd_blob_state(db);if raw<1 || raw>67108863 || stored<1 || stored>raw || id<1 || id>=9223372036854775807 || offset<32 || offset>load64(s+56)-112 || stored>load64(s+56)-offset-112 || (codec!=0 && codec!=1) || (codec==0 && stored!=raw) || (codec==1 && stored>=raw) || crc<0 || crc>4294967295 {fd_corrupt(db,"invalid external blob reference");return 0;}
 let d=fd_blob_find(s,id);if d {if load64(d+16)!=offset || load64(d+24)!=raw || load64(d+32)!=stored || load64(d+40)!=codec || load64(d+48)!=crc {fd_corrupt(db,"conflicting external blob reference");return 0;}return d;}
 d=fd_alloc(db,128);store64(d,db);store64(d+8,id);store64(d+16,offset);store64(d+24,raw);store64(d+32,stored);store64(d+40,codec);store64(d+48,crc);if id>=load64(s+16) {store64(s+16,id+1);}return fd_blob_register(db,d);
}
fn fd_blob_decode(db,r,length) {
 if length>=0 || length<(-67108864) {return 0;}let id=fd_read_word(r);let offset=fd_read_word(r);let stored=fd_read_word(r);let codec=fd_read_word(r);let crc=fd_read_word(r);if !load64(r+24) {return 0;}return fd_blob_ref(db,-length-1,id,offset,stored,codec,crc);
}
fn fd_blob_offset(d) {let s=load64(load64(d)+232);if s && load64(s+88) {return load64(d+96);}return load64(d+16);}
fn fd_blob_encode(p,v) {let d=load64(v+8);store64(p,load64(v+16));store64(p+8,load64(d+8));store64(p+16,fd_blob_offset(d));store64(p+24,load64(d+32));store64(p+32,load64(d+40));store64(p+40,load64(d+48));return 48;}
fn fd_blob_prepare(db,v) {
 let s=fd_blob_state(db);if flexdb_blob_external(v) {let d=load64(v+8);if load64(d)!=db {fd_error(db,"external blob belongs to another database");return 0;}if load64(d+80)!=2 {return v;}}
 else {if load64(v)!=3 || load64(v+16)<load64(s) || !load64(v+16) {return v;}}
 let n=flexdb_bytes(v);let source=flexdb_blob_data(v);if !source {return 0;}let native=fd_codec_native(db);if native && load64(s+8)!=1 {return fd_error(db,"native Zstd currently supports compression level 1 only");}let compressed=native || fd_zstd_init();let bound=n;if native {bound=zstd_compress_bound(n);}else if compressed {bound=ffi_call(fd_z_bound,n,0,0,0,0,0);if ffi_call(fd_z_error,bound,0,0,0,0,0) {return fd_error(db,"blob compression bound failed");}}
 let p=alloc(bound);if p<=0 {return fd_error(db,"cannot allocate blob compression buffer");}let stored=n;let codec=0;
 if compressed {let got=-1;if native {let encoder=zstd_encoder_open();if !encoder {syscall(11,p,bound,0,0,0,0);return fd_error(db,"cannot allocate native Zstd encoder");}got=zstd_compress(encoder,p,bound,source,n);zstd_encoder_close(encoder);}else {got=ffi_call(fd_z_compress,p,bound,source,n,load64(s+8),0);if ffi_call(fd_z_error,got,0,0,0,0,0) {got=-1;}}if got>=0 && got<=n-32 {stored=got;codec=1;}}
 if !codec {fd_copy(p,source,n);} // No expansion for already compressed/random data.
 let keep=(stored+4095)&(-4096);let allocated=(bound+4095)&(-4096);if keep<allocated {syscall(11,p+keep,allocated-keep,0,0,0,0);}let resource=fd_blob_track(db,p,keep);
 let id=load64(s+16);if id>=9223372036854775807 {return fd_error(db,"blob IDs exhausted");}store64(s+16,id+1);let d=fd_alloc(db,128);store64(d,db);store64(d+8,id);store64(d+16,load64(db+56)+load64(s+48));store64(d+24,n);store64(d+32,stored);store64(d+40,codec);store64(d+48,fd_crc(4294967295,p,stored)^4294967295);store64(d+56,p);store64(d+72,1);store64(d+80,1);store64(d+88,resource);fd_blob_register(db,d);fd_push(db,load64(s+40),d);store64(s+48,load64(s+48)+112+stored);return fd_value(db,3,d,-n-1);
}
fn fd_blob_values(db,values) {
 let out=0;let i=0;while i<fd_size(values) {let v=fd_at(values,i);if v && load64(v)==3 {let prepared=fd_blob_prepare(db,v);if !prepared {return 0;}if prepared!=v {if !out {out=fd_clone_vec(db,values);}fd_put(out,i,prepared);}}i=i+1;}if out {return out;}return values;
}
fn fd_blob_write_frame(db,fd,d,offset,a) {
 let p=fd_blob_stored(d);if !p {return 0;}let h=fd_blob_header(a,d,offset);let end=fd_footer(a,"FLEXBLE1",load64(d+8),offset,0);return fd_io(fd,h,64,offset,1) && fd_io(fd,p,load64(d+32),offset+64,1) && fd_io(fd,end,48,offset+64+load64(d+32),1);
}
fn fd_blob_write_pending(db) {
 let s=load64(db+232);if !s || !load64(s+48) {return 1;}let a=load64(db+72);let pending=load64(s+40);let i=0;while i<fd_size(pending) {let d=fd_at(pending,i);if !fd_blob_write_frame(db,load64(db+24),d,load64(d+16),a) {return fd_corrupt(db,"external blob write failed; close and reopen");}i=i+1;}store64(db+56,load64(db+56)+load64(s+48));return 1;
}
fn fd_blob_publish(db) {let s=load64(db+232);if s {let p=load64(s+40);let i=0;while i<fd_size(p) {let d=fd_at(p,i);store64(d+80,0);fd_blob_release_staging(d);i=i+1;}store64(p,0);store64(s+48,0);store64(s+56,load64(db+56));}return 1;}
fn fd_blob_rollback(db) {let s=load64(db+232);if s {let p=load64(s+40);let i=0;while i<fd_size(p) {store64(fd_at(p,i)+80,2);i=i+1;}store64(p,0);store64(s+48,0);}return 1;}
fn fd_blob_stored(d) {return fd_blob_stored_policy(d,0);}
fn fd_blob_crc_pages(d,p,n) {
	let crc=4294967295;let at=0;
	while at<n {let take=n-at;if take>65536 {take=65536;}crc=fd_crc(crc,p+at,take);let start=(p+at)&(-4096);let end=(p+at+take)&(-4096);if end>start && !fd_blob_drop_pages(load64(d),start,end-start) {return -1;}at=at+take;}
	return crc^4294967295;
}
fn fd_blob_stored_policy(d,sequential) {
 let db=load64(d);if !fd_ready(db) {return 0;}let p=load64(d+56);if !p {let offset=load64(d+16);let start=offset&(-4096);let bytes=offset-start+112+load64(d+32);let m=syscall(9,0,bytes,1,2,load64(db+24),start);if m<0 {fd_error(db,"cannot map external blob");return 0;}fd_blob_track(db,m,bytes);let h=m+offset-start;
  if !fd_blob_header_ok(h) || load64(h+8)!=load64(d+32) || load64(h+16)!=load64(d+8) || load64(h+24)!=load64(d+24) || load64(h+32)!=load64(d+40) || load64(h+40)!=load64(d+48) {fd_corrupt(db,"external blob header mismatch");return 0;}let tail=h+64+load64(d+32);if !fd_bytes(tail,"FLEXBLE1",8) || !fd_footer_ok(tail) || load64(tail+8)!=load64(d+8) || load64(tail+16)!=offset || load64(tail+24) {fd_corrupt(db,"external blob footer mismatch");return 0;}p=h+64;store64(d+56,p);
 }if !load64(d+72) {let crc=0;if sequential && !load64(d+80) && !load64(d+88) {crc=fd_blob_crc_pages(d,p,load64(d+32));if crc<0 {return 0;}}else {crc=fd_crc(4294967295,p,load64(d+32))^4294967295;}if crc!=load64(d+48) {fd_corrupt(db,"external blob checksum mismatch");return 0;}store64(d+72,1);}return p;
}
// Bounded-memory reads. A compressed frame is streamed through a 64 KiB
// scratch buffer; only the requested range is copied. No retained decode cache.
fn flexdb_blob_read(v,offset,out,n) {
 if !v || load64(v)!=3 || offset<0 || n<0 || offset>flexdb_bytes(v) || n>flexdb_bytes(v)-offset || (n && !out) {return -1;}
 if !flexdb_blob_external(v) {if n {fd_copy(out,load64(v+8)+offset,n);}return n;}let d=load64(v+8);let db=load64(d);let p=fd_blob_stored(d);if !p {return -1;}if !load64(d+40) {if n {fd_copy(out,p+offset,n);}return n;}
 let decoder=fd_codec_decoder(fd_codec_native(db));if !decoder {fd_error(db,"Zstd decoder unavailable (libzstd.so.1 for C backend)");return -1;}let c=alloc(65664);if c<=0 {fd_codec_decoder_close(decoder);return -1;}store64(c,p);store64(c+8,load64(d+32));let total=0;let ok=1;let done=0;
 while !done && ok {let before=load64(c+16);store64(c+24,c+128);store64(c+32,65536);store64(c+40,0);let result=fd_codec_decode(decoder,c+24,c);let made=load64(c+40);if result<0 || total+made>load64(d+24) || (!made && before==load64(c+16) && result) {ok=0;}else {let lo=offset;if lo<total {lo=total;}let hi=offset+n;if hi>total+made {hi=total+made;}if hi>lo {fd_copy(out+lo-offset,c+128+lo-total,hi-lo);}total=total+made;if !result {done=1;if total!=load64(d+24) || load64(c+16)!=load64(d+32) {ok=0;}}}}
 fd_codec_decoder_close(decoder);syscall(11,c,65664,0,0,0,0);if !ok {fd_corrupt(db,"invalid compressed blob payload");return -1;}return n;
}
// Explicit materialization retains the byte pointer until database close, like
// the existing value API. Prefer blob_read for bounded-memory archive access.
fn flexdb_blob_data(v) {
 if !flexdb_blob_external(v) {if v && load64(v)==3 {return load64(v+8);}return 0;}let d=load64(v+8);if load64(d+64) {return load64(d+64);}let n=load64(d+24);let p=alloc(n+1);if p<=0 {return fd_error(load64(d),"cannot allocate blob data");}if flexdb_blob_read(v,0,p,n)<0 {syscall(11,p,n+1,0,0,0,0);return 0;}store8(p+n,0);fd_blob_track(load64(d),p,n+1);store64(d+64,p);return p;
}
fn fd_blob_close(db) {let s=load64(db+232);if s {let maps=load64(s+32);let i=0;while i<fd_size(maps) {let r=fd_at(maps,i);if load64(r) {syscall(11,load64(r),load64(r+8),0,0,0,0);}i=i+1;}}return 1;}
// Scan a complete frame during sequential recovery, using bounded scratch.
fn fd_blob_recover(db,h,offset,size,a) {
 if !fd_blob_header_ok(h) {return fd_error(db,"invalid external blob header");}let n=load64(h+8);if n>size-offset-112 {return 2;}let tail=fd_alloc(a,48);if !fd_io(load64(db+24),tail,48,offset+64+n,0) || !fd_bytes(tail,"FLEXBLE1",8) || !fd_footer_ok(tail) || load64(tail+8)!=load64(h+16) || load64(tail+16)!=offset || load64(tail+24) {return fd_error(db,"invalid external blob footer");}
 let buffer=fd_alloc(a,65536);let at=0;let crc=4294967295;while at<n {let count=n-at;if count>65536 {count=65536;}if !fd_io(load64(db+24),buffer,count,offset+64+at,0) {return fd_error(db,"cannot read external blob");}crc=fd_crc(crc,buffer,count);at=at+count;}if (crc^4294967295)!=load64(h+40) {return fd_error(db,"external blob checksum mismatch");}let s=fd_blob_state(db);if load64(h+16)>=load64(s+16) {store64(s+16,load64(h+16)+1);}store64(s+80,1);return 1;
}
fn fd_blob_cp_meta(db,a,b) {let s=load64(db+232);if s && load64(s+80) {return fd_word(a,b,load64(s+16)) && fd_word(a,b,load64(s)) && fd_word(a,b,load64(s+8));}return 1;}
fn fd_blob_cp_load(db,r) {let next=fd_read_word(r);let threshold=fd_read_word(r);let level=fd_read_word(r);if next<1 || threshold<0 || threshold>1048576 || level<1 || level>19 {return fd_error(db,"invalid blob checkpoint metadata");}let s=fd_blob_state(db);if next>load64(s+16) {store64(s+16,next);}store64(s,threshold);store64(s+8,level);store64(s+80,1);return 1;}
fn fd_blob_compact_plan(db,a) {
 let s=load64(db+232);let list=fd_vec(a);if !s || !load64(s+80) {return list;}let known=load64(s+24);let ki=0;while ki<fd_size(known) {if !fd_blob_stored(fd_at(known,ki)) {return 0;}ki=ki+1;} // Pin captured/deleted versions before replacing their source inode.
 store64(s+104,load64(s+104)+1);let epoch=load64(s+104);let tables=load64(db+40);let offset=32;let i=0;while i<fd_size(tables) {let t=fd_at(tables,i);let j=0;while j<fd_size(load64(t+24)) {let row=fd_table_row(t,j);if !row {return 0;}let k=0;while k<load64(row+8) {let v=flexdb_cell(row,k);if flexdb_blob_external(v) {let d=load64(v+8);if load64(d+104)!=epoch {if !fd_blob_stored(d) {return 0;}store64(d+104,epoch);store64(d+96,offset);offset=offset+112+load64(d+32);fd_push(a,list,d);}}k=k+1;}j=j+1;}i=i+1;}store64(s+88,1);return list;
}
fn fd_blob_compact_done(db,list,published) {let s=load64(db+232);if s {if published {let i=0;while i<fd_size(list) {let d=fd_at(list,i);store64(d+16,load64(d+96));i=i+1;}store64(s+56,load64(db+56));}store64(s+88,0);}return 1;}

fn fd_blob_value_ok(db,v,kind,n) {
 if kind==2 {return n>=0 && n<=1048576;}if kind!=3 {return 1;}if n>=0 {return n<=67108863;}return n>=(-67108864) && load64(v+8) && load64(load64(v+8))==db;
}

fn fd_blob_cp_ref(db,p,bytes,length) {
 if !load64(db+240) || bytes<40 {fd_corrupt(db,"invalid external checkpoint blob reference");return 0;}let r=load64(db+176);if !r {r=fd_alloc(db,2112);store64(db+176,r);}store64(r,p);store64(r+8,0);store64(r+16,bytes);store64(r+24,1);let d=fd_blob_decode(db,r,length);if !d {fd_corrupt(db,"invalid external checkpoint blob reference");}return d;
}

fn fd_blob_release_staging(d) {let r=load64(d+88);if !load64(d+80) && !load64(d+112) && r {syscall(11,load64(r),load64(r+8),0,0,0,0);store64(r,0);store64(d+56,0);store64(d+72,0);store64(d+88,0);}return 1;}
// Incremental reader: one decoder, caller-provided output buffers. Unlike a
// range request, successive reads do not restart decompression. Close before DB.
// 0 db,8 data,16 stored bytes,24 logical bytes,32 codec,40 decoder,48 done,
// 56 total output,64..80 input,88..104 output,112 failure,
// 120 sequential release cursor (zero for retained/anonymous),128 descriptor.
fn flexdb_blob_reader(v) {return fd_blob_reader_policy(v,0);}
fn flexdb_blob_reader_sequential(v) {
	if !v || load64(v)!=3 {return 0;}
	if flexdb_blob_external(v) {let d=load64(v+8);if !load64(d+56) && !load64(d+80) && !load64(d+88) {return fd_blob_file_reader(v);}}
	return fd_blob_reader_policy(v,1);
}
fn fd_blob_reader_policy(v,sequential) {
 if !v || load64(v)!=3 {return 0;}let r=alloc(144);if r<=0 {return 0;}store64(r+24,flexdb_bytes(v));let p=load64(v+8);let d=0;
 if flexdb_blob_external(v) {d=load64(v+8);p=fd_blob_stored_policy(d,sequential);if !p {syscall(11,r,144,0,0,0,0);return 0;}store64(r,load64(d));store64(r+32,load64(d+40));store64(r+16,load64(d+32));store64(r+128,d);store64(d+112,load64(d+112)+1);if sequential && !load64(d+80) && !load64(d+88) {if !fd_blob_release_pages(d) {flexdb_blob_reader_close(r);return 0;}store64(r+120,p&(-4096));}}else {store64(r+16,flexdb_bytes(v));}store64(r+8,p);store64(r+64,p);store64(r+72,load64(r+16));
 return fd_blob_reader_init(r);
}
fn fd_blob_reader_init(r) {
 if load64(r+32) {let decoder=fd_codec_decoder(fd_codec_native(load64(r)));store64(r+40,decoder);if !decoder {if load64(r) {fd_error(load64(r),"Zstd decoder unavailable (libzstd.so.1 for C backend)");}flexdb_blob_reader_close(r);return 0;}}return r;
}
// Fresh committed extents use bounded pread input: no resident payload mapping
// or kernel fault-around population. A dup pins the original inode across
// compaction. Cached/captured mappings and anonymous staging use the policy above.
// File reader: 144 original extent offset,152 owned CLOEXEC fd,160 bytes loaded,
// 256..65791 input scratch; common field120=-1 identifies this allocation.
fn fd_blob_file_reader(v) {
	let d=load64(v+8);let db=load64(d);if !fd_ready(db) {return 0;}
	let fd=syscall(72,load64(db+24),1030,0,0,0,0);if fd<0 {return fd_error(db,"cannot pin blob source file");}
	let r=alloc(65792);if r<=0 {syscall(3,fd,0,0,0,0,0);return fd_error(db,"cannot allocate sequential blob reader");}
	store64(r,db);store64(r+16,load64(d+32));store64(r+24,load64(d+24));store64(r+32,load64(d+40));store64(r+120,-1);store64(r+128,d);store64(r+144,load64(d+16));store64(r+152,fd);store64(d+112,load64(d+112)+1);
	let h=r+256;let offset=load64(r+144);let n=load64(r+16);
	if !fd_io(fd,h,64,offset,0) || !fd_io(fd,h+64,48,offset+64+n,0) {fd_error(db,"cannot read blob frame");flexdb_blob_reader_close(r);return 0;}
	let tail=h+64;
	if !fd_blob_header_ok(h) || load64(h+8)!=n || load64(h+16)!=load64(d+8) || load64(h+24)!=load64(d+24) || load64(h+32)!=load64(d+40) || load64(h+40)!=load64(d+48) || !fd_bytes(tail,"FLEXBLE1",8) || !fd_footer_ok(tail) || load64(tail+8)!=load64(d+8) || load64(tail+16)!=offset || load64(tail+24) {fd_corrupt(db,"invalid sequential blob frame");flexdb_blob_reader_close(r);return 0;}
	if !load64(d+72) {let crc=4294967295;let at=0;while at<n {let take=n-at;if take>65536 {take=65536;}if !fd_io(fd,h,take,offset+64+at,0) {fd_error(db,"cannot read blob checksum input");flexdb_blob_reader_close(r);return 0;}crc=fd_crc(crc,h,take);at=at+take;}if (crc^4294967295)!=load64(d+48) {fd_corrupt(db,"external blob checksum mismatch");flexdb_blob_reader_close(r);return 0;}store64(d+72,1);}
	store64(r+64,r+256);return fd_blob_reader_init(r);
}
fn fd_blob_reader_input(r) {
	if load64(r+120)!=(-1) || load64(r+80)<load64(r+72) || load64(r+160)==load64(r+16) {return 1;}
	let take=load64(r+16)-load64(r+160);if take>65536 {take=65536;}
	if !fd_io(load64(r+152),r+256,take,load64(r+144)+64+load64(r+160),0) {store64(r+112,1);return fd_error(load64(r),"cannot read sequential blob input");}
	store64(r+160,load64(r+160)+take);store64(r+72,take);store64(r+80,0);return 1;
}
fn fd_blob_reader_input_done(r) {
	if load64(r+120)==(-1) {return load64(r+160)==load64(r+16) && load64(r+80)==load64(r+72);}
	return load64(r+80)==load64(r+16);
}
fn fd_blob_reader_fail(r) {store64(r+112,1);if load64(r) {fd_corrupt(load64(r),"invalid compressed blob stream");}return -1;}
fn fd_blob_reader_consumed(r,consumed) {
	let start=load64(r+120);if start<=0 {return 1;}let end=(load64(r+8)+consumed)&(-4096);
	if end>start {if !fd_blob_drop_pages(load64(r),start,end-start) {store64(r+112,1);return 0;}store64(r+120,end);}return 1;
}
fn flexdb_blob_reader_read(r,out,n) {
 if !r || load64(r+112) || n<0 || (n && !out) {return -1;}if load64(r) && !fd_ready(load64(r)) {return -1;}if !n || load64(r+48) {return 0;}let remaining=load64(r+24)-load64(r+56);if n>remaining {n=remaining;}
 if !load64(r+32) {if n {if load64(r+120)==(-1) {if !fd_io(load64(r+152),out,n,load64(r+144)+64+load64(r+56),0) {store64(r+112,1);fd_error(load64(r),"cannot read raw sequential blob");return -1;}}else {fd_copy(out,load64(r+8)+load64(r+56),n);}}store64(r+56,load64(r+56)+n);if n==remaining {store64(r+48,1);}if !fd_blob_reader_consumed(r,load64(r+56)) {return -1;}return n;}
 store64(r+88,out);store64(r+96,n);store64(r+104,0);let hint=1;while load64(r+104)<n && hint {if !fd_blob_reader_input(r) {return -1;}let before=load64(r+80);let old=load64(r+104);hint=fd_codec_decode(load64(r+40),r+88,r+64);if hint<0 || (hint && before==load64(r+80) && old==load64(r+104)) {return fd_blob_reader_fail(r);}}
 let made=load64(r+104);store64(r+56,load64(r+56)+made);if !hint {if load64(r+56)!=load64(r+24) || !fd_blob_reader_input_done(r) {return fd_blob_reader_fail(r);}store64(r+48,1);}
 if load64(r+56)==load64(r+24) && !load64(r+48) {let done=0;while !done {if !fd_blob_reader_input(r) {return -1;}let before=load64(r+80);store64(r+88,r+136);store64(r+96,1);store64(r+104,0);hint=fd_codec_decode(load64(r+40),r+88,r+64);if hint<0 || load64(r+104) || (hint && before==load64(r+80)) {return fd_blob_reader_fail(r);}if !hint {done=1;if !fd_blob_reader_input_done(r) {return fd_blob_reader_fail(r);}store64(r+48,1);}}}if !fd_blob_reader_consumed(r,load64(r+80)) {return -1;}return made;
}
fn flexdb_blob_reader_close(r) {if !r {return 0;}if load64(r+40) {fd_codec_decoder_close(load64(r+40));}let ok=1;let d=load64(r+128);if d {store64(d+112,load64(d+112)-1);fd_blob_release_staging(d);if load64(r+120)>0 {ok=fd_blob_release_pages(d);}}let bytes=144;if load64(r+120)==(-1) {syscall(3,load64(r+152),0,0,0,0,0);bytes=65792;}syscall(11,r,bytes,0,0,0,0);return ok;}
// Drop this connection's resident file pages after a sequential scan. Keep the
// mapping/inode and every value/reader pointer valid: a later access faults the
// same immutable bytes back in, including captured values after compaction.
// Staged anonymous bytes and explicit materializations must never be discarded.
fn flexdb_blob_release_pages(v) {
	if !v || load64(v)!=3 {return 0;}if !flexdb_blob_external(v) {return 1;}
	return fd_blob_release_pages(load64(v+8));
}
fn fd_blob_drop_pages(db,start,bytes) {if syscall(28,start,bytes,4,0,0,0)<0 {return fd_error(db,"cannot release blob file pages");}return 1;}
fn fd_blob_release_pages(d) {
	let db=load64(d);if !fd_ready(db) {return 0;}
	let p=load64(d+56);if !p || load64(d+80) || load64(d+88) {return 1;}
	let start=(p-64)&(-4096);let bytes=p+load64(d+32)+48-start;
	return fd_blob_drop_pages(db,start,bytes);
}
fn fd_blob_integrity(v) {
	let r=flexdb_blob_reader_sequential(v);if !r {return 0;}let p=alloc(65536);
	if p<=0 {flexdb_blob_reader_close(r);return fd_error(load64(load64(v+8)),"cannot allocate blob integrity buffer");}
	let count=flexdb_blob_reader_read(r,p,65536);while count>0 {count=flexdb_blob_reader_read(r,p,65536);}
	let ok=flexdb_blob_reader_close(r);syscall(11,p,65536,0,0,0,0);return count==0 && ok;
}
