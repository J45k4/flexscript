import "../flexdb.flex";
import "../../../scripts/lib/host.flex";
extend "../schema.flex";
extend "../compile.flex" with "lookup";
extend "../compile.flex" with "positive";
database Test {
    // Virtual row ID may appear anywhere, and does not consume a stored column.
    table Sample {
        name: text
        id: rowid;
        number: i64,
        score: f64;
        data: blob;
        optional: i64?;
        note: text?;
        extra: blob?;
    }
    table Empty { label: text; }
}
// Tokens in comments, strings, globals and ordinary function names are untouched.
global database=3;
fn lookup(row,id) {return Sample_id(row)==id;}
fn positive(row) {return Sample_number(row)>0 && !Sample_optional_is_null(row);}
fn words() {let database="database Ignored { table Bad { } }";return fd_len(database);}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==3,"schema test requires data and mismatch paths");let path=load64(argv+8);let db=Test_open(path);h_assert(db,"schema open");h_assert(Test_init(db),"schema initialization idempotent");let table=Sample_table(db);h_assert(Sample_matches(table) && Empty_table(db),"all tables created");
    h_assert(Sample_name_column()==0 && Sample_number_column()==1 && Sample_extra_column()==6,"generated physical column indices");h_assert(lookup_plan()==1 && positive_plan()==0,"named accessors work with compiler planner");
    h_assert(flexdb_begin(db),"schema insert begin");h_assert(!Test_init(db),"schema initialization inside transaction rejected");let binary="a\0b";
    let v=Sample_values(db,"Puppy",-9223372036854775807-1,0x3ff8000000000000,binary,3,flexdb_null(db),flexdb_null(db),flexdb_null(db));h_assert(flexdb_insert(table,v)==1,"generated value builder");
    v=Sample_values(db,"Ada",42,0,binary,3,flexdb_int(db,10),flexdb_text(db,"hello"),flexdb_blob(db,binary,3));h_assert(flexdb_insert(table,v)==2,"nullable values");h_assert(flexdb_commit(db),"schema insert commit");
    let row=flexdb_get(table,1);h_assert(Sample_id(row)==1 && fd_same(Sample_name(row),"Puppy"),"named row getters");h_assert(Sample_number(row)==-9223372036854775807-1 && Sample_score(row)==0x3ff8000000000000,"integer and f64 getters");h_assert(Sample_data_bytes(row)==3 && fd_bytes(Sample_data(row),binary,3),"blob getter");h_assert(Sample_optional_is_null(row) && Sample_optional(row)==0 && Sample_note(row)==0,"nullable raw getters");
    row=flexdb_get(table,2);h_assert(!Sample_optional_is_null(row) && Sample_optional(row)==10,"nullable integer getter");h_assert(fd_same(Sample_note(row),"hello") && !Sample_extra_is_null(row) && Sample_extra_bytes(row)==3,"nullable text/blob getters");h_assert(flexdb_kind(Sample_number_value(row))==1,"value descriptor getter");
    h_assert(lookup_count(table,2)==1 && positive_count(table)==1 && database==3 && words()>0,"ordinary code and compiler queries");close_flexdb(db);db=Test_open(path);h_assert(db && lookup_count(Sample_table(db),2)==1,"schema reopen");let before=h_sha(path);h_assert(Test_init(db) && fd_same(before,h_sha(path)),"matching schema does not write");close_flexdb(db);
    path=load64(argv+16);db=open_flexdb(path);flexdb_begin(db);let schema=flexdb_schema(db);flexdb_column(db,schema,"wrong",1,0);flexdb_create(db,"Sample",schema);flexdb_commit(db);close_flexdb(db);before=h_sha(path);
    h_assert(!Test_open(path),"unsafe field removal rejected");h_assert(h_has(flexdb_error(0),"schema would remove a field") && fd_same(before,h_sha(path)),"schema mismatch diagnostic preserves data");db=open_flexdb(path);h_assert(!Empty_table(db),"schema mismatch creates no partial tables");close_flexdb(db);
    h_print(1,"FlexDB schema: generated tables, fields, nullable values, planning and reopen pass\n");return 0;
}
