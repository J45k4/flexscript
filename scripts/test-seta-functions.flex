// Independent frontend boundary regression. The sparse acyclic graph has edges
// above both the old function and JIT-cache capacities. The real cycle
// traverses a high-index function too.
import "lib/harness.flex";
global sf_bun=0;
global sf_platform=0;
fn sf_compile(source,target,path) {
    let args=h_args(t_compiler,0,0,0,0,0);if target {h_add(args,"--target");h_add(args,target);}
    if sf_platform {h_add(args,"--platform");h_add(args,sf_platform);}
    h_add(args,source);h_add(args,"-o");h_add(args,path);h_ok(args);return 0;
}
fn sf_program(count,cycle) {
    let out=h_buffer();h_text(out,"plugin test.functions v1 {}\n");let i=0;
    while i<count-1 {
        h_text(out,"fn f");h_text(out,h_int(i));h_text(out,"()->i32{");
        if i==0 {h_text(out,"return f4096()");}
        else if i==4096 {h_text(out,"return f1()");}
        else if i==8192 {h_text(out,h_cat3("return f",h_int(count-2),"()"));}
        else if i==1 && cycle {h_text(out,"return f0()");}
        else {h_text(out,"return 21");}
        h_text(out,"}\n");i=i+1;
    }
    h_text(out,"fn main()->i32{return f0()+f8192()}\n");t_program(h_data(out));return 0;
}
fn sf_native() {sf_compile(t_fixture,0,t_binary);h_check(h_run(h_args(t_binary,0,0,0,0,0)),42,"");t_checks=t_checks+1;return 0;}
fn sf_ir(frontend,path) {
    let args=h_args(t_compiler,0,0,0,0,0);if frontend {h_add(args,"--frontend");h_add(args,frontend);}
    h_add(args,"--target");h_add(args,"ir");h_add(args,t_fixture);h_add(args,"-o");h_add(args,path);h_ok(args);
    return h_read(path);
}
fn sf_routes(count,external_frontend) {
    sf_program(count,0);
    if sf_platform {h_save(t_fixture,h_replace(h_read(t_fixture),"fn f16382()->i32{return 21}","extern fn f16382()->i32;"));}
    sf_native();
    let interpret=h_args(t_compiler,"run","--interpret","--restricted",0,0);if sf_platform {h_add(interpret,"--platform");h_add(interpret,sf_platform);}h_add(interpret,t_fixture);
    h_check(h_run(interpret),42,"");t_checks=t_checks+1;
    let args=h_args(t_compiler,"run","--jit","--stats",0,0);if sf_platform {h_add(args,"--platform");h_add(args,sf_platform);}h_add(args,t_fixture);let jit=h_run(args);h_check(jit,42,"");t_assert(!h_has(h_err(jit),"JIT compilations: 0;"),"wide Seta graph uses JIT");
    let module=h_join(t_work,"functions.wasm");sf_compile(t_fixture,"wasm32",module);
    let request=j_object();j_set(request,"module",j_string(module));let path=h_join(t_work,"wasm.json");j_save(path,request);
    let result=j_parse(h_out(h_ok(h_args(sf_bun,"scripts/wasm-runner.js",path,0,0,0))));
    t_assert(j_n(result,"valid") && !j_get(result,"error") && h_equal(j_s(result,"result"),"42"),"wide Seta graph executes in Wasm");
    let artifact=h_join(t_work,"functions.fir");let ir=sf_ir(0,artifact);t_assert(load64(ir+16)==count,"exact Seta function count preserved in FIR");
    if external_frontend {let external=h_join(t_work,"external.fir");sf_ir("examples/extensions/seta.flex",external);
    t_assert(h_equal(h_sha(artifact),h_sha(external)),"bundled and external frontends agree across function boundary");}
    let saved=h_args(t_compiler,"--language","ir",0,0,0);if sf_platform {h_add(saved,"--platform");h_add(saved,sf_platform);}h_add(saved,artifact);h_add(saved,"-o");h_add(saved,t_binary);h_ok(saved);h_check(h_run(h_args(t_binary,0,0,0,0,0)),42,"");t_checks=t_checks+1;return 0;
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
    sf_routes(10000,1);
    // Compile the same graph through every CPU machine-code emitter. Their
    // function tables use full-word indices; device execution is tested by
    // the platform suites where a host/device is available.
    let targets=h_args("linux-arm64","esp32-elf","esp32s3-elf","esp32c3-elf","esp32c6-elf",0);let target=0;
    while target<h_count(targets) {sf_compile(t_fixture,h_at(targets,target),h_join(t_work,h_at(targets,target)));t_checks=t_checks+1;target=target+1;}
    sf_routes(16384,1);
    sf_reject(16385,0,"too many SetaScript functions (maximum 16384)");
    sf_reject(10000,1,"SetaScript recursion is not allowed");
    // Fill both tables: 16,384 FIR functions plus 2,048 trusted definitions.
    // The high-index import and leaf exercise import binding and JIT caches;
    // Wasm calls and its allocator now require three-byte unsigned LEB indices.
    let platform=h_buffer();let i=0;while i<2047 {h_text(platform,h_cat3("fn p",h_int(i),"(){return 21;}\n"));i=i+1;}
    h_text(platform,"fn f16382(){return p2046();}\n");sf_platform=h_join(t_work,"platform.flex");h_save(sf_platform,h_data(platform));
    sf_routes(16384,0);sf_platform=0;
    return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
