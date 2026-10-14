// Readable embedded schemas, lowered to ordinary Flexscript by a syntax hook.
import "../../compiler/transform-sdk.flex";
global fds_source=0;
global fds_size=0;
global fds_at=0;
global fds_start=0;
global fds_end=0;
global fds_kind=0;
global fds_token=0;
global fds_module=0;
global fds_names=0;
global fds_tables=0;
global fds_fields=0;
fn fds_error(message) {return ext_error_at(fds_module,fds_start,message);}
fn fds_letter(c) {return (c>=65 && c<=90) || (c>=97 && c<=122) || c==95;}
fn fds_next() {
    let more=1;while more {
        while fds_at<fds_size && load8(fds_source+fds_at)<=32 {fds_at=fds_at+1;}
        if fds_at+1<fds_size && load8(fds_source+fds_at)==47 && load8(fds_source+fds_at+1)==47 {while fds_at<fds_size && load8(fds_source+fds_at)!=10 {fds_at=fds_at+1;}}else {more=0;}
    }
    fds_start=fds_at;fds_kind=0;fds_token="";
    if fds_at<fds_size {
        let c=load8(fds_source+fds_at);fds_at=fds_at+1;fds_kind=3;
        if fds_letter(c) {fds_kind=1;while fds_at<fds_size && (fds_letter(load8(fds_source+fds_at)) || (load8(fds_source+fds_at)>=48 && load8(fds_source+fds_at)<=57)) {fds_at=fds_at+1;}}
        else if c==34 {fds_kind=2;let closed=0;while fds_at<fds_size && !closed {let b=load8(fds_source+fds_at);fds_at=fds_at+1;if b==92 {if fds_at<fds_size {fds_at=fds_at+1;}}else if b==34 {closed=1;}}if !closed {fds_error("FlexDB schema: unterminated string");}}
        let n=fds_at-fds_start;fds_token=alloc(n+1);ext_copy(fds_token,fds_source+fds_start,n);
    }
    fds_end=fds_at;return 0;
}
fn fds_is(name) {return fds_kind==1 && ext_equal(fds_token,name);}
fn fds_char(c) {return fds_kind==3 && load8(fds_token)==c;}
fn fds_expect(c,message) {if !fds_char(c) {fds_error(message);}fds_next();return 0;}
fn fds_name() {if fds_kind!=1 || ext_len(fds_token)>63 {fds_error("FlexDB schema: expected identifier (at most 63 bytes)");}let name=fds_token;fds_next();return name;}
fn fds_join(a,b) {let n=ext_len(a);let m=ext_len(b);let p=alloc(n+m+1);ext_copy(p,a,n);ext_copy(p+n,b,m);return p;}
fn fds_register(name) {let p=fds_names;while p {if ext_equal(load64(p),name) {fds_error("FlexDB schema: duplicate generated name");}p=load64(p+8);}let node=alloc(16);store64(node,name);store64(node+8,fds_names);fds_names=node;return 0;}
fn fds_symbol(table,suffix) {return fds_join(fds_join(table,"_"),suffix);}
fn fds_function(table,suffix) {let name=fds_symbol(table,suffix);fds_register(name);ext_emit("fn ");ext_emit(name);return 0;}
// Field: name, kind (0 virtual rowid), nullable, column, next, source, converter, default expression.
// Table: name, first field, next table, physical column count, explicit dropped fields.
fn fds_table() {
    fds_tables=fds_tables+1;if fds_tables>32 {fds_error("FlexDB schema: at most 32 tables per expansion");}
    fds_next();let name=fds_name();let table=alloc(40);store64(table,name);fds_expect(123,"FlexDB schema: expected '{' after table name");
    let tail=0;let columns=0;let rowid=0;
    while !fds_char(125) {
        if !fds_kind {fds_error("FlexDB schema: unterminated table");}
        if fds_is("drop") {fds_next();let removed=fds_name();let node=alloc(16);store64(node,removed);store64(node+8,load64(table+32));store64(table+32,node);fds_expect(59,"FlexDB schema: drop FIELD requires ';'");}
        else {let field_name=fds_name();let prior=load64(table+8);while prior {if ext_equal(load64(prior),field_name) {fds_error("FlexDB schema: duplicate field name");}prior=load64(prior+32);}
        fds_expect(58,"FlexDB schema: expected ':' after field name");let kind=-1;
        if fds_is("rowid") {kind=0;}else if fds_is("i64") {kind=1;}else if fds_is("text") {kind=2;}else if fds_is("blob") {kind=3;}else if fds_is("f64") {kind=4;}else {fds_error("FlexDB schema: expected rowid, i64, f64, text or blob");}
        fds_next();let nullable=0;if fds_char(63) {nullable=1;fds_next();}
        if kind==0 {if nullable || rowid {fds_error("FlexDB schema: rowid must be non-null and declared only once");}rowid=1;}
        else {if columns>=64 {fds_error("FlexDB schema: at most 64 stored columns per table");}columns=columns+1;}
        fds_fields=fds_fields+1;if fds_fields>256 {fds_error("FlexDB schema: at most 256 fields per expansion");}
        let source=0;let converter=0;let fallback=0;
        if fds_is("from") {fds_next();source=fds_name();}
        if fds_is("using") {fds_next();converter=fds_name();}
        if fds_char(61) {
            fds_next();let start=fds_start;let end=start;let depth=0;
            while fds_kind && !(depth==0 && (fds_char(59) || fds_char(44) || fds_char(125))) {
                if fds_char(40) {depth=depth+1;}else if fds_char(41) {depth=depth-1;if depth<0 {fds_error("FlexDB schema: unbalanced default expression");}}
                end=fds_end;fds_next();
            }
            if end==start || depth {fds_error("FlexDB schema: expected default expression");}
            fallback=alloc(end-start+1);ext_copy(fallback,fds_source+start,end-start);
            if !fds_char(59) && !fds_char(44) {fds_error("FlexDB schema: default requires ';' or ','");}
        }
        if kind==0 && (source || converter || fallback) {fds_error("FlexDB schema: rowid cannot have reconciliation rules");}
        if fallback && ext_equal(fallback,"null") && !nullable {fds_error("FlexDB schema: null default requires nullable type");}
        let field=alloc(64);store64(field+40,source);store64(field+48,converter);store64(field+56,fallback);store64(field,field_name);store64(field+8,kind);store64(field+16,nullable);store64(field+24,columns-1);
        if tail {store64(tail+32,field);}else {store64(table+8,field);}tail=field;
        if fds_char(59) || fds_char(44) {fds_next();}
        }
    }
    let dropped=load64(table+32);while dropped {let f=load64(table+8);while f {if ext_equal(load64(f),load64(dropped)) {fds_error("FlexDB schema: cannot drop a declared field");}f=load64(f+32);}dropped=load64(dropped+8);}
    if !columns {fds_error("FlexDB schema: table needs at least one stored column");}store64(table+24,columns);fds_next();if fds_char(59) {fds_next();}return table;
}
fn fds_argument(column) {ext_emit("_fds_a");ext_emit_number(column);return 0;}
fn fds_default(field) {
    let value=load64(field+56);let kind=load64(field+8);
    if !value {ext_emit("0");}
    else if ext_equal(value,"null") {ext_emit("flexdb_null(db)");}
    else if kind==3 {ext_emit("fd_schema_value(db,(");ext_emit(value);ext_emit("))");}
    else {ext_emit("flexdb_");if kind==1 {ext_emit("int");}else if kind==2 {ext_emit("text");}else {ext_emit("real");}ext_emit("(db,(");ext_emit(value);ext_emit("))");}return 0;
}
fn fds_emit_sync(table) {
    let name=load64(table);let fields=load64(table+8);
    fds_function(name,"sync");ext_emit("(db){if !fd_writing(db){return 0;}let t=");ext_emit(fds_symbol(name,"table"));ext_emit("(db);if !t{return ");ext_emit(fds_symbol(name,"create"));ext_emit("(db)!=0;}if ");ext_emit(fds_symbol(name,"matches"));ext_emit("(t){return 1;}let columns=");ext_emit(fds_symbol(name,"schema"));ext_emit("(db);let sources=fd_vec(db);let drops=fd_vec(db);let defaults=fd_vec(db);");
    let f=fields;while f {if load64(f+8) {ext_emit("fd_push(db,sources,");if load64(f+40) {ext_emit("\"");ext_emit(load64(f+40));ext_emit("\"");}else {ext_emit("0");}ext_emit(");{let fallback=");fds_default(f);ext_emit(";");if load64(f+56) {ext_emit("if !fallback{return fd_error(db,\"schema default failed\");}");}ext_emit("fd_push(db,defaults,fallback);}");}f=load64(f+32);}
    let dropped=load64(table+32);while dropped {ext_emit("fd_push(db,drops,\"");ext_emit(load64(dropped));ext_emit("\");");dropped=load64(dropped+8);}
    ext_emit("let map=fd_schema_map(t,columns,sources,drops);if !map{return 0;}let old_columns=load64(t+16);let populated=0;let old_rows=load64(t+24);let ri=0;while ri<fd_size(old_rows){let row=fd_table_row(t,ri);if !row{return 0;}if load64(row+8){populated=1;}ri=ri+1;}");
    f=fields;while f {if load64(f+8) && !load64(f+48) {ext_emit("{let index=fd_at(map,");ext_emit_number(load64(f+24));ext_emit(");if populated && index>=0 && load64(fd_at(old_columns,index)+8)!=");ext_emit_number(load64(f+8));ext_emit("{return fd_error(db,\"schema type change requires using CONVERTER\");}}");}f=load64(f+32);}
    ext_emit("let rows=fd_vec(db);let old=load64(t+24);let i=0;while i<fd_size(old){let row=fd_table_row(t,i);if !row{return 0;}if !load64(row+8){fd_push(db,rows,row);}else{let values=flexdb_values(db);");
    f=fields;while f {if load64(f+8) {
        ext_emit("{let index=fd_at(map,");ext_emit_number(load64(f+24));ext_emit(");let v=0;if index>=0{v=flexdb_cell(row,index);");
        if load64(f+48) {ext_emit("if load64(fd_at(old_columns,index)+8)!=");ext_emit_number(load64(f+8));ext_emit("{v=");ext_emit(load64(f+48));ext_emit("(db,v);if !v{return fd_error(db,\"schema converter failed\");}v=fd_schema_value(db,v);if !v{return 0;}}");}ext_emit("}");
        ext_emit("if !v");if !load64(f+16) {ext_emit(" || !flexdb_kind(v)");}ext_emit("{let fallback=fd_at(defaults,");ext_emit_number(load64(f+24));ext_emit(");if fallback{v=fallback;}else{");
        if load64(f+16) {ext_emit("v=flexdb_null(db);");}else {ext_emit("return fd_error(db,\"schema requires a default for missing or null required field\");");}
        ext_emit("}}if !flexdb_add(db,values,v){return 0;}}");
    }f=load64(f+32);}
    ext_emit("if !fd_check_columns(db,columns,values){return 0;}fd_push(db,rows,fd_row_refs(db,load64(row),values));}i=i+1;}return fd_replace_schema(t,columns,rows); }\n");return 0;
}
fn fds_emit_table(table) {
    let name=load64(table);let fields=load64(table+8);fds_function(name,"schema");ext_emit("(db){let schema=flexdb_schema(db);");let f=fields;
    while f {if load64(f+8) {ext_emit("if flexdb_column(db,schema,\"");ext_emit(load64(f));ext_emit("\",");ext_emit_number(load64(f+8));ext_emit(",");ext_emit_number(load64(f+16));ext_emit(")<0{return 0;}");}f=load64(f+32);}ext_emit("return schema;}\n");
    fds_function(name,"table");ext_emit("(db){return flexdb_table(db,\"");ext_emit(name);ext_emit("\");}\n");
    fds_function(name,"create");ext_emit("(db){return flexdb_create(db,\"");ext_emit(name);ext_emit("\",");ext_emit(fds_symbol(name,"schema"));ext_emit("(db));}\n");
    fds_function(name,"matches");ext_emit("(table){if !fd_table_ready(table){return 0;}let columns=load64(table+16);if fd_size(columns)!=");ext_emit_number(load64(table+24));ext_emit("{return 0;}");f=fields;
    while f {if load64(f+8) {ext_emit("{let c=fd_at(columns,");ext_emit_number(load64(f+24));ext_emit(");if !fd_same(load64(c),\"");ext_emit(load64(f));ext_emit("\") || load64(c+8)!=");ext_emit_number(load64(f+8));ext_emit(" || load64(c+16)!=");ext_emit_number(load64(f+16));ext_emit("{return 0;}}");}f=load64(f+32);}ext_emit("return 1;}\n");
    fds_function(name,"values");ext_emit("(arena");f=fields;while f {if load64(f+8) {ext_emit(",");fds_argument(load64(f+24));if load64(f+8)==3 && !load64(f+16) {ext_emit(",");fds_argument(load64(f+24));ext_emit("_bytes");}}f=load64(f+32);}ext_emit("){let values=flexdb_values(arena);");f=fields;
    while f {let kind=load64(f+8);if kind {ext_emit("if !flexdb_add(arena,values,");if load64(f+16) {fds_argument(load64(f+24));}else {ext_emit("flexdb_");if kind==1 {ext_emit("int");}else if kind==2 {ext_emit("text");}else if kind==3 {ext_emit("blob");}else {ext_emit("real");}ext_emit("(arena,");fds_argument(load64(f+24));if kind==3 {ext_emit(",");fds_argument(load64(f+24));ext_emit("_bytes");}ext_emit(")");}ext_emit("){return 0;}");}f=load64(f+32);}ext_emit("return values;}\n");
    f=fields;while f {
        let field_name=load64(f);fds_function(name,field_name);ext_emit("(row){return ");if !load64(f+8) {ext_emit("flexdb_rowid(row)");}else {ext_emit("flexdb_word(flexdb_cell(row,");ext_emit_number(load64(f+24));ext_emit("))");}ext_emit(";}\n");
        if load64(f+8) {
            fds_function(name,fds_join(field_name,"_column"));ext_emit("(){return ");ext_emit_number(load64(f+24));ext_emit(";}\n");
            fds_function(name,fds_join(field_name,"_value"));ext_emit("(row){return flexdb_cell(row,");ext_emit_number(load64(f+24));ext_emit(");}\n");
            if load64(f+16) {fds_function(name,fds_join(field_name,"_is_null"));ext_emit("(row){return flexdb_kind(flexdb_cell(row,");ext_emit_number(load64(f+24));ext_emit("))==0;}\n");}
            if load64(f+8)==3 {fds_function(name,fds_join(field_name,"_bytes"));ext_emit("(row){return flexdb_bytes(flexdb_cell(row,");ext_emit_number(load64(f+24));ext_emit("));}\n");}
        }f=load64(f+32);
    }fds_emit_sync(table);return 0;
}
fn fds_database() {
    let start=fds_start;fds_next();let name=fds_name();fds_expect(123,"FlexDB schema: expected '{' after database name");let tables=0;let tail=0;
    while !fds_char(125) {if !fds_is("table") {fds_error("FlexDB schema: expected table declaration");}let table=fds_table();if tail {store64(tail+16,table);}else {tables=table;}tail=table;}
    if !tables {fds_error("FlexDB schema: database needs a table");}let end=fds_end;fds_next();if fds_char(59) {end=fds_end;fds_next();}
    ext_begin();ext_emit("\n");let table=tables;while table {fds_emit_table(table);table=load64(table+16);}
    fds_function(name,"init");ext_emit("(db){if !fd_ready(db){return 0;}if load64(db+48){return fd_error(db,\"schema initialization requires no active transaction\");}let changed=0;");table=tables;
    while table {let tname=load64(table);ext_emit("if !");ext_emit(fds_symbol(tname,"matches"));ext_emit("(");ext_emit(fds_symbol(tname,"table"));ext_emit("(db)){changed=1;}");table=load64(table+16);}
    ext_emit("if !changed{return 1;}if !flexdb_begin(db){return 0;}");table=tables;
    while table {let tname=load64(table);ext_emit("if !");ext_emit(fds_symbol(tname,"sync"));ext_emit("(db){flexdb_rollback(db);return 0;}");table=load64(table+16);}
    ext_emit("if !flexdb_commit(db){if load64(db+48)==1{flexdb_rollback(db);}return 0;}return 1;}\n");
    fds_function(name,"open");ext_emit("(path){let db=open_flexdb(path);if !db{return 0;}if !");ext_emit(fds_symbol(name,"init"));ext_emit("(db){close_flexdb(db);return 0;}return db;}\n");
    // Append helpers so a schema declaration does not turn a later ordinary
    // global into an illegal global-after-functions declaration.
    ext_edit(fds_module,start,end,"",0);ext_append_output(fds_module);return 0;
}
fn transform_syntax(context,version) {
    ext_init(context,version);fds_names=0;fds_tables=0;fds_fields=0;let module=0;
    while module<ext_module_count() {fds_module=module;fds_source=ext_module_text(module);fds_size=ext_module_size(module);fds_at=ext_module_declarations(module);let depth=0;let declaration=1;fds_next();
        while fds_kind {if !depth && declaration && fds_is("database") {fds_database();}else {
            if fds_char(123) {depth=depth+1;declaration=0;}else if fds_char(125) {depth=depth-1;if !depth {declaration=1;}}
            else if !depth {declaration=fds_char(59);}fds_next();
        }}module=module+1;
    }return ext_finish();
}
