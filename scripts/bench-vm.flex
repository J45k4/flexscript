import "lib/build.flex";
fn bm_now() {
    let time=h_take(16);
    h_assert(syscall(228,1,time,0,0,0,0)==0,"benchmark clock");
    return load64(time)*1000000000+load64(time+8);
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=h_real(b_option(argc,argv,"--compiler","build/flex"));
    let iterations=h_number(b_option(argc,argv,"--iterations","100"));
    h_assert(iterations>0 && iterations<=1000,"iterations must be 1..1000");
    let report_path=b_option(argc,argv,"--report",0);
    let work=h_temp();
    let source=h_join(work,"benchmark.flex");
    let binary=h_join(work,"native");
    h_save(source,h_cat3("fn sum(n){let i=0;let result=0;while i<n {result=result+i;i=i+1;}return result;}fn main(){let i=0;let total=0;while i<",h_int(iterations),h_cat3(" {total=total+sum(50000);i=i+1;}return total!=",h_int(iterations*1249975000),";}")));
    h_compile(compiler,source,binary);
    let names=h_args("native","interpreter","jit","auto",0,0);
    let report=j_object();
    j_set(report,"iterations",j_int(iterations));
    let results=j_object();
    let i=0;
    while i<4 {
        let samples=h_vec();
        let last=0;
        let k=0;
        while k<3 {
            let args=h_args(binary,0,0,0,0,0);
            if i {
                args=h_args(compiler,"run",0,0,0,0);
                if i==1 {
                    h_add(args,"--interpret");
                }else if i==2 {
                    h_add(args,"--jit");
                }
                h_add(args,"--stats");
                h_add(args,"--fuel=1000000000");
                h_add(args,"--timeout-ms=30000");
                h_add(args,source);
            }
            let start=bm_now();
            last=h_check(h_run(args),0,"");
            h_add(samples,bm_now()-start);
            k=k+1;
        }
        let a=h_at(samples,0);
        let b=h_at(samples,1);
        let c=h_at(samples,2);
        let median=a;
        if (a<=b && b<=c) || (c<=b && b<=a) {
            median=b;
        }else if (a<=c && c<=b) || (b<=c && c<=a) {
            median=c;
        }
        let result=j_object();
        j_set(result,"elapsed_ns",j_int(median));
        j_set(result,"stats",j_string(h_trim(h_err(last))));
        j_set(results,h_at(names,i),result);
        h_print(1,h_cat3(h_at(names,i),": ",h_cat(h_int(median/1000000)," ms median\n")));
        i=i+1;
    }
    j_set(report,"results",results);
    j_set(report,"timing",j_string("median of three complete process runs including source compilation and startup"));
    if report_path {
        j_save(report_path,report);
    }
    h_remove(work);
    return 0;
}
