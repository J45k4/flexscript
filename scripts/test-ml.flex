import "lib/build.flex";
import "lib/harness.flex";
import "../libs/ml/tests/cases.flex";
import "../libs/ml/cuda.flex";
global tm_gpu=0;
global tm_device_runs=0;
fn tm_bad(body,message) {
    t_program(h_cat3("import \"",h_real("libs/ml/ml.flex"),h_cat3("\";fn main(){",body,"return 0;}")));
    t_compile();let result=h_run(h_args(t_binary,0,0,0,0,0));h_check(result,1,0);
    t_assert(h_has(h_err(result),message),h_err(result));return 0;
}
fn tm_cuda(status) {if status {h_assert(0,cuda_error());}return 0;}
fn tm_gpu_case(path) {
    let context=cuda_context();tm_cuda(cuda_status);let module=cuda_module(h_read(path));tm_cuda(cuda_status);
    let ctx=ml_context(1048576);let a=ml_tensor(ctx,17,5,1);let b=ml_tensor(ctx,5,9,1);let i=0;
    while i<ml_size(a) {ml_set(a,i,f64_div(f64_from_i64(i%7-3),f64_from_i64(8)));i=i+1;}
    i=0;while i<ml_size(b) {ml_set(b,i,f64_div(f64_from_i64(i%5-2),f64_from_i64(4)));i=i+1;}
    let expected=ml_matmul(a,b);let used=ml_used(ctx);let result=ml_cuda_matmul(module,a,b);
    t_assert(ml_used(ctx)==used+128+ml_size(result)*16,"GPU temporary packing storage reclaimed");
    i=0;while i<ml_size(result) {t_assert(ml_get(result,i)==ml_get(expected,i),"GPU matmul matches CPU");i=i+1;}
    let saved=ml_alloc(ctx,ml_size(a)*8);let saved_b=ml_alloc(ctx,ml_size(b)*8);ml_backward(ml_sum(expected));i=0;
    while i<ml_size(a) {store64(saved+i*8,ml_grad(a,i));i=i+1;}
    i=0;while i<ml_size(b) {store64(saved_b+i*8,ml_grad(b,i));i=i+1;}
    ml_backward(ml_sum(result));i=0;while i<ml_size(a) {t_assert(ml_grad(a,i)==load64(saved+i*8),"GPU output participates in reverse graph");i=i+1;}
    i=0;while i<ml_size(b) {t_assert(ml_grad(b,i)==load64(saved_b+i*8),"GPU right-operand gradient");i=i+1;}
    tm_cuda(cuda_unload(module));tm_cuda(cuda_close(context));tm_device_runs=tm_device_runs+1;return 0;
}
fn suite(compiler) {
    t_init(compiler);h_timeout=120000;
    t_checks=t_checks+mlt_suite();
    let source=h_real("libs/ml/tests/core.flex");h_compile(t_compiler,source,t_binary);
    h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,"");t_assert(1,"native ML core");
    let args=h_args(t_compiler,"run","--restricted","--interpret","--fuel=1000000000","--timeout-ms=90000");h_add(args,source);
    h_check(h_run(args),0,"");t_assert(1,"interpreted ML core");
    args=h_args(t_compiler,"run","--restricted","--jit","--stats","--fuel=1000000000");h_add(args,"--timeout-ms=90000");h_add(args,source);
    let process=h_run(args);h_check(process,0,0);t_assert(!h_has(h_err(process),"JIT compilations: 0;"),"ML core uses real JIT");
    let wasm=h_join(t_work,"ml.wasm");h_ok(h_args(t_compiler,"--target","wasm32",source,"-o",wasm));
    let request=j_object();j_set(request,"module",j_string(wasm));let request_path=h_join(t_work,"wasm.json");j_save(request_path,request);
    let result=j_parse(h_out(h_ok(h_args(h_executable("bun"),"scripts/wasm-runner.js",request_path,0,0,0))));
    t_assert(j_n(result,"valid") && !j_get(result,"error") && h_equal(j_s(result,"result"),"0"),"WASM ML core");
    h_compile(t_compiler,"libs/ml/examples/xor.flex",t_binary);process=h_run(h_args(t_binary,0,0,0,0,0));h_check(process,0,0);
    t_assert(h_has(h_out(process),"XOR: 4/4 correct"),"two-layer network learns XOR");
    tm_bad("let c=ml_context(256);ml_tensor(c,3,3,1);","arena exhausted");
    tm_bad("let c=ml_context(4096);ml_tensor(c,9223372036854775807,2,0);","shape exceeds");
    tm_bad("let c=ml_context(4096);ml_tensor(c,0,2,0);","dimensions must be positive");
    tm_bad("let c=ml_context(4096);let a=ml_tensor(c,2,2,0);ml_get(a,4);","index out of bounds");
    tm_bad("let c=ml_context(4096);ml_add(ml_tensor(c,2,2,0),ml_tensor(c,3,2,0));","broadcast dimensions");
    tm_bad("let c=ml_context(4096);ml_matmul(ml_tensor(c,2,3,0),ml_tensor(c,2,2,0));","matrix dimensions");
    tm_bad("let c=ml_context(4096);ml_reshape(ml_tensor(c,2,3,0),9223372036854775807,2);","reshape changes");
    tm_bad("ml_add(ml_scalar(ml_context(4096),0,0),ml_scalar(ml_context(4096),0,0));","different contexts");
    tm_bad("let c=ml_context(4096);ml_backward(ml_tensor(c,2,2,1));","scalar loss");
    tm_bad("ml_backward(ml_scalar(ml_context(4096),0,0));","does not require gradients");
    tm_bad("let c=ml_context(4096);let a=ml_scalar(c,0,1);let b=ml_square(a);ml_set(a,0,1);ml_backward(b);","changed after forward");
    tm_bad("let c=ml_context(4096);let a=ml_scalar(c,0,1);ml_set(ml_square(a),0,1);","only leaf tensors");
    tm_bad("let c=ml_context(4096);ml_sgd(ml_scalar(c,0,0),0);","trainable leaf");
    tm_bad("let c=ml_context(4096);ml_sgd(ml_scalar(c,0,1),f64_nan());","learning rate");
    let targets=h_args("ptx","sass-sm75",0,0,0,0);let i=0;
    while i<2 {
        let path=h_join(t_work,"matmul.kernel");h_ok(h_args(t_compiler,"--target",h_at(targets,i),"libs/ml/kernels/matmul.flex","-o",path));
        t_assert(1,"ML matmul kernel compiles");if tm_gpu {tm_gpu_case(path);}i=i+1;
    }return t_checks;
}
fn main(argc,argv) {
    h_environment(argc,argv);let i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {tm_gpu=1;}i=i+1;}
    suite(b_option(argc,argv,"--compiler","build/flex-transform"));let report=j_object();j_set(report,"checks",j_int(t_checks));j_set(report,"device_runs",j_int(tm_device_runs));
    let path=b_option(argc,argv,"--report",0);if path {j_save(path,report);}t_done();return 0;
}
