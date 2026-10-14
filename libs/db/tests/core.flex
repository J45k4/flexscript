import "../flexdb.flex";
import "../../../scripts/lib/host.flex";
global checks=0;
fn check(ok,message) {h_assert(ok,message);checks=checks+1;return 0;}
fn values(a,key,name,score,blob,nullable) {
    let v=flexdb_values(a);flexdb_add(a,v,flexdb_int(a,key));flexdb_add(a,v,flexdb_text(a,name));flexdb_add(a,v,flexdb_real(a,score));flexdb_add(a,v,flexdb_blob(a,blob,3));flexdb_add(a,v,nullable);return v;
}
fn write_file(path,p,n) {let fd=syscall(2,path,0x80241,384,0,0,0);h_assert(fd>=0,"test file open");h_assert(fd_io(fd,p,n,0,1),"test file write");syscall(3,fd,0,0,0,0,0);return 0;}
fn roundtrip(path) {
    let db=open_flexdb(path);check(db,"open new database");check(!open_flexdb(path),"exclusive database lock");check(fd_same(flexdb_error(0),"database is already open (exclusive lock)"),"lock diagnostic");
    let schema=flexdb_schema(db);check(flexdb_column(db,schema,"key",1,0)==0,"key column");check(flexdb_column(db,schema,"name",2,0)==1,"text column");flexdb_column(db,schema,"score",4,0);flexdb_column(db,schema,"bytes",3,0);flexdb_column(db,schema,"optional",1,1);
    check(flexdb_column(db,schema,"key",1,0)==-1,"duplicate column rejected");check(!flexdb_create(db,"people",schema),"mutation outside transaction rejected");
    check(flexdb_begin(db),"begin");check(!flexdb_begin(db),"nested begin rejected");let people=flexdb_create(db,"people",schema);check(people,"create");check(!flexdb_create(db,"people",schema),"duplicate table rejected");
    schema=flexdb_schema(db);flexdb_column(db,schema,"key",1,1);flexdb_column(db,schema,"team",2,0);let teams=flexdb_create(db,"teams",schema);
    let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,7));flexdb_add(db,v,flexdb_text(db,"A"));check(flexdb_insert(teams,v)==1,"team insert");
    v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,7));flexdb_add(db,v,flexdb_text(db,"B"));check(flexdb_insert(teams,v)==2,"duplicate join key allowed");
    v=flexdb_values(db);flexdb_add(db,v,flexdb_null(db));flexdb_add(db,v,flexdb_text(db,"None"));check(flexdb_insert(teams,v)==3,"nullable team");
    let blob="a\0b";check(flexdb_insert(people,values(db,7,"Puppy",0x3ff8000000000000,blob,flexdb_null(db)))==1,"typed insert");
    let q=flexdb_query(db);check(flexdb_insert(people,values(q,8,"Ada",0x4000000000000000,blob,flexdb_int(q,42)))==2,"query arena values copied into database");flexdb_query_close(q);
    check(!flexdb_insert(people,flexdb_values(db)),"wrong column count");v=values(db,9,"Bad",0,blob,flexdb_null(db));fd_put(v,0,flexdb_text(db,"wrong"));check(!flexdb_insert(people,v),"wrong type");fd_put(v,0,flexdb_null(db));check(!flexdb_insert(people,v),"not-null constraint");check(flexdb_commit(db),"commit");
    let stat=h_take(144);syscall(4,path,stat,0,0,0,0);check((load64(stat+24)&511)==384,"private new file permissions");
    q=flexdb_query(db);let all=flexdb_scan(q,people);check(flexdb_count(all)==2,"scan");check(flexdb_column_index(people,"score")==2,"column lookup");check(flexdb_column_index(people,"absent")==-1,"missing column");
    check(flexdb_count(flexdb_where(q,all,0,flexdb_ge(),flexdb_int(q,8)))==1,"integer filter");check(flexdb_count(flexdb_where(q,all,1,flexdb_eq(),flexdb_text(q,"Puppy")))==1,"text filter");
    check(flexdb_count(flexdb_where(q,all,2,flexdb_lt(),flexdb_real(q,0x4000000000000000)))==1,"real filter");check(flexdb_count(flexdb_where(q,all,3,flexdb_eq(),flexdb_blob(q,blob,3)))==2,"binary blob filter");
    check(flexdb_count(flexdb_where(q,all,4,flexdb_eq(),flexdb_null(q)))==0,"null does not equal null");check(flexdb_count(flexdb_where_null(q,all,4,1))==1,"is null");check(flexdb_count(flexdb_where_null(q,all,4,0))==1,"is not null");
    check(!flexdb_where(q,all,0,0,flexdb_text(q,"x")),"filter type mismatch");check(!flexdb_where(q,all,5,0,flexdb_int(q,1)),"filter column bounds");
    let joined=flexdb_join(q,all,0,flexdb_scan(q,teams),0);check(flexdb_count(joined)==2 && flexdb_columns(joined)==7,"one-to-many join");
    let cols=flexdb_selection(q);flexdb_pick(q,cols,1);flexdb_pick(q,cols,6);let projection=flexdb_project(q,joined,cols);check(flexdb_columns(projection)==2,"projection shape");check(fd_same(flexdb_word(flexdb_cell(flexdb_at(projection,1),1)),"B"),"projection contents");
    check(flexdb_count(flexdb_limit(q,joined,1,1))==1,"offset and limit");check(flexdb_count(flexdb_limit(q,joined,10,1))==0,"limit past end");check(!flexdb_join(q,all,1,flexdb_scan(q,teams),0),"join type mismatch");
    check(flexdb_begin(db),"begin rollback");check(flexdb_update(people,1,values(db,99,"Changed",0,blob,flexdb_null(db))),"update");check(flexdb_delete(people,2),"delete");check(flexdb_insert(people,values(db,3,"New",0,blob,flexdb_null(db)))==3,"insert during transaction");
    schema=flexdb_schema(db);flexdb_column(db,schema,"x",1,0);let ghost=flexdb_create(db,"ghost",schema);check(ghost,"create during transaction");check(flexdb_word(flexdb_cell(flexdb_at(all,0),0))==7,"scan keeps immutable previous rows");
    check(flexdb_rollback(db),"rollback");check(!flexdb_table(db,"ghost") && !load64(ghost+40),"rollback table creation");check(flexdb_word(flexdb_cell(flexdb_get(people,1),0))==7 && flexdb_get(people,2) && !flexdb_get(people,3),"rollback row changes");flexdb_query_close(q);
    check(flexdb_begin(db),"begin durable changes");check(flexdb_update(people,1,values(db,-7,"Updated",0x7ff8000000000000,blob,flexdb_null(db))),"durable update");check(flexdb_delete(people,2),"durable delete");check(flexdb_insert(people,values(db,10,"Final",0,blob,flexdb_int(db,5)))==3,"rolled-back ID reused");check(flexdb_commit(db),"durable commit");close_flexdb(db);
    db=open_flexdb(path);check(db,"reopen");people=flexdb_table(db,"people");check(flexdb_word(flexdb_cell(flexdb_get(people,1),0))==-7,"signed integer replay");check(fd_same(flexdb_word(flexdb_cell(flexdb_get(people,1),1)),"Updated"),"updated text replay");check(!flexdb_get(people,2) && flexdb_get(people,3),"delete/insert replay");let bytes=flexdb_cell(flexdb_get(people,3),3);check(flexdb_bytes(bytes)==3 && fd_bytes(flexdb_word(bytes),blob,3),"embedded zero blob replay");
    q=flexdb_query(db);all=flexdb_scan(q,people);check(flexdb_count(flexdb_where(q,all,2,flexdb_ge(),flexdb_real(q,0)))==1,"NaN excluded from ordered comparison");check(flexdb_count(flexdb_where(q,all,2,flexdb_eq(),flexdb_real(q,0x8000000000000000)))==1,"signed zero equality");flexdb_query_close(q);
    let original=h_sha(path);check(flexdb_begin(db) && flexdb_commit(db),"empty transaction");check(fd_same(original,h_sha(path)),"empty commit does not append");
    check(flexdb_begin(db),"begin abandoned transaction");check(flexdb_delete(people,1),"uncommitted delete");close_flexdb(db);db=open_flexdb(path);check(flexdb_get(flexdb_table(db,"people"),1),"close discards uncommitted work");close_flexdb(db);return 0;
}
fn recovery(work) {
    let path=h_join(work,"recovery.db");let db=open_flexdb(path);flexdb_begin(db);let schema=flexdb_schema(db);flexdb_column(db,schema,"n",1,0);let t=flexdb_create(db,"numbers",schema);let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,11));flexdb_insert(t,v);flexdb_commit(db);let end=load64(db+56);
    flexdb_begin(db);v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,22));flexdb_update(t,1,v);flexdb_commit(db);close_flexdb(db);
    let whole=h_read(path);let bytes=h_file_size;let fixture=h_join(work,"torn.db");let cut=end;
    while cut<bytes {write_file(fixture,whole,cut);db=open_flexdb(fixture);check(db,"recover incomplete frame");check(flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"numbers"),1),0))==11,"incomplete transaction has no effect");close_flexdb(db);h_read(fixture);check(h_file_size==end,"recover truncates to last complete commit");cut=cut+1;}
    write_file(fixture,whole,bytes);db=open_flexdb(fixture);check(db && flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"numbers"),1),0))==22,"complete transaction survives");close_flexdb(db);
    let copy=h_take(bytes);h_copy(copy,whole,bytes);store8(copy+end+40,load8(copy+end+40)^1);write_file(fixture,copy,bytes);let before=h_sha(fixture);check(!open_flexdb(fixture),"checksum corruption rejected");check(fd_same(before,h_sha(fixture)),"corruption never rewritten");
    h_copy(copy,whole,bytes);store64(copy+end+8,16777217);write_file(fixture,copy,bytes);check(!open_flexdb(fixture),"oversized frame rejected");
    h_copy(copy,whole,bytes);store64(copy+end+8,load64(copy+end+8)+256);write_file(fixture,copy,bytes);before=h_sha(fixture);check(!open_flexdb(fixture),"corrupt length cannot masquerade as interrupted write");check(fd_same(before,h_sha(fixture)),"corrupt length never truncated");
    h_copy(copy,whole,bytes);store64(copy+bytes-8,999);write_file(fixture,copy,bytes);check(!open_flexdb(fixture),"bad footer rejected");
    write_file(fixture,"not a database",14);before=h_sha(fixture);check(!open_flexdb(fixture),"bad file header rejected");check(fd_same(before,h_sha(fixture)),"bad header untouched");
    let link=h_join(work,"link.db");syscall(88,path,link,0,0,0,0);check(!open_flexdb(link),"symlink rejected");check(!open_flexdb(work),"directory rejected");
    db=open_flexdb(path);t=flexdb_table(db,"numbers");flexdb_begin(db);v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,33));flexdb_update(t,1,v);syscall(3,load64(db+24),0,0,0,0,0);check(!flexdb_commit(db),"commit failure reported");check(!flexdb_begin(db) && !flexdb_get(t,1),"uncertain database cannot be reused");close_flexdb(db);db=open_flexdb(path);check(flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"numbers"),1),0))==22,"failed write does not publish RAM changes");close_flexdb(db);return 0;
}
fn many(path) {
    let db=open_flexdb(path);flexdb_begin(db);let schema=flexdb_schema(db);flexdb_column(db,schema,"n",1,0);let t=flexdb_create(db,"numbers",schema);let i=0;
    while i<300 {let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,i*i-10));check(flexdb_insert(t,v)==i+1,"ordered IDs across vector growth");i=i+1;}check(flexdb_commit(db),"large transaction");close_flexdb(db);db=open_flexdb(path);t=flexdb_table(db,"numbers");i=0;while i<300 {check(flexdb_word(flexdb_cell(flexdb_get(t,i+1),0))==i*i-10,"primary-key lookup after replay");i=i+1;}
    check(!flexdb_get(t,0) && !flexdb_get(t,301),"missing primary keys");let q=flexdb_query(db);check(flexdb_count(flexdb_scan(q,t))==300,"scan after vector growth");flexdb_query_close(q);close_flexdb(db);return 0;
}
fn child(path,mode) {
    let db=open_flexdb(path);if fd_same(mode,"locked") {h_assert(!db,"another process bypassed database lock");return 0;}
    h_assert(db,"child open");let t=flexdb_table(db,"numbers");h_assert(flexdb_begin(db),"child begin");let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,77));h_assert(flexdb_update(t,1,v),"child update");
    if fd_same(mode,"commit") {h_assert(flexdb_commit(db),"child commit");}
    // Exit without database/query cleanup, as a killed process would.
    syscall(231,0,0,0,0,0,0);return 0;
}
fn process_exit(work,self) {
    let path=h_join(work,"process.db");let db=open_flexdb(path);flexdb_begin(db);let schema=flexdb_schema(db);flexdb_column(db,schema,"n",1,0);let t=flexdb_create(db,"numbers",schema);let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,12));flexdb_insert(t,v);flexdb_commit(db);
    h_check(h_run(h_args(self,path,"locked",0,0,0)),0,"");check(1,"exclusive lock across processes");close_flexdb(db);
    h_check(h_run(h_args(self,path,"abandon",0,0,0)),0,"");db=open_flexdb(path);check(flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"numbers"),1),0))==12,"abrupt exit discards uncommitted changes");close_flexdb(db);
    h_check(h_run(h_args(self,path,"commit",0,0,0)),0,"");db=open_flexdb(path);check(flexdb_word(flexdb_cell(flexdb_get(flexdb_table(db,"numbers"),1),0))==77,"committed changes survive abrupt exit");close_flexdb(db);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);if argc==3 {return child(load64(argv+8),load64(argv+16));}h_assert(argc==2,"provide private fixture directory");let work=load64(argv+8);check((fd_crc(4294967295,"123456789",9)^4294967295)==0xcbf43926,"standard CRC32 check vector");
    roundtrip(h_join(work,"main.db"));recovery(work);many(h_join(work,"many.db"));process_exit(work,load64(argv));let entries=h_entries(work);let i=0;while i<h_count(entries) {check(!h_has(h_at(entries,i),"-wal") && !h_has(h_at(entries,i),"-journal"),"no sidecar journal");i=i+1;}
    h_print(1,h_cat3("FlexDB: ",h_int(checks)," checks passed\n"));return 0;
}
