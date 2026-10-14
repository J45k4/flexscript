import "../flexdb.flex";
extend "../schema.flex";
extend "../compile.flex" with "adult";
extend "../compile.flex" with "by_id";

database App {
    table Person {
        id:      rowid;
        name:    text;
        age:     i64;
        team_id: i64?;
    }
    table Team {
        id:   rowid;
        name: text;
    }
}

fn adult(person,minimum) {return Person_age(person)>=minimum;}
fn by_id(person,id) {return Person_id(person)==id;}
fn main(argc,argv) {
    let path="build/flexdb-schema.db";if argc>1 {path=load64(argv+8);}let db=App_open(path);if !db {return 1;}
    let people=Person_table(db);let teams=Team_table(db);
    if !by_id_count(people,1) {
        flexdb_begin(db);flexdb_insert(teams,Team_values(db,"Compilers"));flexdb_insert(teams,Team_values(db,"Graphics"));
        flexdb_insert(people,Person_values(db,"Puppy",28,flexdb_int(db,1)));flexdb_insert(people,Person_values(db,"Mira",17,flexdb_null(db)));flexdb_insert(people,Person_values(db,"Ada",35,flexdb_int(db,2)));if !flexdb_commit(db) {close_flexdb(db);return 1;}
    }
    let q=flexdb_query(db);let result=adult_query(q,people,18);let i=0;
    while i<flexdb_count(result) {let row=flexdb_at(result,i);let name=Person_name(row);syscall(1,1,name,fd_len(name),0,0,0);syscall(1,1,"\n",1,0,0,0);i=i+1;}
    let ok=adult_count(people,18)==2 && by_id_plan()==1 && Person_team_id_is_null(flexdb_get(people,2));flexdb_query_close(q);close_flexdb(db);if !ok {return 1;}return 0;
}
