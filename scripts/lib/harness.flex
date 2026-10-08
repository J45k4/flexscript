// Shared assertions, compiler fixtures and JSON reports; compiled by Flexscript.
import "json.flex";
global t_checks=0;
global t_compiler=0;
global t_work=0;
global t_fixture=0;
global t_binary=0;
fn t_init(compiler) {
    t_checks=0;
    t_compiler=h_real(compiler);
    t_work=h_temp();
    t_fixture=h_join(t_work,"test.flex");
    t_binary=h_join(t_work,"program");
    return 0;
}
fn t_assert(ok,message) {
    h_assert(ok,message);
    t_checks=t_checks+1;
    return 0;
}
fn t_program(text) {
    h_save(t_fixture,text);
    return 0;
}
fn t_compile() {
    return h_compile(t_compiler,t_fixture,t_binary);
}
fn t_native(text,status,out) {
    t_program(text);
    t_compile();
    h_check(h_run(h_args(t_binary,0,0,0,0,0)),status,out);
    t_checks=t_checks+1;
    return 0;
}
fn t_location(error) {
    let i=0;
    let size=h_len(error);
    while i<size {
        if load8(error+i)==58 {
            let at=i+1;
            let first=at;
            while load8(error+at)>=48 && load8(error+at)<=57 {
                at=at+1;
            }
            if at>first && load8(error+at)==58 {
                at=at+1;
                first=at;
                while load8(error+at)>=48 && load8(error+at)<=57 {
                    at=at+1;
                }
                if at>first && h_starts(error+at,": error: ") {
                    return 1;
                }
            }
        }
        i=i+1;
    }
    return 0;
}
fn t_reject(source,destination,message) {
    let original=h_sha(source);
    let existed=h_exists(destination);
    let before=0;
    if existed {
        before=h_sha(destination);
    }
    let p=h_run(h_args(t_compiler,source,"-o",destination,0,0));
    h_check(p,1,0);
    h_assert(h_has(h_err(p),message),h_err(p));
    h_assert(t_location(h_err(p)),"missing diagnostic location");
    h_assert(h_equal(h_sha(source),original),"rejected source changed");
    if existed {
        h_assert(h_equal(h_sha(destination),before),"existing destination changed");
    }else {
        h_assert(!h_exists(destination),"invalid source produced a binary");
    }
    t_checks=t_checks+1;
    return p;
}
fn t_done() {
    h_remove(t_work);
    h_print(1,h_cat3(t_compiler,": ",h_cat(h_int(t_checks)," checks passed\n")));
    return t_checks;
}
fn t_report(results) {
    let total=0;
    let i=0;
    while i<j_count(results) {
        total=total+j_n(j_at(results,i),"checks");
        i=i+1;
    }
    let report=j_object();
    j_set(report,"results",results);
    j_set(report,"total",j_int(total));
    return report;
}
fn t_entry(argc,argv) {
    h_environment(argc,argv);
    let results=j_array();
    let report=0;
    let i=1;
    while i<argc {
        let arg=load64(argv+i*8);
        if h_equal(arg,"--report") {
            i=i+1;
            h_assert(i<argc,"--report needs a path");
            report=load64(argv+i*8);
        }else {
            let mark=h_mark();
            let checks=suite(arg);
            h_reset(mark);
            let item=j_object();
            j_set(item,"compiler",j_string(h_absolute(arg)));
            j_set(item,"checks",j_int(checks));
            j_push(results,item);
        }
        i=i+1;
    }
    h_assert(j_count(results)>0,"provide one or more compiler paths");
    let result=t_report(results);
    if report {
        j_save(report,result);
    }
    h_print(1,h_cat3("Total: ",h_int(j_n(result,"total"))," checks passed\n"));
    return 0;
}
