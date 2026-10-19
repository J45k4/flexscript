import "lib/harness.flex";
fn ns_reject(body,message) {
    t_program(body);let before=h_sha(t_binary);let p=h_run(h_args(t_compiler,t_fixture,"-o",t_binary,0,0));h_check(p,1,0);
    t_assert(h_has(h_err(p),message) && t_location(h_err(p)),"unreachable code still receives located diagnostics");
    t_assert(h_equal(before,h_sha(t_binary)),"failed validation preserves output");return 0;
}
fn suite(compiler) {
    t_init(compiler);let all=h_join(t_work,"all");let marker=h_cat("UNREACHABLE_PAYLOAD_",h_repeat("abcdef0123456789",1024));
    t_program(h_cat3("global state=0;fn unused(){return ffi_open(\"",marker,"\");}fn dead_a(){return dead_b();}fn dead_b(){return dead_a();}fn leaf(n){if n{return leaf(n-1)+1;}return 40;}fn main(){state=2;return leaf(0)+state;}"));
    t_compile();h_ok(h_args(t_compiler,"--native-link","all",t_fixture,"-o",all));
    h_check(h_run(h_args(t_binary,0,0,0,0,0)),42,"");h_check(h_run(h_args(all,0,0,0,0,0)),42,"");
    let data=h_read(t_binary);let small=h_file_size;let retained=h_has(data,"UNREACHABLE_PAYLOAD_");h_read(all);let large=h_file_size;
    t_assert(!retained && large>small+16384,"unreachable functions and literal payloads are removed");h_elf(t_binary,1);
    t_assert(!h_has(data,"/lib64/ld-linux-x86-64.so.2"),"unreachable FFI does not require the dynamic loader");
    ns_reject("fn bad(){return missing();}fn main(){return 0;}","undefined function");
    ns_reject("fn bad(){return missing;}fn main(){return 0;}","undefined variable");
    ns_reject("fn bad(){return f(1);}fn f(){}fn main(){return 0;}","wrong function argument count");
    ns_reject("fn bad(){return ffi_call(0);}fn main(){return 0;}","wrong FFI argument count");
    ns_reject("fn bad(){return @;}fn main(){return 0;}","unexpected source byte");
    // Exercise both sides of disp8, imm8 frame/cleanup boundaries, writes to
    // uncached incoming parameters, and caller-saved register spill slots.
    let count=0;while count<=24 {
        let b=h_buffer();h_text(b,"fn sum(");let i=0;while i<count {if i {h_text(b,",");}h_text(b,h_cat("p",h_int(i)));i=i+1;}h_text(b,"){let result=0;");i=0;while i<count {h_text(b,h_cat3("p",h_int(i),h_cat3("=p",h_int(i),"+1;")));i=i+1;}i=0;while i<count {h_text(b,h_cat3("result=result+p",h_int(i),";"));i=i+1;}h_text(b,"return result;}fn main(){return sum(");i=0;while i<count {if i {h_text(b,",");}h_text(b,h_int(i));i=i+1;}h_text(b,");}");t_native(h_data(b),(count*(count+1)/2)&255,"");count=count+1;
    }
    t_native("fn clobber(a,b,c,d,e,f,g,h){return a+b+c+d+e+f+g+h;}fn recurse(n){let a=n+1;let b=n+2;let c=n+3;let d=n+4;let e=n+5;let f=n+6;let g=n+7;let h=n+8;if n {let nested=recurse(n-1);clobber(8,7,6,5,4,3,2,1);return a+b+c+d+e+f+g+h+nested;}return a+b+c+d+e+f+g+h;}fn main(){return recurse(4);}",4,"");
    let p=h_run(h_args(t_compiler,"--native-link","bad",t_fixture,"-o",all));h_check(p,1,0);t_assert(h_has(h_err(p),"expected reachable or all"),"invalid native link mode");
    let args=h_args(t_compiler,"--target","wasm32","--native-link","all",t_fixture);h_add(args,"-o");h_add(args,all);p=h_run(args);h_check(p,1,0);t_assert(h_has(h_err(p),"native link mode requires"),"link mode cannot silently affect another target");
    return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
