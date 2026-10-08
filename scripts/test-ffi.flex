import "lib/harness.flex";
fn suite(compiler) {
    t_init(compiler);
    let library=h_join(t_work,"library.so");
    // Explicit output path; no shell quoting is involved even with spaces.
    let args=h_args("cc","-shared","-fPIC","-O2","tests/tooling/ffi.c","-o");
    h_add(args,library);
    h_ok(args);
    let cases=j_parse(h_read("tests/tooling/ffi.json"));
    let root=h_absolute(".");
    let i=0;
    while i<j_count(cases) {
        let mark=h_mark();
        let item=j_at(cases,i);
        let env=h_env;
        if j_count(j_need(item,"environment")) {
            h_setenv("FLEX_FFI_TEST","yes");
        }
        t_program(h_replace(h_replace(j_s(item,"source"),"{work}",t_work),"{root}",root));
        t_compile();
        h_check(h_run(h_args(t_binary,0,0,0,0,0)),j_n(item,"status"),j_s(item,"stdout"));
        let elf=h_read(t_binary);
        let headers=load8(elf+56)|(load8(elf+57)<<8);
        let expected=1;
        if j_n(item,"dynamic") {
            expected=4;
        }
        t_assert(headers==expected,"FFI ELF linkage");
        h_env=env;
        h_reset(mark);
        i=i+1;
    }
    let calls=h_args("ffi_open()","ffi_open(1,2)","ffi_symbol(1)","ffi_call(1,2)","ffi_call_i32(1,2)","ffi_call_u32(1,2)");
    i=0;
    while i<h_count(calls) {
        let mark=h_mark();
        t_program(h_cat3("fn main(){return ",h_at(calls,i),";}"));
        t_reject(t_fixture,h_join(t_work,"invalid"),"wrong FFI argument count");
        h_reset(mark);
        i=i+1;
    }
    return t_done();
}
fn main(argc,argv) {
    return t_entry(argc,argv);
}
