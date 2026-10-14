import "../flexdb.flex";
extend "../compile.flex" with "adult";
extend "../compile.flex" with "by_id";
fn adult(row,minimum) {
    let age=flexdb_cell(row,1);
    return flexdb_kind(age)==flexdb_int_type() && flexdb_word(age)>=minimum;
}
fn by_id(row,id) {return flexdb_rowid(row)==id;}
fn main(argc,argv) {
    let path="build/people.db";if argc>1 {path=load64(argv+8);}let db=open_flexdb(path);if !db {return 1;}
    let table=flexdb_table(db,"people");if !table {close_flexdb(db);return 1;}
    let q=flexdb_query(db);let adults=adult_query(q,table,18);let person=by_id_query(q,table,1);
    let plan=adult_plan_name();syscall(1,1,plan,fd_len(plan),0,0,0);syscall(1,1,"\n",1,0,0,0);plan=by_id_plan_name();syscall(1,1,plan,fd_len(plan),0,0,0);syscall(1,1,"\n",1,0,0,0);
    let ok=flexdb_count(adults)==adult_count(table,18) && flexdb_count(person)==1 && by_id_count(table,1)==1;
    flexdb_query_close(q);close_flexdb(db);if !ok {return 1;}return 0;
}
