import "../adapters/workspace.flex";
import "../../../lib/net.flex";
// Durable worker registry, message journal and named VM values. This trusted
// broker shares the workspace DB; generated code can read but not mutate these
// runtime-owned tables through the general table API.
global ag_owner=0;
global ag_key=0;
global ag_sequence=0;
fn ag_n(object,key){let v=j_get(object,key);if v{return j_value(v);}return 0;}
fn ag_table(name){return flexdb_table(cw_db,name);}
fn ag_text(row,col){return flexdb_word(flexdb_cell(row,col));}
fn ag_number(row,col){return flexdb_word(flexdb_cell(row,col));}
fn ag_terminal(status){return h_equal(status,"done") || h_equal(status,"failed") || h_equal(status,"cancelled") || h_equal(status,"paused");}
fn ag_reserved(name){return h_starts(name,"collie_");}
fn ag_schema_valid(table,names,kinds){
    let columns=load64(table+16);if fd_size(columns)!=h_count(names){return cw_fail("Reserved worker table has an incompatible schema.");}let i=0;
    while i<h_count(names){let c=fd_at(columns,i);if !h_equal(load64(c),h_at(names,i)) || load64(c+8)!=load8(kinds+i)-48 || load64(c+16){return cw_fail("Reserved worker table has an incompatible schema.");}i=i+1;}return 1;
}
fn ag_schema(name,names,kinds){
    let table=ag_table(name);if table{return ag_schema_valid(table,names,kinds);}let s=flexdb_schema(cw_db);let i=0;
    while i<h_count(names){if flexdb_column(cw_db,s,h_at(names,i),load8(kinds+i)-48,0)<0 {return 0;}i=i+1;}
    return flexdb_create(cw_db,name,s)!=0;
}
fn ag_worker_names(){let a=h_args("title","task","status","result","error","revision");h_add(a,"request_key");h_add(a,"updated");return a;}
fn ag_open(){
    if !cw_open(){return 0;}
    if ag_table("collie_workers") && ag_table("collie_messages") && ag_table("collie_state"){
        return ag_schema_valid(ag_table("collie_workers"),ag_worker_names(),"22222121")
            && ag_schema_valid(ag_table("collie_messages"),h_args("worker","role","content","kind","key","revision"),"122221")
            && ag_schema_valid(ag_table("collie_state"),h_args("owner","name","value",0,0,0),"123");
    }
    if load64(cw_db+48)==1 {return cw_fail("Worker storage cannot be initialized inside a user transaction.");}
    if !flexdb_begin(cw_db){return 0;}
    let ok=ag_schema("collie_workers",ag_worker_names(),"22222121")
        && ag_schema("collie_messages",h_args("worker","role","content","kind","key","revision"),"122221")
        && ag_schema("collie_state",h_args("owner","name","value",0,0,0),"123");
    if !ok {flexdb_rollback(cw_db);return cw_fail("Cannot initialize worker storage.");}return flexdb_commit(cw_db);
}
fn ag_values(row){let v=flexdb_values(cw_db);let i=0;while i<load64(row+8){flexdb_add(cw_db,v,flexdb_cell(row,i));i=i+1;}return v;}
fn ag_replace(v,i,value){fd_put(v,i,value);return v;}
fn ag_find(table,col,text,owner){let rows=load64(table+24);let i=0;while i<fd_size(rows){let r=fd_table_row(table,i);if r && load64(r+8) && h_equal(ag_text(r,col),text) && (owner<0 || ag_number(r,0)==owner){return r;}i=i+1;}return 0;}
fn ag_message(id,role,text,kind,key,revision){
    let t=ag_table("collie_messages");let old=ag_find(t,4,key,-1);if old{return flexdb_rowid(old);}
    let v=flexdb_values(cw_db);flexdb_add(cw_db,v,flexdb_int(cw_db,id));flexdb_add(cw_db,v,flexdb_text(cw_db,role));flexdb_add(cw_db,v,flexdb_text(cw_db,text));flexdb_add(cw_db,v,flexdb_text(cw_db,kind));flexdb_add(cw_db,v,flexdb_text(cw_db,key));flexdb_add(cw_db,v,flexdb_int(cw_db,revision));return flexdb_insert(t,v);
}
fn ag_clip(text,limit){let n=h_len(text);if n<=limit{return text;}n=limit;while n>0 && (load8(text+n)&192)==128{n=n-1;}return h_slice(text,n);}
fn ag_summary(row){let out=db_list();db_add(out,db_int(flexdb_rowid(row)));let values=db_list();let i=0;while i<8{let value=flexdb_cell(row,i);if flexdb_kind(value)==2{let limit=128;if i==0{limit=160;}db_add(values,db_text(ag_clip(flexdb_word(value),limit)));}else{db_add(values,db_int(flexdb_word(value)));}i=i+1;}db_add(out,values);return out;}
fn ag_update(id,status,result,error){
    let t=ag_table("collie_workers");let row=flexdb_get(t,id);if !row{return cw_fail("Unknown worker ID.");}
    let v=ag_values(row);ag_replace(v,2,flexdb_text(cw_db,status));if result {ag_replace(v,3,flexdb_text(cw_db,ag_clip(result,32768)));}if error {ag_replace(v,4,flexdb_text(cw_db,ag_clip(error,1024)));}ag_replace(v,7,flexdb_int(cw_db,net_now()));return flexdb_update(t,id,v);
}
fn ag_active(){let t=ag_table("collie_workers");let rows=load64(t+24);let n=0;let i=0;while i<fd_size(rows){let row=fd_table_row(t,i);if row && load64(row+8) && !ag_terminal(ag_text(row,2)){n=n+1;}i=i+1;}return n;}
fn ag_create(title,task,key){
    let t=ag_table("collie_workers");let old=ag_find(t,6,key,-1);
    if old {if !h_equal(ag_text(old,0),title) || !h_equal(ag_text(old,1),task){return cw_fail("Worker request key was reused with different input.");}return db_int(flexdb_rowid(old));}
    if fd_size(load64(t+24))>=64{return cw_fail("This workspace already has 64 workers.");}
    if ag_active()>=8{return cw_fail("At most eight active workers are allowed.");}
    let v=flexdb_values(cw_db);flexdb_add(cw_db,v,flexdb_text(cw_db,title));flexdb_add(cw_db,v,flexdb_text(cw_db,task));flexdb_add(cw_db,v,flexdb_text(cw_db,"queued"));flexdb_add(cw_db,v,flexdb_text(cw_db,""));flexdb_add(cw_db,v,flexdb_text(cw_db,""));flexdb_add(cw_db,v,flexdb_int(cw_db,1));flexdb_add(cw_db,v,flexdb_text(cw_db,key));flexdb_add(cw_db,v,flexdb_int(cw_db,net_now()));
    let id=flexdb_insert(t,v);if !id || !ag_message(id,"user",task,"message",h_cat(key,":task"),1){return 0;}return db_int(id);
}
fn ag_dispatch(r){
    if !ag_open(){return 0;}let op=db_word(db_at(r,0));
    if h_equal(op,"worker_list"){if db_count(r)!=1{return cw_fail("worker_list takes no arguments.");}let out=db_list();let t=ag_table("collie_workers");let rows=load64(t+24);let i=0;while i<fd_size(rows){db_add(out,ag_summary(fd_table_row(t,i)));i=i+1;}return out;}
    if h_equal(op,"worker_start"){
        if ag_owner {return cw_fail("Only the main conversation can start workers.");}
        if db_count(r)!=3 || db_kind(db_at(r,1))!=2 || db_kind(db_at(r,2))!=2 || db_bytes(db_at(r,1))<1 || db_bytes(db_at(r,1))>160 || db_bytes(db_at(r,2))<1 || db_bytes(db_at(r,2))>16384{return cw_fail("worker_start requires a title (1..160 bytes) and task (1..16384 bytes).");}
        ag_sequence=ag_sequence+1;let key=h_cat3(ag_key,":start:",h_int(ag_sequence));return ag_create(db_word(db_at(r,1)),db_word(db_at(r,2)),key);
    }
    if h_starts(op,"state_"){
        let name=db_at(r,1);if db_kind(name)!=2 || db_bytes(name)<1 || db_bytes(name)>160{return cw_fail("State names must contain 1..160 bytes.");}
        let t=ag_table("collie_state");let row=ag_find(t,1,db_word(name),ag_owner);
        if h_equal(op,"state_get") && db_count(r)==2{if !row{return db_null();}let blob=flexdb_cell(row,2);return db_decode(flexdb_blob_data(blob),flexdb_bytes(blob));}
        if h_equal(op,"state_set") && db_count(r)==3{let n=db_encode(db_at(r,2));if n<1 || n>32768{return cw_fail("A persistent value must encode to at most 32 KiB.");}let v=flexdb_values(cw_db);flexdb_add(cw_db,v,flexdb_int(cw_db,ag_owner));flexdb_add(cw_db,v,flexdb_text(cw_db,db_word(name)));flexdb_add(cw_db,v,flexdb_blob(cw_db,db_wire,n));let ok=0;if row{ok=flexdb_update(t,flexdb_rowid(row),v);}else{if fd_size(load64(t+24))>=512{return cw_fail("Persistent state is limited to 512 named values per workspace.");}ok=flexdb_insert(t,v);}if ok{return db_int(1);}return 0;}
        return cw_fail("Invalid persistent state operation.");
    }
    let id=db_at(r,1);if db_kind(id)!=1 || db_word(id)<1{return cw_fail("A worker ID is required.");}let t=ag_table("collie_workers");let row=flexdb_get(t,db_word(id));if !row{return cw_fail("Unknown worker ID.");}
    if h_equal(op,"worker_get") && db_count(r)==2{return cw_row(row);}
    if h_equal(op,"worker_messages") && db_count(r)==4{
        let after=db_at(r,2);let limit=db_at(r,3);if db_kind(after)!=1 || db_word(after)<0 || db_kind(limit)!=1 || db_word(limit)<1 || db_word(limit)>64{return cw_fail("Message pages require after>=0 and limit 1..64.");}
        let out=db_list();let messages=ag_table("collie_messages");let rows=load64(messages+24);let i=0;let bytes=0;
        while i<fd_size(rows) && db_count(out)<db_word(limit){let message=fd_table_row(messages,i);if message && load64(message+8) && flexdb_rowid(message)>db_word(after) && ag_number(message,0)==db_word(id){let n=h_len(ag_text(message,2));if bytes+n>48000 {return out;}db_add(out,cw_row(message));bytes=bytes+n;}i=i+1;}return out;
    }
    if ag_owner{return cw_fail("Only the main conversation can manage workers.");}
    if h_equal(op,"worker_cancel") && db_count(r)==2{if ag_update(db_word(id),"cancelled",0,""){return db_int(1);}return 0;}
    if h_equal(op,"worker_send") && db_count(r)==3{
        let text=db_at(r,2);if db_kind(text)!=2 || db_bytes(text)<1 || db_bytes(text)>16384{return cw_fail("Worker messages must contain 1..16384 bytes.");}
        ag_sequence=ag_sequence+1;let key=h_cat3(ag_key,":send:",h_int(ag_sequence));let old=ag_find(ag_table("collie_messages"),4,key,-1);if old{if ag_number(old,0)!=db_word(id) || !h_equal(ag_text(old,2),db_word(text)){return cw_fail("Message request key was reused with different input.");}return db_int(1);}
        let revision=ag_number(row,5)+1;let v=ag_values(row);ag_replace(v,5,flexdb_int(cw_db,revision));let status=ag_text(row,2);if ag_terminal(status){if ag_active()>=8{return cw_fail("At most eight active workers are allowed.");}ag_replace(v,2,flexdb_text(cw_db,"queued"));}ag_replace(v,4,flexdb_text(cw_db,""));
        if !flexdb_update(t,db_word(id),v) || !ag_message(db_word(id),"user",db_word(text),"message",key,revision){return 0;}return db_int(1);
    }
    return cw_fail("Unknown worker operation or incorrect argument count.");
}
fn ag_rpc(r){
    if !ag_open(){return 0;}let writing=!(h_equal(db_word(db_at(r,0)),"worker_list") || h_equal(db_word(db_at(r,0)),"worker_get") || h_equal(db_word(db_at(r,0)),"worker_messages") || h_equal(db_word(db_at(r,0)),"state_get"));
    if writing && load64(cw_db+48)==1{return cw_fail("Commit or roll back the database transaction before managing workers or persistent state.");}
    if writing && !flexdb_begin(cw_db){return 0;}let result=ag_dispatch(r);
    if writing{if result{if !flexdb_commit(cw_db){return 0;}}else{flexdb_rollback(cw_db);}}return result;
}
fn ag_json_value(v){
    let k=db_kind(v);if k==0{return j_node(0,0);}if k==1{return j_int(db_word(v));}if k==2{return j_string(db_word(v));}let a=j_array();if k==5{let i=0;while i<db_count(v){j_push(a,ag_json_value(db_at(v,i)));i=i+1;}}return a;
}
// Trusted scheduler entry. It may claim/update jobs but never exposes model
// credentials, native file paths, or context reasoning in public DB messages.
fn ag_host(request){
    cw_config=j_need(request,"config");if !ag_open(){return c_error(cw_problem);}let action=j_s(request,"action");let id=ag_n(request,"id");let out=j_object();cw_problem=0;
    if h_equal(action,"list"){let r=db_request("worker_list");let v=ag_dispatch(r);j_set(out,"workers",ag_json_value(v));return out;}
    if h_equal(action,"messages"){let r=db_request("worker_messages");db_add(r,db_int(id));db_add(r,db_int(ag_n(request,"after")));db_add(r,db_int(64));let v=ag_dispatch(r);if !v{return c_error(cw_problem);}j_set(out,"messages",ag_json_value(v));return out;}
    if !flexdb_begin(cw_db){return c_error("Cannot begin worker update.");}let row=flexdb_get(ag_table("collie_workers"),id);let ok=0;
    if row{
        let status=ag_text(row,2);
        if h_equal(action,"claim") && h_equal(status,"queued"){ok=ag_update(id,"running",0,"");}
        else if h_equal(action,"pause") && (h_equal(status,"running") || h_equal(status,"waiting")){ok=ag_update(id,"paused",0,"App stopped. Resume this worker to continue.");}
        else if h_equal(action,"resume") && h_equal(status,"paused") && ag_active()<8{ok=ag_update(id,"queued",0,"");}
        else if h_equal(action,"cancel"){ok=ag_update(id,"cancelled",0,"");}
        else if h_equal(action,"append") && !h_equal(status,"cancelled"){
            let text=j_s(request,"text");if h_len(text)<=32768{ok=ag_message(id,j_s(request,"role"),text,j_s(request,"kind"),h_cat3(h_int(id),":",j_s(request,"key")),ag_number(row,5));}
        }
        else if h_equal(action,"finish") && !h_equal(status,"cancelled"){
            let next=j_s(request,"status");if ag_number(row,5)>ag_n(request,"revision"){next="queued";}
            if h_equal(next,"done") || h_equal(next,"failed") || h_equal(next,"paused") || h_equal(next,"queued"){ok=ag_update(id,next,j_s(request,"result"),j_s(request,"error"));}
        }
    }
    if !ok{flexdb_rollback(cw_db);j_set(out,"changed",j_bool(0));return out;}
    if !flexdb_commit(cw_db){return c_error("Cannot commit worker update.");}j_set(out,"changed",j_bool(1));return out;
}
