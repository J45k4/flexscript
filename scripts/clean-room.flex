import "lib/build.flex";
fn cr_run(compiler,source,output,interpret,expected) {
    let args=h_args("bwrap","--unshare-all","--die-with-parent","--clearenv","--tmpfs","/");
    h_add(args,"--dir");
    h_add(args,"/work");
    h_add(args,"--chdir");
    h_add(args,"/work");
    h_add(args,"--ro-bind");
    h_add(args,h_real(compiler));
    h_add(args,"/compiler");
    let input="/source.flex";
    if source {
        h_add(args,"--ro-bind");
        h_add(args,h_real(source));
        if h_isdir(source) {
            h_add(args,"/sources");
            input="/sources/main.flex";
        }else {
            h_add(args,input);
        }
    }
    if output {
        h_add(args,"--bind");
        h_add(args,h_real(h_dir(output)));
        h_add(args,"/work");
    }
    h_add(args,"/compiler");
    if source {
        if interpret {
            h_add(args,"run");
            h_add(args,"--interpret");
            h_add(args,input);
        }else {
            h_add(args,input);
            h_add(args,"-o");
            let name=output+h_len(h_dir(output))+1;
            h_add(args,h_cat("/work/",name));
        }
    }else if expected && h_starts(expected,"flexscript ") {
        h_add(args,"--version");
    }
    let p=h_check(h_run(args),0,expected);
    h_assert(h_equal(h_err(p),""),h_err(p));
    return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    h_assert(argc>=2,"provide the static core compiler");
    let compiler=h_real(load64(argv+8));
    let source=b_option(argc,argv,"--source",0);
    h_assert(source,"--source is required");
    let out=h_absolute(b_option(argc,argv,"--out-dir","build/clean"));
    let report=b_option(argc,argv,"--report",0);
    h_mkdir(out);
    let rebuilt=h_join(out,"rebuilt");
    let hello=h_join(out,"hello");
    let imported=h_join(out,"imported");
    let version=h_cat3("flexscript ",b_version(),"\n");
    cr_run(compiler,0,0,0,version);
    cr_run(compiler,source,rebuilt,0,"");
    cr_run(rebuilt,0,0,0,version);
    cr_run(rebuilt,"examples/hello.flex",hello,0,"");
    cr_run(hello,0,0,0,"Hello from native Flexscript!\n");
    cr_run(rebuilt,"examples/imports",imported,0,"");
    cr_run(imported,0,0,0,"Hello from imported Flexscript!\n");
    cr_run(rebuilt,"examples/hello.flex",0,1,"Hello from native Flexscript!\n");
    cr_run(rebuilt,"examples/imports",0,1,"Hello from imported Flexscript!\n");
    let sha=h_sha(compiler);
    h_assert(h_equal(sha,h_sha(rebuilt)),"clean self rebuild differs");
    let result=j_object();
    j_set(result,"compiler_sha256",j_string(sha));
    j_set(result,"rebuilt_sha256",j_string(sha));
    j_set(result,"checks",j_int(10));
    j_set(result,"environment",j_string("empty bubblewrap root, empty environment, no network, no Rust/Cargo/libc"));
    if report {
        j_save(report,result);
    }
    h_print(1,"Clean room: 10 checks passed without a toolchain or libc.\n");
    return 0;
}
