// Desired schemas are mapped by name. Removal needs an explicit drop rule.
// Sources/drops are vectors of names; a source alias is used only on first open.
fn fd_schema_map(t,columns,sources,drops) {
    let db=load64(t);let old=load64(t+16);let map=fd_vec(db);let used=fd_vec(db);let i=0;
    while i<fd_size(old) {fd_push(db,used,0);i=i+1;}i=0;
    while i<fd_size(columns) {
        let name=load64(fd_at(columns,i));let source=fd_at(sources,i);let index=flexdb_column_index(t,name);
        if source && !fd_same(name,source) {
            let alias=flexdb_column_index(t,source);
            if index>=0 && alias>=0 {fd_error(db,"schema rename is ambiguous: both field names exist");return 0;}
            if index<0 {index=alias;}
        }
        if index>=0 {if fd_at(used,index) {fd_error(db,"schema maps one old field more than once");return 0;}fd_put(used,index,1);}
        fd_push(db,map,index);i=i+1;
    }
    i=0;while i<fd_size(old) {
        if !fd_at(used,i) {let name=load64(fd_at(old,i));let j=0;let allowed=0;while j<fd_size(drops) {if fd_same(name,fd_at(drops,j)) {allowed=1;}j=j+1;}
            if !allowed {fd_error(db,"schema would remove a field; declare drop FIELD explicitly");return 0;}}
        i=i+1;
    }return map;
}
// Replacement covers every existing row and tombstone, preserving IDs and next ID.
fn fd_schema_rows_valid(t,columns,rows) {
    let db=load64(t);let old=load64(t+24);if fd_size(rows)!=fd_size(old) {return fd_error(db,"schema replacement must preserve all row IDs");}
    let i=0;while i<fd_size(rows) {
        let row=fd_at(rows,i);let before=fd_table_row(t,i);
        if !row || !before || load64(row)!=load64(before) || (!load64(row+8))!=(!load64(before+8)) {return fd_error(db,"schema replacement must preserve row IDs and deletions");}
        if load64(row+8) {let values=load64(row+8);if values!=fd_size(columns) {return fd_error(db,"row does not match column count");}let j=0;while j<values {let v=load64(row+16+j*8);let c=fd_at(columns,j);if !v {return fd_error(db,"invalid value");}let kind=load64(v);if (kind==0 && !load64(c+16)) || (kind!=0 && kind!=load64(c+8)) || ((kind==2 || kind==3) && (load64(v+16)<0 || load64(v+16)>1048576)) {return fd_error(db,"row value does not match column type/nullability");}j=j+1;}}
        i=i+1;
    }return 1;
}
fn fd_log_columns(db,columns) {
    fd_log_word(db,fd_size(columns));let i=0;while i<fd_size(columns) {let c=fd_at(columns,i);let name=load64(c);fd_log_word(db,fd_len(name));fd_log_bytes(db,name,fd_len(name));fd_log_word(db,load64(c+8));fd_log_word(db,load64(c+16));i=i+1;}return 1;
}
fn fd_log_value(db,v) {
    let kind=load64(v);fd_log_word(db,kind);if kind==2 || kind==3 {fd_log_word(db,load64(v+16));fd_log_bytes(db,load64(v+8),load64(v+16));}else {fd_log_word(db,load64(v+8));}return 1;
}
fn fd_replace_schema(t,columns,rows) {
    if !fd_table_ready(t) || !fd_writing(load64(t)) {return 0;}let db=load64(t);
    if !fd_schema_rows_valid(t,columns,rows) {return 0;}
    let n=32;let i=0;while i<fd_size(columns) {n=n+24+fd_len(load64(fd_at(columns,i)));i=i+1;}i=0;
    while i<fd_size(rows) {let row=fd_at(rows,i);n=n+16;let j=0;while j<load64(row+8) {let v=flexdb_cell(row,j);n=n+16;if load64(v)==2 || load64(v)==3 {n=n+load64(v+16);}j=j+1;}i=i+1;}
    if !fd_command(db,n) {return 0;}fd_log_word(db,4);fd_log_word(db,fd_table_id(t));fd_log_columns(db,columns);fd_log_word(db,fd_size(rows));i=0;
    while i<fd_size(rows) {let row=fd_at(rows,i);fd_log_word(db,load64(row));fd_log_word(db,load64(row+8));let j=0;while j<load64(row+8) {fd_log_value(db,flexdb_cell(row,j));j=j+1;}i=i+1;}
    fd_cp_cache_clear(t);fd_auto_clear(t);store64(t+16,columns);store64(t+24,rows);return fd_logged(db);
}
fn fd_replay_schema(db,t,r) {
    let columns=fd_vec(db);let count=fd_read_word(r);if count<1 || count>64 {return 0;}let i=0;
    while i<count && load64(r+24) {let name=fd_read_name(db,r);let kind=fd_read_word(r);let nullable=fd_read_word(r);if flexdb_column(db,columns,name,kind,nullable)<0 {return 0;}i=i+1;}
    let rows=fd_vec(db);count=fd_read_word(r);if count!=fd_size(load64(t+24)) {return 0;}i=0;
    while i<count && load64(r+24) {
        let id=fd_read_word(r);let cells=fd_read_word(r);if cells!=0 && cells!=fd_size(columns) {return 0;}let values=fd_decode_values(r,cells,0,0);
        if load64(r+24) {fd_push(db,rows,fd_row(db,id,values));}i=i+1;
    }
    if !load64(r+24) || !fd_schema_rows_valid(t,columns,rows) {return 0;}fd_cp_cache_clear(t);fd_auto_clear(t);store64(t+16,columns);store64(t+24,rows);return 1;
}
