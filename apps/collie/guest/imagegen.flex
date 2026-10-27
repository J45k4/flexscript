// Model-tool requests suspend the existing VM; image bytes stay in the host.
fn imagen(prompt,path){let r=db_request("agent_imagegen");db_add(r,db_text(prompt));db_add(r,db_text(path));let ticket=db_rpc(r);if !ticket{return 0;}let id=db_word(ticket);syscall(10001,-4,0,0,0,0,0);r=db_request("agent_answer");db_add(r,db_int(id));return db_rpc(r);}
