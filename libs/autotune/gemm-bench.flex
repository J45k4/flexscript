// Standalone HIP harness: no model, trainer, Bun or Python dependency.
import "tiles.flex";
import "../../lib/hip.flex";
import "../../lib/gpu.flex";
global ab_words=0;
global ab_values=0;
global ab_args=0;
global ab_config=0;
fn ab_check(status) {h_assert(status==0,hip_error());return 0;}
fn ab_set_words(a,b,c,d,e,f,g,h) {store64(ab_words,a);store64(ab_words+8,b);store64(ab_words+16,c);store64(ab_words+24,d);store64(ab_words+32,e);store64(ab_words+40,f);store64(ab_words+48,g);store64(ab_words+56,h);return 0;}
fn ab_launch(function,input,output,count,blocks,threads,shared) {
    h_assert(count>0 && count<=2147483647 && blocks>0 && blocks<=2147483647,"invalid benchmark launch");store64(ab_values,input);store64(ab_values+8,output);store64(ab_values+16,count);store64(ab_config+8,blocks);store64(ab_config+32,threads);store64(ab_config+56,shared);return ab_check(hip_dispatch(function,ab_config,ab_args));
}
fn ab_multiply(function,merge,a,b,y,scratch,m,n,k,flags,groups,chunk,tile) {
    let splits=1;if chunk {splits=(k+chunk-1)/chunk;}let tm=j_n(tile,"m");let tn=j_n(tile,"n");let threads=j_n(tile,"threads");let blocks=((m+tm-1)/tm)*((n+tn-1)/tn)*groups*splits;let destination=y;if splits>1 {destination=scratch;}
    ab_set_words(a,b,m,n,k,flags,0,chunk);ab_launch(function,0,destination,blocks*threads,blocks,threads,j_n(tile,"sharedBytes"));
    if splits>1 {ab_set_words(m*n,splits,0,0,0,0,0,0);ab_launch(merge,scratch,y,m*n*groups,(m*n*groups+127)/128,128,0);}return 0;
}
fn ab_module(path) {let module=hip_module(h_read(path));h_assert(module,hip_error());return module;}
fn ab_function(module) {let function=hip_function(module,"flex_kernel");h_assert(function,hip_error());return function;}
fn ab_alloc(bytes) {h_assert(bytes>0 && bytes<=1073741824,"benchmark allocation limit");let buffer=hip_buffer(bytes);h_assert(buffer,hip_error());return buffer;}
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==2,"autotune-gemm REQUEST");let request=j_parse(h_read(load64(argv+8)));let tile=at_tile(j_need(request,"tile"));h_assert(h_equal(j_s(tile,"family"),"gemm"),"only GEMM benchmark family is supported");
    let m=at_integer(request,"m",1,16777216);let n=at_integer(request,"n",1,16777216);let k=at_integer(request,"k",1,1048576);let groups=at_integer(request,"groups",1,128);let flags=at_integer(request,"flags",0,3);let chunk=at_integer(request,"chunk",0,1048576);let warmup=at_integer(request,"warmup",0,100);let samples=at_integer(request,"samples",1,100);
    h_assert(m*k*groups<=268435456 && n*k*groups<=268435456 && m*n*groups<=16777216,"benchmark matrix too large");h_assert(!chunk || chunk%j_n(tile,"k")==0,"split chunks must align with K tile");let splits=1;if chunk {splits=(k+chunk-1)/chunk;}h_assert(m*n*groups<=16777216/splits,"split scratch exceeds 64 MiB");
    h_assert(hip_device_count()>0,hip_error());let context=hip_context_device(0);h_assert(context,hip_error());let module=ab_module(j_s(request,"image"));let fill=ab_module(j_s(request,"fill"));let merger=ab_module(j_s(request,"merge"));let function=ab_function(module);let fill_function=ab_function(fill);let merge_function=ab_function(merger);
    ab_words=h_zero(h_take(64),64);ab_values=h_take(24);ab_args=h_take(88);ab_config=hip_config(1,1,1,128,1,1,0,0);h_assert(ab_config,hip_error());let i=0;while i<3 {store64(ab_args+i*8,ab_values+i*8);i=i+1;}i=0;while i<8 {store64(ab_args+24+i*8,ab_words+i*8);i=i+1;}
    let a=ab_alloc(m*k*groups*4);let b=ab_alloc(k*n*groups*4);let y=ab_alloc(m*n*groups*4);let scratch=y;if splits>1 {scratch=ab_alloc(m*n*groups*splits*4);}ab_launch(fill_function,0,a,m*k*groups,(m*k*groups+127)/128,128,0);ab_launch(fill_function,0,b,k*n*groups,(k*n*groups+127)/128,128,0);
    let start=hip_event();let end=hip_event();h_assert(start && end,hip_error());let timings=j_array();i=0;
    while i<warmup+samples {ab_check(hip_event_record(start,0));ab_multiply(function,merge_function,a,b,y,scratch,m,n,k,flags,groups,chunk,tile);ab_check(hip_event_record(end,0));ab_check(hip_event_wait(end));let ms=gpu_f32_unpack(hip_event_elapsed_f32(start,end));h_assert(f64_is_finite(ms) && f64_gt(ms,0),"invalid GPU timing");if i>=warmup {let ns=f64_to_i64_trunc(f64_add(f64_mul(ms,f64_from_i64(1000000)),0x3fe0000000000000));j_push(timings,j_int(ns));}i=i+1;}
    let cell=h_take(4);let checked=0;let maximum=0;let group=0;
    while group<groups {i=0;while i<32 {let row=(i*7919)%m;let col=(i*104729)%n;if i==31 {row=m-1;col=n-1;}let expected_scaled=0;let at=0;
        while at<k {let ai=group*m*k+row*k+at;if flags&1 {ai=group*m*k+at*m+row;}let bi=group*k*n+at*n+col;if flags&2 {bi=group*k*n+col*k+at;}expected_scaled=expected_scaled+(ai%11-5)*(bi%11-5);at=at+1;}
        ab_check(hip_download(cell,y+(group*m*n+row*n+col)*4,4));let actual=gpu_f32_unpack(gpu_load_u32(cell));h_assert(f64_is_finite(actual),"nonfinite GEMM output");let expected=f64_div(f64_from_i64(expected_scaled),f64_from_i64(64));let error=f64_magnitude(f64_sub(actual,expected));if f64_gt(error,maximum) {maximum=error;}let tolerance=f64_add(f64_div(f64_from_i64(4),f64_from_i64(100000)),f64_mul(f64_magnitude(expected),f64_div(f64_from_i64(3),f64_from_i64(100000))));h_assert(!f64_gt(error,tolerance),"generated GEMM failed independent CPU reference");checked=checked+1;i=i+1;
    }group=group+1;}
    let out=j_object();j_set(out,"gpu_name",j_string(hip_device_name(0)));j_set(out,"gpu_arch",j_string(hip_device_arch(0)));j_set(out,"nanoseconds",timings);j_set(out,"checked_cells",j_int(checked));j_set(out,"max_error_nano",j_int(f64_to_i64_trunc(f64_mul(maximum,f64_from_i64(1000000000)))));j_set(out,"reference",j_string("independent exact integer dot product / 64"));j_set(out,"flops",j_int(2*m*n*k*groups));h_print(1,h_cat(j_dump(out),"\n"));
    ab_check(hip_event_close(start));ab_check(hip_event_close(end));ab_check(hip_free(a));ab_check(hip_free(b));ab_check(hip_free(y));if scratch!=y {ab_check(hip_free(scratch));}ab_check(hip_unload(module));ab_check(hip_unload(fill));ab_check(hip_unload(merger));ab_check(hip_close(context));return 0;
}
