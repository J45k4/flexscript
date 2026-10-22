// Durable workers are IDs, so ordinary typed lists and state_set can hold them.
fn worker_start(title,task){let r=db_request("worker_start");db_add(r,db_text(title));db_add(r,db_text(task));return db_word(db_rpc(r));}
fn worker_list(){return db_rpc(db_request("worker_list"));}
fn worker_get(id){let r=db_request("worker_get");db_add(r,db_int(id));return db_rpc(r);}
fn worker_status(worker){return db_word(db_cell(worker,2));}
fn worker_result(worker){return db_cell(worker,3);}
fn worker_messages(id,after,limit){let r=db_request("worker_messages");db_add(r,db_int(id));db_add(r,db_int(after));db_add(r,db_int(limit));return db_rpc(r);}
fn worker_send(id,text){let r=db_request("worker_send");db_add(r,db_int(id));db_add(r,db_text(text));return db_word(db_rpc(r));}
fn worker_cancel(id){let r=db_request("worker_cancel");db_add(r,db_int(id));return db_word(db_rpc(r));}
fn worker_equal(a,b){let i=0;while load8(a+i)==load8(b+i){if !load8(a+i){return 1;}i=i+1;}return 0;}
fn worker_await(id){let worker=worker_get(id);while worker {let s=worker_status(worker);if worker_equal(s,"done") || worker_equal(s,"failed") || worker_equal(s,"cancelled") || worker_equal(s,"paused"){return worker;}syscall(10001,id,0,0,0,0,0);worker=worker_get(id);}return 0;}
fn state_get(name){let r=db_request("state_get");db_add(r,db_text(name));return db_rpc(r);}
fn state_set(name,value){let r=db_request("state_set");db_add(r,db_text(name));db_add(r,value);return db_word(db_rpc(r));}
