import "lib/build.flex";
import "lib/harness.flex";
import "../libs/ml/pup/tests/cases.flex";
import "../libs/ml/pup/runtime.flex";
global tp_gpu=0;
global tp_runs=0;
global tp_frontend=0;
global tp_mnist_runs=0;
fn tp_args(source,target,output) {
    let args=h_args(t_compiler,"--frontend",tp_frontend,0,0,0);
    if target {h_add(args,"--target");h_add(args,target);}h_add(args,source);h_add(args,"-o");h_add(args,output);return args;
}
fn tp_bad(text,message,target) {
    h_save(t_fixture,text);h_save(t_binary,"preserve existing artifact");let before=h_sha(t_binary);
    let result=h_run(tp_args(t_fixture,target,t_binary));h_check(result,1,0);
    t_assert(h_has(h_err(result),message),h_err(result));t_assert(t_location(h_err(result)),"located frontend diagnostic");
    t_assert(h_equal(before,h_sha(t_binary)),"frontend error preserves output");return 0;
}
fn tp_wasm(module,expected) {
    let request=j_object();j_set(request,"module",j_string(module));let path=h_join(t_work,"wasm.json");j_save(path,request);
    let result=j_parse(h_out(h_ok(h_args(h_executable("bun"),"scripts/wasm-runner.js",path,0,0,0))));
    t_assert(j_n(result,"valid") && !j_get(result,"error") && h_equal(j_s(result,"result"),h_int(expected)),"WASM reference/source frontend");return 0;
}
fn tp_plugin(source,extra) {
    let path=h_join(t_work,"frontend.flex");
    let body=h_cat3("import \"",h_real("compiler/source-sdk.flex"),"\";fn frontend_compile(text,size,version,path){let blob=frontend_source(");
    body=h_cat(body,j_dump(j_string(source)));body=h_cat3(body,",",h_int(h_len(source)));body=h_cat3(body,");",extra);
    h_save(path,h_cat(body,"return blob;}"));
    tp_frontend=path;return path;
}
fn tp_source_frontend() {
    let source="global x=41;fn add(x){return x+1;}fn main(){let p=alloc(8);store64(p,add(x));return load64(p)+load8(\"ok\")-111;}";
    tp_plugin(source,"");h_save(t_fixture,"arbitrary domain input");
    h_ok(tp_args(t_fixture,0,t_binary));h_check(h_run(h_args(t_binary,0,0,0,0,0)),42,"");t_assert(1,"FSX1 native uses normal native compiler");
    let modes=h_args("--interpret","--jit",0,0,0,0);let i=0;
    while i<2 {let args=h_args(t_compiler,"run",h_at(modes,i),"--restricted","--frontend",tp_frontend);h_add(args,t_fixture);h_check(h_run(args),42,"");t_assert(1,"FSX1 VM route");i=i+1;}
    let wasm=h_join(t_work,"source.wasm");h_ok(tp_args(t_fixture,"wasm32",wasm));tp_wasm(wasm,42);
    tp_bad("input","requires portable FIR","ir");
    tp_plugin(source,"store64(blob+32,1);");tp_bad("input","invalid source frontend result",0);
    tp_plugin(source,"store64(blob+16,72);");tp_bad("input","invalid source frontend result",0);
    tp_plugin(source,"store64(blob+24,1);");tp_bad("input","invalid source frontend result",0);
    tp_plugin(source,"store8(blob+64,0);");tp_bad("input","contains a zero byte",0);
    tp_plugin("import \"/etc/passwd\";fn main(){return 0;}","");tp_bad("input","imports must precede declarations",0);
    tp_plugin("extend \"/etc/passwd\";fn main(){return 0;}","");tp_bad("input","expected global or function definition",0);
    tp_plugin("fn main(){return missing();}","");tp_bad("input","undefined function",0);
    tp_plugin(source,"syscall(2,path,0,0,0,0,0);");tp_bad("input","frontend execution failed",0);
    tp_plugin(source,"");let before=h_sha(tp_frontend);let result=h_run(tp_args(t_fixture,0,tp_frontend));h_check(result,1,0);
    t_assert(h_has(h_err(result),"frontend source file") && h_equal(before,h_sha(tp_frontend)),"FSX1 protects frontend source identity");
    let sdk=h_join(t_work,"sdk.flex");let alias=h_join(t_work,"sdk-alias.flex");h_save(sdk,h_read("compiler/source-sdk.flex"));
    h_save(tp_frontend,h_replace(h_read(tp_frontend),h_real("compiler/source-sdk.flex"),sdk));
    t_assert(syscall(86,sdk,alias,0,0,0,0)==0,"create frontend dependency hardlink fixture");before=h_sha(sdk);
    result=h_run(tp_args(t_fixture,0,alias));h_check(result,1,0);
    t_assert(h_has(h_err(result),"frontend source file") && h_equal(before,h_sha(sdk)),"FSX1 protects aliased frontend dependencies");
    let original=h_sha(t_fixture);result=h_run(tp_args(t_fixture,0,t_fixture));h_check(result,1,0);t_assert(h_equal(original,h_sha(t_fixture)),"FSX1 protects original domain input");
    tp_frontend=h_real("examples/extensions/postfix.flex");tp_bad("10 4 - 7 *","source frontend result","sass-sm75");
    return 0;
}
fn tp_close(status) {if status {h_assert(0,cuda_error());}return 0;}
fn tp_device(path,special) {
    let context=cuda_context();tp_close(cuda_status);let module=cuda_module(h_read(path));tp_close(cuda_status);
    let run=pup_gpu_open(module);let memory=alloc(pg_words*8);let i=0;
    while i<pg_param_count {let v=load64(pg_params+i*8);let data=memory+load64(v+64)*8;let j=0;
        while j<pg_size(v) {let value=gpu_f32_div(gpu_f32_from_i64((j*7+i*3)%17-8),gpu_f32_from_i64(8));
            if special {if j%4==0 {value=0x7fa00001;}else if j%4==1 {value=0x80000000;}else if j%4==2 {value=0;}else {value=0xff800000;}}
            store64(data+j*8,value);j=j+1;
        }pup_gpu_bind(run,v,data,pg_size(v));i=i+1;
    }
    pg_execute(memory);pup_gpu_execute(run);i=0;
    while i<pg_output_count {let v=load64(pg_outputs+i*8);let actual=alloc(pg_size(v)*8);pup_gpu_read(run,i,actual);let j=0;
        while j<pg_size(v) {let a=load64(actual+j*8);let b=load64(memory+(load64(v+64)+j)*8);
            let same=a==b;if !same && !special {let x=gpu_f32_unpack(a);let y=gpu_f32_unpack(b);
                let tolerance=f64_mul(f64_div(f64_from_i64(1),f64_from_i64(1000000)),f64_add(f64_from_i64(1),f64_magnitude(y)));
                same=f64_is_finite(x) && f64_le(f64_magnitude(f64_sub(x,y)),tolerance);
            }t_assert(same,h_cat3("GPU graph output mismatch ",h_int(i),h_cat(":",h_int(j))));j=j+1;
        }i=i+1;
    }
    pup_gpu_close(run);tp_close(cuda_unload(module));tp_close(cuda_close(context));tp_runs=tp_runs+1;return 0;
}
fn tp_kernel(text,special) {
    h_save(t_fixture,text);pup_parse(text,h_len(text),t_fixture);let targets=h_args("sass-sm75","ptx",0,0,0,0);let i=0;
    while i<2 {let path=h_join(t_work,"model.kernel");h_ok(tp_args(t_fixture,h_at(targets,i),path));t_assert(1,"Pup compiles through normal GPU backend");
        if tp_gpu {tp_device(path,special);}i=i+1;
    }return 0;
}
fn tp_tensor(fields,name,shape,begin,end) {
    let item=j_object();j_set(item,"dtype",j_string("F32"));j_set(item,"shape",shape);let offsets=j_array();j_push(offsets,j_int(begin));j_push(offsets,j_int(end));j_set(item,"data_offsets",offsets);j_set(fields,name,item);return 0;
}
fn tp_shape(a,b) {let shape=j_array();j_push(shape,j_int(a));if b {j_push(shape,j_int(b));}return shape;}
fn tp_be32(p,value) {store8(p,value>>24);store8(p+1,value>>16);store8(p+2,value>>8);store8(p+3,value);return 0;}
fn tp_mnist() {
    // A known classifier: zero weights and a positive bias for class three.
    // 129 rows exercise a full batch and a padded tail without external assets.
    let fields=j_object();tp_tensor(fields,"b1",tp_shape(64,0),0,256);tp_tensor(fields,"b2",tp_shape(10,0),256,296);
    tp_tensor(fields,"w1",tp_shape(784,64),296,201000);tp_tensor(fields,"w2",tp_shape(64,10),201000,203560);
    let header=j_dump(fields);let size=h_len(header);let checkpoint=alloc(8+size+203560);store64(checkpoint,size);pg_copy(checkpoint+8,header,size);
    let bias=checkpoint+8+size+256+3*4;store8(bias+2,128);store8(bias+3,63);
    let weights=h_join(t_work,"weights.safetensors");h_save_bytes(weights,checkpoint,8+size+203560,420);
    let images=alloc(16+129*784);tp_be32(images,2051);tp_be32(images+4,129);tp_be32(images+8,28);tp_be32(images+12,28);
    let labels=alloc(8+129);tp_be32(labels,2049);tp_be32(labels+4,129);let i=0;while i<129 {store8(labels+8+i,3);i=i+1;}
    let image_path=h_join(t_work,"images.idx");let label_path=h_join(t_work,"labels.idx");h_save_bytes(image_path,images,16+129*784,420);h_save_bytes(label_path,labels,8+129,420);
    let runner=h_join(t_work,"mnist-infer");h_compile(t_compiler,"scripts/mnist-infer.flex",runner);let report=h_join(t_work,"mnist.json");
    let args=h_args(runner,"--compiler",t_compiler,"--checkpoint",weights,"--images");h_add(args,image_path);h_add(args,"--labels");h_add(args,label_path);
    h_add(args,"--verify-reference");h_add(args,"0");h_add(args,"--min-accuracy-bps");h_add(args,"10000");h_add(args,"--report");h_add(args,report);h_add(args,"--output");h_add(args,h_join(t_work,"mnist.cubin"));
    h_check(h_run(args),0,0);let result=j_parse(h_read(report));
    t_assert(j_n(result,"examples")==129 && j_n(result,"correct")==129 && j_n(result,"accuracy_basis_points")==10000,"MNIST checkpoint loader, argmax and padded tail");tp_mnist_runs=tp_mnist_runs+1;
    store8(labels+8,0);h_save_bytes(label_path,labels,8+129,420);h_add(args,"--limit");h_add(args,"1");let process=h_run(args);h_check(process,1,0);
    t_assert(h_has(h_err(process),"accuracy below"),"MNIST accuracy guard rejects incorrect classifier result");tp_mnist_runs=tp_mnist_runs+1;
    // Keep an invalid tensor header in bounds so shape checking must reject it.
    j_set(j_need(fields,"w1"),"shape",tp_shape(783,64));header=j_dump(fields);size=h_len(header);let bad=alloc(8+size+203560);store64(bad,size);pg_copy(bad+8,header,size);h_save_bytes(weights,bad,8+size+203560,420);
    process=h_run(args);h_check(process,1,0);t_assert(h_has(h_err(process),"tensor shape mismatch"),"MNIST checkpoint shape mismatch rejected");
    store8(bias+2,192);store8(bias+3,127);h_save_bytes(weights,checkpoint,8+load64(checkpoint)+203560,420);
    process=h_run(args);h_check(process,1,0);t_assert(h_has(h_err(process),"nonfinite MNIST logit"),"MNIST rejects nonfinite predictions");tp_mnist_runs=tp_mnist_runs+1;
    h_save_bytes(image_path,images,16,420);process=h_run(args);h_check(process,1,0);t_assert(h_has(h_err(process),"truncated or trailing"),"MNIST truncated IDX rejected");
    return 0;
}
fn suite(compiler) {
    t_init(compiler);h_timeout=120000;t_checks=t_checks+pgt_suite();
    let core=h_real("libs/ml/pup/tests/core.flex");h_compile(t_compiler,core,t_binary);h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,"");t_assert(1,"native primitive reference");
    let modes=h_args("--interpret","--jit",0,0,0,0);let i=0;
    while i<2 {let args=h_args(t_compiler,"run",h_at(modes,i),"--restricted","--fuel=1000000000",core);h_check(h_run(args),0,"");t_assert(1,"VM primitive reference");i=i+1;}
    let wasm=h_join(t_work,"reference.wasm");h_ok(h_args(t_compiler,"--target","wasm32",core,"-o",wasm));tp_wasm(wasm,0);
    tp_source_frontend();tp_frontend=h_real("libs/ml/pup/frontend.flex");
    tp_kernel("a=input(\"a\",[17,5])\nb=input(\"b\",[5,9])\nbias=input(\"bias\",[9])\nz=dense(a,b,bias)\nv=permute(z,[1,0])\ns=reduce(v,add,1)\nr=max(-z/2.0,0.0)+1e-1\noutput z,v,s,r,reduce(z,max,1),a\n",0);
    tp_kernel("a=input(\"a\",[2,1,3])\nb=input(\"b\",[1,4,1])\nx=a+b\noutput x,reduce(x,add,2),permute(x,[2,0,1]),reduce(x,max,3)\n",0);
    tp_kernel("a=reshape(param(7,f32,6),[2,3])\noutput a\n",0);
    tp_kernel("a=input(\"a\",[17])\noutput max(a,-0.0),relu(a),reduce(a,max,1)\n",1);
    tp_kernel("output -1.25e1/2+.5,2*(3+4)\n",0);
    tp_bad("output missing\n","unknown binding",0);tp_bad("x=1\nx=2\noutput x\n","duplicate binding",0);
    tp_bad("a=input(\"a\",[2,3])\nb=input(\"b\",[2])\noutput a+b\n","broadcast",0);
    tp_bad("a=input(\"a\",[2,3])\noutput reshape(a,[5])\n","element count",0);
    tp_bad("a=input(\"a\",[2,3])\noutput permute(a,[1,1])\n","invalid permutation",0);
    tp_bad("output reduce(input(\"a\",[2]),add,2)\n","unsupported reduction",0);
    tp_bad("output input(\"a\",[16777216,2])\n","tensor shape",0);
    tp_bad("output param(0,f32,0)\n","tensor shape",0);tp_bad("output param(0,f32,16777217)\n","static integer",0);
    tp_bad("output param(0,f32,1.5)\n","static integer",0);tp_bad("output param(64,f32,1)\n","slot limit",0);
    tp_bad("a=param(0,f32,1)\nb=param(0,f32,1)\noutput a\n","duplicate parameter",0);
    tp_bad("output reshape(f32,[])\n","tensor operands",0);tp_bad("output -f32\n","tensor operands",0);
    tp_bad("output cast(f32,f32)\n","tensor operands",0);tp_bad("output f32\n","graph outputs",0);
    tp_bad("output exp(1)\n","unsupported operation",0);tp_bad("output 1e100\n","finite f32 range",0);
    tp_bad("output 1e\n","missing numeric exponent",0);tp_bad("x=1\n","missing output",0);
    tp_bad("output 1\nx=2\n","bindings must precede",0);tp_bad("output 1;\n","token after output",0);
    tp_bad(h_cat3("output ",h_repeat("-",65),"1\n"),"unary nesting",0);
    let model=h_real("libs/ml/examples/mnist-inference.pup");let text=h_read(model);pup_parse(text,h_file_size,model);
    t_assert(pg_stage_count==4 && pg_words*8<2000000,"MNIST plan avoids broadcast product storage");
    h_ok(tp_args(model,"sass-sm75",h_join(t_work,"mnist.cubin")));h_ok(tp_args(model,"ptx",h_join(t_work,"mnist.ptx")));t_assert(1,"full MNIST model compiles on both GPU targets");
    if tp_gpu {tp_mnist();}
    return t_checks;
}
fn main(argc,argv) {
    h_environment(argc,argv);let i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {tp_gpu=1;}i=i+1;}
    suite(b_option(argc,argv,"--compiler","build/flex-pup"));let report=j_object();j_set(report,"checks",j_int(t_checks));j_set(report,"device_runs",j_int(tp_runs));
    j_set(report,"mnist_fixture_runs",j_int(tp_mnist_runs));
    let path=b_option(argc,argv,"--report",0);if path {j_save(path,report);}t_done();return 0;
}
