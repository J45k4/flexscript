// Independent frontend boundary regression. The sparse acyclic graph has edges
// across both sides of the old1024 row boundary; retaining the old edge stride
// creates a false cycle. The real cycle traverses a high-index function too.
import "lib/harness.flex";
global sf_bun=0;
fn sf_program(count,cycle) {
    let out=h_buffer();h_text(out,"plugin test.functions v1 {}\n");let i=0;
    while i<count-1 {
        h_text(out,"fn f");h_text(out,h_int(i));h_text(out,"()->i32{");
        if i==0 {h_text(out,"return f1024()");}
        else if i==1024 {h_text(out,"return f1()");}
        else if i==1025 {h_text(out,h_cat3("return f",h_int(count-2),"()"));}
        else if i==1 && cycle {h_text(out,"return f0()");}
        else {h_text(out,"return 21");}
        h_text(out,"}\n");i=i+1;
    }
    h_text(out,"fn main()->i32{return f0()+f1025()}\n");t_program(h_data(out));return 0;
}
fn sf_native() {h_compile(t_compiler,t_fixture,t_binary);h_check(h_run(h_args(t_binary,0,0,0,0,0)),42,"");t_checks=t_checks+1;return 0;}
fn sf_ir(frontend,path) {
    let args=h_args(t_compiler,0,0,0,0,0);if frontend {h_add(args,"--frontend");h_add(args,frontend);}
    h_add(args,"--target");h_add(args,"ir");h_add(args,t_fixture);h_add(args,"-o");h_add(args,path);h_ok(args);
    return h_read(path);
}
fn sf_routes(count) {
    sf_program(count,0);sf_native();
    h_check(h_run(h_args(t_compiler,"run","--interpret","--restricted",t_fixture,0)),42,"");t_checks=t_checks+1;
    let jit=h_run(h_args(t_compiler,"run","--jit","--stats",t_fixture,0));h_check(jit,42,"");t_assert(!h_has(h_err(jit),"JIT compilations: 0;"),"wide Seta graph uses JIT");
    let module=h_join(t_work,"functions.wasm");h_ok(h_args(t_compiler,"--target","wasm32",t_fixture,"-o",module));
    let request=j_object();j_set(request,"module",j_string(module));let path=h_join(t_work,"wasm.json");j_save(path,request);
    let result=j_parse(h_out(h_ok(h_args(sf_bun,"scripts/wasm-runner.js",path,0,0,0))));
    t_assert(j_n(result,"valid") && !j_get(result,"error") && h_equal(j_s(result,"result"),"42"),"wide Seta graph executes in Wasm");
    let artifact=h_join(t_work,"functions.fir");let ir=sf_ir(0,artifact);t_assert(load64(ir+16)==count,"exact Seta function count preserved in FIR");
    let external=h_join(t_work,"external.fir");sf_ir("examples/extensions/seta.flex",external);
    t_assert(h_equal(h_sha(artifact),h_sha(external)),"bundled and external frontends agree across function boundary");
    h_ok(h_args(t_compiler,"--language","ir",artifact,"-o",t_binary));h_check(h_run(h_args(t_binary,0,0,0,0,0)),42,"");t_checks=t_checks+1;return 0;
}
fn sf_reject(count,cycle,message) {
    sf_program(count,cycle);t_reject(t_fixture,t_binary,message);
    let absent=h_join(t_work,"rejected-output");t_reject(t_fixture,absent,message);
    let before=h_sha(t_binary);let args=h_args(t_compiler,"--frontend","examples/extensions/seta.flex",t_fixture,"-o",t_binary);
    let p=h_run(args);h_check(p,1,0);t_assert(h_has(h_err(p),message) && t_location(h_err(p)),"external frontend diagnoses invalid graph");
    t_assert(h_equal(before,h_sha(t_binary)),"external rejection preserves existing output");return 0;
}
fn suite(compiler) {
    t_init(compiler);t_fixture=h_join(t_work,"functions.seta");sf_bun=h_executable("bun");h_timeout=120000;
    sf_routes(1030);sf_routes(2048);
    sf_reject(2049,0,"too many SetaScript functions (maximum 2048)");
    sf_reject(2048,1,"SetaScript recursion is not allowed");
    return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
