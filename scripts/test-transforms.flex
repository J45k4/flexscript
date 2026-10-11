import "lib/build.flex";
import "lib/harness.flex";
import "../lib/cuda.flex";
import "../lib/gpu.flex";
global tt_bun=0;
global tt_gpu=0;
global tt_runs=0;
fn tt_assert(ok,message) {
    if !ok {h_print(2,h_cat3("Transform test: ",message,"\n"));syscall(231,1,0,0,0,0,0);}t_checks=t_checks+1;return 0;
}
fn tt_cuda(status) {if status {h_print(2,cuda_error());syscall(231,1,0,0,0,0,0);}return 0;}
fn tt_extension(body) {
    let path=h_join(t_work,"extension.flex");
    h_save(path,h_cat3("import \"",h_real("compiler/transform-sdk.flex"),h_cat("\";\n",body)));return path;
}
fn tt_source(extension,body) {return h_cat3(h_cat3("extend \"",extension,"\";\n"),body,"\n");}
fn tt_wasm(module,expected) {
    let request=j_object();j_set(request,"module",j_string(module));let path=h_join(t_work,"wasm.json");j_save(path,request);
    let result=j_parse(h_out(h_ok(h_args(tt_bun,"scripts/wasm-runner.js",path,0,0,0))));
    tt_assert(j_n(result,"valid") && !j_get(result,"error"),"transformed WebAssembly executes");
    tt_assert(h_equal(j_s(result,"result"),h_int(expected)),"transformed WebAssembly result");return 0;
}
fn tt_routes(text,expected) {
    t_program(text);let hash=h_sha(t_fixture);
    h_compile(t_compiler,t_fixture,t_binary);h_check(h_run(h_args(t_binary,0,0,0,0,0)),expected,"");tt_assert(1,"transformed native result");
    h_check(h_run(h_args(t_compiler,"run","--interpret","--restricted",t_fixture,0)),expected,"");tt_assert(1,"transformed interpreted result");
    let p=h_run(h_args(t_compiler,"run","--jit","--stats","--restricted",t_fixture));h_check(p,expected,0);
    tt_assert(!h_has(h_err(p),"JIT compilations: 0;"),"transformed code runs in real JIT");
    let module=h_join(t_work,"transformed.wasm");h_ok(h_args(t_compiler,"--target","wasm32",t_fixture,"-o",module));tt_wasm(module,expected);
    tt_assert(h_equal(hash,h_sha(t_fixture)),"extensions do not modify source files");return 0;
}
fn tt_bad(text,message) {
    t_program(text);let before=h_sha(t_binary);let p=h_run(h_args(t_compiler,t_fixture,"-o",t_binary,0,0));h_check(p,1,0);
    tt_assert(h_has(h_err(p),message),h_err(p));tt_assert(t_location(h_err(p)),"located transformation error");
    tt_assert(h_equal(before,h_sha(t_binary)),"failed transformation preserves output");return 0;
}
fn tt_ad(width,definition,argument,expected,extra) {
    let source=h_cat3("import \"",h_real("lib/gpu.flex"),"\";\n");
    source=h_cat(source,h_cat3("extend \"",h_real("extensions/autodiff.flex"),h_cat3("\" with \"f",h_int(width),":loss\";\n")));
    source=h_cat(source,h_cat(extra,definition));
    source=h_cat(source,h_cat3("fn main(){let value=loss_grad(",h_int(argument),h_cat3(");if value==",h_int(expected),"{return 42;}return 1;}")));
    tt_routes(source,42);return 0;
}
fn tt_gpu_case(source,kind) {
    t_program(source);let target=h_args("ptx","sass-sm75",0,0,0,0);let t=0;
    while t<2 {
        let path=h_join(t_work,"transformed.kernel");h_ok(h_args(t_compiler,"--target",h_at(target,t),t_fixture,"-o",path));tt_assert(1,"transformed GPU kernel compiles");
        if tt_gpu {
            let context=cuda_context();tt_cuda(cuda_status);let module=cuda_module(h_read(path));tt_cuda(cuda_status);
            let input=alloc(2048);let output=alloc(2048);let i=0;while i<256 {store64(input+i*8,i-128);i=i+1;}
            let a=cuda_buffer(2048);tt_cuda(cuda_status);let b=cuda_buffer(2048);tt_cuda(cuda_status);
            tt_cuda(cuda_upload(a,input,2048));tt_cuda(cuda_launch(module,a,b,256));tt_cuda(cuda_download(output,b,2048));
            i=0;while i<256 {
                let expected=(i-128)*9+28;if kind==1 {expected=gpu_f64_from_i64((i-128)*2+3);}
                else if kind==2 {expected=gpu_f32_from_i64((i-128)*2+3);}
                else if kind==3 {expected=f64_div(0x3ff0000000000000,f64_from_i64(8*(i+1)));}
                tt_assert(load64(output+i*8)==expected,"transformed GPU result");i=i+1;
            }
            tt_cuda(cuda_free(b));tt_cuda(cuda_free(a));tt_cuda(cuda_unload(module));tt_cuda(cuda_close(context));tt_runs=tt_runs+1;
        }t=t+1;
    }return 0;
}
fn suite(compiler) {
    t_init(compiler);
    // Fixture is elsewhere, so example-relative extension paths become absolute.
    let compose=h_real("extensions/compose.flex");let declaration=h_cat3("extend \"",compose,"\" with \"step\";\n");
    tt_routes(h_cat(declaration,"fn step(x){return x+7;}fn main(){return step_twice(28);}"),42);
    tt_routes(h_cat3(declaration,h_cat3("extend \"",compose,"\" with \"step_twice\";\n"),"fn step(x){return x+7;}fn main(){return step_twice_twice(14);}"),42);
    let extension=tt_extension("fn transform_program(ctx,version){ext_init(ctx,version);let f=ext_find_function(\"step\");if ext_function_arity(f)!=1 || ext_function_effects(f) || load8(ext_function_source(f)+ext_function_size(f)-1)!=125 {ext_error(\"metadata mismatch\");}ext_replace_function(f,\"fn step(x){return x+20;}\");return ext_finish();}");
    tt_routes(tt_source(extension,"fn step(x){return x+1;}\n// This comment belongs to main.\nfn main(){return step(22);}"),42);
    extension=tt_extension("fn transform_syntax(ctx,version){ext_init(ctx,version);let m=ext_request_module();let text=ext_module_text(m);let i=ext_module_declarations(m);while i<ext_module_size(m)-6 {if load8(text+i)==64 {ext_edit(m,i,i+7,\"42\",2);}i=i+1;}return ext_finish();}fn transform_program(ctx,version){ext_init(ctx,version);let f=ext_find_function(\"main\");if ext_op(f,1)!=1 || ext_arg(f,1)!=42 {ext_error(\"syntax hook did not run first\");}return ext_finish();}");
    tt_routes(tt_source(extension,"fn main(){return @answer;}"),42);
    extension=tt_extension("fn transform_program(ctx,version){ext_init(ctx,version);ext_replace_function(ext_find_function(\"b\"),\"fn b(){return 22;}\");ext_replace_function(ext_find_function(\"a\"),\"fn a(){return 20;}\");return ext_finish();}");
    tt_routes(tt_source(extension,"fn a(){return 1;}fn b(){return 2;}fn main(){return a()+b();}"),42);
    let helper=h_join(t_work,"helper.flex");h_save(helper,h_cat(declaration,"fn step(x){return x+7;}"));
    tt_routes("import \"helper.flex\";import \"./helper.flex\";fn main(){return step_twice(28);}",42);
    let portable=h_read("examples/transforms/portable.flex");portable=h_replace(portable,"../../lib/f64.flex",h_real("lib/f64.flex"));portable=h_replace(portable,"../../extensions/autodiff.flex",h_real("extensions/autodiff.flex"));tt_routes(portable,42);
    tt_ad(64,"fn loss(x){let y=gpu_f64_mul(x,x);return gpu_f64_add(y,gpu_f64_mul(gpu_f64_from_i64(3),x));}",0x4000000000000000,0x401c000000000000,"");
    tt_ad(32,"fn loss(x){return gpu_f32_add(gpu_f32_mul(x,x),gpu_f32_mul(gpu_f32_from_i64(3),x));}",0x40000000,0x40e00000,"");
    tt_ad(64,"fn loss(x){return gpu_f64_div(x,0x4010000000000000);}",0x4000000000000000,0x3fd0000000000000,"");
    tt_ad(32,"fn loss(x){return gpu_f32_sqrt(x);}",0x40800000,0x3e800000,"");
    tt_ad(64,"fn loss(x){return gpu_f64_sub(x,gpu_f64_mul(x,x));}",0x4000000000000000,0xc008000000000000,"");
    tt_ad(64,"fn loss(x){return gpu_f64_sqrt(0);}",0x4000000000000000,0,"");
    tt_ad(64,"fn loss(x){return cube(x);}",0x4000000000000000,0x4028000000000000,"fn cube(x){return gpu_f64_mul(gpu_f64_mul(x,x),x);}fn cube_jvp(x,dx){return gpu_f64_mul(gpu_f64_mul(gpu_f64_from_i64(3),gpu_f64_mul(x,x)),dx);}");
    tt_ad(64,"fn loss(x){return mix(x,x);}",0x4000000000000000,0x4010000000000000,"fn mix(a,b){return gpu_f64_mul(a,b);}fn mix_jvp(a,da,b,db){return gpu_f64_add(gpu_f64_mul(a,db),gpu_f64_mul(da,b));}");
    let gpu=h_cat(declaration,"fn step(x){return x*3+7;}fn kernel(i,a,b,n){store64(b+i*8,step_twice(load64(a+i*8)));return 0;}");tt_gpu_case(gpu,0);
    let ad=h_read("examples/transforms/autodiff.flex");ad=h_replace(ad,"../../lib/gpu.flex",h_real("lib/gpu.flex"));ad=h_replace(ad,"../../extensions/autodiff.flex",h_real("extensions/autodiff.flex"));tt_gpu_case(ad,1);
    // FMA primal and derivative execute as actual GPU intrinsics.
    ad=h_replace(ad,"gpu_f64_add(square,gpu_f64_mul(gpu_f64_from_i64(3),x))","gpu_f64_fma(x,x,gpu_f64_mul(gpu_f64_from_i64(3),x))");tt_gpu_case(ad,1);
    let single=h_read("examples/transforms/autodiff.flex");single=h_replace(single,"../../lib/gpu.flex",h_real("lib/gpu.flex"));single=h_replace(single,"../../extensions/autodiff.flex",h_real("extensions/autodiff.flex"));
    single=h_replace(single,"f64:","f32:");single=h_replace(single,"gpu_f64_","gpu_f32_");tt_gpu_case(single,2);
    let rooted=h_replace(ad,"gpu_f64_fma(x,x,gpu_f64_mul(gpu_f64_from_i64(3),x))","gpu_f64_sqrt(gpu_f64_div(x,0x4010000000000000))");
    rooted=h_replace(rooted,"gpu_f64_from_i64(i-128)","gpu_f64_from_i64(4*(i+1)*(i+1))");tt_gpu_case(rooted,3);
    extension=tt_extension("fn transform_program(ctx,version){ext_init(ctx,version);ext_append(ext_request_module(),\"fn broken(){return missing;}\");return ext_finish();}");
    tt_bad(tt_source(extension,"fn main(){return 42;}"),"undefined variable");
    extension=tt_extension("fn transform_program(ctx,version){ext_init(ctx,version);ext_edit(0,0,0,\"x\",1);return ext_finish();}");tt_bad(tt_source(extension,"fn main(){return 42;}"),"cannot edit module imports");
    extension=tt_extension("fn transform_program(ctx,version){ext_init(ctx,version);let s=ext_module_declarations(0);ext_edit(0,s,s+4,\"x\",1);ext_edit(0,s+1,s+3,\"y\",1);return ext_finish();}");tt_bad(tt_source(extension,"fn main(){return 42;}"),"overlapping transformation edits");
    extension=tt_extension("fn transform_program(ctx,version){return 1;}");tt_bad(tt_source(extension,"fn main(){return 42;}"),"invalid result pointer");
    extension=tt_extension("fn transform_program(ctx,version){ext_init(ctx,version);let result=ext_finish();store64(result,0);return result;}");tt_bad(tt_source(extension,"fn main(){return 42;}"),"invalid transformation result");
    extension=tt_extension("fn transform_program(ctx){return 0;}");tt_bad(tt_source(extension,"fn main(){return 42;}"),"hook must take context and version");
    extension=tt_extension("fn main(){return 0;}");tt_bad(tt_source(extension,"fn main(){return 42;}"),"extension must export");
    extension=tt_extension("fn transform_program(ctx,version){syscall(39,0,0,0,0,0,0);return 0;}");tt_bad(tt_source(extension,"fn main(){return 42;}"),"capability, budget or early exit");
    extension=tt_extension("fn transform_program(ctx,version){ffi_open(\"libc.so.6\");return 0;}");tt_bad(tt_source(extension,"fn main(){return 42;}"),"capability, budget or early exit");
    extension=tt_extension("fn transform_program(ctx,version){while 1 {}return 0;}");tt_bad(tt_source(extension,"fn main(){return 42;}"),"capability, budget or early exit");
    // Output aliases must not truncate the extension or any of its imports.
    extension=tt_extension("fn transform_program(ctx,version){ext_init(ctx,version);return ext_finish();}");
    t_program(tt_source(extension,"fn main(){return 42;}"));let hash=h_sha(extension);
    let alias=h_join(t_work,"alias.flex");h_ok(h_args("ln",extension,alias,0,0,0));
    let p=h_run(h_args(t_compiler,t_fixture,"-o",alias,0,0));h_check(p,1,0);
    tt_assert(h_has(h_err(p),"output refers to a transformation source file") && h_equal(hash,h_sha(extension)),"extension output alias preserves source");
    let dependency=h_join(t_work,"rules.flex");h_save(dependency,"fn unused_rule(){return 0;}");
    let body=h_read(extension);h_save(extension,h_cat3("import \"rules.flex\";\n",body,"\n"));
    hash=h_sha(dependency);p=h_run(h_args(t_compiler,t_fixture,"-o",dependency,0,0));h_check(p,1,0);
    tt_assert(h_has(h_err(p),"output refers to a transformation source file") && h_equal(hash,h_sha(dependency)),"extension imports are protected outputs");
    extension=tt_extension(h_cat3("extend \"",compose,"\" with \"step\";fn transform_program(ctx,version){return 0;}"));
    tt_bad(tt_source(extension,"fn main(){return 42;}"),"extensions cannot load nested extensions");
    let prefix=h_cat3("import \"",h_real("lib/gpu.flex"),h_cat3("\";extend \"",h_real("extensions/autodiff.flex"),"\" with \"f64:loss\";"));
    tt_bad(h_cat(prefix,"fn loss(x){return x*x;}fn main(){return 0;}"),"integer arithmetic on active float bits");
    tt_bad(h_cat(prefix,"fn loss(x){if x {return x;}return 0;}fn main(){return 0;}"),"only straight-line arithmetic");
    tt_bad(h_cat(prefix,"fn loss(x){return load64(x);}fn main(){return 0;}"),"memory, global effects");
    tt_bad(h_cat(prefix,"fn loss(x){return gpu_f64_from_i64(x);}fn main(){return 0;}"),"active integer conversions");
    tt_ad(64,"fn loss(x){return gpu_f64_from_i64(x);}",2,0,"fn gpu_f64_from_i64_jvp(x,dx){return 0;}");
    return t_checks;
}
fn main(argc,argv) {
    h_environment(argc,argv);tt_bun=h_executable("bun");h_assert(tt_bun,"Bun is required for WASM transformation tests");
    let i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {tt_gpu=1;}i=i+1;}
    suite(b_option(argc,argv,"--compiler","build/flex-transform"));let report=j_object();j_set(report,"checks",j_int(t_checks));j_set(report,"device_runs",j_int(tt_runs));
    let path=b_option(argc,argv,"--report",0);if path {j_save(path,report);}t_done();return 0;
}
