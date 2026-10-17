// Explicit symbol bindings, native/reference routes, extension registration and
// exact IEEE corpora. Run from the Flexscript repository with the new compiler.
import "lib/harness.flex";
fn ln_mode(mode,binary) {return h_ok(h_args(t_compiler,"--lowering-mode",mode,t_fixture,"-o",binary));}
fn ln_run(mode,status) {ln_mode(mode,t_binary);h_check(h_run(h_args(t_binary,0,0,0,0,0)),status,"");t_checks=t_checks+1;return 0;}
fn ln_bad(text,message) {t_program(text);t_reject(t_fixture,t_binary,message);return 0;}
fn ln_corpus() {
    let prefix=h_cat3("import \"",h_real("lib/f32.flex"),"\";\nglobal vectors=0;\n");
    let text=h_cat(prefix,"fn calc(op,a,b){if op==0{return f32_add(a,b);}if op==1{return f32_sub(a,b);}if op==2{return f32_mul(a,b);}if op==3{return f32_div(a,b);}if op==4{return f32_sqrt(a);}if op==5{return gpu_f64_add(a,b);}if op==6{return gpu_f64_sub(a,b);}if op==7{return gpu_f64_mul(a,b);}if op==8{return gpu_f64_div(a,b);}if op==9{return gpu_f64_sqrt(a);}let x=a&4294967295;let y=b&4294967295;let z=(a^b)&4294967295;let u=(a>>32)&4294967295;let v=(b>>32)&4294967295;let w=u^v;if op==10{return f32_dot3(x,y,z,u,v,w);}store64(vectors,x);store64(vectors+8,y);store64(vectors+16,z);store64(vectors+24,u);store64(vectors+32,v);store64(vectors+40,w);return f32_dot3_load(vectors,vectors+24);}\n");
    text=h_cat(text,"fn main(argc,argv){vectors=alloc(48);let fd=syscall(2,load64(argv+8),577,384,0,0,0);if fd<0{return 1;}let p=alloc(8);let seed=12345;let i=0;while i<12000{seed=seed*6364136223846793005+1442695040888963407;let a=seed;seed=seed*6364136223846793005+1442695040888963407;let b=seed;let op=0;while op<12{let x=a;let y=b;if op<5{x=a&4294967295;y=b&4294967295;}store64(p,calc(op,x,y));if syscall(1,fd,p,8,0,0,0)!=8{return 2;}op=op+1;}i=i+1;}syscall(3,fd,0,0,0,0,0);return 0;}");
    t_program(text);let native=h_join(t_work,"native.words");let reference=h_join(t_work,"reference.words");
    ln_mode("hardware",t_binary);h_ok(h_args(t_binary,native,0,0,0,0));
    ln_mode("reference",t_binary);h_ok(h_args(t_binary,reference,0,0,0,0));
    t_assert(h_equal(h_sha(native),h_sha(reference)),"144000 randomized FP32/FP64 results match software exactly");t_checks=t_checks+144000;
    // Existing independently generated oracle also tests signed zero, gradual
    // underflow, infinities, NaNs and rounding boundaries in accelerated FP64.
    let fixture=h_real("tests/tooling/f64-goldens.words");
    text=h_cat(prefix,"fn execute(op,a,b){if op==0{return f64_add(a,b);}if op==1{return f64_sub(a,b);}if op==2{return f64_mul(a,b);}if op==3{return f64_div(a,b);}if op==4{return f64_lt(a,b);}if op==5{return f64_eq(a,b);}if op==6{return f64_le(a,b);}if op==7{return f64_from_i64(a);}if op==8{return f64_to_i64_trunc(a);}if op==9{return f64_to_i64_nearest(a);}if op==10{return f64_to_i64_round(a);}if op==11{return f64_gt(a,b);}if op==12{return f64_ge(a,b);}if op==13{return f64_ne(a,b);}return f64_sqrt(a);}\n");
    text=h_cat3(text,"fn main(){let fd=syscall(2,\"",h_cat(fixture,"\",0,0,0,0,0);let p=alloc(32);let i=0;while i<64498{if syscall(0,fd,p,32,0,0,0)!=32{return 1;}if execute(load64(p),load64(p+8),load64(p+16))!=load64(p+24){return 2;}i=i+1;}return 0;}"));
    t_program(text);ln_run("hardware",0);t_checks=t_checks+64498;
    // Directed FP32 edge cases (including polluted high words and NaN inputs).
    text=h_cat(prefix,"fn main(){if f32_add(0x7f800000,0xff800000)!=0x7fc00000{return 1;}if f32_mul(0,0x7f800000)!=0x7fc00000{return 2;}if f32_div(0,0)!=0x7fc00000{return 3;}if f32_sqrt(0xbf800000)!=0x7fc00000{return 4;}if f32_mul(1,0x3f800000)!=1{return 5;}if f32_add(0x80000000,0x80000000)!=0x80000000{return 6;}if f32_add(0xffffffff3f800000,0xffffffff3f800000)!=0x40000000{return 7;}if f32_sqrt(0x80000000)!=0x80000000{return 8;}return 0;}");
    t_program(text);ln_run("hardware",0);ln_run("reference",0);return 0;
}
fn suite(compiler) {
    t_init(compiler);h_timeout=120000;
    let custom="lowering custom \"word.add\" \"native-x86_64\";fn custom(a,b){return 7;}fn main(){return custom(20,22);}";
    t_program(custom);ln_run("hardware",42);ln_run("reference",7);
    h_check(h_run(h_args(t_compiler,"run","--interpret","--restricted",t_fixture,0)),7,"");t_checks=t_checks+1;
    h_check(h_run(h_args(t_compiler,"run","--jit","--restricted",t_fixture,0)),7,"");t_checks=t_checks+1;
    let wasm=h_join(t_work,"fallback.wasm");h_ok(h_args(t_compiler,"--target","wasm32",t_fixture,"-o",wasm));let request=j_object();j_set(request,"module",j_string(wasm));let path=h_join(t_work,"wasm.json");j_save(path,request);
    let result=j_parse(h_out(h_ok(h_args("bun","scripts/wasm-runner.js",path,0,0,0))));t_assert(j_n(result,"valid") && !j_get(result,"error") && h_equal(j_s(result,"result"),"7"),"Wasm uses portable body");
    t_program("fn f32_add(a,b){return 7;}fn main(){return f32_add(20,22);}");ln_run("hardware",7);
    // Native FIR callers use the registered entry thunk even though platform
    // modules are loaded after FIR instruction emission.
    let platform=h_join(t_work,"platform.flex");h_save(platform,"lowering custom \"word.add\" \"native-x86_64\";fn custom(a,b){return 7;}");
    let seta=h_join(t_work,"main.seta");h_save(seta,"plugin lowering v1 {}\nextern fn custom(a:i32,b:i32)->i32;\nfn main()->i32{return custom(20,22)}\n");
    let args=h_args(t_compiler,"--platform",platform,seta,"-o",t_binary);h_ok(args);h_check(h_run(h_args(t_binary,0,0,0,0,0)),42,"");t_checks=t_checks+1;
    // Syntax extensions can register ordinary user symbols, using the existing
    // source-edit boundary rather than receiving arbitrary code-emission access.
    let extension=h_join(t_work,"extension.flex");let head=h_cat3("import \"",h_real("compiler/transform-sdk.flex"),"\";\n");
    h_save(extension,h_cat(head,"fn transform_syntax(ctx,version){ext_init(ctx,version);let m=ext_request_module();let at=ext_module_declarations(m);let text=\"lowering custom \\\"word.xor\\\" \\\"native-x86_64\\\";\\n\";ext_edit(m,at,at,text,ext_len(text));return ext_finish();}"));
    t_program(h_cat3("extend \"",extension,"\";fn custom(a,b){return a^b;}fn main(){return custom(20,62);}"));ln_run("hardware",42);ln_run("reference",42);
    ln_bad("lowering missing \"f32.add\";fn main(){return 0;}","lowering requires a defined function");
    ln_bad("lowering foo \"f32.add\";fn foo(a){return a;}fn main(){return 0;}","wrong lowering function arity");
    ln_bad("lowering foo \"f32.add\";fn foo(a,b){return a;}fn main(){return foo(1);}","wrong lowering function arity");
    ln_bad("lowering foo \"f32.add\";lowering foo \"f32.mul\";fn foo(a,b){return a;}fn main(){return 0;}","conflicting lowering");
    ln_bad("lowering foo \"f32.nope\";fn main(){return 0;}","unknown lowering operation");
    ln_bad("lowering foo \"word.add\" \"nope\";fn main(){return 0;}","unknown lowering target");
    ln_bad("fn main(){return 0;}lowering foo \"word.add\";", "lowerings must precede functions");
    t_program("lowering custom \"word.add\" \"gpu\";fn custom(a,b){return 7;}fn main(){return custom(20,22);}");ln_run("hardware",7);
    let kernel=h_cat3("import \"",h_real("lib/f32.flex"),"\";\n");
    t_program(h_cat(kernel,"lowering custom \"f32.add\";fn custom(a,b){return f32_add(a,b);}fn kernel(i,input,output,count){if i<count{store64(output+i*8,custom(load64(input+i*8),1065353216));}return 0;}"));
    let targets=h_args("ptx","sass-sm75",0,0,0,0);let t=0;while t<2 {h_ok(h_args(t_compiler,"--target",h_at(targets,t),t_fixture,"-o",t_binary));t_checks=t_checks+1;t=t+1;}
    ln_corpus();return t_done();
}
fn main(argc,argv){return t_entry(argc,argv);}
