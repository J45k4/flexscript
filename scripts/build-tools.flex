import "lib/build.flex";
fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=h_real(b_option(argc,argv,"--compiler","build/flex"));
    let out=b_option(argc,argv,"--out-dir","build/tools");
    h_mkdir(out);
    let names=h_args("bootstrap","package","sign-release","clean-room","test","test-imports");
    h_add(names,"test-upgrade");
    h_add(names,"test-url-imports");
    h_add(names,"test-signature");
    h_add(names,"test-ffi");
    h_add(names,"test-network");
    h_add(names,"test-vm");
    h_add(names,"test-wasm");
    h_add(names,"test-extensions");
    h_add(names,"test-f64");
    h_add(names,"test-f64-math");
    h_add(names,"test-tetris");
    h_add(names,"test-todo");
    h_add(names,"test-http");
    h_add(names,"test-harness");
    h_add(names,"bench-vm");
    let i=0;
    while i<h_count(names) {
        let name=h_at(names,i);
        h_compile(compiler,h_cat3("scripts/",name,".flex"),h_join(out,name));
        h_print(1,h_cat("Built ",h_cat(name,"\n")));
        i=i+1;
    }
    return 0;
}
