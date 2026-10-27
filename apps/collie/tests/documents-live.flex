// Original SAF VM assertions, parameterized with independently selected grants.
fn document_live_ticket(ticket){let g=state_get(ticket);db_io(0,1,db_word(g),db_bytes(g));return 0;}
fn document_live_deny(){if document_pick("denied",1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}
fn document_live_replay(grant){let again=document_pick("fixture-write",1);if !worker_equal(db_word(again),grant){return 1;}let h=document_tree_open(grant);if !h{return 2;}state_set("old-handle",h);return device_close(db_word(h))-1;}
fn document_live_readonly(readonly){let h=document_tree_open(readonly);if !h{return 1;}let t=db_word(h);if document_create(t,"root","forbidden.txt","text/plain"){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"read_only"){return 3;}if document_file_open(t,"root","w"){return 4;}if !worker_equal(db_word(db_at(device_error(),0)),"read_only"){return 5;}return device_close(t)-1;}
fn document_live_forget_other(other){return db_word(document_forget(other))-1;}
fn document_live_reopen(grant){let h=document_tree_open(grant);if !h{return 1;}return device_close(db_word(h))-1;}
fn document_live_forget_write(grant){return db_word(document_forget(grant))-1;}
fn document_live_forget_read(readonly){return db_word(document_forget(readonly))-1;}
fn document_live_cancelled(){if document_pick("cancelled",1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"cancelled"){return 2;}let p=document_trees(0,16);let d=db_at(device_field(p,"trees"),0);return db_word(document_forget(db_word(device_field(d,"id"))))-1;}
fn document_live_live_handle(grant){let h=document_tree_open(grant);if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}
fn document_live_restart(old,grant,folder){if device_info(old){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_handle"){return 2;}let h=document_tree_open(grant);if !h{return 3;}let d=document_info(db_word(h),"root");if !worker_equal(db_word(device_field(d,"name")),folder){return 4;}return device_close(db_word(h))-1;}
fn document_live_cleanup(){let p=document_trees(0,16);let rows=device_field(p,"trees");let i=0;while i<db_count(rows){if !document_forget(db_word(device_field(db_at(rows,i),"id"))){return 1;}i=i+1;}return 0;}
fn document_live_pick(ticket,writable){let g=document_pick(ticket,writable);if !g{return 1;}state_set(ticket,g);return 0;}
fn document_live_cancel(){if document_pick("cancelled",1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"cancelled"){return 2;}return 0;}
