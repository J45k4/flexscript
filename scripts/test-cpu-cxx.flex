// CPU kernel word ABI, source restrictions and independent software oracles.
import "lib/harness.flex";
fn cx_emit(source,output){return h_ok(h_args(t_compiler,"--target","cpu-cxx",source,"-o",output));}
fn cx_link(source,output){
    let args=h_args("clang++","-std=c++17","-O2","-fno-fast-math","-ffp-contract=off","-fno-math-errno");
    h_add(args,"-shared");h_add(args,"-fPIC");h_add(args,source);h_add(args,"-o");h_add(args,output);h_add(args,"-lm");return h_ok(args);
}
fn cx_reject(text,message){
    t_program(text);let source=h_sha(t_fixture);h_save(t_binary,"preserve me");let before=h_sha(t_binary);
    let result=h_run(h_args(t_compiler,"--target","cpu-cxx",t_fixture,"-o",t_binary));
    h_check(result,1,0);t_assert(h_has(h_err(result),message),h_err(result));
    t_assert(h_equal(h_sha(t_fixture),source) && h_equal(h_sha(t_binary),before),"rejection changed source or destination");return 0;
}
fn cx_input(path){
    let edges=h_vec();h_add(edges,0);h_add(edges,1);h_add(edges,0x80000000);h_add(edges,0x7f800000);h_add(edges,0xff800000);h_add(edges,0x7fc12345);h_add(edges,0xff800001);h_add(edges,0x7fffffff);h_add(edges,0x3f800000);h_add(edges,0x00800000);h_add(edges,0x007fffff);h_add(edges,-1);h_add(edges,0x8000000000000000);h_add(edges,0x7ff0000000000000);h_add(edges,0xfff0000000000000);h_add(edges,0x7ff0000000000001);h_add(edges,0xfff8123456789abc);
    let directed=h_count(edges)*h_count(edges);let pairs=directed+12000;let data=h_take(1+pairs*30*24);store8(data,0xa5);let seed=12345;let i=0;
    while i<pairs{let a=0;let b=0;if i<directed{a=h_at(edges,i/h_count(edges));b=h_at(edges,i%h_count(edges));}else{seed=seed*6364136223846793005+1442695040888963407;a=seed;seed=seed*6364136223846793005+1442695040888963407;b=seed;}
        let op=0;while op<30{let r=data+1+(i*30+op)*24;store64(r,op);store64(r+8,a);store64(r+16,b);op=op+1;}i=i+1;
    }h_save_bytes(path,data,1+pairs*30*24,384);return pairs*30;
}
fn suite(compiler){
    t_init(compiler);h_timeout=120000;
    let fixture=h_real("tests/cpu-cxx/corpus.flex");let cpp=h_join(t_work,"kernel.cpp");let library=h_join(t_work,"kernel.so");cx_emit(fixture,cpp);cx_link(cpp,library);
    let input=h_join(t_work,"input.words");let checks=cx_input(input);
    let prefix=h_cat3("import \"",h_real("scripts/lib/host.flex"),"\";\n");
    let host=h_cat3(prefix,"import \"",h_cat(fixture,"\";\nfn main(argc,argv){h_environment(argc,argv);let input=h_read(load64(argv+8));let n=(h_file_size-1)/24;let output=h_take(n*8+1);h_assert(kernel(input+1,output+1,n)==n,\"kernel result\");h_save_bytes(load64(argv+16),output+1,n*8,384);return 0;}"));
    let native=h_join(t_work,"native.words");let reference=h_join(t_work,"reference.words");let optimized=h_join(t_work,"optimized.words");
    t_program(host);h_ok(h_args(t_compiler,"--lowering-mode","hardware",t_fixture,"-o",t_binary));h_ok(h_args(t_binary,input,native,0,0,0));
    h_ok(h_args(t_compiler,"--lowering-mode","reference",t_fixture,"-o",t_binary));h_ok(h_args(t_binary,input,reference,0,0,0));
    host=h_cat(prefix,"fn main(argc,argv){h_environment(argc,argv);let lib=ffi_open(load64(argv+8));h_assert(lib,\"open CPU library\");let abi=ffi_symbol(lib,\"flex_kernel_abi\");let arity=ffi_symbol(lib,\"flex_kernel_arity\");let call=ffi_symbol(lib,\"flex_kernel\");h_assert(abi && arity && call && ffi_call(abi,0,0,0,0,0,0)==1 && ffi_call(arity,0,0,0,0,0,0)==3,\"CPU kernel ABI\");let input=h_read(load64(argv+16));let n=(h_file_size-1)/24;let output=h_take(n*8+1);let math=ffi_open(\"libm.so.6\");let set=ffi_symbol(math,\"fesetround\");let get=ffi_symbol(math,\"fegetround\");h_assert(set && get && !ffi_call(set,1024,0,0,0,0,0),\"set caller rounding\");h_assert(ffi_call(call,input+1,output+1,n,0,0,0)==n,\"kernel count\");h_assert(ffi_call(get,0,0,0,0,0,0)==1024,\"kernel changed caller rounding\");h_assert(!ffi_call(set,0,0,0,0,0,0),\"restore rounding\");h_save_bytes(load64(argv+24),output+1,n*8,384);return 0;}");
    t_program(host);t_compile();h_ok(h_args(t_binary,library,input,optimized,0,0));
    t_assert(h_equal(h_sha(native),h_sha(reference)) && h_equal(h_sha(optimized),h_sha(reference)),"CPU C++ float, packed lane and word corpus differs from software");t_checks=t_checks+checks;
    cx_reject("fn kernel(){return alloc(8);}","cannot allocate");
    cx_reject("fn kernel(){return syscall(39,0,0,0,0,0,0);}","host I/O");
    cx_reject("fn kernel(){return ffi_open(0);}","call FFI");
    cx_reject("global value=1;fn kernel(){return value;}","globals or static data");
    cx_reject("fn kernel(){return kernel();}","recursive CPU kernels");
    cx_reject("fn main(){return 0;}","requires kernel");
    cx_reject("fn kernel(a,b,c,d,e,f,g){return a;}","at most six");
    cx_reject("fn kernel(){return \"host data\";}","string literals");
    cx_reject("lowering f \"word.add\" \"native-x86_64\";lowering f \"word.xor\" \"cpu-cxx\";fn f(a,b){return a+b;}fn kernel(){return 0;}","conflicting lowering");
    cx_reject("lowering f \"word.add\" \"cpu-cxx\";lowering f \"word.xor\" \"native-x86_64\";fn f(a,b){return a+b;}fn kernel(){return 0;}","conflicting lowering");
    let gpu=h_cat3("import \"",h_real("lib/rdna.flex"),"\";fn kernel(){return gpu_rdna_gemv_stage_f16(0,0);}");cx_reject(gpu,"host I/O");
    return t_done();
}
fn main(argc,argv){return t_entry(argc,argv);}
