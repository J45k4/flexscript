import "lib/build.flex";
import "lib/harness.flex";
global te_bun=0;
global te_frontend=0;
fn te_compile(source,target,out) {
    let args=h_args(t_compiler,0,0,0,0,0);
    if te_frontend {h_add(args,"--frontend");h_add(args,te_frontend);}
    if target {h_add(args,"--target");h_add(args,target);}
    h_add(args,source);h_add(args,"-o");h_add(args,out);h_ok(args);return 0;
}
fn te_wasm(module,expected) {
    let request=j_object();j_set(request,"module",j_string(module));let path=h_join(t_work,"wasm.json");j_save(path,request);
    let result=j_parse(h_out(h_ok(h_args(te_bun,"scripts/wasm-runner.js",path,0,0,0))));
    let message="frontend WebAssembly validation or execution failed";if j_get(result,"error") {message=j_s(result,"error");}
    t_assert(j_n(result,"valid") && !j_get(result,"error"),message);
    t_assert(h_equal(j_s(result,"result"),h_int(expected)),"frontend WebAssembly result");return 0;
}
fn te_routes(source,expected) {
    let args=h_args(t_compiler,"run","--interpret","--restricted",0,0);
    if te_frontend {h_add(args,"--frontend");h_add(args,te_frontend);}h_add(args,source);
    h_check(h_run(args),expected,"");t_checks=t_checks+1;
    args=h_args(t_compiler,"run","--jit","--stats",0,0);
    if te_frontend {h_add(args,"--frontend");h_add(args,te_frontend);}h_add(args,source);
    let jit=h_run(args);h_check(jit,expected,"");
    t_assert(!h_has(h_err(jit),"JIT compilations: 0;"),"extension IR uses the existing JIT");
    te_compile(source,0,t_binary);h_check(h_run(h_args(t_binary,0,0,0,0,0)),expected,"");t_checks=t_checks+1;
    let module=h_join(t_work,"app.wasm");te_compile(source,"wasm32",module);te_wasm(module,expected);
    return 0;
}
fn te_program(text,expected) {h_save(t_fixture,text);te_routes(t_fixture,expected);return 0;}
fn te_bad(source,message) {
    let before=h_sha(t_binary);let args=h_args(t_compiler,0,0,0,0,0);
    if te_frontend {h_add(args,"--frontend");h_add(args,te_frontend);}
    else {h_add(args,"--language");h_add(args,"seta");}
    h_add(args,source);h_add(args,"-o");h_add(args,t_binary);let p=h_run(args);h_check(p,1,0);
    t_assert(h_has(h_err(p),message),h_err(p));t_assert(t_location(h_err(p)),"frontend diagnostic location");
    t_assert(h_equal(before,h_sha(t_binary)),"frontend rejection changed output");return 0;
}
fn te_reject(text,message) {h_save(t_fixture,h_cat("plugin test v1 {}\n",text));te_bad(t_fixture,message);return 0;}
fn te_ir_bad(original,offset,value) {
    let size=load64(original+8);let copy=alloc(size);let i=0;while i<size {store8(copy+i,load8(original+i));i=i+1;}store64(copy+offset,value);
    let path=h_join(t_work,"bad.fir");h_save_bytes(path,copy,size,420);let before=h_sha(t_binary);
    let p=h_run(h_args(t_compiler,"--language","ir",path,"-o",t_binary));h_check(p,1,0);
    t_assert(h_has(h_err(p),"invalid frontend IR"),h_err(p));t_assert(h_equal(before,h_sha(t_binary)),"malformed IR changed output");return 0;
}
fn te_extension(body) {
    let path=h_join(t_work,"parser.flex");let sdk=h_real("compiler/extension-sdk.flex");
    h_save(path,h_cat3("import \"",sdk,h_cat3("\";fn frontend_compile(text,size,version,path){ir_init(text,size,path,version);",body,"}")));
    return path;
}
fn suite(compiler) {
    t_init(compiler);te_bun=h_executable("bun");te_frontend=0;t_fixture=h_join(t_work,"test.seta");
    te_routes("examples/seta/policy.seta",42);
    te_program("plugin test v1 {} fn f(a:i32,b:i32,c:i32)->i32{return a*100+b*10+c} fn main()->i32{return f(0,4,2)}",42);
    te_program("plugin test v1 {} fn main()->i32 {let x=0 for i in -2..3 {for j in 0..4 {x+=i*i+j}} return x-28}",42);
    te_program("plugin test v1 {} fn main()->i32 {let x=7 {let x:bool=true if x {return 42} else {return 1}}}",42);
    te_program("plugin test v1 {} fn leaf(x:bool)->i32{if x {return 42}else if not x {return 0}else{return 1}}fn main()->i32{return leaf(true)}",42);
    te_program("plugin test v1 {} fn main()->i32{let n=0 repeat(6){n+=7} return n}",42);
    te_program("plugin test v1 {} fn main()->i32{let n=42 for i in 0..0 {n=0} return n}",42);
    te_program("plugin test v1 {} fn main()->i32{let n=84 n/=2 n*=3 n-=84 return n}",42);
    te_program("plugin test v1 {} fn main()->i32{return ((-17/5 == -3) and (-17%5 == -2) and (3<<65 == 6) and (-8>>65 == -4) and ((((7&3)^2)|1) == 1)) ? 42 : 0}",42);
    te_program("plugin test v1 {} fn main()->i32{return (false and 1/0==0) or (true or 1/0==0) ? 42 : 0}",42);
    let artifact=h_join(t_work,"policy.fir");te_compile("examples/seta/policy.seta","ir",artifact);
    let original=h_read(artifact);t_assert(load64(original)==0x31524946,"FIR1 artifact magic");
    t_assert(syscall(21,artifact,1,0,0,0,0)!=0,"IR artifact is not executable");
    // A saved frontend result is independently consumable by every backend.
    h_check(h_run(h_args(t_compiler,"run","--language=ir",artifact,0,0)),42,"");t_checks=t_checks+1;
    h_ok(h_args(t_compiler,"--language","ir",artifact,"-o",t_binary));h_check(h_run(h_args(t_binary,0,0,0,0,0)),42,"");t_checks=t_checks+1;
    let module=h_join(t_work,"ir.wasm");let args=h_args(t_compiler,"--target","wasm32","--language","ir",artifact);h_add(args,"-o");h_add(args,module);h_ok(args);te_wasm(module,42);
    // The bundled and externally loaded copies of the Seta frontend emit the same bytes.
    te_frontend="examples/extensions/seta.flex";te_compile("examples/seta/policy.seta","ir",h_join(t_work,"external.fir"));
    t_assert(h_equal(h_sha(artifact),h_sha(h_join(t_work,"external.fir"))),"external and bundled frontend IR identity");
    te_routes("examples/seta/policy.seta",42);
    te_frontend="examples/extensions/postfix.flex";te_routes("examples/extensions/answer.postfix",42);
    te_program("10 4 - 7 *",42);te_frontend=0;
    te_reject("fn main()->i32{return true}","type mismatch");
    te_reject("fn main()->i32{if 1 {return 42}else{return 0}}","type mismatch");
    te_reject("fn main()->i32{let x:bool=1 return 42}","type mismatch");
    te_reject("fn f(x:bool)->i32{return 42}fn main()->i32{return f(1)}","type mismatch");
    te_reject("fn f(x:i32)->i32{return x}fn main()->i32{return f()}","argument count");
    te_reject("fn main()->i32{return main()}","recursion");
    te_reject("fn a()->i32{return b()}fn b()->i32{return a()}fn main()->i32{return 42}","recursion");
    te_reject("fn main()->i32{while true {} return 42}","unbounded while");
    te_reject("fn main()->i32{let n=5 for i in 0..n {} return 42}","bounds must be integer literals");
    te_reject("fn main()->i32{for i in 0..5 {i=4}return 42}","index is read-only");
    te_reject("fn main()->i32{repeat(1000001){}return 42}","bounds exceed");
    te_reject("fn main()->f32{return 42}","only i32 and bool");
    te_reject("fn main()->i32{return 4.2}","floating point");
    te_reject("fn main()->i32{return syscall(60,0,0,0,0,0,0)}","host calls are not supported");
    te_reject("fn main()->i32{let x=1 let x=2 return x}","duplicate SetaScript local");
    te_reject("fn main()->i32{{let x=42}return x}","unknown SetaScript local");
    te_reject("fn main()->i32{if true {return 42}}","return on every path");
    te_reject("actor Foo {} fn main()->i32{return 42}","only pure function");
    te_reject("fn main()->i32{return true ? 42 : false}","type mismatch");
    te_reject("fn main()->i32{return (1 and 2) ? 42 : 0}","type mismatch");
    te_reject("fn main()->i32{return 9223372036854775808}","out of range");
    // Full-width word arithmetic matches the pre-existing SetaScript runtime.
    te_program("plugin test v1 {} fn main()->i32{let n=9223372036854775807+1 return n<0 ? 42 : 0}",42);
    // Malformed artifacts never reach native lowering, the VM or Wasm emission.
    te_ir_bad(original,0,0);te_ir_bad(original,8,63);te_ir_bad(original,16,2049);
    te_ir_bad(original,24,64);te_ir_bad(original,32,-1);te_ir_bad(original,40,0);
    te_ir_bad(original,48,-1);te_ir_bad(original,56,1);te_ir_bad(original,64,-1);
    te_ir_bad(original,72,256);te_ir_bad(original,80,16);te_ir_bad(original,88,4097);
    te_ir_bad(original,96,-1);te_ir_bad(original,104,1);
    let code_at=load64(original+24);te_ir_bad(original,code_at,17);
    te_ir_bad(original,code_at+8,4097);te_ir_bad(original,code_at+16,3);
    te_ir_bad(original,code_at+32,17);te_ir_bad(original,code_at+32,18);te_ir_bad(original,code_at+32,5);
    te_ir_bad(original,code_at+32,7);te_ir_bad(original,code_at+32,10);
    te_ir_bad(original,code_at+32,8);te_ir_bad(original,code_at+40,4097);
    // A jump may only target its own function, with an identical stack height.
    te_ir_bad(original,code_at+32,11);
    te_frontend=te_extension("ir_begin(\"main\",4,0);let skip=ir_emit(11,0);ir_emit(2,0);ir_patch(skip,ir_code_size);ir_emit(1,1);ir_emit(7,43);ir_emit(9,0);ir_end(0);return ir_finish();");
    te_bad("examples/extensions/answer.postfix","invalid frontend IR");
    // Extension execution is restricted even when the resulting app is permissive.
    te_frontend=te_extension("return -1;");te_bad("examples/extensions/answer.postfix","invalid IR pointer");
    te_frontend=te_extension("return alloc(8);");te_bad("examples/extensions/answer.postfix","invalid IR pointer");
    te_frontend=te_extension("ffi_open(\"libc.so.6\");return 0;");te_bad("examples/extensions/answer.postfix","frontend execution failed");
    te_frontend=te_extension("syscall(2,path,0,0,0,0,0);return 0;");te_bad("examples/extensions/answer.postfix","frontend execution failed");
    te_frontend=te_extension("while 1 {} return 0;");te_bad("examples/extensions/answer.postfix","frontend execution failed");
    te_frontend=te_extension("ir_error(\"intentional frontend diagnostic\",2);return 0;");te_bad("examples/extensions/answer.postfix","intentional frontend diagnostic");
    // Also protect extension imports against output hard-link aliases.
    let sdk_copy=h_join(t_work,"sdk-copy.flex");h_save(sdk_copy,h_read("compiler/extension-sdk.flex"));
    te_frontend=h_join(t_work,"alias-parser.flex");h_save(te_frontend,h_cat3("import \"",sdk_copy,"\";fn frontend_compile(text,size,version,path){ir_init(text,size,path,version);ir_begin(\"main\",4,0);ir_emit(1,42);ir_emit(9,0);ir_end(0);return ir_finish();}"));
    let alias=h_join(t_work,"sdk-alias.flex");h_ok(h_args("ln",sdk_copy,alias,0,0,0));let hash=h_sha(alias);
    let p=h_run(h_args(t_compiler,"--frontend",te_frontend,"examples/extensions/answer.postfix","-o",alias));h_check(p,1,0);
    t_assert(h_has(h_err(p),"frontend source file") && h_equal(hash,h_sha(alias)),"output must preserve extension inputs");
    te_frontend=0;return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
