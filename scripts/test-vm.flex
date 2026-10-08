import "lib/harness.flex";
import "lib/build.flex";
fn tv_args(engine,options,source,params) {
    let args=h_args(t_compiler,"run",engine,0,0,0);
    let i=0;
    if options {
        while i<h_count(options) {
            h_add(args,h_at(options,i));
            i=i+1;
        }
    }
    if source {
        h_add(args,source);
    }
    i=0;
    if params {
        while i<h_count(params) {
            h_add(args,h_at(params,i));
            i=i+1;
        }
    }
    return args;
}
fn tv_run(engine,options,source,params) {
    return h_run(tv_args(engine,options,source,params));
}
fn tv_stats(p) {
    let text=h_err(p);
    let at=h_find(text,"VM steps: ");
    h_assert(at>=0,text);
    let values=h_take(32);
    let i=at+10;
    let k=0;
    while k<4 {
        while load8(text+i) && (load8(text+i)<48 || load8(text+i)>57) {
            i=i+1;
        }
        let n=0;
        let start=i;
        while load8(text+i)>=48 && load8(text+i)<=57 {
            n=n*10+load8(text+i)-48;
            i=i+1;
        }
        h_assert(i>start,"missing VM statistics");
        store64(values+k*8,n);
        k=k+1;
    }
    return values;
}
fn tv_trap(source,error,options) {
    t_program(source);
    let i=0;
    while i<2 {
        let engine="--interpret";
        if i {
            engine="--jit";
        }
        let p=tv_run(engine,options,t_fixture,0);
        h_check(p,70,0);
        t_assert(h_has(h_err(p),error),h_err(p));
        i=i+1;
    }
    return 0;
}
fn tv_words(line) {
    let v=h_vec();
    let i=0;
    while load8(line+i) {
        while load8(line+i)==32 || load8(line+i)==9 {
            i=i+1;
        }
        let start=i;
        while load8(line+i) && load8(line+i)!=32 && load8(line+i)!=9 {
            i=i+1;
        }
        if i>start {
            h_add(v,h_slice(line+start,i-start));
        }
    }
    return v;
}
fn suite(compiler) {
    t_init(compiler);
    let environment=h_env;
    h_setenv("PATH","/no/executables");
    let cases=j_parse(h_read("tests/cases.json"));
    let valid=j_need(cases,"valid");
    let i=0;
    while i<j_count(valid) {
        let mark=h_mark();
        let item=j_at(valid,i);
        if !h_equal(j_s(item,"source"),"valid/file-io.flex") {
            let source=h_join("tests",j_s(item,"source"));
            h_compile(t_compiler,source,t_binary);
            let params=h_vec();
            let strings=j_need(item,"args");
            let k=0;
            while k<j_count(strings) {
                h_add(params,h_replace(j_value(j_at(strings,k)),"{work}",t_work));
                k=k+1;
            }
            let args=h_args(t_binary,0,0,0,0,0);
            k=0;
            while k<h_count(params) {
                h_add(args,h_at(params,k));
                k=k+1;
            }
            let expected=h_check(h_run(args),j_n(item,"exit"),j_s(item,"stdout"));
            let previous=0;
            k=0;
            while k<2 {
                let engine="--interpret";
                if k {
                    engine="--jit";
                }
                let p=tv_run(engine,h_args("--stats",0,0,0,0,0),source,params);
                h_check(p,h_status(expected),h_out(expected));
                let stats=tv_stats(p);
                if previous {
                    h_assert(load64(previous)==load64(stats) && load64(previous+24)==load64(stats+24),"VM instruction accounting differs");
                }
                previous=stats;
                t_checks=t_checks+1;
                k=k+1;
            }
        }
        h_reset(mark);
        i=i+1;
    }
    let invalid=j_need(cases,"invalid");
    i=0;
    while i<j_count(invalid) {
        let mark=h_mark();
        let item=j_at(invalid,i);
        let p=tv_run("--interpret",0,h_join("tests",j_s(item,"source")),0);
        h_check(p,1,0);
        t_assert(h_has(h_err(p),j_s(item,"error")),h_err(p));
        h_reset(mark);
        i=i+1;
    }
    let traps=j_parse(h_read("tests/tooling/vm-traps.json"));
    i=0;
    while i<j_count(traps) {
        let mark=h_mark();
        let item=j_at(traps,i);
        let options=h_vec();
        let values=j_need(item,"options");
        let k=0;
        while k<j_count(values) {
            h_add(options,j_value(j_at(values,k)));
            k=k+1;
        }
        tv_trap(j_s(item,"source"),j_s(item,"error"),options);
        h_reset(mark);
        i=i+1;
    }
    let descriptors=h_args("1","4095","-1",0,0,0);
    let events=h_args("4","1","1",0,0,0);
    let revents=h_args("4","32","0",0,0,0);
    i=0;
    while i<3 {
        t_program(h_cat3("fn main(){let p=alloc(8);store64(p,(",h_at(descriptors,i),h_cat3("&0xffffffff)|(",h_at(events,i),h_cat3("<<32));let n=syscall(7,p,1,0,0,0,0);return (load64(p)>>48)==",h_at(revents,i),";}"))));
        h_check(tv_run(0,0,t_fixture,0),1,0);
        t_checks=t_checks+1;
        i=i+1;
    }
    t_program("fn main(){return syscall(7,0,68,0,0,0,0)==-22;}");
    h_check(tv_run(0,0,t_fixture,0),1,0);
    t_checks=t_checks+1;
    t_program("fn main(){let p=alloc(4096);return p==-12;}");
    h_check(tv_run(0,h_args("--memory=4096",0,0,0,0,0),t_fixture,0),1,0);
    t_checks=t_checks+1;
    t_program("fn main(argc,argv){let p=load64(argv+16);syscall(1,1,p,3,0,0,0);return argc;}");
    h_check(tv_run(0,0,t_fixture,h_args("first","two",0,0,0,0)),3,"two");
    t_checks=t_checks+1;
    t_program("fn main(){let p=alloc(8);let n=syscall(0,0,p,8,0,0,0);syscall(1,1,p,n,0,0,0);return 0;}");
    h_check(h_wait(h_spawn(tv_args(0,h_args("--allow-stdin",0,0,0,0,0),t_fixture,0),"input",0)),0,"input");
    t_checks=t_checks+1;
    let p=h_wait(h_spawn(tv_args(0,h_args("--allow-stdin","--timeout-ms=20",0,0,0,0),t_fixture,0),0,0));
    h_check(p,70,0);
    t_assert(h_has(h_err(p),"deadline exceeded"),h_err(p));
    let allowed=h_join(t_work,"allowed");
    h_mkdir(allowed);
    h_save(h_join(allowed,"file"),"capability read");
    let outside=h_join(t_work,"outside");
    h_save(outside,"secret outside capability");
    h_assert(syscall(88,outside,h_join(allowed,"escape"),0,0,0,0)==0,"symlink");
    let option=h_cat("--allow-read=",allowed);
    let paths=h_args("file",h_join(allowed,"file"),0,0,0,0);
    i=0;
    while i<2 {
        h_check(tv_run(0,h_args(option,0,0,0,0,0),"examples/vm-read.flex",h_args(h_at(paths,i),0,0,0,0,0)),0,"capability read");
        t_checks=t_checks+1;
        i=i+1;
    }
    paths=h_args("../outside",outside,"escape","/proc/self/mem",0,0);
    i=0;
    while i<h_count(paths) {
        p=tv_run(0,h_args(option,0,0,0,0,0),"examples/vm-read.flex",h_args(h_at(paths,i),0,0,0,0,0));
        t_assert((h_status(p)==2 || h_status(p)==70) && h_size(load64(p+16))==0,"read capability escape");
        i=i+1;
    }
    h_assert(syscall(133,h_join(allowed,"fifo"),4480,0,0,0,0)==0,"mkfifo");
    paths=h_args("fifo",".",0,0,0,0);
    i=0;
    while i<2 {
        p=tv_run(0,h_args(option,0,0,0,0,0),"examples/vm-read.flex",h_args(h_at(paths,i),0,0,0,0,0));
        h_check(p,70,0);
        t_assert(h_has(h_err(p),"capability denied"),h_err(p));
        i=i+1;
    }
    tv_trap("fn main(){return syscall(2,\"file\",577,384,0,0,0);}","capability denied",h_args(option,0,0,0,0,0));
    h_assert(h_equal(h_read(h_join(allowed,"file")),"capability read"),"write changed allowed file");
    let descriptor=syscall(2,outside,0,0,0,0,0);
    h_assert(descriptor>=3,"inherited descriptor");
    t_program(h_cat3("fn main(){let p=alloc(32);return syscall(0,",h_int(descriptor),",p,32,0,0,0)==-9;}"));
    h_inherit_fd=descriptor;
    h_check(tv_run(0,0,t_fixture,0),1,0);
    h_inherit_fd=-1;
    t_checks=t_checks+1;
    h_close(descriptor);
    let root=h_real(".");
    let args=h_args(t_compiler,"run","--interpret",h_cat("--allow-read=",root),"--memory=256m","--fuel=100000000");
    h_add(args,"--timeout-ms=10000");
    h_add(args,h_join(root,"flexvm.flex"));
    h_add(args,"run");
    h_add(args,"--interpret");
    h_add(args,h_join(root,"examples/hello.flex"));
    h_check(h_run(args),0,"Hello from native Flexscript!\n");
    t_checks=t_checks+1;
    let sandbox=h_join(t_work,"nested");
    h_mkdir(sandbox);
    h_save(h_join(sandbox,"flexvm.flex"),b_flatten(0));
    h_save(h_join(sandbox,"network.flex"),"fn main(){return syscall(41,2,1,0,0,0,0);}");
    args=h_args(t_compiler,"run","--interpret",h_cat("--allow-read=",sandbox),"--memory=256m","--fuel=100000000");
    h_add(args,"--timeout-ms=10000");
    h_add(args,h_join(sandbox,"flexvm.flex"));
    h_add(args,"run");
    h_add(args,"--interpret");
    h_add(args,h_join(sandbox,"network.flex"));
    p=h_run(args);
    h_check(p,70,0);
    t_assert(h_has(h_err(p),"capability denied"),h_err(p));
    let measurements=h_vec();
    let engines=h_args("--interpret","--jit","--stats",0,0,0);
    i=0;
    while i<3 {
        p=tv_run(h_at(engines,i),h_args("--stats",0,0,0,0,0),"examples/vm-compute.flex",0);
        h_check(p,0,0);
        h_add(measurements,tv_stats(p));
        t_checks=t_checks+1;
        i=i+1;
    }
    let a=h_at(measurements,0);
    let b=h_at(measurements,1);
    let c=h_at(measurements,2);
    h_assert(load64(a+8)==0 && load64(a+16)==0 && load64(b+8)==1 && load64(b+16)==40 && load64(c+8)==1 && load64(c+16)==25,"VM JIT tiering");
    h_assert(load64(a)==load64(b) && load64(a)==load64(c) && load64(a+24)==load64(b+24) && load64(a+24)==load64(c+24),"JIT fuel accounting");
    h_child_memory=134217728;
    p=tv_run("--jit",h_args("--stats",0,0,0,0,0),"examples/vm-compute.flex",0);
    h_child_memory=0;
    h_check(p,0,0);
    a=tv_stats(p);
    t_assert(load64(a+8)==0 && load64(a+16)==0,"JIT allocation fallback");
    // Frozen seeded corpus preserves the exact 80 prior full-word cases.
    let arithmetic=j_parse(h_read("tests/tooling/vm-arithmetic.json"));
    i=0;
    while i<j_count(arithmetic) {
        let mark=h_mark();
        t_program(j_value(j_at(arithmetic,i)));
        t_compile();
        let expected=h_run(h_args(t_binary,0,0,0,0,0));
        let k=0;
        while k<2 {
            let engine="--interpret";
            if k {
                engine="--jit";
            }
            p=tv_run(engine,0,t_fixture,0);
            if h_status(expected)!=0 {
                h_assert(h_status(expected)==-8,"unexpected native arithmetic trap");
                h_check(p,70,0);
                h_assert(h_has(h_err(p),"division trap"),h_err(p));
            }else {
                h_check(p,0,0);
                h_assert(h_size(load64(expected+16))==8 && h_size(load64(p+16))==8 && h_bytes(h_out(p),h_out(expected),8),"64-bit differential result");
            }
            t_checks=t_checks+1;
            k=k+1;
        }
        h_reset(mark);
        i=i+1;
    }
    t_program("fn spin(){while 1 {}return 0;}fn main(){return spin();}");
    p=h_spawn(tv_args("--jit",h_args("--fuel=1000000000","--timeout-ms=100",0,0,0,0),t_fixture,0),"",0);
    let observed=0;
    let maps_path=h_cat3("/proc/",h_int(load64(p)),"/maps");
    let end=net_now()+3000;
    while !observed && h_status(p)==-999 && net_now()<end {
        h_pump(p,0);
        if h_exists(maps_path) {
            let maps=h_read(maps_path);
            let at=0;
            while load8(maps+at) {
                let start=at;
                while load8(maps+at) && load8(maps+at)!=10 {
                    at=at+1;
                }
                let fields=tv_words(h_slice(maps+start,at-start));
                if h_count(fields)==5 {
                    h_assert(!h_has(h_at(fields,1),"rwx"),"writable executable JIT mapping");
                    if h_starts(h_at(fields,1),"r-x") {
                        observed=1;
                    }
                }
                if load8(maps+at) {
                    at=at+1;
                }
            }
        }
        h_sleep(1);
    }
    h_wait(p);
    h_assert(observed,"no executable JIT mapping observed");
    h_check(p,70,0);
    t_assert(h_has(h_err(p),"deadline exceeded"),h_err(p));
    let bad=h_args("--fuel=0","--fuel=-1","--memory=1","--timeout-ms=0","--fuel=99999999999999999999","--unknown");
    h_add(bad,"--allow-read=");
    i=0;
    while i<h_count(bad) {
        h_check(tv_run(h_at(bad,i),0,"examples/vm-compute.flex",0),1,0);
        t_checks=t_checks+1;
        i=i+1;
    }
    h_check(tv_run(0,0,0,0),1,0);
    t_checks=t_checks+1;
    h_check(tv_run("--help",0,0,0),0,0);
    t_checks=t_checks+1;
    h_env=environment;
    return t_done();
}
fn main(argc,argv) {
    return t_entry(argc,argv);
}
