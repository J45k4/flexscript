import "../flexdb.flex";
fn need(db,ok) {if !ok {let s=flexdb_error(db);syscall(1,2,s,fd_len(s),0,0,0);syscall(1,2,"\n",1,0,0,0);close_flexdb(db);syscall(60,1,0,0,0,0,0);}return ok;}
fn person(db,name,age,team) {let v=flexdb_values(db);flexdb_add(db,v,flexdb_text(db,name));flexdb_add(db,v,flexdb_int(db,age));flexdb_add(db,v,flexdb_int(db,team));return v;}
fn main(argc,argv) {
    let path="build/flexdb-people.db";if argc>1 {path=load64(argv+8);}let db=open_flexdb(path);need(db,db);
    let people=flexdb_table(db,"people");let teams=flexdb_table(db,"teams");
    if !people {
        need(db,flexdb_begin(db));let schema=flexdb_schema(db);
        flexdb_column(db,schema,"name",2,0);flexdb_column(db,schema,"age",1,0);flexdb_column(db,schema,"team_id",1,0);people=flexdb_create(db,"people",schema);need(db,people);
        schema=flexdb_schema(db);flexdb_column(db,schema,"id",1,0);flexdb_column(db,schema,"name",2,0);teams=flexdb_create(db,"teams",schema);need(db,teams);
        let v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,1));flexdb_add(db,v,flexdb_text(db,"Compilers"));need(db,flexdb_insert(teams,v));
        v=flexdb_values(db);flexdb_add(db,v,flexdb_int(db,2));flexdb_add(db,v,flexdb_text(db,"Graphics"));need(db,flexdb_insert(teams,v));
        need(db,flexdb_insert(people,person(db,"Puppy",28,1)));need(db,flexdb_insert(people,person(db,"Mira",17,2)));need(db,flexdb_insert(people,person(db,"Ada",35,2)));need(db,flexdb_commit(db));
    }
    let q=flexdb_query(db);let adults=flexdb_where(q,flexdb_scan(q,people),1,flexdb_ge(),flexdb_int(q,18));need(db,adults);
    let joined=flexdb_join(q,adults,2,flexdb_scan(q,teams),0);need(db,joined);let columns=flexdb_selection(q);flexdb_pick(q,columns,0);flexdb_pick(q,columns,4);
    let result=flexdb_project(q,joined,columns);need(db,result);let i=0;
    while i<flexdb_count(result) {let row=flexdb_at(result,i);let name=flexdb_word(flexdb_cell(row,0));let team=flexdb_word(flexdb_cell(row,1));syscall(1,1,name,fd_len(name),0,0,0);syscall(1,1," -> ",4,0,0,0);syscall(1,1,team,fd_len(team),0,0,0);syscall(1,1,"\n",1,0,0,0);i=i+1;}
    flexdb_query_close(q);close_flexdb(db);return 0;
}
