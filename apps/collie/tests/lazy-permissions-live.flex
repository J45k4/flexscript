// Guest programs from the original real-view permission scenarios.
fn nested(){let p=alloc(8);store64(p,77);fs_write("once.txt",db_text("initial"));let v=fs_read("once.txt",0,100);if !v{return 1;}db_io(0,1,db_word(v),db_bytes(v));return load64(p)-77;}fn lazy_live_write_read(){return nested();}
fn lazy_live_read(){let v=fs_read("once.txt",0,100);db_io(0,1,db_word(v),db_bytes(v));return 0;}
fn lazy_live_deny(){let r=fs_write("denied.txt",db_text("no"));let e=db_error();db_io(0,1,e,db_len(e));return r;}
fn lazy_live_cancel(){return fs_write("cancelled.txt",db_text("no"));}
fn lazy_live_coordinator(){let a=worker_start("One","List files");let b=worker_start("Two","List files");worker_await(a);worker_await(b);return 0;}
fn lazy_live_reader(){let v=fs_list("/");if !v{return 1;}return 0;}
fn lazy_live_background(){return worker_start("Background","Write a file")-1;}
fn lazy_live_background_write(){return fs_write("old-conversation.txt",db_text("no"));}
