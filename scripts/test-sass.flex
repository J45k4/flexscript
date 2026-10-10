import "lib/build.flex";
import "lib/harness.flex";
global ss_gpu=0;
global ss_disassembler=0;
global ss_programs=0;
global ss_device_runs=0;
global ss_stride=8;
fn ss_u32(p) {return load64(p)&4294967295;}
fn ss_host() {
    let source=h_cat3("import \"",h_real("scripts/lib/gpu-harness.flex"),"\";\n");
    source=h_cat(source,h_cat3("import \"",t_fixture,"\";\n"));
    source=h_cat(source,h_cat3("fn main(argc,argv){h_environment(argc,argv);return gpu_run_stride(load64(argv+8),j_value(j_parse(load64(argv+16))),",h_int(ss_stride),");}"));
    let path=h_join(t_work,"host.flex");h_save(path,source);
    let binary=h_join(t_work,"host");h_compile(t_compiler,path,binary);return binary;
}
fn ss_run(host,artifact,count) {
    let p=h_ok(h_args(host,artifact,h_int(count),0,0,0));
    t_assert(h_has(h_out(p),"GPU/CPU parity:"),"physical SASS/CPU parity");ss_device_runs=ss_device_runs+1;return 0;
}
fn ss_compile() {
    // There are no compiler subprocesses, assembler, linker, CUDA libraries,
    // template files or instruction databases in the emission path.
    let saved=h_getenv("PATH");h_setenv("PATH","/no-flexscript-toolchain");
    h_ok(h_args(t_compiler,"--target","sass-sm75",t_fixture,"-o",t_binary));h_setenv("PATH",saved);
    let bytes=h_read(t_binary);let size=h_file_size;
    t_assert(size>64 && load64(bytes)==0x33010102464c457f && ss_u32(bytes+16)==0x00be0002,"native CUDA ELF header");
    t_assert((ss_u32(bytes+48)&255)==75,"native Turing architecture");
    t_assert(syscall(21,t_binary,1,0,0,0,0)!=0,"cubin has data permissions");
    let shoff=load64(bytes+40);let count=load8(bytes+60)|(load8(bytes+61)<<8);
    t_assert(shoff>=64 && count>0 && shoff+count*64<=size,"ELF section table bounds");
    let i=1;let sections=1;
    while i<count {let s=bytes+shoff+i*64;let at=load64(s+24);let n=load64(s+32);if at<0 || n<0 || at>size-n {sections=0;}i=i+1;}
    t_assert(sections,"ELF section payload bounds");
    let first=h_sha(t_binary);let again=h_join(t_work,"again.cubin");
    h_ok(h_args(t_compiler,"--target","sass-sm75",t_fixture,"-o",again));
    t_assert(h_equal(first,h_sha(again)),"deterministic SASS emission without toolchain PATH");
    if ss_disassembler {
        let p=h_ok(h_args(ss_disassembler,"-hex",t_binary,0,0,0));
        t_assert(!h_len(h_err(p)) && !h_has(h_out(p),"INVALID") && h_has(h_out(p),"flex_kernel:") && h_has(h_out(p),"EXIT"),"independent native instruction validation");
    }
    if ss_gpu {
        let host=ss_host();ss_run(host,t_binary,129);
        let ptx=h_join(t_work,"reference.ptx");h_ok(h_args(t_compiler,"--target","ptx",t_fixture,"-o",ptx));
        ss_run(host,ptx,129);
    }
    ss_programs=ss_programs+1;return 0;
}
fn ss_case(body) {
    t_program(h_cat3("fn kernel(i,input,output,count){let x=load64(input+i*8);",body,"}"));return ss_compile();
}
fn ss_reject(source,message) {
    t_program(source);let before=h_sha(t_binary);
    let p=h_run(h_args(t_compiler,"--target","sass-sm75",t_fixture,"-o",t_binary));h_check(p,1,0);
    t_assert(h_has(h_err(p),message),h_err(p));t_assert(t_location(h_err(p)),"SASS diagnostic location");
    t_assert(h_equal(before,h_sha(t_binary)),"unsupported SASS program preserves existing artifact");return 0;
}
fn suite(compiler) {
    t_init(compiler);t_program(h_read("examples/gpu/direct.flex"));ss_compile();
    if ss_gpu {
        let host=ss_host();let counts=h_args("0","1","127","128","4099",0);let i=0;
        while i<h_count(counts) {ss_run(host,t_binary,j_value(j_parse(h_at(counts,i))));i=i+1;}
    }
    let ops=h_args("+","-","*","&","|","^");let i=0;
    while i<h_count(ops) {ss_case(h_cat3("store64(output+i*8,x ",h_at(ops,i)," load64(input+((i+1)*8)));return 0;"));i=i+1;}
    ops=h_args("<<",">>","==","!=","<",">");h_add(ops,"<=");h_add(ops,">=");
    i=0;while i<h_count(ops) {ss_case(h_cat3("store64(output+i*8,x ",h_at(ops,i)," (i+65));return 0;"));i=i+1;}
    ss_case("store64(output+i*8,(!x)^(x||1)^(x&&7));return 0;");
    ss_case("store64(output+i*8,x/3+x%3);return 0;");
    ss_case("store64(output+i*8,x/(i+1)+x%(i+1));return 0;");
    ss_case("store64(output+i*8,x/(-7)+x%(-7));return 0;");
    ss_case("store64(output+i*8,x/(load64(input+(i+1)*8)|1)+x%(load64(input+(i+1)*8)|1));return 0;");
    ss_case("store64(output+i*8,x/0x8000000000000000+x%0x8000000000000000);return 0;");
    ss_case("let n=0;let total=0;while n<5 {if (x&1) && n!=2 {total=total+x;}else {total=total-7;}n=n+1;}store64(output+i*8,total);return 0;");
    t_program("fn mix(a,b,c){if a<0 {return -a;}return a*100+b*10+c;}fn kernel(i,input,output,count){store64(output+i*8,mix(load64(input+i*8),0||1,1&&2));return 0;}");ss_compile();
    t_program("fn later(x){return x*7;}fn nest(x){return later(x)+later(x+1);}fn kernel(i,input,output,count){if i&1 {store64(output+i*8,nest(i));}else {store64(output+i*8,nest(-i));}return 0;}");ss_compile();
    ss_case("store64(output+i*8,x+0xffffffff);return 0;");
    ss_case("store64(output+i*8,x-0x100000001);return 0;");
    ss_case("store64(output+i*8,x*0xdeadbeefffffffff);return 0;");
    ss_case("store64(output+i*8,-x);return 0;");
    ss_case("store64(output+i*8,~x);return 0;");
    ss_case("store64(output+i*8,(-x)^(~x));return 0;");
    ss_case("store64(output+i*8,load64(input+i*8+1));return 0;");
    ss_case("store8(output+i*8,load8(input+i*8+1));return 0;");
    ss_case("store64(output+i*8,store8(output+i*8,x));return 0;");
    // Each lane writes a disjoint unaligned word inside a sixteen-byte element.
    ss_stride=16;
    t_program("fn kernel(i,input,output,count){store64(output+i*16+1,load64(input+i*16+1)^0x8877665544332211);return 0;}");ss_compile();
    ss_stride=8;
    // Mutating parameters and locals retain their full 64-bit values.
    ss_case("i=i*8;let a=x+1;let b=a*17;a=b-3;store64(output+i,a);return 0;");
    h_save(h_join(t_work,"body.flex"),"fn kernel(i,a,b,n){store64(b+i*8,load64(a+i*8)+7);return 0;}");
    t_program("import \"body.flex\";fn unused(){return alloc(8)+unused();}");ss_compile();
    ss_reject("fn main(){return 0;}","requires kernel");
    ss_reject("fn kernel(x){return x;}","must take four parameters");
    ss_reject("fn kernel(i,a,b,n){return alloc(8);}","cannot allocate");
    ss_reject("fn kernel(i,a,b,n){return syscall(39,0,0,0,0,0,0);}","host I/O");
    ss_reject("fn kernel(i,a,b,n){return ffi_open(a);}","FFI");
    ss_reject("fn helper(x){return helper(x);}fn kernel(i,a,b,n){return helper(i);}","cannot recurse");
    ss_reject("global x=1;fn kernel(i,a,b,n){return x;}","globals or static data");
    ss_reject("fn kernel(i,a,b,n){return load8(\"x\");}","string literals");
    let source="fn kernel(i,a,b,n){";i=0;while i<120 {source=h_cat(source,h_cat3("let x",h_int(i),"=0;"));i=i+1;}
    ss_reject(h_cat(source,"return 0;}"),"physical register budget");
    let args=h_args(t_compiler,"--language","seta","--target","sass-sm75",t_fixture);h_add(args,"-o");h_add(args,t_binary);
    let p=h_run(args);h_check(p,1,0);t_assert(h_has(h_err(p),"requires the Flexscript frontend"),"unsupported SASS frontend rejected");
    return t_done();
}
fn main(argc,argv) {
    h_environment(argc,argv);ss_disassembler=b_option(argc,argv,"--nvdisasm",0);
    if ss_disassembler {ss_disassembler=h_real(ss_disassembler);}
    let i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {ss_gpu=1;}i=i+1;}
    let checks=suite(b_option(argc,argv,"--compiler","build/flex-sass"));
    let report=j_object();j_set(report,"checks",j_int(checks));j_set(report,"sass_cubins",j_int(ss_programs));j_set(report,"device_runs",j_int(ss_device_runs));
    let path=b_option(argc,argv,"--report",0);if path {j_save(path,report);}
    h_print(1,h_cat3("Direct SASS cubins: ",h_int(ss_programs),"\n"));
    h_print(1,h_cat3("Physical-device runs: ",h_int(ss_device_runs),"\n"));return 0;
}
