import "../flexdb.flex";
import "../../../scripts/lib/host.flex";
fn pack_value(db,i,j,kind,nullable) {
 if nullable && (i+j)%5==0 {return flexdb_null(db);}if kind==1 {if i%3==0 {return flexdb_int(db,1<<63);}return flexdb_int(db,9223372036854775807-i-j);}if kind==4 {return flexdb_real(db,0x7ff8000000000001);}
 let choice=(i+j)%8;let n=choice;if choice==2 {n=7;}if choice==3 {n=8;}if choice==4 {n=31;}if choice==5 {n=32;}if choice==6 {n=33;}if choice==7 {n=257;}let p=h_take(n+1);let k=0;while k<n {store8(p+k,65+(k%26));k=k+1;}if kind==3 {if n {store8(p+n/2,0);}return flexdb_blob(db,p,n);}return flexdb_text(db,p);
}
fn seed(db,count) {
 let s=flexdb_schema(db);let j=0;while j<count {let kind=1+j%4;let nullable=j%3!=0;if j==63 {nullable=1;}flexdb_column(db,s,h_int(j),kind,nullable);j=j+1;}let t=flexdb_create(db,h_cat("table",h_int(count)),s);let i=0;
 while i<140 {let v=flexdb_values(db);j=0;while j<count {let c=fd_at(s,j);flexdb_add(db,v,pack_value(db,i,j,load64(c+8),load64(c+16)));j=j+1;}h_assert(flexdb_insert(t,v),"native pack seed");i=i+1;}h_assert(flexdb_delete(t,1) && flexdb_delete(t,17) && flexdb_delete(t,140),"pack tombstones");return t;
}
fn parity(db) {
 let code=fd_crc_code;h_assert(code>0,"native CRC available");let a=alloc(32);let b=fd_cp_build(db,a);h_assert(b,"native checkpoint image");let reference=alloc(32);fd_crc_code=-1;let other=fd_cp_build(db,reference);fd_crc_code=code;h_assert(other && load64(b)==load64(other) && fd_bytes(load64(b+16),load64(other+16),load64(b)),"native and fallback complete checkpoint images match");
 let tables=load64(db+40);let i=0;while i<fd_size(tables) {let t=fd_at(tables,i);let temp=fd_vec(reference);let j=0;while j<fd_size(load64(t+24)) {let row=fd_at(load64(t+24),j);if load64(row+8) {h_assert(fd_cp_row(reference,temp,row),"reference row pack");}j=j+1;}h_assert(fd_pack_size(t)==load64(temp),"native sizing matches exact reference payload");i=i+1;}
 fd_clear(reference);syscall(11,reference,32,0,0,0,0);fd_clear(a);syscall(11,a,32,0,0,0,0);return 1;
}
fn bounded(db) {
 // Two variable fields plus a scalar end exactly at an inaccessible page.
 let s=flexdb_schema(db);flexdb_column(db,s,"text",2,0);flexdb_column(db,s,"blob",3,0);flexdb_column(db,s,"n",1,0);flexdb_begin(db);let t=flexdb_create(db,"bounds",s);let v=flexdb_values(db);flexdb_add(db,v,flexdb_text(db,"abcdefg"));flexdb_add(db,v,flexdb_blob(db,"\0x\0",3));flexdb_add(db,v,flexdb_int(db,-1));h_assert(flexdb_insert(t,v) && flexdb_commit(db),"bounds row");let bytes=fd_pack_size(t)+16;let p=syscall(9,0,8192,3,34,-1,0);h_assert(p>0 && syscall(10,p+4096,4096,0,0,0,0)==0,"packer guard page");let b=fd_vec(db);store64(b,16);store64(b+8,bytes);store64(b+16,p+4096-bytes);
 h_assert(fd_pack_rows(t,b,0)==1 && load64(b)==bytes,"packer ends exactly at guard page");let cap=16;while cap<bytes {store64(b,16);store64(b+8,cap);store64(b+16,p+4096-cap);h_assert(fd_pack_rows(t,b,0)==-1 && load64(b)==16,"every short buffer rejected without crossing guard page");cap=cap+1;}store64(b+8,bytes);store64(b+16,p+4096-bytes);h_assert(fd_pack_rows(t,b,17)==-1,"directory outside reserved prefix rejected");
 // A declared oversized payload must be rejected without reading its pointer.
 let cell=flexdb_cell(flexdb_get(t,1),1);let old=load64(cell+16);store64(cell+16,1048577);h_assert(fd_pack_size(t)==-1 && fd_pack_rows(t,b,0)==-1,"oversized blob rejected");store64(cell+16,old);syscall(11,p,8192,0,0,0,0);return 1;
}
fn size_limit(t) {
 // Sizing reads descriptors, never payloads. Repeated references here model
 // a >16 MiB payload without allocating or reading those fixture bytes.
 let rows=load64(t+24);let saved=h_take(24);h_copy(saved,rows,24);let row=fd_at(rows,0);let refs=h_take(17*8);let i=0;while i<17 {store64(refs+i*8,row);i=i+1;}let cell=flexdb_cell(row,1);let length=load64(cell+16);store64(cell+16,1048576);store64(rows,17*8);store64(rows+8,17*8);store64(rows+16,refs);h_assert(fd_pack_size(t)==-1,"total payload above 16 MiB rejected by exact sizing");h_copy(rows,saved,24);store64(cell+16,length);return 1;
}
fn main(argc,argv) {
 h_environment(argc,argv);h_assert(argc==2,"pack fixture path");let path=load64(argv+8);let db=open_flexdb(path);h_assert(db && flexdb_begin(db),"pack begin");seed(db,1);seed(db,2);seed(db,7);seed(db,64);h_assert(flexdb_commit(db),"pack commit");parity(db);bounded(db);size_limit(flexdb_table(db,"bounds"));h_assert(flexdb_checkpoint(db) && close_flexdb(db),"native checkpoint publication");db=open_flexdb(path);h_assert(db && flexdb_integrity(db),"native image reopen/integrity");parity(db);h_assert(flexdb_compact(db) && close_flexdb(db),"native compaction");db=open_flexdb(path);h_assert(db && flexdb_integrity(db) && close_flexdb(db),"compacted native image reopen");
 h_print(1,"FlexDB native packing: exact sizing/image parity, 1..64 mixed/null fields, payload boundaries, tombstones, guard page, overflow, reopen and compaction pass\n");return 0;
}
