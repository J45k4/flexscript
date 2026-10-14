// Real Chromium regression tests; the harness itself is compiled Flexscript.
import "cdp.flex";
global bt_binary=0;
global bt_database=0;
global bt_port=0;
global bt_checks=0;
global bt_source=0;
global bt_name=0;
fn bt_free_port() {
    let fd=tcp_listen("127.0.0.1","0",8);h_assert(fd>=0,"cannot allocate test port");let address=h_take(16);let size=h_take(8);store64(size,16);syscall(51,fd,address,size,0,0,0);let port=(load8(address+2)<<8)|load8(address+3);h_close(fd);return port;
}
fn bt_start() {
    let args=h_args(bt_binary,h_int(bt_port),bt_database,0,0,0);
    if bt_source {args=h_args(bt_binary,"run",bt_source,h_int(bt_port),bt_database,0);}
    let process=h_spawn(args,"",0);h_until(process,bt_name,5000);return process;}
fn bt_check(tab,expression,message) {let result=cd_eval(tab,expression);h_assert(j_kind(result)==5 && j_value(result),message);bt_checks=bt_checks+1;return 0;}
fn bt_add(tab,title) {
    let literal=j_dump(j_string(title));cd_eval(tab,h_cat3("document.querySelector('[data-mkey=\"draft\"]').value=",literal,";document.querySelector('[data-mkey=\"add-form\"]').requestSubmit();true"));
    cd_wait(tab,h_cat3("[...document.querySelectorAll('.task-title')].some(n=>n.textContent===",literal,")"));return 0;
}
fn bt_counter() {
    bt_name="Monolith Counter listening";
    if bt_source {bt_source=h_real("examples/monolith/counter.flex");}else {bt_binary=h_real("build/monolith-counter");}
    bt_database=h_cat(bt_database,"-unused");let process=bt_start();
    let url=h_cat3("http://127.0.0.1:",h_int(bt_port),"/");let a=cd_tab(url);let b=cd_tab(url);
    let live="document.querySelector('[data-mono-status]')?.textContent==='Live'";cd_wait(a,live);cd_wait(b,live);
    cd_eval(b,"window.note=document.querySelector('[data-mkey=\"note\"]');note.value='My counter draft';note.focus();note.setSelectionRange(3,8);document.querySelector('[data-mkey=\"step\"]').value='7';document.querySelector('[data-mkey=\"choice\"]').value='large';true");
    let preserved="document.querySelector('[data-mkey=\"note\"]')===note && note.value==='My counter draft' && document.activeElement===note && note.selectionStart===3 && note.selectionEnd===8 && document.querySelector('[data-mkey=\"step\"]').value==='7' && document.querySelector('[data-mkey=\"choice\"]').value==='large'";
    cd_eval(a,"document.querySelector('[data-mkey=\"increase\"]').click();true");cd_wait(b,"document.querySelector('[data-mkey=\"count\"]').textContent==='1'");
    bt_check(b,"document.querySelector('[data-mkey=\"increase\"]').dataset.action==='double' && document.querySelector('[data-mkey=\"increase\"]').getAttribute('aria-label')==='Increase from 1' && document.querySelector('[data-mkey=\"increase\"]').dataset.odd==='yes'","generic attributes and action changes failed");bt_check(b,preserved,"counter update lost local draft");
    cd_eval(a,"document.querySelector('[data-mkey=\"increase\"]').click();true");cd_wait(b,"document.querySelector('[data-mkey=\"count\"]').textContent==='3'");bt_check(b,preserved,"changed action lost draft");
    cd_eval(a,"document.querySelector('[data-mkey=\"step\"]').value='4';document.querySelector('[data-mkey=\"step-form\"]').requestSubmit();true");cd_wait(b,"document.querySelector('[data-mkey=\"count\"]').textContent==='7'");bt_check(b,preserved,"arbitrary form fields lost draft");
    cd_eval(a,"document.querySelector('[data-mkey=\"rejected-check\"]').click();true");cd_wait(a,"document.querySelector('[data-mono-error]').textContent.includes('422')");bt_check(a,"!document.querySelector('[data-mkey=\"rejected-check\"]').checked","rejected checkbox action was not restored");
    cd_eval(a,"document.querySelector('[data-mkey=\"reset\"]').click();true");cd_wait(b,"document.querySelector('[data-mkey=\"count\"]').textContent==='0'");bt_check(b,"!document.querySelector('[data-mkey=\"increase\"]').hasAttribute('data-odd') && document.querySelector('[data-mkey=\"increase\"]').dataset.action==='increase'","attribute removal failed");
    // The counter deliberately resets on restart; local form state survives.
    h_stop(process);cd_wait(b,"document.querySelector('[data-mono-status]').textContent==='Reconnecting…'");process=bt_start();cd_wait(b,live);cd_wait(a,live);
    bt_check(b,preserved,"counter snapshot lost textarea/select state");
    bt_check(a,"document.querySelector('[data-mono-error]').textContent===''","successful generic action did not clear errors");
    bt_check(a,h_cat3("document.title===",j_dump(j_string("Monolith Counter")),""),"app page title was not configured");
    bt_check(a,"document.querySelector('[data-mkey=\"count\"]').textContent==='0'","counter clients diverged");
    h_assert(!h_exists(bt_database),"database-free app created a database");bt_checks=bt_checks+1;
    cd_screenshot(a,"build/monolith-counter-desktop.png",1100,1100,0);cd_close(a);cd_close(b);h_stop(process);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==3 || (argc==4 && h_equal(load64(argv+24),"--source")),"Usage: test-browser TODO-BINARY-OR-COMPILER CHROMIUM [--source]");if argc==4 {bt_source=h_real("examples/monolith/todo.flex");}bt_name="Monolith Todo listening";bt_binary=h_real(load64(argv+8));let chromium=load64(argv+16);let temp=h_temp();bt_database=h_join(temp,"todo.db");bt_port=bt_free_port();let process=bt_start();
    let profile=h_join(temp,"chromium");let args=h_args(chromium,"--headless","--no-sandbox","--disable-gpu","--no-first-run","--no-default-browser-check");h_add(args,h_cat("--user-data-dir=",profile));h_add(args,"--remote-debugging-address=127.0.0.1");h_add(args,"--remote-debugging-port=0");h_add(args,"about:blank");let chrome=h_spawn(args,"",0);
    cd_chrome=chrome;let port_file=h_join(profile,"DevToolsActivePort");let end=net_now()+10000;
    while !h_exists(port_file) {h_pump(chrome,10);h_assert(h_status(chrome)==-999 && net_now()<end,h_cat("Chromium did not start: ",h_err(chrome)));}
    let text=h_read(port_file);let newline=h_find(text,"\n");h_assert(newline>0,"DevTools port file invalid");cd_port=h_number(h_slice(text,newline));
    let url=h_cat3("http://127.0.0.1:",h_int(bt_port),"/");let a=cd_tab(url);let b=cd_tab(url);let live="document.querySelector('[data-mkey=\"connection\"]')?.textContent==='Live'";cd_wait(a,live);cd_wait(b,live);
    bt_check(a,"document.querySelectorAll('.task').length===0","initial UI not empty");
    cd_eval(b,"window.testDraft=document.querySelector('[data-mkey=\"draft\"]');testDraft.value='My unfinished local draft';testDraft.focus();testDraft.setSelectionRange(3,8);true");
    let preserved="document.querySelector('[data-mkey=\"draft\"]')===testDraft && testDraft.value==='My unfinished local draft' && document.activeElement===testDraft && testDraft.selectionStart===3 && testDraft.selectionEnd===8";
    bt_add(a,"Build Monolith with Flexscript");cd_wait(b,"document.querySelectorAll('.task').length===1");bt_check(b,preserved,"remote insert lost local state");
    cd_eval(a,"document.querySelector('.task input[type=\"checkbox\"]').click();true");cd_wait(b,"document.querySelector('.task input[type=\"checkbox\"]').checked && document.querySelector('.task-title').classList.contains('completed')");bt_check(b,preserved,"completion lost local state");
    bt_add(a,"Realtime across two windows");cd_wait(b,"document.querySelectorAll('.task').length===2");h_stop(process);cd_wait(b,"document.querySelector('[data-mkey=\"connection\"]').textContent==='Reconnecting…'");
    let lib=ffi_open("libsqlite3.so.0");let slot=h_take(8);store64(slot,0);h_assert(ffi_call_i32(ffi_symbol(lib,"sqlite3_open"),bt_database,slot,0,0,0,0)==0,"offline DB open failed");let db=load64(slot);
    h_assert(ffi_call_i32(ffi_symbol(lib,"sqlite3_exec"),db,"DELETE FROM Todo WHERE id=2; INSERT INTO Todo(title,completed) VALUES ('Keep local drafts intact',0)",0,0,0,0)==0,"offline DB update failed");ffi_call_i32(ffi_symbol(lib,"sqlite3_close"),db,0,0,0,0,0);
    process=bt_start();cd_wait(b,"document.querySelector('[data-mkey=\"connection\"]').textContent==='Live' && [...document.querySelectorAll('.task-title')].some(n=>n.textContent==='Keep local drafts intact')");
    bt_check(b,"![...document.querySelectorAll('.task-title')].some(n=>n.textContent==='Realtime across two windows')","reconnect retained a deleted task");bt_check(b,preserved,"reconnect lost draft, focus or selection");cd_wait(a,live);
    bt_add(a,"Ship something small 🌱");cd_wait(b,"document.querySelectorAll('.task').length===3");bt_check(b,"document.querySelector('[data-mkey=\"summary\"]').textContent==='2 remaining · 1 complete'","reconnect actions or summary failed");
    cd_screenshot(a,"build/monolith-todo-desktop.png",1100,900,0);cd_screenshot(a,"build/monolith-todo-mobile.png",390,844,1);bt_check(a,"document.documentElement.scrollWidth<=390","mobile layout overflowed");
    bt_check(a,"document.querySelector('[data-mkey=\"error\"]').textContent===''","browser action failed");cd_close(a);cd_close(b);h_stop(process);bt_counter();h_stop(chrome);
    h_print(1,h_cat3("PASS: ",h_int(bt_checks)," real Chromium UI/reconnect/local-state checks\n"));return 0;
}
