// Reuse the production Collie UI lowering/flattening, avoiding a second view
// compiler and preserving the exact compiled UI used by the desktop package.
import "../apps/collie/desktop/source.flex";
fn main(argc,argv){
    h_environment(argc,argv);let compiler=h_real(b_option(argc,argv,"--compiler","build/compiler"));
    let out=b_option(argc,argv,"--out","build/migration");h_mkdir(out);out=h_real(out);
    bf_lower(compiler,out);bf_flatten(h_args("tests/ui/backend-performance.flex",0,0,0,0,0));
    let source=h_join(out,"benchmark-generated.flex");h_save(source,h_cat(h_data(bf_globals),h_data(bf_functions)));
    let args=h_args(compiler,"--native-literals","shared",source,"-o",h_join(out,"ui-benchmark"));h_check(h_run(args),0,0);
    bf_resources(out);h_print(1,h_cat("Built ",h_join(out,"ui-benchmark\n")));return 0;
}
