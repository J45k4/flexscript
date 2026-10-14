import "../libs/db/flexdb.flex";
import "lib/json.flex";
extend "../libs/db/schema.flex";
extend "../libs/db/compile.flex" with "lookup";
database App {table Items {id: rowid; key: i64;}}
fn lookup(row,key) {return Items_key(row)==key;}
fn now() {let t=h_take(16);h_assert(syscall(228,1,t,0,0,0,0)==0,"clock");return load64(t)*1000000000+load64(t+8);}
fn main(argc,argv) {
 h_environment(argc,argv);h_assert(argc==3,"path rows");let path=load64(argv+8);let n=h_number(load64(argv+16));let db=App_open(path);let t=Items_table(db);h_assert(db && flexdb_begin(db),"open");let input=Items_values(db,0);let key=fd_at(input,0);let i=0;while i<n {store64(key+8,i);h_assert(flexdb_insert(t,input)==i+1,"insert");i=i+1;}h_assert(flexdb_commit(db),"commit");
 let report=j_object();h_assert(flexdb_auto_budget(db,0),"scan mode");let start=now();let sum=0;i=0;while i<100 {sum=sum+lookup_count(t,(i*7919)%n);i=i+1;}j_set(report,"scan_100_ns",j_int(now()-start));h_assert(sum==100,"scan results");
 h_assert(flexdb_auto_budget(db,8388608),"adaptive mode");start=now();sum=0;i=0;while flexdb_index_state(t,0)!=2 && i<100 {sum=sum+lookup_count(t,(i*7919)%n);i=i+1;}j_set(report,"learn_build_ns",j_int(now()-start));j_set(report,"learn_queries",j_int(i));h_assert(sum==i && flexdb_index_state(t,0)==2,"learned index");
 start=now();sum=0;i=0;while i<100000 {sum=sum+lookup_count(t,(i*7919)%n);i=i+1;}j_set(report,"indexed_100000_ns",j_int(now()-start));h_assert(sum==100000,"indexed results");j_set(report,"index_bytes",j_int(flexdb_index_bytes(db)));
 start=now();h_assert(flexdb_begin(db),"indexed update begin");i=0;while i<1000 {store64(key+8,n+i);h_assert(flexdb_update(t,i+1,input),"indexed update");i=i+1;}h_assert(flexdb_commit(db),"indexed update commit");j_set(report,"indexed_update_1000_ns",j_int(now()-start));h_assert(lookup_count(t,42)==0 && lookup_count(t,n+42)==1,"updated index results");
 start=now();h_assert(flexdb_checkpoint(db) && close_flexdb(db),"checkpoint");j_set(report,"checkpoint_close_ns",j_int(now()-start));let stat=h_take(144);h_assert(syscall(4,path,stat,0,0,0,0)==0,"stat");j_set(report,"bytes",j_int(load64(stat+48)));start=now();db=App_open(path);t=Items_table(db);h_assert(db && lookup_count(t,n+42)==1,"reopen lookup");j_set(report,"reopen_first_lookup_ns",j_int(now()-start));j_set(report,"reopen_rows_decoded",j_int(load64(db+184)));close_flexdb(db);let usage=h_take(144);h_assert(syscall(98,0,usage,0,0,0,0)==0,"usage");j_set(report,"peak_kib",j_int(load64(usage+32)));h_print(1,j_dump(report));h_print(1,"\n");return 0;
}
