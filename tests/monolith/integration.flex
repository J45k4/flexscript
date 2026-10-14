// End-to-end tests compile, launch, and exercise real native servers and SQLite.
import "../../scripts/lib/host.flex";
global mt_checks=0;
global mt_token=0;
global mt_database=0;
global mt_binary=0;
global mt_port=0;
global mt_source=0;
global mt_cwd=0;
fn mt_check(ok,message) {h_assert(ok,message);mt_checks=mt_checks+1;return 0;}
fn mt_request(port,request) {
    let fd=tcp_connect("127.0.0.1",h_int(port),2000);h_assert(fd>=0,net_message);let end=net_now()+4000;
    h_assert(tcp_write(fd,request,h_len(request),end),"request send failed");let b=h_buffer();let scratch=h_take(4096);
    while 1 {let n=tcp_read(fd,scratch,4096,end);if n<=0 {h_close(fd);return h_data(b);}h_append(b,scratch,n);}return 0;
}
fn mt_get(port,path) {return mt_request(port,h_cat3("GET ",path,h_cat3(" HTTP/1.1\r\nHost: 127.0.0.1:",h_int(port),"\r\n\r\n")));}
fn mt_status(response,code) {mt_check(h_starts(response,h_cat3("HTTP/1.1 ",h_int(code)," ")),h_cat("unexpected HTTP response: ",response));return 0;}
fn mt_body(response) {let i=h_find(response,"\r\n\r\n");h_assert(i>=0,"missing HTTP headers");return response+i+4;}
fn mt_extract_token(html) {
    let at=h_find(html,"name=\"monolith-token\" content=\"");h_assert(at>=0,"SSR action token missing");let p=html+at+h_len("name=\"monolith-token\" content=\"");return h_slice(p,32);
}
fn mt_command() {
    if mt_source {return h_args(mt_binary,"run",mt_source,h_int(mt_port),mt_database,0);}
    return h_args(mt_binary,h_int(mt_port),mt_database,0,0,0);
}
fn mt_start() {
    let p=h_spawn(mt_command(),"",mt_cwd);h_until(p,"Monolith Todo listening",5000);
    let html=mt_get(mt_port,"/");mt_status(html,200);mt_token=mt_extract_token(html);return p;
}
fn mt_stop(process) {h_stop(process);return 0;}
fn mt_form(port,form,token,extra) {
    let body=h_cat3("token=",token,h_cat("&",form));let b=h_buffer();h_text(b,h_cat3("POST /action HTTP/1.1\r\nHost: 127.0.0.1:",h_int(port),"\r\nContent-Type: application/x-www-form-urlencoded\r\nAccept: application/json\r\nContent-Length: "));
    h_text(b,h_int(h_len(body)));h_text(b,"\r\n");h_text(b,extra);h_text(b,"\r\n");h_text(b,body);return mt_request(port,h_data(b));
}
fn mt_action(form) {let response=mt_form(mt_port,form,mt_token,"");mt_status(response,200);return response;}
fn mt_event(fd) {
    let b=h_buffer();let scratch=h_take(4096);let end=net_now()+4000;
    while !h_has(h_data(b),"\n\n") {let n=tcp_read(fd,scratch,4096,end);h_assert(n>0,"missing realtime event");h_append(b,scratch,n);}return h_data(b);
}
fn mt_subscribe() {
    let fd=tcp_connect("127.0.0.1",h_int(mt_port),2000);h_assert(fd>=0,"SSE connect failed");let request=h_cat3("GET /events HTTP/1.1\r\nHost: 127.0.0.1:",h_int(mt_port),"\r\n\r\n");
    h_assert(tcp_write(fd,request,h_len(request),net_now()+2000),"SSE send failed");let event=mt_event(fd);mt_check(h_has(event,"text/event-stream") && h_has(event,"\"reset\":true"),"initial SSE snapshot missing");return fd;
}
fn mt_sql(path,sql,query) {
    let lib=ffi_open("libsqlite3.so.0");h_assert(lib,"SQLite test dependency missing");let slot=h_take(8);store64(slot,0);
    h_assert(ffi_call_i32(ffi_symbol(lib,"sqlite3_open"),path,slot,0,0,0,0)==0,"test DB open failed");let db=load64(slot);let out=h_take(8);store64(out,0);
    h_assert(ffi_call_i32(ffi_symbol(lib,"sqlite3_prepare_v2"),db,sql,-1,out,0,0)==0,"test SQL prepare failed");let stmt=load64(out);let code=ffi_call_i32(ffi_symbol(lib,"sqlite3_step"),stmt,0,0,0,0,0);
    h_assert(code==100 || code==101,"test SQL execute failed");let result=0;if query {h_assert(code==100,"test query missing row");result=ffi_call(ffi_symbol(lib,"sqlite3_column_int64"),stmt,0,0,0,0,0);}
    ffi_call_i32(ffi_symbol(lib,"sqlite3_finalize"),stmt,0,0,0,0,0);ffi_call_i32(ffi_symbol(lib,"sqlite3_close"),db,0,0,0,0,0);return result;
}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==2 || (argc==3 && h_equal(load64(argv+16),"--source")),"Usage: integration FLEX-COMPILER [--source]");let compiler=h_real(load64(argv+8));let temp=h_temp();mt_binary=h_join(temp,"todo");mt_database=h_join(temp,"todo.db");
    h_compile(compiler,"scripts/monolith-build.flex","build/monolith-builder");let builder=h_real("build/monolith-builder");let args=h_args(builder,"build","examples/monolith/external-schema.flex","--schema","examples/monolith/todo.mono","--compiler");h_add(args,compiler);h_add(args,"-o");h_add(args,mt_binary);h_ok(args);mt_check(h_exists(mt_binary),"native app output missing");
    if argc==3 {
        mt_source=h_real("examples/monolith/todo.flex");mt_cwd=temp;
        // Source apps carry their schema and bundle; no generated companion
        // or source-relative working directory should be needed.
        mt_check(h_exists(mt_source),"source app missing");
    }
    let before=h_read(mt_binary);let original_size=h_file_size;
    let bad=h_join(temp,"bad.mono");h_save(bad,"model Todo { id Int primary auto; title Mystery; }");
    let bad_args=h_args(builder,"build","examples/monolith/external-schema.flex","--schema",bad,"--compiler");h_add(bad_args,compiler);h_add(bad_args,"-o");h_add(bad_args,mt_binary);
    let failure=h_run(bad_args);mt_check(h_status(failure)==1 && h_has(h_err(failure),"schema line"),"invalid schema accepted");let after=h_read(mt_binary);mt_check(original_size==h_file_size && h_bytes(before,after,original_size),"failed build modified binary");
    let listener=tcp_listen("127.0.0.1","0",8);h_assert(listener>=0,"test port allocation failed");let address=h_take(16);let size=h_take(8);store64(size,16);syscall(51,listener,address,size,0,0,0);mt_port=(load8(address+2)<<8)|load8(address+3);h_close(listener);
    if mt_source {mt_binary=compiler;}
    let process=mt_start();
    if mt_source {
        let exe=h_take(4096);let n=syscall(89,h_cat3("/proc/",h_int(load64(process)),"/exe"),exe,4095,0,0,0);
        mt_check(n>0,"cannot inspect native handoff");store8(exe+n,0);
        mt_check(h_has(exe,"/app (deleted)"),"source app did not hand off to native server");
        mt_check(!h_exists(h_dir(exe)),"temporary application directory leaked");
        let idle=net_now()+5500;while net_now()<idle {h_pump(process,100);}
        mt_check(h_status(process)==-999,"source server stopped at the VM deadline");
    }
    let html=mt_get(mt_port,"/");mt_check(h_has(html,"0 remaining") && h_has(html,"<form") && h_has(html,"data-mkey=\"draft\""),"empty SSR page missing");
    mt_check(mt_sql(mt_database,"SELECT count(*) FROM _monolith_schema",1)==1,"schema metadata missing");
    mt_status(mt_get(mt_port,"/missing"),404);mt_status(mt_get(mt_port,"/client.js"),200);mt_status(mt_get(mt_port,"/style.css"),200);
    let head=mt_request(mt_port,h_cat3("HEAD / HTTP/1.1\r\nHost: 127.0.0.1:",h_int(mt_port),"\r\n\r\n"));mt_status(head,200);mt_check(h_len(mt_body(head))==0,"HEAD returned a body");
    let first=mt_subscribe();let second=mt_subscribe();mt_action("action=add&title=Ship+Monolith");let event=mt_event(first);let other=mt_event(second);
    mt_check(h_equal(event,other),"clients received different patches");mt_check(h_has(event,"\"op\":\"insert\"") && h_has(event,"todo-1") && h_has(event,"1 remaining"),"add diff missing");mt_check(!h_has(event,"\"key\":\"draft\"") && !h_has(event,"\"key\":\"todo-app\""),"add replaced local state or entire UI");
    mt_check(mt_sql(mt_database,"SELECT count(*) FROM Todo WHERE title='Ship Monolith' AND completed=0",1)==1,"task was not persisted");
    mt_action("action=toggle&id=1");event=mt_event(first);mt_event(second);mt_check(h_has(event,"\"op\":\"checked\"") && h_has(event,"\"value\":true") && !h_has(event,"\"op\":\"insert\""),"toggle was not a property patch");
    mt_check(mt_sql(mt_database,"SELECT completed FROM Todo WHERE id=1",1)==1,"completion did not persist");
    mt_action("action=add&title=%3Cscript%3Ealert%281%29%3C%2Fscript%3E%20%26%20%22hello%22");event=mt_event(first);mt_event(second);html=mt_get(mt_port,"/");
    mt_check(h_has(html,"&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;hello&quot;") && !h_has(html,"<script>alert"),"SSR did not escape task title");
    mt_check(h_has(event,"&lt;script&gt;") && !h_has(event,"<script>alert"),"patch did not escape task title");
    mt_action("action=add&title=Unicode+%E4%BD%A0%E5%A5%BD+%F0%9F%8C%B1");mt_event(first);mt_event(second);mt_check(h_has(mt_get(mt_port,"/"),"Unicode 你好 🌱"),"UTF-8 title lost");
    mt_action("action=add&title=x%27%29%3B+DROP+TABLE+Todo%3B--");mt_event(first);mt_event(second);mt_check(mt_sql(mt_database,"SELECT count(*) FROM Todo",1)==4,"SQL injection altered table");
    mt_status(mt_form(mt_port,"action=add&title=bad","incorrect",""),403);
    mt_status(mt_form(mt_port,"action=add&title=bad",mt_token,"Origin: https://evil.example\r\n"),403);
    mt_status(mt_form(mt_port,"action=add&title=",mt_token,""),422);
    mt_status(mt_form(mt_port,"action=add&title=++%09",mt_token,""),422);
    mt_status(mt_form(mt_port,"action=toggle&id=999999",mt_token,""),404);
    mt_status(mt_form(mt_port,"action=delete&id=999999",mt_token,""),404);
    mt_status(mt_form(mt_port,"action=unknown",mt_token,""),422);
    mt_status(mt_form(mt_port,"action=add&title=%00",mt_token,""),400);
    mt_status(mt_form(mt_port,"action=add&title=%GG",mt_token,""),400);
    mt_status(mt_form(mt_port,"action=add&title=%FF",mt_token,""),400);
    mt_status(mt_form(mt_port,"action=add&title=%ED%A0%80",mt_token,""),400);
    mt_status(mt_form(mt_port,"action=add&title=%C0%AF",mt_token,""),400);
    mt_status(mt_form(mt_port,"action=add&title=a&title=b",mt_token,""),400);
    let long=h_buffer();let i=0;while i<241 {h_text(long,"x");i=i+1;}mt_status(mt_form(mt_port,h_cat("action=add&title=",h_data(long)),mt_token,""),422);
    mt_check(mt_sql(mt_database,"SELECT count(*) FROM Todo",1)==4,"rejected actions changed DB");
    mt_status(mt_request(mt_port,"GET / HTTP/1.1\r\nHost: evil.example\r\n\r\n"),403);
    mt_status(mt_request(mt_port,h_cat3("GET / HTTP/1.1\r\nHost: 127.0.0.1:",h_int(mt_port),"\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n")),400);
    mt_status(mt_request(mt_port,h_cat3("POST /action HTTP/1.1\r\nHost: 127.0.0.1:",h_int(mt_port),"\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")),400);
    mt_status(mt_request(mt_port,h_cat3("POST /action HTTP/1.1\r\nHost: 127.0.0.1:",h_int(mt_port),"\r\nContent-Length: 999999\r\n\r\n")),413);
    mt_status(mt_request(mt_port,h_cat3("POST /action HTTP/1.1\r\nHost: 127.0.0.1:",h_int(mt_port),"\r\nContent-Length: 0\r\nContent-Type: application/json\r\n\r\n")),415);
    mt_status(mt_request(mt_port,h_cat3("PUT / HTTP/1.1\r\nHost: 127.0.0.1:",h_int(mt_port),"\r\n\r\n")),405);
    mt_sql(mt_database,"UPDATE Todo SET title='Changed externally' WHERE id=1",0);event=mt_event(first);mt_event(second);mt_check(h_has(event,"\"op\":\"text\"") && h_has(event,"Changed externally"),"external DB write did not invalidate UI");mt_check(h_has(event,"\"op\":\"label\"") && h_has(event,"Complete Changed externally"),"checkbox accessibility label did not update");
    mt_action("action=delete&id=2");event=mt_event(first);mt_event(second);mt_check(h_has(event,"\"op\":\"remove\"") && h_has(event,"todo-2"),"delete patch missing");h_close(first);h_close(second);
    let reconnected=mt_subscribe();h_close(reconnected);mt_stop(process);process=mt_start();html=mt_get(mt_port,"/");mt_check(h_has(html,"Changed externally") && h_has(html,"Unicode 你好 🌱") && !h_has(html,"alert(1)"),"restart lost persisted state");
    let active=mt_subscribe();mt_action("action=add&title=After+restart");event=mt_event(active);mt_check(h_has(event,"todo-5"),"automatic IDs reused deleted values");h_close(active);mt_stop(process);
    mt_sql(mt_database,"UPDATE _monolith_schema SET definition='changed'",0);let mismatch=h_run(mt_command());mt_check(h_status(mismatch)==1 && h_has(h_err(mismatch),"explicit migration"),"schema drift did not refuse startup");
    if mt_source {
        let original=mt_source;let code=h_read(original);
        let relocated=code;
        mt_source=h_join(temp,"renamed todo.flex");h_save(mt_source,relocated);mt_database=h_join(temp,"relocated.db");
        process=mt_start();mt_check(h_has(mt_get(mt_port,"/"),"0 remaining"),"relocated source failed");mt_stop(process);
        h_save(mt_source,h_replace(relocated,"Text(240)","Mystery"));
        failure=h_run(mt_command());mt_check(h_status(failure)==1 && h_has(h_err(failure),"schema line"),"invalid inline schema accepted");
        h_save(mt_source,h_cat(relocated,"\nfn broken( {\n"));
        failure=h_run(mt_command());mt_check(h_status(failure)==1,"invalid source accepted");
        // Source edits must take effect on the next run of the same filename.
        h_save(mt_source,h_replace(relocated,"A little room for progress.","Updated source application."));
        process=mt_start();mt_check(h_has(mt_get(mt_port,"/"),"Updated source application."),"source edit did not take effect");
        syscall(62,load64(process),2,0,0,0,0);h_wait(process);
        mt_check(h_status(process)==-2,"native handoff did not preserve Ctrl-C");
    }
    h_print(1,h_cat3("PASS: ",h_int(mt_checks)," compiler/schema/SQLite/HTTP/realtime checks\n"));return 0;
}
