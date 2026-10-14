import "../flexdb.flex";
import "../../../scripts/lib/host.flex";
extend "../schema.flex";
extend "../compile.flex" with "adult";
database Desired { table Items { note: text?; id: rowid; age: i64; name: text from old_name; } }
fn adult(row) {return flexdb_word(flexdb_cell(row,1))>=0;}
fn values(db,n,name) {let v=flexdb_values(db);flexdb_add(db,v,flexdb_text(db,name));flexdb_add(db,v,flexdb_int(db,n));return v;}
fn seed(path) {
    let db=open_flexdb(path);h_assert(db && flexdb_begin(db),"seed");let s=flexdb_schema(db);flexdb_column(db,s,"old_name",2,0);flexdb_column(db,s,"age",1,0);let t=flexdb_create(db,"Items",s);flexdb_insert(t,values(db,10,"Ada"));flexdb_insert(t,values(db,20,"Puppy"));flexdb_insert(t,values(db,30,"Deleted"));flexdb_delete(t,3);flexdb_commit(db);let end=load64(db+56);
    h_assert(flexdb_begin(db) && !flexdb_checkpoint(db) && flexdb_rollback(db),"checkpoint rejects active transaction");h_assert(flexdb_checkpoint(db),"checkpoint");let hash=h_sha(path);h_assert(flexdb_checkpoint(db) && fd_same(hash,h_sha(path)),"unchanged checkpoint writes nothing");h_assert(close_flexdb(db),"checkpoint close");return end;
}
fn lazy_and_tail(path) {
    seed(path);let db=open_flexdb(path);h_assert(db && load64(db+144)>0 && load64(db+184)==0,"checkpoint open loads no rows");let t=flexdb_table(db,"Items");h_assert(fd_at(load64(t+24),0)==0 && load64(t+32)==4,"persisted directory/next ID");let row=flexdb_get(t,2);h_assert(row && flexdb_word(flexdb_cell(row,1))==20 && load64(db+184)==1,"only requested row decoded");h_assert(flexdb_get(t,2)==row && load64(db+184)==1,"row cache");
    flexdb_begin(db);flexdb_update(t,1,values(db,99,"Changed"));flexdb_insert(t,values(db,40,"New"));h_assert(flexdb_rollback(db) && flexdb_word(flexdb_cell(flexdb_get(t,1),1))==10 && !flexdb_get(t,4),"lazy rollback");
    let q=flexdb_query(db);let result=flexdb_scan(q,t);h_assert(result && flexdb_count(result)==2 && load64(db+184)==3,"scan checks remaining rows including tombstones");
    flexdb_begin(db);flexdb_update(t,1,values(db,99,"Changed"));flexdb_insert(t,values(db,40,"New"));flexdb_commit(db);h_assert(fd_same(flexdb_word(flexdb_cell(flexdb_at(result,0),0)),"Ada"),"immutable checkpoint query rows");flexdb_query_close(q);let cp=load64(db+144);close_flexdb(db);
    db=open_flexdb(path);h_assert(db && load64(db+144)==cp && load64(db+184)==1,"checkpoint with transaction tail loads only updated base row");t=flexdb_table(db,"Items");h_assert(flexdb_word(flexdb_cell(flexdb_get(t,1),1))==99 && flexdb_word(flexdb_cell(flexdb_get(t,4),1))==40 && !flexdb_get(t,3),"tail replay");h_assert(flexdb_integrity(db),"full current-state integrity check");
    h_assert(Desired_init(db) && Items_matches(t),"schema reconciliation after lazy checkpoint");row=flexdb_get(t,1);h_assert(Items_age(row)==99 && fd_same(Items_name(row),"Changed") && Items_note_is_null(row),"reconciled values");close_flexdb(db);
    db=Desired_open(path);h_assert(db && Items_age(flexdb_get(Items_table(db),4))==40 && flexdb_integrity(db),"reconciled tail reopen");close_flexdb(db);return 0;
}
fn write_file(path,p,n) {let fd=syscall(2,path,0x80241,384,0,0,0);h_assert(fd>=0 && fd_io(fd,p,n,0,1),"fixture write");syscall(3,fd,0,0,0,0,0);return 0;}
fn recovery(work) {
    let path=h_join(work,"cp-source.db");let end=seed(path);let all=h_read(path);let size=h_file_size;let fixture=h_join(work,"cp-torn.db");let cut=end;
    while cut<size {write_file(fixture,all,cut);let db=open_flexdb(fixture);h_assert(db && !load64(db+144),"partial checkpoint falls back to committed log");let t=flexdb_table(db,"Items");h_assert(flexdb_word(flexdb_cell(flexdb_get(t,1),1))==10 && !flexdb_get(t,3),"partial checkpoint preserves committed rows");h_assert(load64(db+56)==end,"partial checkpoint truncated at start");close_flexdb(db);cut=cut+1;}
    write_file(fixture,all,size);let db=open_flexdb(fixture);h_assert(db && load64(db+184)==0 && flexdb_integrity(db),"complete checkpoint recognized");close_flexdb(db);
    db=open_flexdb(path);let t=flexdb_table(db,"Items");flexdb_begin(db);flexdb_update(t,1,values(db,55,"Tail"));flexdb_commit(db);close_flexdb(db);all=h_read(path);let total=h_file_size;cut=size;
    while cut<total {write_file(fixture,all,cut);db=open_flexdb(fixture);h_assert(db && flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"Items"),1),1))==10,"partial modern transaction preserves checkpoint");h_assert(load64(db+56)==size,"partial modern tail truncated");close_flexdb(db);cut=cut+1;}
    write_file(fixture,all,total);db=open_flexdb(fixture);h_assert(db && flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"Items"),1),1))==55,"complete modern transaction replays");close_flexdb(db);return 0;
}
fn corruption(work) {
    let path=h_join(work,"cp-corrupt-source.db");let cp=seed(path);let all=h_read(path);let size=h_file_size;let copy=h_take(size);let fixture=h_join(work,"cp-corrupt.db");
    let offsets=h_args(h_int(cp+24),h_int(cp+40),h_int(size-8),0,0,0);let i=0;while i<h_count(offsets) {h_copy(copy,all,size);let offset=h_number(h_at(offsets,i));store8(copy+offset,load8(copy+offset)^1);write_file(fixture,copy,size);let before=h_sha(fixture);h_assert(!open_flexdb(fixture) && fd_same(before,h_sha(fixture)),"metadata/header/footer corruption fails without rewrite");i=i+1;}
    let db=open_flexdb(path);let t=flexdb_table(db,"Items");let directory=load64(t+64)-load64(db+128);let body=cp+32;let row=body+load64(all+directory);close_flexdb(db);
    h_copy(copy,all,size);store8(copy+directory,load8(copy+directory)^1);write_file(fixture,copy,size);let before=h_sha(fixture);db=open_flexdb(fixture);h_assert(db,"directory corruption is checked lazily");h_assert(!flexdb_get(flexdb_table(db,"Items"),1) && load64(db+48)==2 && h_has(flexdb_error(db),"directory checksum"),"directory corruption poisons connection");close_flexdb(db);h_assert(fd_same(before,h_sha(fixture)),"directory corruption untouched");
    h_copy(copy,all,size);store8(copy+row+10,load8(copy+row+10)^1);write_file(fixture,copy,size);before=h_sha(fixture);db=open_flexdb(fixture);h_assert(db && adult_count(flexdb_table(db,"Items"))==-1 && h_has(flexdb_error(db),"row checksum"),"compiled lazy counts propagate corruption");close_flexdb(db);h_assert(fd_same(before,h_sha(fixture)),"row corruption untouched");
    // The checkpoint is the authoritative state; historical superseded bytes
    // are not part of current-state integrity validation.
    h_copy(copy,all,size);store8(copy+80,load8(copy+80)^1);write_file(fixture,copy,size);db=open_flexdb(fixture);h_assert(db && flexdb_integrity(db),"authoritative checkpoint skips superseded history");close_flexdb(db);return 0;
}
fn compaction(path,fixture) {
    seed(path);let db=open_flexdb(path);let t=flexdb_table(db,"Items");let saved=flexdb_get(t,1);let i=0;
    while i<100 {flexdb_begin(db);flexdb_update(t,1,values(db,i,"Current"));flexdb_commit(db);i=i+1;}
    let stat=h_take(144);syscall(4,path,stat,0,0,0,0);let before=load64(stat+48);flexdb_begin(db);h_assert(!flexdb_compact(db) && flexdb_rollback(db),"compaction rejects active transaction");h_assert(flexdb_compact(db),"atomic compaction");syscall(4,path,stat,0,0,0,0);h_assert(load64(stat+48)<before && fd_same(flexdb_word(flexdb_cell(saved,0)),"Ada"),"compaction shrinks file and preserves captured row");h_assert(!open_flexdb(path),"new inode lock held after compaction");let bytes=h_read(path);let size=h_file_size;let cut=32;while cut<size {write_file(fixture,bytes,cut);let hash=h_sha(fixture);h_assert(!open_flexdb(fixture) && fd_same(hash,h_sha(fixture)),"incomplete compacted base fails without erasing data");cut=cut+1;}
    flexdb_begin(db);h_assert(flexdb_insert(t,values(db,44,"Next"))==4,"compaction keeps next ID");flexdb_commit(db);close_flexdb(db);db=open_flexdb(path);h_assert(db && flexdb_integrity(db),"compacted checkpoint/tail reopen");t=flexdb_table(db,"Items");h_assert(flexdb_word(flexdb_cell(flexdb_get(t,1),1))==99 && !flexdb_get(t,3) && flexdb_word(flexdb_cell(flexdb_get(t,4),1))==44,"compaction preserves data and tombstones");close_flexdb(db);return 0;
}
fn failed_checkpoint(path) {
    let db=open_flexdb(path);flexdb_begin(db);let s=flexdb_schema(db);flexdb_column(db,s,"n",1,0);let t=flexdb_create(db,"t",s);let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,123));flexdb_insert(t,v);flexdb_commit(db);let before=h_sha(path);syscall(3,load64(db+24),0,0,0,0,0);h_assert(!flexdb_checkpoint(db) && load64(db+48)==2,"checkpoint IO failure poisons connection");close_flexdb(db);h_assert(fd_same(before,h_sha(path)),"failed checkpoint preserves committed file");db=open_flexdb(path);h_assert(db && flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"t"),1),0))==123,"failed checkpoint reopens committed state");close_flexdb(db);return 0;
}
fn main(argc,argv) {h_environment(argc,argv);h_assert(argc==2,"fixture directory");let work=load64(argv+8);lazy_and_tail(h_join(work,"lazy.db"));recovery(work);corruption(work);compaction(h_join(work,"compact.db"),h_join(work,"compact-torn.db"));failed_checkpoint(h_join(work,"failed-cp.db"));h_print(1,"FlexDB checkpoints: lazy rows, tails, schema sync, corruption and every torn prefix pass\n");return 0;}
