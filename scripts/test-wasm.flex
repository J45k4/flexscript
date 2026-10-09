import "lib/build.flex";
import "lib/harness.flex";
global tw_bun=0;
fn tw_compile(source) {
    h_ok(h_args(t_compiler,"--target","wasm32",source,"-o",t_binary));
    let data=h_read(t_binary);
    t_assert(h_file_size>=8 && load64(data)==0x000000016d736100,"WebAssembly magic and version");
    t_assert(syscall(21,t_binary,1,0,0,0,0)!=0,"WebAssembly output is a module, not a host executable");
    return 0;
}
fn tw_run(request) {
    j_set(request,"module",j_string(t_binary));
    let path=h_join(t_work,"request.json");j_save(path,request);
    let process=h_ok(h_args(tw_bun,"scripts/wasm-runner.js",path,0,0,0));
    return j_parse(h_out(process));
}
fn tw_success(result) {
    t_assert(j_n(result,"valid"),"WebAssembly validation");
    let error=j_get(result,"error");let message="WebAssembly execution failed";
    if error {message=j_value(error);}t_assert(!error,message);
    return 0;
}
fn tw_program(text,expected) {
    t_program(text);tw_compile(t_fixture);let result=tw_run(j_object());tw_success(result);
    t_assert(h_equal(j_s(result,"result"),h_int(expected)),"WebAssembly full-word result");
    return result;
}
fn tw_reject(source,message) {
    let before=h_sha(t_binary);
    let p=h_run(h_args(t_compiler,"--target","wasm32",source,"-o",t_binary));
    h_check(p,1,0);t_assert(h_has(h_err(p),message),h_err(p));
    t_assert(t_location(h_err(p)),"WebAssembly diagnostic source location");
    t_assert(h_equal(before,h_sha(t_binary)),"invalid source changed existing module");return 0;
}
fn suite(compiler) {
    t_init(compiler);tw_bun=h_executable("bun");
    let cases=j_parse(h_read("tests/cases.json"));let valid=j_need(cases,"valid");let i=0;
    while i<j_count(valid) {
        let mark=h_mark();let item=j_at(valid,i);tw_compile(h_join("tests",j_s(item,"source")));
        let request=j_object();let argv=j_array();j_push(argv,j_string("app.wasm"));
        let params=j_need(item,"args");let k=0;
        while k<j_count(params) {j_push(argv,j_string(h_replace(j_value(j_at(params,k)),"{work}","/work")));k=k+1;}
        j_set(request,"argv",argv);
        if j_get(item,"file_content") {j_set(request,"output",j_string("/work/file.txt"));}
        let result=tw_run(request);tw_success(result);
        let word=j_value(j_parse(j_s(result,"result")));
        t_assert((word&255)==j_n(item,"exit"),h_cat("WebAssembly result: ",j_s(item,"source")));
        t_assert(h_equal(j_s(result,"stdout"),j_s(item,"stdout")),"WebAssembly stdout");
        if j_get(item,"file_content") {t_assert(h_equal(j_s(result,"output"),j_s(item,"file_content")),"virtual file contents");}
        h_reset(mark);i=i+1;
    }
    let invalid=j_need(cases,"invalid");i=0;
    while i<j_count(invalid) {
        let mark=h_mark();let item=j_at(invalid,i);tw_reject(h_join("tests",j_s(item,"source")),j_s(item,"error"));h_reset(mark);i=i+1;
    }
    tw_program("fn main(){return 0x7fffffffffffffff+1;}",-9223372036854775807-1);
    tw_program("fn main(){return (0xffffffffffffffff>>65) + (3<<65);}",5);
    tw_program("fn f(a,b,c){return a*100+b*10+c;}fn main(){return f(7,0||1,1&&2);}",711);
    t_program("fn main(){let i=0;let n=0;while i<20 {let j=0;while j<20 {if (i+j)%3==0 {n=n+1;}else if i==j {n=n+10;}else {n=n+2;}j=j+1;}i=i+1;}return n;}");tw_compile(t_fixture);
    // Compare nested control-flow with the native target rather than duplicate its answer.
    let native=h_join(t_work,"native");h_compile(t_compiler,t_fixture,native);
    let expected=h_run(h_args(native,0,0,0,0,0));let actual=tw_run(j_object());
    t_assert((j_value(j_parse(j_s(actual,"result")))&255)==h_status(expected),"nested control flow matches native");
    let memory=tw_program("fn main(){let p=alloc(70000);store64(p+1,0x1122334455667788);if load64(p+1)!=0x1122334455667788{return 1;}if load8(p+2)!=119{return 2;}if load64(p+69992)!=0{return 3;}return store8(p+69999,255);}",255);
    t_assert(j_count(j_need(memory,"imports"))==0,"pure modules need no host imports");
    let probe=j_object();j_set(probe,"probe",j_string("alloc"));let allocation=tw_run(probe);tw_success(allocation);
    let values=j_need(allocation,"values");
    t_assert(h_equal(j_value(j_at(values,0)),"-22"),"zero allocation errno");
    t_assert(h_equal(j_value(j_at(values,1)),"-12") && h_equal(j_value(j_at(values,2)),"-12"),"invalid allocations do not consume memory");
    t_assert(h_equal(j_value(j_at(values,3)),"16") && h_equal(j_value(j_at(values,4)),"24"),"allocator alignment and state");
    t_assert(j_n(allocation,"pages")==2,"allocator grows linear memory");
    let traps=h_args("1/0","1%0","(-9223372036854775807-1)/-1","(-9223372036854775807-1)%-1","load64(0)","load64(-1)");
    h_add(traps,"load8(0x100000010)");h_add(traps,"store64(0x100000010,1)");h_add(traps,"load64(65535)");
    i=0;while i<h_count(traps) {
        let mark=h_mark();t_program(h_cat3("fn main(){return ",h_at(traps,i),";}"));tw_compile(t_fixture);
        let result=tw_run(j_object());t_assert(j_n(result,"trap"),h_cat("missing WebAssembly trap: ",h_at(traps,i)));
        h_reset(mark);i=i+1;
    }
    // Seeded full-width differential corpus, shared with the VM and JIT tests.
    let arithmetic=j_parse(h_read("tests/tooling/vm-arithmetic.json"));i=0;
    while i<j_count(arithmetic) {
        let mark=h_mark();t_program(j_value(j_at(arithmetic,i)));h_compile(t_compiler,t_fixture,native);
        let expected=h_run(h_args(native,0,0,0,0,0));tw_compile(t_fixture);
        let request=j_object();j_set(request,"binary",j_bool(1));let actual=tw_run(request);
        if h_status(expected) {
            t_assert(h_status(expected)==-8 && j_n(actual,"trap"),"native and WebAssembly division trap");
        }else {
            tw_success(actual);
            t_assert(h_equal(j_s(actual,"stdoutHex"),h_hex(h_out(expected),h_size(load64(expected+16)))),"full-width native/WebAssembly arithmetic");
        }
        h_reset(mark);i=i+1;
    }
    // Imports share exactly the same frontend and global identity as native builds.
    h_save(h_join(t_work,"helper.flex"),"global count=5;fn bump(){count=count+1;return count;}");
    tw_program("import \"helper.flex\";import \"./helper.flex\";fn main(){return bump()*10+count;}",66);
    h_save(h_join(t_work,"helper.flex"),"import \"test.flex\";fn bump(){return 0;}");
    tw_reject(t_fixture,"circular import");
    t_program("fn main(){return port_in8(96);}");tw_reject(t_fixture,"hardware builtins require");
    t_program("fn main(){return native_callback(main);}");tw_reject(t_fixture,"native_callback requires");
    t_program("fn memory(){return 0;}fn main(){return memory();}");tw_reject(t_fixture,"runtime export");
    t_program("fn __flex_alloc(){return 0;}fn main(){return __flex_alloc();}");tw_reject(t_fixture,"runtime export");
    t_program("fn main(){let p=ffi_symbol(ffi_open(\"virtual\"),\"sum\");return ffi_call(p,1,2,3,4,5,6)+ffi_call_i32(p,0,0,0,0,0,0)+ffi_call_u32(p,0,0,0,0,0,0);}");
    tw_compile(t_fixture);let ffi=j_object();j_set(ffi,"ffi",j_bool(1));let result=tw_run(ffi);tw_success(result);
    t_assert(h_equal(j_s(result,"result"),"4295621615"),"host FFI argument order and i32/u32 returns");
    result=tw_run(j_object());t_assert(h_has(j_s(result,"error"),"host capability unavailable"),"missing host FFI reports an explicit error");
    tw_program("fn ffi_open(x){return x+1;}fn main(){return ffi_open(41);}",42);
    tw_program("fn main(){return syscall(9999,0,0,0,0,0,0);}",-38);
    tw_program("fn main(){syscall(60,42,0,0,0,0,0);return 99;}",42);
    // Build the actual compiler as WASM, then have it compile itself inside WASM.
    tw_compile("compiler/main.flex");
    let wasm_compiler=h_join(t_work,"compiler.wasm");h_save_bytes(wasm_compiler,h_read(t_binary),h_file_size,420);
    let request=j_object();let files=j_object();let root=h_cat(h_real("."),"/");
    b_flatten(0);i=0;while i<h_count(b_seen) {
        let path=h_at(b_seen,i);j_set(files,h_replace(path,root,""),j_string(h_read(path)));i=i+1;
    }
    j_set(request,"files",files);let argv=j_array();
    j_push(argv,j_string("flex"));j_push(argv,j_string("--target"));j_push(argv,j_string("wasm32"));j_push(argv,j_string("compiler/main.flex"));j_push(argv,j_string("-o"));j_push(argv,j_string("rebuilt.wasm"));
    j_set(request,"argv",argv);j_set(request,"output",j_string("rebuilt.wasm"));
    let rebuilt=h_join(t_work,"rebuilt.wasm");j_set(request,"save",j_string(rebuilt));
    result=tw_run(request);tw_success(result);t_assert(h_equal(j_s(result,"result"),"0"),"WASM compiler self-build exits successfully");
    t_assert(h_equal(h_sha(wasm_compiler),h_sha(rebuilt)),"WASM compiler rebuild is byte-identical");
    h_save_bytes(t_binary,h_read(rebuilt),h_file_size,420);
    request=j_object();files=j_object();j_set(files,"app.flex",j_string("fn main(){return 42;}"));j_set(request,"files",files);
    argv=j_array();j_push(argv,j_string("flex"));j_push(argv,j_string("--target"));j_push(argv,j_string("wasm32"));j_push(argv,j_string("app.flex"));j_push(argv,j_string("-o"));j_push(argv,j_string("app.wasm"));j_set(request,"argv",argv);
    j_set(request,"output",j_string("app.wasm"));let child=h_join(t_work,"child.wasm");j_set(request,"save",j_string(child));
    result=tw_run(request);tw_success(result);t_assert(h_equal(j_s(result,"result"),"0"),"rebuilt WASM compiler builds an application");
    argv=j_array();j_push(argv,j_string("flex"));j_push(argv,j_string("app.flex"));j_push(argv,j_string("-o"));j_push(argv,j_string("app.elf"));j_set(request,"argv",argv);
    j_set(request,"output",j_string("app.elf"));j_set(request,"save",j_string(native));
    result=tw_run(request);tw_success(result);t_assert(h_equal(j_s(result,"result"),"0"),"WASM compiler emits native Linux ELF");
    h_elf(native,1);h_check(h_ok(h_args("chmod","+x",native,0,0,0)),0,0);
    h_check(h_run(h_args(native,0,0,0,0,0)),42,"");t_checks=t_checks+1;
    h_save_bytes(t_binary,h_read(child),h_file_size,420);result=tw_run(j_object());tw_success(result);
    t_assert(h_equal(j_s(result,"result"),"42"),"application built by self-hosted WASM compiler runs");
    // The bundled frontend and portable IR lowerers also run inside the compiler's
    // own WebAssembly build, without subprocesses or a native frontend adapter.
    h_save_bytes(t_binary,h_read(wasm_compiler),h_file_size,420);
    request=j_object();files=j_object();j_set(files,"policy.seta",j_string("plugin test v1 {} state {a:i32[10000]=0 b:i32[3]=[4,5,6]} fn main()->i32{state.a[9999]=state.b[1]*8+2 return state.a[9999]}"));j_set(request,"files",files);
    argv=j_array();j_push(argv,j_string("flex"));j_push(argv,j_string("--target"));j_push(argv,j_string("wasm32"));j_push(argv,j_string("policy.seta"));j_push(argv,j_string("-o"));j_push(argv,j_string("policy.wasm"));j_set(request,"argv",argv);
    j_set(request,"output",j_string("policy.wasm"));j_set(request,"save",j_string(child));
    result=tw_run(request);tw_success(result);t_assert(h_equal(j_s(result,"result"),"0"),"WASM compiler runs bundled SetaScript frontend");
    argv=j_array();j_push(argv,j_string("flex"));j_push(argv,j_string("policy.seta"));j_push(argv,j_string("-o"));j_push(argv,j_string("policy.elf"));j_set(request,"argv",argv);
    j_set(request,"output",j_string("policy.elf"));j_set(request,"save",j_string(native));
    result=tw_run(request);tw_success(result);t_assert(h_equal(j_s(result,"result"),"0"),"WASM compiler lowers portable IR to native ELF");
    h_elf(native,1);h_ok(h_args("chmod","+x",native,0,0,0));h_check(h_run(h_args(native,0,0,0,0,0)),42,"");t_checks=t_checks+1;
    h_save_bytes(t_binary,h_read(child),h_file_size,420);result=tw_run(j_object());tw_success(result);
    t_assert(h_equal(j_s(result,"result"),"42"),"SetaScript application compiled inside WASM executes");
    // FIR4 crosses the former4MiB artifact limit inside the self-hosted compiler.
    h_save_bytes(t_binary,h_read(wasm_compiler),h_file_size,420);
    request=j_object();files=j_object();j_set(files,"world.seta",j_string("plugin test v1 {} state {a:i32[1048573]=0 b:i32[3]=[4,5,6]} fn main()->i32{state.a[1048572]=state.b[1]*8+2 return state.a[1048572]}"));j_set(request,"files",files);
    argv=j_array();j_push(argv,j_string("flex"));j_push(argv,j_string("--target"));j_push(argv,j_string("wasm32"));j_push(argv,j_string("world.seta"));j_push(argv,j_string("-o"));j_push(argv,j_string("world.wasm"));j_set(request,"argv",argv);
    j_set(request,"output",j_string("world.wasm"));j_set(request,"save",j_string(child));
    result=tw_run(request);tw_success(result);t_assert(h_equal(j_s(result,"result"),"0"),"WASM compiler builds one-million-word FIR4 module");
    argv=j_array();j_push(argv,j_string("flex"));j_push(argv,j_string("world.seta"));j_push(argv,j_string("-o"));j_push(argv,j_string("world.elf"));j_set(request,"argv",argv);
    j_set(request,"output",j_string("world.elf"));j_set(request,"save",j_string(native));
    result=tw_run(request);tw_success(result);t_assert(h_equal(j_s(result,"result"),"0"),"WASM compiler lowers FIR4 to native ELF");
    h_elf(native,1);h_ok(h_args("chmod","+x",native,0,0,0));h_check(h_run(h_args(native,0,0,0,0,0)),42,"");t_checks=t_checks+1;
    h_save_bytes(t_binary,h_read(child),h_file_size,420);result=tw_run(j_object());tw_success(result);
    t_assert(h_equal(j_s(result,"result"),"42"),"FIR4 application compiled inside WASM executes");
    // FIR5 retains the complete scene beyond the old eight-MiB state ceiling.
    h_save_bytes(t_binary,h_read(wasm_compiler),h_file_size,420);
    request=j_object();files=j_object();j_set(files,"scene.seta",j_string("plugin test v1 {} state {a:i32[2097149]=0 b:i32[3]=[4,5,6]} fn main()->i32{state.a[2097148]=state.b[1]*8+2 return state.a[2097148]}"));j_set(request,"files",files);
    argv=j_array();j_push(argv,j_string("flex"));j_push(argv,j_string("--target"));j_push(argv,j_string("wasm32"));j_push(argv,j_string("scene.seta"));j_push(argv,j_string("-o"));j_push(argv,j_string("scene.wasm"));j_set(request,"argv",argv);
    j_set(request,"output",j_string("scene.wasm"));j_set(request,"save",j_string(child));
    result=tw_run(request);tw_success(result);t_assert(h_equal(j_s(result,"result"),"0"),"WASM compiler builds maximum-state FIR5 module");
    argv=j_array();j_push(argv,j_string("flex"));j_push(argv,j_string("scene.seta"));j_push(argv,j_string("-o"));j_push(argv,j_string("scene.elf"));j_set(request,"argv",argv);
    j_set(request,"output",j_string("scene.elf"));j_set(request,"save",j_string(native));
    result=tw_run(request);tw_success(result);t_assert(h_equal(j_s(result,"result"),"0"),"WASM compiler lowers FIR5 to native ELF");
    h_elf(native,1);h_ok(h_args("chmod","+x",native,0,0,0));h_check(h_run(h_args(native,0,0,0,0,0)),42,"");t_checks=t_checks+1;
    h_save_bytes(t_binary,h_read(child),h_file_size,420);result=tw_run(j_object());tw_success(result);
    t_assert(h_equal(j_s(result,"result"),"42"),"FIR5 application compiled inside WASM executes");
    return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
