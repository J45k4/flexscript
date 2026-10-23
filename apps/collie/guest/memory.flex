// Read-only recall across saved conversations. No host paths enter the VM.
fn memory_search(query,session_after,message_after,limit){let r=db_request("memory_search");db_add(r,db_text(query));db_add(r,db_text(session_after));db_add(r,db_int(message_after));db_add(r,db_int(limit));return db_rpc(r);}
fn memory_history(session,after,limit){let r=db_request("memory_history");db_add(r,db_text(session));db_add(r,db_int(after));db_add(r,db_int(limit));return db_rpc(r);}
fn memory_read(session,id,field,offset,limit){let r=db_request("memory_read");db_add(r,db_text(session));db_add(r,db_int(id));db_add(r,db_text(field));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
