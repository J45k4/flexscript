import "lib/harness.flex";
fn suite(compiler) {
    t_init(compiler);
    let version=h_out(h_check(h_run(h_args(t_compiler,"--version",0,0,0,0)),0,0));
    let current=h_trim(h_read("VERSION"));
    t_assert(h_equal(version,"flexscript 0.0.1\n") || h_equal(version,h_cat3("flexscript ",current,"\n")),"compiler version");
    let help=h_check(h_run(h_args(t_compiler,"--help",0,0,0,0)),0,0);
    t_assert(h_starts(h_out(help),"Usage: flexscript <source.flex> -o <binary>\n"),"compiler help");
    h_check(h_run(h_args(t_compiler,0,0,0,0,0)),1,0);
    t_checks=t_checks+1;
    let cases=j_parse(h_read("tests/cases.json"));
    let valid=j_need(cases,"valid");
    let i=0;
    while i<j_count(valid) {
        let mark=h_mark();
        let item=j_at(valid,i);
        let source=h_join("tests",j_s(item,"source"));
        h_compile(t_compiler,source,t_binary);
        h_elf(t_binary,0);
        h_assert(syscall(21,t_binary,1,0,0,0,0)==0,"binary not executable");
        let args=h_args(t_binary,0,0,0,0,0);
        let params=j_need(item,"args");
        let k=0;
        while k<j_count(params) {
            h_add(args,h_replace(j_value(j_at(params,k)),"{work}",t_work));
            k=k+1;
        }
        h_check(h_run(args),j_n(item,"exit"),j_s(item,"stdout"));
        let content=j_get(item,"file_content");
        if content {
            h_assert(h_equal(h_read(h_join(t_work,"file.txt")),j_value(content)),"file output");
        }
        t_checks=t_checks+1;
        h_reset(mark);
        i=i+1;
    }
    let invalid=j_need(cases,"invalid");
    i=0;
    while i<j_count(invalid) {
        let mark=h_mark();
        let item=j_at(invalid,i);
        t_reject(h_join("tests",j_s(item,"source")),h_join(t_work,"invalid"),j_s(item,"error"));
        h_reset(mark);
        i=i+1;
    }
    let limits=h_vec();
    let messages=h_vec();
    h_add(limits,h_cat3("fn main(){return ",h_cat3(h_repeat("(",130),"1",h_repeat(")",130)),";}"));
    h_add(messages,"expression nesting");
    h_add(limits,h_cat3("fn main(){",h_cat3(h_repeat("{",130),"return 0;",h_repeat("}",130)),"}"));
    h_add(messages,"block nesting");
    h_add(limits,h_cat3("fn main(){",h_repeat("if 0 {} else ",130),"{} return 0;}"));
    h_add(messages,"conditional nesting");
    let b=h_buffer();
    i=0;
    while i<2049 {
        h_text(b,h_cat3("global x",h_int(i),"=0;"));
        i=i+1;
    }
    h_text(b,"fn main(){return 0;}");
    h_add(limits,h_data(b));
    h_add(messages,"too many globals");
    b=h_buffer();
    h_text(b,"fn main(){");
    i=0;
    while i<4097 {
        h_text(b,h_cat3("let x",h_int(i),"=0;"));
        i=i+1;
    }
    h_text(b,"return 0;}");
    h_add(limits,h_data(b));
    h_add(messages,"too many locals");
    b=h_buffer();
    h_text(b,"fn main(){return 0;}");
    i=0;
    while i<2048 {
        h_text(b,h_cat3("fn f",h_int(i),"(){}"));
        i=i+1;
    }
    h_add(limits,h_data(b));
    h_add(messages,"too many functions");
    h_add(limits,h_cat3("fn main(){",h_repeat("f();",65537),"} fn f(){}"));
    h_add(messages,"too many calls");
    i=0;
    while i<h_count(limits) {
        let mark=h_mark();
        t_program(h_at(limits,i));
        t_reject(t_fixture,h_join(t_work,"invalid"),h_at(messages,i));
        h_reset(mark);
        i=i+1;
    }
    let mark=h_mark();
    t_program(h_repeat(" ",16777216));
    t_reject(t_fixture,h_join(t_work,"invalid"),"source must be smaller");
    h_reset(mark);
    mark=h_mark();
    t_program(h_cat3("fn main(){",h_repeat("1;",6711000),"}"));
    t_reject(t_fixture,h_join(t_work,"invalid"),"output exceeds");
    h_reset(mark);
    t_program("fn main(){return 42;}\n");
    let original=h_sha(t_fixture);
    h_check(h_run(h_args(t_compiler,t_fixture,"-o",t_fixture,0,0)),1,0);
    t_assert(h_equal(original,h_sha(t_fixture)),"source alias changed");
    let alias=h_join(t_work,"hardlink");
    h_assert(syscall(86,t_fixture,alias,0,0,0,0)==0,"hardlink failed");
    h_check(h_run(h_args(t_compiler,t_fixture,"-o",alias,0,0)),1,0);
    t_assert(h_equal(original,h_sha(t_fixture)),"hardlink changed");
    alias=h_join(t_work,"symlink");
    h_assert(syscall(88,t_fixture,alias,0,0,0,0)==0,"symlink failed");
    h_check(h_run(h_args(t_compiler,t_fixture,"-o",alias,0,0)),1,0);
    t_assert(h_equal(original,h_sha(t_fixture)),"symlink changed");
    h_check(h_run(h_args(t_compiler,t_fixture,"-o",h_join(t_work,"missing-dir/out"),0,0)),1,0);
    h_check(h_run(h_args(t_compiler,h_join(t_work,"absent.flex"),"-o",h_join(t_work,"absent"),0,0)),1,0);
    h_check(h_run(h_args(t_compiler,t_work,"-o",h_join(t_work,"directory"),0,0)),1,0);
    h_check(h_run(h_args(t_compiler,t_fixture,"--bad",h_join(t_work,"bad"),0,0)),1,0);
    t_checks=t_checks+4;
    let existing=h_join(t_work,"existing");
    h_save(existing,"keep me");
    t_reject("tests/invalid/undefined-variable.flex",existing,"undefined variable");
    h_save(existing,h_repeat("old",10000));
    syscall(90,existing,384,0,0,0,0);
    h_compile(t_compiler,t_fixture,existing);
    h_check(h_run(h_args(existing,0,0,0,0,0)),42,"");
    h_read(existing);
    t_assert(h_file_size<1000,"output not truncated");
    t_program("fn main() {\n  // diagnostic location\n  return @;\n}\n");
    let p=h_run(h_args(t_compiler,t_fixture,"-o",h_join(t_work,"location"),0,0));
    h_check(p,1,0);
    t_assert(h_has(h_err(p),":3:10: error: unexpected source byte"),h_err(p));
    t_native("fn main(){return 1/0;}",-8,"");
    t_native("fn main(){return 0x8000000000000000/-1;}",-8,"");
    return t_done();
}
fn main(argc,argv) {
    return t_entry(argc,argv);
}
