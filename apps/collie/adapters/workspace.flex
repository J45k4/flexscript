// Trusted FlexDB broker. The VM sends values, never native pointers or paths.
import "../lib/json.flex";
import "../../../libs/db/flexdb.flex";
import "../guest/runtime.flex";
import "../guest/source.flex";

global cw_db=0;
global cw_problem=0;
global cw_config=0;
global cw_history=0;
fn cw_fail(text) {cw_problem=text;return 0;}
fn cw_name(v) {return db_kind(v)==2 && db_bytes(v)>0 && db_bytes(v)<=255;}
fn cw_int(v) {return db_kind(v)==1;}
fn cw_arg(request,i,kind) {let v=db_at(request,i);if db_kind(v)!=kind {cw_fail("Invalid database argument type.");return 0;}return v;}
fn cw_table(request) {let name=cw_arg(request,1,2);if !cw_name(name) {return cw_fail("Invalid table name.");}let t=flexdb_table(cw_db,db_word(name));if !t {cw_fail("Table does not exist.");}return t;}
fn cw_open() {
    if cw_db {return 1;}let path=c_string(cw_config,"workspace_file");if !path || !h_len(path) {return cw_fail("No workspace database was granted.");}
    h_mkdir(h_dir(path));cw_db=open_flexdb(path);if !cw_db {return cw_fail(flexdb_error(0));}
    if syscall(91,load64(cw_db+24),384,0,0,0,0)<0 {return cw_fail("Cannot protect workspace database.");}return 1;
}
fn cw_value(v) {
    let kind=db_kind(v);if kind<0 || kind>4 {cw_fail("Rows require scalar database values.");return 0;}
    if kind==0 {return flexdb_null(cw_db);}if kind==1 {return flexdb_int(cw_db,db_word(v));}if kind==4 {return flexdb_real(cw_db,db_word(v));}
    if kind==2 {return flexdb_text(cw_db,db_word(v));}return flexdb_blob(cw_db,db_word(v),db_bytes(v));
}
fn cw_values(v) {
    if db_kind(v)!=5 || db_count(v)<1 || db_count(v)>64 {return cw_fail("A row must contain 1..64 scalar values.");}
    let values=flexdb_values(cw_db);let i=0;while i<db_count(v) {let value=cw_value(db_at(v,i));if !value {return 0;}flexdb_add(cw_db,values,value);i=i+1;}return values;
}
fn cw_scalar(v) {
    let kind=flexdb_kind(v);if kind==0 {return db_null();}if kind==1 {return db_int(flexdb_word(v));}if kind==4 {return db_real(flexdb_word(v));}
    if flexdb_bytes(v)>32768 {return cw_fail("Value exceeds the 32 KiB VM transfer limit.");}if kind==2 {return db_text(flexdb_word(v));}
    let data=flexdb_blob_data(v);if !data {return cw_fail(flexdb_error(cw_db));}return db_blob(data,flexdb_bytes(v));
}
fn cw_row(row) {
    if !row {return db_null();}let result=db_list();db_add(result,db_int(flexdb_rowid(row)));let values=db_list();let i=0;
    while i<load64(row+8) {let v=cw_scalar(flexdb_cell(row,i));if !v {return 0;}db_add(values,v);i=i+1;}db_add(result,values);return result;
}
fn cw_schema(value) {
    if db_kind(value)!=5 || db_count(value)<1 || db_count(value)>64 {return cw_fail("A schema requires 1..64 columns.");}let schema=flexdb_schema(cw_db);let i=0;
    while i<db_count(value) {let c=db_at(value,i);let name=db_at(c,0);let kind=db_at(c,1);let nullable=db_at(c,2);
        if db_kind(c)!=5 || db_count(c)!=3 || !cw_name(name) || !cw_int(kind) || !cw_int(nullable) {return cw_fail("Invalid schema column.");}
        if flexdb_column(cw_db,schema,db_word(name),db_word(kind),db_word(nullable))<0 {return 0;}i=i+1;}return schema;
}
fn cw_alter(request,op) {
    let t=cw_table(request);if !t {return 0;}let name=cw_arg(request,2,2);if !cw_name(name) {return cw_fail("Invalid column name.");}let old=load64(t+16);let index=flexdb_column_index(t,db_word(name));let adding=h_equal(op,"add_column");let dropping=h_equal(op,"drop_column");
    if adding && index>=0 {return cw_fail("Column already exists.");}if !adding && index<0 {return cw_fail("Column does not exist.");}
    if dropping && fd_size(old)==1 {return cw_fail("Cannot drop the last column.");}
    let replacement=0;let kind=0;let nullable=0;let default=0;
    if adding {kind=cw_arg(request,3,1);nullable=cw_arg(request,4,1);if !kind || !nullable {return 0;}default=cw_value(db_at(request,5));if !default {return 0;}}
    else if !dropping {replacement=cw_arg(request,3,2);if !cw_name(replacement) {return cw_fail("Invalid replacement column name.");}}
    if !fd_writing(cw_db) {return 0;}let columns=flexdb_schema(cw_db);let i=0;
    while i<fd_size(old) {let c=fd_at(old,i);if !dropping || i!=index {let text=load64(c);if replacement && i==index {text=db_word(replacement);}if flexdb_column(cw_db,columns,text,load64(c+8),load64(c+16))<0 {return 0;}}i=i+1;}
    if adding && flexdb_column(cw_db,columns,db_word(name),db_word(kind),db_word(nullable))<0 {return 0;}
    let rows=fd_vec(cw_db);i=0;while i<fd_size(load64(t+24)) {let row=fd_table_row(t,i);if !row {return 0;}let values=flexdb_values(cw_db);let j=0;
        while j<load64(row+8) {if !dropping || j!=index {flexdb_add(cw_db,values,flexdb_cell(row,j));}j=j+1;}
        if adding && load64(row+8) {flexdb_add(cw_db,values,default);}fd_push(cw_db,rows,fd_row(cw_db,flexdb_rowid(row),values));i=i+1;}
    if !fd_replace_schema(t,columns,rows) {return 0;}return db_int(1);
}
fn cw_history_field(item,field) {
    if h_equal(field,"observation") {let value=j_get(item,field);if value {return j_dump(value);}return "";}
    if !(h_equal(field,"content") || h_equal(field,"source") || h_equal(field,"role")) {return 0;}let text=c_string(item,field);if !text {text="";}return text;
}
fn cw_history_request(request,op) {
    let first=cw_arg(request,1,1);if !first || db_word(first)<0 {return cw_fail("Invalid history offset.");}let offset=db_word(first);
    if h_equal(op,"history_read") {
        let field=cw_arg(request,2,2);let at=cw_arg(request,3,1);let limit=cw_arg(request,4,1);if !field || !at || !limit || offset<1 || offset>j_count(cw_history) || db_word(at)<0 || db_word(limit)<1 || db_word(limit)>16384 {return cw_fail("Invalid history slice.");}
        let text=cw_history_field(j_at(cw_history,offset-1),db_word(field));if !text {return cw_fail("Unknown history field.");}let n=h_len(text);if db_word(at)>=n {return db_blob("",0);}n=n-db_word(at);if n>db_word(limit) {n=db_word(limit);}return db_blob(text+db_word(at),n);
    }
    let limit=cw_arg(request,2,1);if !limit || db_word(limit)<1 || db_word(limit)>128 {return cw_fail("History page size must be 1..128.");}let result=db_list();let i=offset;
    while i<j_count(cw_history) && db_count(result)<db_word(limit) {let item=j_at(cw_history,i);let row=db_list();db_add(row,db_int(i+1));let values=db_list();let keys=h_args("role","content","source","observation",0,0);let k=0;while k<4 {let text=cw_history_field(item,h_at(keys,k));let n=h_len(text);if n>4096 {n=4096;while n>0 && (load8(text+n)&192)==128 {n=n-1;}}db_add(values,db_text(h_slice(text,n)));k=k+1;}db_add(row,values);db_add(result,row);i=i+1;}return result;
}
fn cw_dispatch(request) {
    if db_kind(request)!=5 || db_count(request)<1 || db_kind(db_at(request,0))!=2 {return cw_fail("Invalid database request.");}let op=db_word(db_at(request,0));let expected=0;
    if h_equal(op,"begin") || h_equal(op,"commit") || h_equal(op,"rollback") || h_equal(op,"tables") {expected=1;}
    else if h_equal(op,"columns") {expected=2;}
    else if h_equal(op,"create") || h_equal(op,"insert") || h_equal(op,"get") || h_equal(op,"delete") || h_equal(op,"drop_column") || h_equal(op,"history") {expected=3;}
    else if h_equal(op,"update") || h_equal(op,"scan") || h_equal(op,"rename_column") {expected=4;}
    else if h_equal(op,"history_read") {expected=5;}else if h_equal(op,"add_column") {expected=6;}
    if !expected || db_count(request)!=expected {return cw_fail("Unknown operation or incorrect argument count.");}
    if h_equal(op,"history") || h_equal(op,"history_read") {return cw_history_request(request,op);}
    if !cw_open() {return 0;}store64(cw_db+32,"");
    if h_equal(op,"begin") {if flexdb_begin(cw_db) {return db_int(1);}return 0;}
    if h_equal(op,"commit") {if flexdb_commit(cw_db) {return db_int(1);}return 0;}
    if h_equal(op,"rollback") {if flexdb_rollback(cw_db) {return db_int(1);}return 0;}
    if h_equal(op,"tables") {let result=db_list();let tables=load64(cw_db+40);let i=0;while i<fd_size(tables) {db_add(result,db_text(load64(fd_at(tables,i)+8)));i=i+1;}return result;}
    if h_equal(op,"create") && db_kind(db_at(request,1))==2 && h_starts(db_word(db_at(request,1)),"collie_") {return cw_fail("The collie_ table prefix is reserved for runtime state.");}
    if h_equal(op,"create") {let name=cw_arg(request,1,2);if !cw_name(name) {return cw_fail("Invalid table name.");}let schema=cw_schema(db_at(request,2));if !schema || !flexdb_create(cw_db,db_word(name),schema) {return 0;}return db_int(1);}
    if h_equal(op,"add_column") || h_equal(op,"rename_column") || h_equal(op,"drop_column") {if db_kind(db_at(request,1))==2 && h_starts(db_word(db_at(request,1)),"collie_"){return cw_fail("Runtime-owned collie_ tables are read-only.");}return cw_alter(request,op);}
    if db_kind(db_at(request,1))==2 && h_starts(db_word(db_at(request,1)),"collie_") && !(h_equal(op,"columns") || h_equal(op,"get") || h_equal(op,"scan")) {return cw_fail("Runtime-owned collie_ tables are read-only. Use the worker/state functions.");}
    let t=cw_table(request);if !t {return 0;}
    if h_equal(op,"columns") {let result=db_list();let columns=load64(t+16);let i=0;while i<fd_size(columns) {let c=fd_at(columns,i);let v=db_list();db_add(v,db_text(load64(c)));db_add(v,db_int(load64(c+8)));db_add(v,db_int(load64(c+16)));db_add(result,v);i=i+1;}return result;}
    if h_equal(op,"insert") {let values=cw_values(db_at(request,2));if !values {return 0;}let id=flexdb_insert(t,values);if !id {return 0;}return db_int(id);}
    let id=cw_arg(request,2,1);if !id || db_word(id)<0 {return cw_fail("Invalid row ID.");}let number=db_word(id);
    if h_equal(op,"get") {return cw_row(flexdb_get(t,number));}
    if h_equal(op,"delete") {if flexdb_delete(t,number) {return db_int(1);}return 0;}
    if h_equal(op,"update") {let values=cw_values(db_at(request,3));if !values || !flexdb_update(t,number,values) {return 0;}return db_int(1);}
    let limit=cw_arg(request,3,1);if !limit || db_word(limit)<1 || db_word(limit)>128 {return cw_fail("Scan page size must be 1..128.");}
    let result=db_list();let rows=load64(t+24);let i=0;while i<fd_size(rows) && db_count(result)<db_word(limit) {let row=fd_table_row(t,i);if !row {return 0;}if flexdb_rowid(row)>number && load64(row+8) {let value=cw_row(row);if !value {return 0;}db_add(result,value);}i=i+1;}return result;
}
fn cw_reply(payload,n) {
    cw_problem=0;let request=db_decode(payload,n);let result=0;if request {result=cw_dispatch(request);}else {cw_fail("Invalid database value encoding.");}
    if !result && !cw_problem && cw_db {cw_problem=flexdb_error(cw_db);}if !result && (!cw_problem || !h_len(cw_problem)) {cw_problem="Database operation failed.";}
    let reply=db_list();let error=db_null();if cw_problem {error=db_text(cw_problem);result=db_null();}db_add(reply,error);db_add(reply,result);n=db_encode(reply);
    if !n {reply=db_list();db_add(reply,db_text("Database response exceeds 64 KiB; request a smaller page."));db_add(reply,db_null());n=db_encode(reply);}return n;
}
fn cw_close() {if cw_db {if load64(cw_db+48)==1 {flexdb_rollback(cw_db);}close_flexdb(cw_db);cw_db=0;}return 0;}
fn cw_state_root() {let base=h_getenv("XDG_STATE_HOME");if !base || !h_len(base) {let home=h_getenv("HOME");h_assert(home,"HOME or --workspace is required");base=h_join(home,".local/state");}return h_join(base,"collie/workspaces");}
fn cw_prepare(config) {
    let path=c_string(config,"workspace_file");if path && h_len(path) {return path;}let random=h_take(8);h_assert(syscall(318,random,8,0,0,0,0)==8,"workspace ID generation failed");path=h_join(cw_state_root(),h_cat(h_hex(random,8),".flexdb"));j_set(config,"workspace_file",j_string(path));return path;
}
fn cw_archive_path(config) {return h_cat(j_s(config,"workspace_file"),".history.json");}
fn cw_archive_load(config) {
    let text=c_read(cw_archive_path(config),16777216);let key="items";
    if !text && h_exists(cw_archive_path(config)) {h_die("Workspace history is unreadable or exceeds 16 MiB.");}
    if !text {let file=c_string(config,"history_file");if file && h_len(file) {text=c_read(file,16777216);}}
    if !text {return j_array();}let data=c_json(text);let items=j_get(data,key);h_assert(items && j_kind(items)==3 && j_count(items)<=4095,"invalid workspace history");return items;
}
fn cw_archive_save(config,items) {
    let data=j_object();j_set(data,"items",items);let text=j_dump(data);h_assert(h_len(text)<=16777216 && j_count(items)<=4095,"workspace history limit reached");let file=cw_archive_path(config);h_mkdir(h_dir(file));let temp=h_cat3(file,".tmp-",h_int(syscall(39,0,0,0,0,0,0)));let fd=syscall(2,temp,0xa0241,384,0,0,0);h_assert(fd>=0,"cannot save workspace history");
    let ok=syscall(91,fd,384,0,0,0,0)==0 && h_write(fd,text,h_len(text))==h_len(text) && syscall(74,fd,0,0,0,0,0)==0;h_close(fd);h_assert(ok && syscall(82,temp,file,0,0,0,0)==0,"cannot save workspace history");return 0;
}
