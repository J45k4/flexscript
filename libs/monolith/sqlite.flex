import "support.flex";
global db_handle=0;
global db_seen_version=0;
global db_library=0;
global db_prepare_ptr=0;
global db_step_ptr=0;
global db_finalize_ptr=0;
global db_text_ptr=0;
global db_int_ptr=0;
global db_column_text_ptr=0;
global db_column_int_ptr=0;
global db_error_ptr=0;
global db_changes_ptr=0;
fn db_symbol(name) {let p=ffi_symbol(db_library,name);m_assert(p,m_cat("missing SQLite symbol: ",name));return p;}
fn db_error() {return ffi_call(db_error_ptr,db_handle,0,0,0,0,0);}
fn db_prepare(sql) {
    let result=m_take(8);store64(result,0);
    m_assert(ffi_call_i32(db_prepare_ptr,db_handle,sql,-1,result,0,0)==0,db_error());return load64(result);
}
fn db_text(stmt,index,text) {m_assert(ffi_call_i32(db_text_ptr,stmt,index,text,m_len(text),0,0)==0,db_error());return 0;}
fn db_int(stmt,index,value) {m_assert(ffi_call_i32(db_int_ptr,stmt,index,value,0,0,0)==0,db_error());return 0;}
fn db_step(stmt) {let n=ffi_call_i32(db_step_ptr,stmt,0,0,0,0,0);m_assert(n==100 || n==101,db_error());return n==100;}
fn db_finish(stmt) {m_assert(ffi_call_i32(db_finalize_ptr,stmt,0,0,0,0,0)==0,db_error());return 0;}
fn db_column_text(stmt,index) {let p=ffi_call(db_column_text_ptr,stmt,index,0,0,0,0);return m_slice(p,m_len(p));}
fn db_column_int(stmt,index) {return ffi_call(db_column_int_ptr,stmt,index,0,0,0,0);}
fn db_exec(sql) {let stmt=db_prepare(sql);db_step(stmt);db_finish(stmt);return 0;}
fn db_changed() {return ffi_call_i32(db_changes_ptr,db_handle,0,0,0,0,0);}
fn db_connect(path) {
    db_library=ffi_open("libsqlite3.so.0");m_assert(db_library,"install libsqlite3.so.0");
    db_prepare_ptr=db_symbol("sqlite3_prepare_v2");db_step_ptr=db_symbol("sqlite3_step");db_finalize_ptr=db_symbol("sqlite3_finalize");
    db_text_ptr=db_symbol("sqlite3_bind_text");db_int_ptr=db_symbol("sqlite3_bind_int64");
    db_column_text_ptr=db_symbol("sqlite3_column_text");db_column_int_ptr=db_symbol("sqlite3_column_int64");
    db_error_ptr=db_symbol("sqlite3_errmsg");db_changes_ptr=db_symbol("sqlite3_changes");
    let slot=m_take(8);store64(slot,0);let status=ffi_call_i32(db_symbol("sqlite3_open_v2"),path,slot,6,0,0,0);db_handle=load64(slot);
    m_assert(status==0,"cannot open SQLite database");
    ffi_call_i32(db_symbol("sqlite3_busy_timeout"),db_handle,2000,0,0,0,0);
    db_exec("PRAGMA journal_mode=WAL");db_exec("PRAGMA foreign_keys=ON");return 0;
}

// Optional persistence helpers. Applications choose transaction boundaries.
fn db_transaction(code) {if code==200 {db_exec("COMMIT");}else {db_exec("ROLLBACK");}return code;}
fn db_data_version() {let stmt=db_prepare("PRAGMA data_version");db_step(stmt);let version=db_column_int(stmt,0);db_finish(stmt);return version;}
fn db_poll() {let next=db_data_version();let changed=next!=db_seen_version;db_seen_version=next;return changed;}
fn db_schema(name,definition) {
    db_exec("BEGIN IMMEDIATE");
    db_exec("CREATE TABLE IF NOT EXISTS _monolith_schema (name TEXT PRIMARY KEY, definition TEXT NOT NULL)");
    let stmt=db_prepare("SELECT definition FROM _monolith_schema WHERE name=?1");db_text(stmt,1,name);
    let known=db_step(stmt);let previous=0;if known {previous=db_column_text(stmt,0);}db_finish(stmt);
    if known {m_assert(m_eq(previous,definition),"schema changed: an explicit migration is required");}
    else {
        stmt=db_prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?1");db_text(stmt,1,name);let exists=db_step(stmt);db_finish(stmt);
        m_assert(!exists,"refusing to adopt an existing table without schema metadata");db_exec(definition);
        stmt=db_prepare("INSERT INTO _monolith_schema (name,definition) VALUES (?1,?2)");db_text(stmt,1,name);db_text(stmt,2,definition);db_step(stmt);db_finish(stmt);
    }
    db_exec("COMMIT");db_seen_version=db_data_version();return 0;
}
