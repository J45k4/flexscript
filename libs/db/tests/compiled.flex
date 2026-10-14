import "../flexdb.flex";
import "../../../scripts/lib/host.flex";
extend "../compile.flex" with "adult";
extend "../compile.flex" with "lookup";
extend "../compile.flex" with "reversed";
extend "../compile.flex" with "fixed";
extend "../compile.flex" with "complex";
extend "../compile.flex" with "all_rows";
fn age_at_least(row,minimum) {let age=flexdb_cell(row,0);return flexdb_kind(age)==1 && flexdb_word(age)>=minimum;}
fn adult(row,minimum) {return age_at_least(row,minimum);}
fn lookup(row,id) {return flexdb_rowid(row)==id;}
fn reversed(row,id,ignored) {let alias=row;let key=id;return key==flexdb_rowid(alias);}
fn fixed(row) {return flexdb_rowid(row)==42;}
fn complex(row,id) {return flexdb_rowid(row)==id || age_at_least(row,90);}
fn all_rows(row) {return 1;}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==2,"provide compiled fixture path");let db=open_flexdb(load64(argv+8));h_assert(db,"compiled open");flexdb_begin(db);let schema=flexdb_schema(db);flexdb_column(db,schema,"age",1,1);let t=flexdb_create(db,"people",schema);let i=0;
    while i<200 {let v=flexdb_values(db);let value=flexdb_int(db,i);if i%9==0 {value=flexdb_null(db);}flexdb_add(db,v,value);flexdb_insert(t,v);i=i+1;}flexdb_delete(t,42);flexdb_commit(db);
    h_assert(adult_plan()==0 && lookup_plan()==1 && reversed_plan()==1 && fixed_plan()==1 && complex_plan()==0,"compiler access-path selection");
    let head=load64(db);let used=load64(db+8);h_assert(adult_count(t,18)==160,"fused normal helper predicate");h_assert(all_rows_count(t)==199,"all rows count");h_assert(head==load64(db) && used==load64(db+8),"compiled counts allocate no database memory");
    let q=flexdb_query(db);let all=flexdb_scan(q,t);let expected=flexdb_where(q,all,0,flexdb_ge(),flexdb_int(q,18));let actual=adult_query(q,t,18);h_assert(flexdb_count(expected)==flexdb_count(actual),"fused scan matches ordinary query");i=0;
    while i<flexdb_count(actual) {h_assert(flexdb_rowid(flexdb_at(actual,i))==flexdb_rowid(flexdb_at(expected,i)),"fused scan preserves row order");i=i+1;}
    i=-2;while i<=202 {let want=flexdb_get(t,i)!=0;h_assert(lookup_count(t,i)==want,"seek count matches get");h_assert(reversed_count(t,i,999)==want,"reversed equality and aliases");h_assert(flexdb_count(lookup_query(q,t,i))==want,"seek query matches get");i=i+1;}
    h_assert(fixed_count(t)==0 && flexdb_count(fixed_query(q,t))==0,"seek handles deleted ID");h_assert(complex_count(t,1)>1,"disjunction stays a scan");
    flexdb_begin(db);let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,100));let id=flexdb_insert(t,v);h_assert(lookup_count(t,id)==1,"seek sees own writes");flexdb_rollback(db);h_assert(lookup_count(t,id)==0,"seek observes rollback");
    flexdb_query_close(q);close_flexdb(db);h_print(1,"FlexDB compiled predicates: fusion, seeks, counts, helpers and rollback pass\n");return 0;
}
