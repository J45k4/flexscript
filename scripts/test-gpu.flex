import "lib/build.flex";
import "lib/harness.flex";
global tg_ptxas=0;
global tg_arch=0;
global tg_gpu=0;
global tg_programs=0;
global tg_assembled=0;
global tg_executed=0;
fn tg_compile() {
    h_ok(h_args(t_compiler,"--target","ptx",t_fixture,"-o",t_binary));
    let text=h_read(t_binary);
    t_assert(h_starts(text,"// Flexscript experimental PTX backend\n.version 6.0\n.target sm_50\n.address_size 64"),"PTX target header");
    t_assert(h_has(text,".visible .entry flex_kernel("),"device entry point");
    t_assert(syscall(21,t_binary,1,0,0,0,0)!=0,"PTX is non-executable data");
    tg_programs=tg_programs+1;
    let cubin=h_join(t_work,"program.cubin");
    if tg_ptxas {
        h_ok(h_args(tg_ptxas,h_cat("-arch=",tg_arch),t_binary,"-o",cubin,0));
        let bytes=h_read(cubin);
        t_assert(h_file_size>64 && load8(bytes)==127 && load8(bytes+1)==69 && load8(bytes+2)==76 && load8(bytes+3)==70
            && load8(bytes+18)==190 && load8(bytes+19)==0,"native NVIDIA ELF cubin");
        tg_assembled=tg_assembled+1;
    }
    if tg_gpu {
        let host=h_join(t_work,"host.flex");let binary=h_join(t_work,"host");
        let source=h_cat3("import \"",h_real("scripts/lib/gpu-harness.flex"),"\";\n");
        source=h_cat(source,h_cat3("import \"",t_fixture,"\";\n"));
        source=h_cat(source,"fn main(argc,argv){h_environment(argc,argv);return gpu_run(load64(argv+8),129);}");
        h_save(host,source);h_compile(t_compiler,host,binary);
        h_ok(h_args(binary,t_binary,0,0,0,0));tg_executed=tg_executed+1;
        if tg_ptxas {h_ok(h_args(binary,cubin,0,0,0,0));tg_executed=tg_executed+1;}
    }
    return text;
}
fn tg_case(body) {
    t_program(h_cat3("fn kernel(i,input,output,count){let x=load64(input+i*8);",body,"}"));return tg_compile();
}
fn tg_reject(source,message) {
    t_program(source);let before=h_sha(t_binary);
    let p=h_run(h_args(t_compiler,"--target","ptx",t_fixture,"-o",t_binary));h_check(p,1,0);
    t_assert(h_has(h_err(p),message),h_err(p));t_assert(t_location(h_err(p)),"PTX diagnostic location");
    t_assert(h_equal(before,h_sha(t_binary)),"rejected kernel changed existing output");return 0;
}
fn suite(compiler) {
    t_init(compiler);
    t_program(h_read("examples/gpu/vector.flex"));tg_compile();
    let ops=h_args("+","-","*","&","|","^");
    h_add(ops,"<<");h_add(ops,">>");h_add(ops,"==");h_add(ops,"!=");h_add(ops,"<");h_add(ops,">");h_add(ops,"<=");h_add(ops,">=");
    let i=0;while i<h_count(ops) {
        tg_case(h_cat3("store64(output+i*8,x ",h_at(ops,i)," (i+65));return 0;"));i=i+1;
    }
    tg_case("store64(output+i*8,(x/3)+(x%3));return 0;");
    tg_case("let n=0;let total=0;while n<5 {if (x&1) && n!=2 {total=total+x;}else {total=total-7;}n=n+1;}store64(output+i*8,total);return 0;");
    tg_case("store64(output+i*8,(-x)^(~x)^(!x)^(x||1));return 0;");
    tg_case("store64(output+i*8,load64(input+i*8+1));return 0;");
    tg_case("store8(output+i*8,load8(input+i*8+1));return 0;");
    tg_case("store64(output+i*8,store8(output+i*8,x));return 0;");
    tg_case("if i==0 {store64(output+1,0x8877665544332211);}return 0;");
    // Evaluation order and short-circuiting must preserve pending call arguments.
    t_program("fn mix(a,b,c){return a*100+b*10+c;}fn kernel(i,input,output,count){store64(output+i*8,mix(i,0||1,1&&2));return 0;}");tg_compile();
    t_program("fn kernel(i,input,output,count){if i&1 {store64(output+i*8,later(i));}else {store64(output+i*8,later(-i));}return 0;}fn later(x){return x*7;}");tg_compile();
    // Host-only functions are discarded, even if they recurse or use host calls.
    t_program("fn host(){return alloc(8)+host();}fn host_main(){return syscall(39,0,0,0,0,0,0);}fn kernel(i,input,output,count){return 0;}");
    let text=tg_compile();t_assert(!h_has(text,"flex_fn0") && !h_has(text,"flex_fn1"),"only kernel call graph is emitted");
    tg_reject("fn main(){return 0;}","requires kernel");
    tg_reject("fn kernel(i){return i;}","must take four parameters");
    tg_reject("fn kernel(i,a,b,n){return alloc(8);}","cannot allocate");
    tg_reject("fn kernel(i,a,b,n){return syscall(39,0,0,0,0,0,0);}","host I/O");
    tg_reject("fn kernel(i,a,b,n){return ffi_open(a);}","FFI");
    tg_reject("fn kernel(i,a,b,n){return kernel(i,a,b,n);}","cannot recurse");
    tg_reject("fn a(){return b();}fn b(){return a();}fn kernel(i,x,y,n){return a();}","cannot recurse");
    tg_reject("global x=1;fn kernel(i,a,b,n){return x;}","globals or static data");
    tg_reject("fn kernel(i,a,b,n){return load8(\"abc\");}","string literals");
    tg_reject("fn kernel(i,a,b,n){return missing();}","undefined function");
    tg_reject("fn helper(x){return x;}fn kernel(i,a,b,n){return helper();}","wrong function argument count");
    // Keep trap guards in front of signed division/remainder, including MIN/-1.
    text=tg_case("store64(output+i*8,x/(i+1)+x%(i+1));return 0;");
    t_assert(h_has(text,"@%p trap;") && h_has(text,"0x8000000000000000") && h_has(text,"and.pred %p, %p, %q;"),"explicit division trap guards");
    let a=h_args(t_compiler,"--language","seta","--target","ptx",t_fixture);h_add(a,"-o");h_add(a,t_binary);
    let p=h_run(a);h_check(p,1,0);t_assert(h_has(h_err(p),"requires the Flexscript frontend"),"unsupported frontend rejected");
    return t_done();
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=b_option(argc,argv,"--compiler","build/flex-gpu");
    tg_ptxas=b_option(argc,argv,"--ptxas",0);tg_arch=b_option(argc,argv,"--arch","sm_75");
    let i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {tg_gpu=1;}i=i+1;}
    let checks=suite(compiler);let report=j_object();j_set(report,"checks",j_int(checks));
    j_set(report,"ptx_programs",j_int(tg_programs));j_set(report,"native_cubins",j_int(tg_assembled));j_set(report,"device_runs",j_int(tg_executed));
    let path=b_option(argc,argv,"--report",0);if path {j_save(path,report);}
    h_print(1,h_cat3("PTX programs: ",h_int(tg_programs),"\n"));
    h_print(1,h_cat3("Native cubins: ",h_int(tg_assembled),"\n"));
    h_print(1,h_cat3("Physical-device runs: ",h_int(tg_executed),"\n"));return 0;
}
