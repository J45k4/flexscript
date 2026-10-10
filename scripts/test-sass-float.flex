// Bitwise PTX/SASS differential tests, plus the independent binary64 library.
import "lib/build.flex";
import "lib/harness.flex";
import "../lib/cuda.flex";
import "../lib/gpu.flex";
global ff_gpu=0;
global ff_runs=0;
global ff_dec=0;
fn ff_check(ok,message) {
    if !ok {h_print(2,h_cat3("SASS float test: ",message,"\n"));syscall(231,1,0,0,0,0,0);}
    t_checks=t_checks+1;return 0;
}
fn ff_cuda(status) {
    if status {h_print(2,h_cat3("CUDA: ",cuda_error(),"\n"));syscall(231,1,0,0,0,0,0);}return 0;
}
fn ff_nan(value,width) {
    if width==32 {return (value&0x7fffffff)>0x7f800000;}
    return (value&0x7fffffffffffffff)>0x7ff0000000000000;
}
fn ff_same(a,b,width) {return a==b || (ff_nan(a,width) && ff_nan(b,width));}
fn ff_edges(width) {
    let f=52;let bias=1023;let sign=0x8000000000000000;
    if width==32 {f=23;bias=127;sign=0x80000000;}
    let implicit=1<<f;let inf=(bias*2+1)<<f;let one=bias<<f;let p=alloc(512);
    store64(p,0);store64(p+8,1);store64(p+16,2);
    store64(p+24,implicit-1);store64(p+32,implicit);store64(p+40,implicit+1);
    store64(p+48,one-1);store64(p+56,one);store64(p+64,one+1);
    store64(p+72,one|(implicit>>1));store64(p+80,one+implicit);
    store64(p+88,inf-1);store64(p+96,inf);store64(p+104,inf+1);
    store64(p+112,inf|(implicit>>1));store64(p+120,inf|(implicit>>1)|123);
    // Odd subnormals divided by2 exercise ties both toward and away from zero;
    // neighbors at binade boundaries exercise significand carry/normalization.
    store64(p+128,3);store64(p+136,5);store64(p+144,7);store64(p+152,implicit-2);
    store64(p+160,implicit+2);store64(p+168,implicit+3);store64(p+176,one-2);store64(p+184,one+2);
    store64(p+192,one+3);store64(p+200,one+implicit-1);store64(p+208,one+implicit+1);
    store64(p+216,one-implicit);store64(p+224,one-implicit+1);store64(p+232,inf-2);
    store64(p+240,inf-implicit);store64(p+248,inf|(implicit>>1)-1);
    let i=0;while i<32 {store64(p+256+i*8,load64(p+i*8)|sign);i=i+1;}return p;
}
fn ff_execute(ptx,cubin,width,root,nested) {
    let count=20480;let edges=ff_edges(width);let input=alloc(count*16);let expected=alloc(count*8);let actual=alloc(count*8);
    let i=0;let state=0x7a31d962bcb42105;
    while i<count {
        let a=0;let b=0;
        if i<4096 {a=load64(edges+(i%64)*8);b=load64(edges+(i/64)*8);}
        else {
            state=state*6364136223846793005+1442695040888963407;a=state;
            state=state*6364136223846793005+1442695040888963407;b=state;
            if i&1 {a=a&0x7fffffffffffffff;}
        }
        if width==32 {
            a=a&0xffffffff;b=b&0xffffffff;
            if i>=4096 {if i&1 {a=a&0x7fffffff;}a=a|(state<<32);b=b|(state&0xffffffff00000000);}
        }
        store64(input+i*16,a);store64(input+i*16+8,b);i=i+1;
    }
    let context=cuda_context();ff_cuda(cuda_status);ff_check(context,"CUDA context");
    let a=cuda_buffer(count*16);ff_cuda(cuda_status);let b=cuda_buffer(count*8);ff_cuda(cuda_status);
    ff_cuda(cuda_upload(a,input,count*16));
    let module=cuda_module(h_read(ptx));ff_cuda(cuda_status);
    ff_cuda(cuda_launch_threads(module,a,b,count,128));ff_cuda(cuda_download(expected,b,count*8));ff_cuda(cuda_unload(module));ff_runs=ff_runs+1;
    module=cuda_module(h_read(cubin));ff_cuda(cuda_status);
    ff_cuda(cuda_launch_threads(module,a,b,count,128));ff_cuda(cuda_download(actual,b,count*8));ff_cuda(cuda_unload(module));ff_runs=ff_runs+1;
    i=0;while i<count {
        let got=load64(actual+i*8);let want=load64(expected+i*8);
        let same=ff_same(got,want,width);if nested {same=got==want;}
        ff_check(same,h_cat3("PTX mismatch at ",h_int(i),h_cat3(" actual ",h_int(got),h_cat(" expected ",h_int(want)))));
        if width==32 {ff_check((got>>32)==0,"binary32 zero-extends its result");}
        if width==64 && !nested {
            let x=load64(input+i*16);let y=load64(input+i*16+8);let cpu=0;
            if root {cpu=f64_sqrt(x);}else {cpu=f64_div(x,y);}
            ff_check(ff_same(got,cpu,width),h_cat("independent binary64 reference at ",h_int(i)));
        }
        i=i+1;
    }
    ff_cuda(cuda_free(b));ff_cuda(cuda_free(a));ff_cuda(cuda_close(context));return 0;
}
fn ff_case(width,root,nested) {
    let name="gpu_f64_div";if width==32 {name="gpu_f32_div";}
    if root {name="gpu_f64_sqrt";if width==32 {name="gpu_f32_sqrt";}}
    let expression=h_cat(name,"(load64(input+i*16)");
    if !root {expression=h_cat(expression,",load64(input+i*16+8)");}expression=h_cat(expression,")");
    let source=h_cat3("import \"",h_real("lib/gpu.flex"),"\";\n");
    if nested {
        // Math scratch must not overwrite caller locals, argument stacks, helper
        // frames, or values live across multiple math sites and divergent paths.
        source=h_cat(source,"fn helper(x,y){let keep=x^y;let r=gpu_f64_div(x,y);if x&1 {r=gpu_f64_sqrt(r);}if f64_is_nan(r) {r=0x7ff8000000000000;}return r^keep;}\n");
        expression="helper(load64(input+i*16),load64(input+i*16+8))^helper(load64(input+i*16+8),load64(input+i*16))";
    }
    source=h_cat(source,h_cat3("fn kernel(i,input,output,count){store64(output+i*8,",expression,");return 0;}"));t_program(source);
    let cubin=h_join(t_work,"float.cubin");let ptx=h_join(t_work,"float.ptx");
    let saved=h_getenv("PATH");h_setenv("PATH","/no-flexscript-toolchain");
    h_ok(h_args(t_compiler,"--target","sass-sm75",t_fixture,"-o",cubin));h_setenv("PATH",saved);
    ff_check(load64(h_read(cubin))==0x33010102464c457f,"tool-free direct CUDA ELF");
    let hash=h_sha(cubin);h_ok(h_args(t_compiler,"--target","sass-sm75",t_fixture,"-o",cubin));
    ff_check(h_equal(hash,h_sha(cubin)),"deterministic float emission");
    h_ok(h_args(t_compiler,"--target","ptx",t_fixture,"-o",ptx));
    if ff_dec {let p=h_ok(h_args(ff_dec,cubin,0,0,0,0));ff_check(!h_has(h_out(p),"INVALID") && !h_len(h_err(p)),"float SASS decodes");}
    if ff_gpu {ff_execute(ptx,cubin,width,root,nested);}
    return 0;
}
fn suite(compiler) {
    t_init(compiler);
    ff_case(32,0,0);ff_case(32,1,0);ff_case(64,0,0);ff_case(64,1,0);ff_case(64,0,1);
    let source="fn gpu_f64_sqrt(x){return x;}fn kernel(i,a,b,n){";let i=0;
    while i<100 {source=h_cat(source,h_cat3("let local",h_int(i),"=0;"));i=i+1;}
    t_program(h_cat(source,"return 0;}"));let path=h_join(t_work,"registers.cubin");
    h_ok(h_args(t_compiler,"--target","sass-sm75",t_fixture,"-o",path));let before=h_sha(path);
    t_program(h_cat(source,"return gpu_f64_sqrt(i);}"));
    let p=h_run(h_args(t_compiler,"--target","sass-sm75",t_fixture,"-o",path));h_check(p,1,0);
    ff_check(h_has(h_err(p),"physical register budget"),"float scratch counts against register budget");
    ff_check(h_equal(before,h_sha(path)),"math register rejection preserves existing cubin");
    return t_checks;
}
fn main(argc,argv) {
    h_environment(argc,argv);let i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {ff_gpu=1;}i=i+1;}
    ff_dec=b_option(argc,argv,"--nvdisasm",0);suite(b_option(argc,argv,"--compiler","build/flex-float"));
    let report=j_object();j_set(report,"checks",j_int(t_checks));j_set(report,"device_runs",j_int(ff_runs));
    let path=b_option(argc,argv,"--report",0);if path {j_save(path,report);}t_done();return 0;
}
