import "lib/build.flex";
import "lib/x11.flex";
global td_binary=0;
global td_work=0;
global td_path=0;
global td_process=0;
fn td_records(path) {
    if !h_exists(path) {
        return "FLEXTODO1\n";
    }
    return h_read(path);
}
fn td_expect(expected) {
    let end=net_now()+8000;
    while !h_equal(td_records(td_path),expected) {
        h_pump(td_process,5);
        h_assert(h_status(td_process)==-999,h_err(td_process));
        h_assert(net_now()<end,h_cat("Todo records differ: ",td_records(td_path)));
    }
    return 0;
}
fn td_start() {
    let previous=x_windows();
    td_process=h_spawn(h_args(td_binary,"--data",td_path,0,0,0),"",0);
    let end=net_now()+8000;
    let found=0;
    while !found {
        let names=x_windows();
        let i=0;
        while i<h_count(names) {
            let candidate=h_at(names,i);
            let existed=0;
            let k=0;
            while k<h_count(previous) {
                if candidate==h_at(previous,k) {
                    existed=1;
                }
                k=k+1;
            }
            if !existed {
                x_window=candidate;
                found=1;
            }
            i=i+1;
        }
        h_pump(td_process,10);
        h_assert(h_status(td_process)==-999,h_err(td_process));
        h_assert(net_now()<end,"Todo window did not open");
    }
    h_sleep(300);
    return 0;
}
fn td_stop() {
    x_close_window();
    h_check(h_wait(td_process),0,"");
    h_assert(h_equal(h_err(td_process),""),h_err(td_process));
    return 0;
}
fn td_add(text) {
    x_text(text);
    x_key(0xff0d,0);
    return 0;
}
fn td_storage() {
    let result=h_ok(h_args(td_binary,"--self-test",0,0,0,0));
    h_print(1,h_out(result));
    let path=h_join(td_work,"roundtrip.db");
    result=h_ok(h_args(td_binary,"--self-test","--data",path,0,0));
    h_print(1,h_out(result));
    h_assert(h_equal(h_read(path),"FLEXTODO1\n1\tLearn Flexscript\n1\tMake something useful\n"),"Todo storage roundtrip");
    let stat=h_take(144);
    syscall(4,path,stat,0,0,0,0);
    h_assert((load64(stat+24)&511)==384,"Todo database permissions");
    let before=h_sha(path);
    h_check(h_run(h_args(td_binary,"--self-test","--data",path,0,0)),1,0);
    h_assert(h_equal(before,h_sha(path)),"Todo self-test overwrote existing data");
    let bad=h_args("","wrong header\n","FLEXTODO1\n2\tbad\n","FLEXTODO1\n0\t\n","FLEXTODO1\n0\tno newline",0);
    let nonprint=h_take(2);
    store8(nonprint,1);
    store8(nonprint+1,0);
    h_add(bad,h_cat3("FLEXTODO1\n0\tnon",nonprint,"printable\n"));
    h_add(bad,h_cat3("FLEXTODO1\n0\t",h_repeat("x",121),"\n"));
    h_add(bad,h_cat("FLEXTODO1\n",h_repeat("0\ta\n",257)));
    let env=h_env;
    h_setenv("DISPLAY",":99999");
    let i=0;
    while i<h_count(bad) {
        let file=h_join(td_work,h_cat3("bad-",h_int(i),".db"));
        h_save(file,h_at(bad,i));
        let p=h_check(h_run(h_args(td_binary,"--data",file,0,0,0)),1,0);
        h_assert(h_has(h_err(p),"Invalid or unreadable"),h_err(p));
        h_assert(h_equal(h_read(file),h_at(bad,i)),"Todo corrupt file changed");
        i=i+1;
    }
    let link=h_join(td_work,"symlink.db");
    syscall(88,path,link,0,0,0,0);
    h_check(h_run(h_args(td_binary,"--data",link,0,0,0)),1,0);
    h_assert(h_equal(before,h_sha(path)),"Todo followed data symlink");
    h_setenv("DISPLAY",0);
    let p=h_check(h_run(h_args(td_binary,"--data",h_join(td_work,"missing-display.db"),0,0,0)),1,0);
    h_assert(h_has(h_err(p),"DISPLAY is not set"),h_err(p));
    h_env=env;
    h_check(h_run(h_args(td_binary,"--bad-option",0,0,0,0)),1,0);
    h_assert(h_starts(h_out(h_ok(h_args(td_binary,"--help",0,0,0,0))),"Flexscript Todo"),"Todo help");
    let names=h_entries(td_work);
    i=0;
    while i<h_count(names) {
        h_assert(!h_has(h_at(names,i),".tmp."),"Todo temporary file leaked");
        i=i+1;
    }
    h_print(1,"Todo storage checks passed.\n");
    return 0;
}
fn td_gui() {
    x_open();
    td_path=h_join(td_work,"gui.db");
    td_start();
    let size=x_size();
    let w=load64(size);
    let height=load64(size+8);
    h_assert(w>=760 && height>=560,"Todo window dimensions");
    td_add("Buy groceries");
    td_expect("FLEXTODO1\n0\tBuy groceries\n");
    td_add("Write Flexscript");
    td_expect("FLEXTODO1\n0\tBuy groceries\n0\tWrite Flexscript\n");
    x_click(270,294,1);
    td_expect("FLEXTODO1\n1\tBuy groceries\n0\tWrite Flexscript\n");
    x_click(60,250,1);
    x_click(w-98,294,1);
    td_add("Build something useful");
    td_expect("FLEXTODO1\n1\tBuy groceries\n0\tBuild something useful\n");
    x_click(60,302,1);
    x_click(w-60,294,1);
    td_expect("FLEXTODO1\n0\tBuild something useful\n");
    x_click(60,198,1);
    x_click(270,294,1);
    td_expect("FLEXTODO1\n1\tBuild something useful\n");
    x_key(0xff09,0);
    td_add("Take a break");
    td_expect("FLEXTODO1\n1\tBuild something useful\n0\tTake a break\n");
    x_key(0xff09,0);
    x_key(0xffbf,0);
    td_add("Take a walk");
    td_expect("FLEXTODO1\n1\tBuild something useful\n0\tTake a walk\n");
    let locked=h_check(h_run(h_args(td_binary,"--data",td_path,0,0,0)),1,0);
    h_assert(h_has(h_err(locked),"Another Todo instance"),h_err(locked));
    td_stop();
    td_start();
    td_expect("FLEXTODO1\n1\tBuild something useful\n0\tTake a walk\n");
    size=x_size();
    w=load64(size);
    height=load64(size+8);
    x_click(w-100,239,1);
    td_expect("FLEXTODO1\n0\tTake a walk\n");
    let blocked=h_cat3(td_path,".tmp.",h_int(load64(td_process)));
    h_save(blocked,"Leave this file alone");
    let before=h_sha(td_path);
    x_click(270,294,1);
    h_sleep(200);
    h_assert(h_equal(before,h_sha(td_path)) && h_equal(h_read(blocked),"Leave this file alone"),"Todo overwrote temporary collision");
    syscall(87,blocked,0,0,0,0,0);
    x_key(115,4);
    td_expect("FLEXTODO1\n1\tTake a walk\n");
    x_click(270,294,1);
    td_expect("FLEXTODO1\n0\tTake a walk\n");
    x_click(300,182,1);
    let tasks=h_args("Review the weekly plan","Sketch a new idea","Learn a little Flexscript","Water the plants","Read a chapter","Make time for a friend");
    h_add(tasks,"Keep the small promises");
    h_add(tasks,"Finish the first draft");
    h_add(tasks,"Tidy the desk");
    let expected=h_buffer();
    h_text(expected,"FLEXTODO1\n0\tTake a walk\n");
    let i=0;
    while i<h_count(tasks) {
        td_add(h_at(tasks,i));
        h_text(expected,h_cat3("0\t",h_at(tasks,i),"\n"));
        i=i+1;
    }
    td_expect(h_data(expected));
    i=0;
    while i<20 {
        x_click(400,350,4);
        i=i+1;
    }
    x_click(270,294,1);
    store8(h_data(expected)+10,49);
    td_expect(h_data(expected));
    h_sleep(250);
    x_screenshot("build/todo.png");
    x_click(300,182,1);
    let capacity=(height-326)/66;
    if capacity<1 {
        capacity=1;
    }
    let count=10;
    while count<=capacity+5 {
        let text=h_cat("Extra task ",h_int(count));
        td_add(text);
        h_text(expected,h_cat3("0\t",text,"\n"));
        count=count+1;
    }
    td_expect(h_data(expected));
    let last_page=count-capacity;
    x_click(270,294,1);
    let at=10;
    let row=0;
    while row<last_page {
        while load8(h_data(expected)+at)!=10 {
            at=at+1;
        }
        at=at+1;
        row=row+1;
    }
    store8(h_data(expected)+at,49);
    td_expect(h_data(expected));
    i=0;
    while i<count {
        x_click(400,350,4);
        i=i+1;
    }
    x_click(400,350,5);
    x_click(270,294,1);
    at=10;
    while load8(h_data(expected)+at)!=10 {
        at=at+1;
    }
    store8(h_data(expected)+at+1,49);
    td_expect(h_data(expected));
    td_stop();
    td_start();
    syscall(62,load64(td_process),15,0,0,0,0);
    h_check(h_wait(td_process),0,"");
    h_assert(h_equal(h_err(td_process),""),h_err(td_process));
    ffi_call(x_symbol("XCloseDisplay"),x_display,0,0,0,0,0);
    h_print(1,"Todo GUI checks passed: controls, persistence, retry, scrolling, locking, restart and PNG screenshot.\n");
    return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=h_real(b_option(argc,argv,"--compiler","build/flex"));
    h_mkdir("build");
    td_binary=h_absolute("build/todo");
    h_compile(compiler,"examples/todo.flex",td_binary);
    td_work=h_temp();
    td_storage();
    let i=1;
    while i<argc {
        if h_equal(load64(argv+i*8),"--gui") {
            td_gui();
        }
        i=i+1;
    }
    h_remove(td_work);
    return 0;
}
