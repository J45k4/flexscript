import "../flexdb.flex";
import "../../../scripts/lib/host.flex";
extend "../schema.flex";
database Desired {
    table Record {
        id: rowid;
        age: i64 using parse_age;
        name: text from legacy_name;
        enabled: i64 = (1 + 2);
        score: f64 = 0x3ff8000000000000;
        memo: text?;
        nullable: i64 = 9;
        payload: blob = flexdb_blob(db, "x\0y", 3);
        drop obsolete;
    }
    table Must { n: i64 = 4; }
}
database Required { table Needs { old: i64; added: text; } }
database EmptyDesired { table Vacant { x: i64; } }
database Safe { table Keep { b: text?; a: i64?; added: i64?; } }
database Borrowed { table Borrow { key: text using borrow_key; payload: blob = borrow_blob; } }
global borrow_key_value=0;
global borrow_blob=0;
global conversions=0;
fn borrow_key(db,v) {let p=flexdb_word(borrow_key_value);store8(p,48+flexdb_word(v));return borrow_key_value;}
fn borrowed_values(path) {
    let db=open_flexdb(path);flexdb_begin(db);let schema=flexdb_schema(db);flexdb_column(db,schema,"key",1,0);let t=flexdb_create(db,"Borrow",schema);let i=1;while i<=3 {let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,i));flexdb_insert(t,v);i=i+1;}flexdb_commit(db);
    let external=alloc(32);borrow_key_value=flexdb_text(external,"0");borrow_blob=flexdb_blob(external,"x\0y",3);h_assert(Borrowed_init(db),"borrowed converter and blob default");store8(flexdb_word(borrow_key_value),57);store8(flexdb_word(borrow_blob),122);fd_clear(external);syscall(11,external,32,0,0,0,0);
    i=1;while i<=3 {let row=flexdb_get(t,i);h_assert(load8(Borrow_key(row))==48+i && fd_bytes(Borrow_payload(row),"x\0y",3),"schema owns copies of external and reused converter values");i=i+1;}
    h_assert(flexdb_checkpoint(db),"reference rows checkpoint");close_flexdb(db);db=open_flexdb(path);t=Borrow_table(db);h_assert(fd_same(Borrow_key(flexdb_get(t,1)),"1") && fd_same(Borrow_key(flexdb_get(t,3)),"3") && fd_bytes(Borrow_payload(flexdb_get(t,2)),"x\0y",3),"reference row checkpoint replay");close_flexdb(db);return 1;
}
fn parse_age(db,value) {
    conversions=conversions+1;
    let text=flexdb_word(value);if fd_same(text,"42") {return flexdb_int(db,42);}if fd_same(text,"17") {return flexdb_int(db,17);}
    if fd_same(text,"wrong") {return flexdb_text(db,"wrong");}return 0;
}
fn seed(path,mode) {
    let db=open_flexdb(path);h_assert(db && flexdb_begin(db),"seed open");let s=flexdb_schema(db);
    flexdb_column(db,s,"legacy_name",2,0);flexdb_column(db,s,"age",2,0);flexdb_column(db,s,"obsolete",3,0);flexdb_column(db,s,"nullable",1,1);
    if mode==3 {flexdb_column(db,s,"name",2,0);}let t=flexdb_create(db,"Record",s);let i=0;
    while i<3 {let v=flexdb_values(db);flexdb_add(db,v,flexdb_text(db,"Ada"));let age="17";if i==0 {age="42";}if i==1 && mode==2 {age="bad";}if i==1 && mode==4 {age="wrong";}flexdb_add(db,v,flexdb_text(db,age));flexdb_add(db,v,flexdb_blob(db,"a\0b",3));flexdb_add(db,v,flexdb_null(db));if mode==3 {flexdb_add(db,v,flexdb_text(db,"Other"));}h_assert(flexdb_insert(t,v)==i+1,"seed row");i=i+1;}
    flexdb_delete(t,3);if mode==1 {s=flexdb_schema(db);flexdb_column(db,s,"n",2,0);let must=flexdb_create(db,"Must",s);let value=flexdb_values(db);flexdb_add(db,value,flexdb_text(db,"saved"));flexdb_insert(must,value);}
    h_assert(flexdb_commit(db),"seed commit");let end=load64(db+56);close_flexdb(db);return end;
}
fn success(path) {
    seed(path,0);let db=open_flexdb(path);let t=Record_table(db);let old_row=flexdb_get(t,1);let old_columns=load64(t+16);let before=h_sha(path);
    h_assert(!Record_sync(db),"sync requires transaction");h_assert(flexdb_begin(db) && Record_sync(db),"transactional sync");h_assert(Record_matches(t) && Record_age(flexdb_get(t,1))==42,"replacement visible inside transaction");
    h_assert(flexdb_word(flexdb_cell(old_row,1))!=42 && fd_same(flexdb_word(flexdb_cell(old_row,0)),"Ada"),"old row remains immutable");
    h_assert(flexdb_rollback(db) && load64(t+16)==old_columns && flexdb_get(t,1)==old_row,"rollback restores schema and rows");h_assert(fd_same(before,h_sha(path)),"rollback writes nothing");
    conversions=0;h_assert(Desired_init(db),"automatic reconciliation");h_assert(conversions==2,"converter runs on every live old-type value");h_assert(Record_matches(t) && Must_table(db),"all desired tables synchronized");let row=flexdb_get(t,1);
    h_assert(Record_id(row)==1 && Record_age(row)==42 && fd_same(Record_name(row),"Ada"),"rename and conversion preserve ID");h_assert(Record_enabled(row)==3 && Record_score(row)==0x3ff8000000000000,"typed defaults");h_assert(Record_memo_is_null(row) && Record_nullable(row)==9,"nullable addition and explicit null backfill");
    h_assert(Record_payload_bytes(row)==3 && fd_bytes(Record_payload(row),"x\0y",3),"blob default");h_assert(!flexdb_get(t,3) && load64(t+32)==4,"deleted IDs and next ID retained");h_assert(flexdb_column_index(t,"obsolete")==-1 && flexdb_column_index(t,"legacy_name")==-1,"explicit drop and rename applied");
    before=h_sha(path);h_assert(Desired_init(db) && fd_same(before,h_sha(path)) && conversions==2,"converged schema writes nothing and skips converters");close_flexdb(db);
    db=Desired_open(path);h_assert(db,"reconciled schema replay");t=Record_table(db);row=flexdb_get(t,2);h_assert(Record_age(row)==17 && Record_nullable(row)==9 && !flexdb_get(t,3) && load64(t+32)==4,"replacement durable with IDs");close_flexdb(db);return 0;
}
fn failure(path,mode,message) {
    seed(path,mode);let before=h_sha(path);let db=open_flexdb(path);let t=Record_table(db);let schema=load64(t+16);let row=flexdb_get(t,1);
    h_assert(!Desired_init(db) && h_has(flexdb_error(db),message),"unsafe reconciliation diagnostic");h_assert(load64(db+48)==0 && load64(t+16)==schema && flexdb_get(t,1)==row,"failed reconciliation restores earlier tables and rows");h_assert(fd_same(before,h_sha(path)),"failed reconciliation file unchanged");if mode!=1 {h_assert(!Must_table(db),"failed reconciliation creates no partial table");}close_flexdb(db);
    h_assert(!Desired_open(path) && fd_same(before,h_sha(path)),"failed schema open unchanged");return 0;
}
fn safe_changes(path) {
    let db=open_flexdb(path);flexdb_begin(db);let s=flexdb_schema(db);flexdb_column(db,s,"a",1,0);flexdb_column(db,s,"b",2,0);let t=flexdb_create(db,"Keep",s);let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,8));flexdb_add(db,v,flexdb_text(db,"saved"));flexdb_insert(t,v);flexdb_commit(db);
    h_assert(Safe_init(db),"reorder, loosen nullability, add nullable field");let row=flexdb_get(t,1);h_assert(Keep_a(row)==8 && fd_same(Keep_b(row),"saved") && Keep_added_is_null(row),"safe changes preserve values by name");close_flexdb(db);db=Safe_open(path);h_assert(db && Keep_a(flexdb_get(Keep_table(db),1))==8,"safe reconciliation replay");close_flexdb(db);return 0;
}
fn empty_change(path) {
    let db=open_flexdb(path);flexdb_begin(db);let s=flexdb_schema(db);flexdb_column(db,s,"x",2,0);let t=flexdb_create(db,"Vacant",s);let v=flexdb_values(db);flexdb_add(db,v,flexdb_text(db,"deleted"));flexdb_insert(t,v);flexdb_delete(t,1);flexdb_commit(db);
    h_assert(EmptyDesired_init(db) && Vacant_matches(t) && !flexdb_get(t,1) && load64(t+32)==2,"empty type change needs no converter, retains deleted IDs");close_flexdb(db);db=EmptyDesired_open(path);h_assert(db && Vacant_matches(Vacant_table(db)),"empty type replacement replay");close_flexdb(db);return 0;
}
fn missing_default(path) {
    let db=open_flexdb(path);flexdb_begin(db);let s=flexdb_schema(db);flexdb_column(db,s,"old",1,0);let t=flexdb_create(db,"Needs",s);let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,12));flexdb_insert(t,v);flexdb_commit(db);let before=h_sha(path);
    h_assert(!Required_init(db) && h_has(flexdb_error(db),"requires a default"),"required addition needs explicit default");h_assert(fd_same(before,h_sha(path)) && flexdb_column_index(t,"added")==-1,"missing default leaves original schema");close_flexdb(db);return 0;
}
fn write_file(path,p,n) {let fd=syscall(2,path,0x80241,384,0,0,0);h_assert(fd>=0 && fd_io(fd,p,n,0,1),"fixture write");syscall(3,fd,0,0,0,0,0);return 0;}
fn recovery(work) {
    let path=h_join(work,"replace-source.db");let end=seed(path,0);let db=Desired_open(path);h_assert(db,"replacement recovery seed");close_flexdb(db);let bytes=h_read(path);let size=h_file_size;let fixture=h_join(work,"replace-torn.db");let cut=end;
    while cut<size {write_file(fixture,bytes,cut);db=open_flexdb(fixture);h_assert(db,"partial replacement recovers");let t=Record_table(db);h_assert(flexdb_column_index(t,"legacy_name")==0 && fd_same(flexdb_word(flexdb_cell(flexdb_get(t,1),1)),"42"),"partial schema transaction has no effect");h_assert(!Must_table(db) && !flexdb_get(t,3),"partial transaction keeps tables and deletions");close_flexdb(db);cut=cut+1;}
    write_file(fixture,bytes,size);db=Desired_open(fixture);h_assert(db && Record_age(flexdb_get(Record_table(db),1))==42,"complete replacement recovers");close_flexdb(db);
    let copy=h_take(size);h_copy(copy,bytes,size);store8(copy+end+64,load8(copy+end+64)^1);write_file(fixture,copy,size);let before=h_sha(fixture);h_assert(!open_flexdb(fixture) && fd_same(before,h_sha(fixture)),"corrupt replacement never rewritten");
    // Give malformed replacement payloads valid checksums to exercise semantic validation.
    h_copy(copy,bytes,size);store64(copy+end+75,2);let n=load64(copy+end+8);let crc=fd_crc(fd_crc(4294967295,copy+end,24),copy+end+32,n)^4294967295;store64(copy+end+24,(load64(copy+end+24)&0xffffffff00000000)|crc);write_file(fixture,copy,size);before=h_sha(fixture);h_assert(!open_flexdb(fixture) && fd_same(before,h_sha(fixture)),"valid CRC with incompatible replacement type rejected");
    h_copy(copy,bytes,size);let at=end+64;let columns=load64(copy+end+56);let ci=0;while ci<columns {at=at+24+load64(copy+at);ci=ci+1;}store64(copy+at+8,999);crc=fd_crc(fd_crc(4294967295,copy+end,24),copy+end+32,n)^4294967295;store64(copy+end+24,(load64(copy+end+24)&0xffffffff00000000)|crc);write_file(fixture,copy,size);before=h_sha(fixture);h_assert(!open_flexdb(fixture) && fd_same(before,h_sha(fixture)),"valid CRC with changed replacement ID rejected");return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==2,"provide fixture directory");let work=load64(argv+8);
    borrowed_values(h_join(work,"borrowed.db"));success(h_join(work,"evolve.db"));failure(h_join(work,"atomic.db"),1,"requires using");failure(h_join(work,"conversion.db"),2,"converter failed");failure(h_join(work,"ambiguous.db"),3,"ambiguous");failure(h_join(work,"bad-type.db"),4,"type/nullability");safe_changes(h_join(work,"safe.db"));empty_change(h_join(work,"empty-evolve.db"));missing_default(h_join(work,"required.db"));recovery(work);
    let a=alloc(32);let v=fd_vec(a);store64(v+8,20000000);h_assert(!fd_reserve(a,v,16777217),"transaction bound checked before spare capacity");fd_clear(a);syscall(11,a,32,0,0,0,0);
    h_print(1,"FlexDB reconciliation: defaults, renames, conversions, safe changes, atomic rollback and recovery pass\n");return 0;
}
