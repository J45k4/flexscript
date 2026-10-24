// Preloaded only in an installed background ISO-DEP callback, not an agent turn.
// card_command returns [bytes blob, total integer, next offset or-1].
fn card_command(offset,limit){let r=db_request("card_command");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn card_state(){return db_rpc(db_request("card_state"));}
fn card_reply_begin(total){let r=db_request("card_reply_begin");db_add(r,db_int(total));return db_rpc(r);}
fn card_reply_write(offset,bytes){let r=db_request("card_reply_write");db_add(r,db_int(offset));db_add(r,bytes);return db_rpc(r);}
fn card_commit(state){let r=db_request("card_commit");db_add(r,state);return db_rpc(r);}
fn card_reply(bytes,state){if !card_reply_begin(db_bytes(bytes)){return 0;}if !card_reply_write(0,bytes){return 0;}return card_commit(state);}
