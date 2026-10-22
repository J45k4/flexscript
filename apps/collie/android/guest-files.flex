// App-private filesystem capability. Paths are relative to this session's root.
fn fs_read(path,offset,limit){let r=db_request("fs_read");db_add(r,db_text(path));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn fs_write(path,value){let r=db_request("fs_write");db_add(r,db_text(path));db_add(r,value);return db_word(db_rpc(r));}
fn fs_list(path){let r=db_request("fs_list");db_add(r,db_text(path));return db_rpc(r);}
fn fs_mkdir(path){let r=db_request("fs_mkdir");db_add(r,db_text(path));return db_word(db_rpc(r));}
// Bounded text HTTPS GET through Android TLS, with no model credentials/cookies.
fn http_get(url){let r=db_request("http_get");db_add(r,db_text(url));return db_rpc(r);}
fn http_status(response){return db_word(db_at(response,0));}
fn http_body(response){return db_at(response,1);}
fn http_url(response){return db_at(response,2);}
fn http_truncated(response){return db_word(db_at(response,3));}
fn view_file(path){return view_file_range(path,0,16384);}
fn view_file_range(path,offset,limit){let r=db_request("view_file");db_add(r,db_text(path));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_word(db_rpc(r));}
fn view_image(path){let r=db_request("view_image");db_add(r,db_text(path));return db_word(db_rpc(r));}
