import "../flexdb.flex";
import "../../../scripts/lib/host.flex";
fn crc_reference(crc,p,n) {let i=0;while i<n {crc=crc^load8(p+i);let bit=0;while bit<8 {if crc&1 {crc=(crc>>1)^0xedb88320;}else {crc=crc>>1;}bit=bit+1;}i=i+1;}return crc&0xffffffff;}
fn crc_and_copy() {
    let p=h_take(8192);let i=0;while i<8192 {store8(p+i,(i*37+i/13)&255);i=i+1;}let alignment=0;
    let native=fd_crc_native_init();h_assert(native!=0,"native CRC initialized or safely disabled");while alignment<8 {let n=0;while n<256 {let expected=crc_reference(0xffffffff,p+alignment,n);h_assert(fd_crc(0xffffffff,p+alignment,n)==expected,"CRC tails/alignment");fd_crc_code=-1;h_assert(fd_crc(0xffffffff,p+alignment,n)==expected,"portable CRC fallback");fd_crc_code=native;let seed=(n*2654435761)&0xffffffff;h_assert(fd_crc(seed,p+alignment,n)==crc_reference(seed,p+alignment,n),"CRC arbitrary initial states");let split=n/3;h_assert(fd_crc(fd_crc(0xffffffff,p+alignment,split),p+alignment+split,n-split)==expected,"incremental CRC");n=n+1;}h_assert(fd_crc(0xffffffff,p+alignment,4096)==crc_reference(0xffffffff,p+alignment,4096),"CRC long input");alignment=alignment+1;}
    let guard=syscall(9,0,8192,3,34,-1,0);h_assert(guard>0 && syscall(10,guard+4096,4096,0,0,0,0)==0,"CRC guard page");i=0;while i<4096 {store8(guard+i,(i*37)&255);i=i+1;}let length=0;while length<=257 {let end=guard+4096-length;h_assert(fd_crc(0xffffffff,end,length)==crc_reference(0xffffffff,end,length),"CRC never reads beyond exact byte count");length=length+1;}syscall(11,guard,8192,0,0,0,0);let to=h_take(256);let n=0;while n<=128 {i=0;while i<256 {store8(to+i,0xa5);i=i+1;}fd_copy(to+3,p+7,n);h_assert(fd_bytes(to+3,p+7,n) && load8(to+2)==0xa5 && load8(to+3+n)==0xa5,"word copy never touches guards");n=n+1;}return 0;
}
fn one(db,n) {let values=flexdb_values(db);flexdb_add(db,values,flexdb_int(db,n));return values;}
fn transaction_undo(path) {
    let db=open_flexdb(path);flexdb_begin(db);let s=flexdb_schema(db);flexdb_column(db,s,"n",1,0);let t=flexdb_create(db,"t",s);let u=flexdb_create(db,"u",s);let i=0;while i<8 {flexdb_insert(t,one(db,i));i=i+1;}flexdb_insert(u,one(db,88));flexdb_commit(db);
    let old=flexdb_get(t,1);let next=load64(t+32);let before=h_sha(path);flexdb_begin(db);h_assert(!load64(db+72),"empty begin needs no rollback arena");flexdb_update(t,1,one(db,10));h_assert(load64(load64(db+88)+16)!=0,"first mutation captures rollback snapshots");flexdb_update(t,1,one(db,11));flexdb_delete(t,1);
    i=0;while i<100 {flexdb_insert(t,one(db,i));i=i+1;}flexdb_update(t,50,one(db,99));flexdb_delete(t,60);flexdb_update(u,1,one(db,7));flexdb_insert(u,one(db,8));flexdb_create(db,"ghost",s);
    // Replace the schema after edits, then edit its replacement as well.
    let schema=flexdb_schema(db);flexdb_column(db,schema,"renamed",1,0);let rows=fd_clone_vec(db,load64(t+24));h_assert(fd_replace_schema(t,schema,rows),"schema replacement after row mutations");flexdb_update(t,2,one(db,123));flexdb_insert(t,one(db,124));h_assert(flexdb_rollback(db),"undo rollback");
    h_assert(flexdb_get(t,1)==old && flexdb_word(flexdb_cell(old,0))==0 && load64(t+32)==next && fd_size(load64(t+24))==8,"reverse undo after repeated edits and vector growth");h_assert(flexdb_column_index(t,"n")==0 && !flexdb_table(db,"ghost") && flexdb_word(flexdb_cell(flexdb_get(u,1),0))==88 && !flexdb_get(u,2),"schema and other tables restored");h_assert(fd_same(before,h_sha(path)),"undo does not write disk");
    flexdb_begin(db);let new_table=flexdb_create(db,"new",s);h_assert(fd_table_id(new_table)==2,"rolled back table ordinal reused");flexdb_insert(t,one(db,99));flexdb_insert(u,one(db,89));flexdb_update(t,2,one(db,55));flexdb_insert(t,one(db,100));flexdb_delete(t,3);flexdb_insert(t,one(db,101));flexdb_insert(new_table,one(db,3));h_assert(flexdb_commit(db),"interleaved batch commit");close_flexdb(db);
    db=open_flexdb(path);h_assert(db,"interleaved replay");t=flexdb_table(db,"t");h_assert(!flexdb_get(t,3) && flexdb_word(flexdb_cell(flexdb_get(t,2),0))==55 && flexdb_word(flexdb_cell(flexdb_get(t,11),0))==101,"interleaved batch values and deletes");h_assert(flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"new"),1),0))==3,"ordinal reuse replay");close_flexdb(db);return 0;
}
fn wide_batch(path) {
    let db=open_flexdb(path);flexdb_begin(db);let s=flexdb_schema(db);let i=0;while i<64 {flexdb_column(db,s,h_int(i),1,1);i=i+1;}let t=flexdb_create(db,"wide",s);let v=flexdb_values(db);i=0;while i<64 {let value=flexdb_int(db,i);if i==63 {value=flexdb_null(db);}flexdb_add(db,v,value);i=i+1;}flexdb_insert(t,v);flexdb_insert(t,v);flexdb_commit(db);close_flexdb(db);
    db=open_flexdb(path);h_assert(db,"64 column batch replay");t=flexdb_table(db,"wide");h_assert(flexdb_kind(flexdb_cell(flexdb_get(t,2),63))==0 && flexdb_word(flexdb_cell(flexdb_get(t,1),62))==62,"bit 63 null mask");close_flexdb(db);return 0;
}
fn legacy(path) {
    let db=open_flexdb(path);flexdb_begin(db);let schema=flexdb_schema(db);flexdb_column(db,schema,"n",1,0);flexdb_create(db,"legacy",schema);flexdb_commit(db);flexdb_begin(db);
    // Original version-one upsert record for a newly inserted integer row.
    h_assert(fd_command(db,48),"legacy command");fd_log_word(db,2);fd_log_word(db,0);fd_log_word(db,1);fd_log_word(db,1);fd_log_word(db,1);fd_log_word(db,123);fd_logged(db);flexdb_commit(db);close_flexdb(db);
    db=open_flexdb(path);h_assert(db && flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"legacy"),1),0))==123,"original insert encoding still replays");close_flexdb(db);return 0;
}
fn main(argc,argv) {h_environment(argc,argv);h_assert(argc==2,"fixture directory");let work=load64(argv+8);crc_and_copy();transaction_undo(h_join(work,"undo.db"));wide_batch(h_join(work,"wide-batch.db"));legacy(h_join(work,"legacy.db"));h_print(1,"FlexDB fast paths: reference CRC, bounded copies, undo, batch replay and legacy records pass\n");return 0;}
