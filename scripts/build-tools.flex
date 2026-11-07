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
    h_add(names,"test-gui");
    h_add(names,"test-tui");
    h_add(names,"test-network");
    h_add(names,"test-vm");
    h_add(names,"test-proof");
    h_add(names,"test-proof-learning");
    h_add(names,"test-proof-words");
    h_add(names,"test-proof-properties");
    h_add(names,"test-proof-memory");
    h_add(names,"test-proof-regions");
    h_add(names,"test-proof-lifetimes");
    h_add(names,"test-proof-allocations");
    h_add(names,"test-proof-source");
    h_add(names,"test-proof-state");
    h_add(names,"test-proof-loops");
    h_add(names,"test-proof-modular");
    h_add(names,"test-proof-ghost");
    h_add(names,"test-proof-quantifiers");
    h_add(names,"test-proof-functions");
    h_add(names,"test-proof-trusted");
    h_add(names,"test-wasm");
    h_add(names,"test-esp32");
    h_add(names,"test-esp32-branches");
    h_add(names,"test-esp32-locals");
    h_add(names,"test-esp32-riscv");
    h_add(names,"test-esp32-frontends");
    h_add(names,"esp32-link");
    h_add(names,"esp32-data-object");
    h_add(names,"build-esp32-radio");
    h_add(names,"test-esp32-link");
    h_add(names,"test-esp32-network");
    h_add(names,"test-gpu");
    h_add(names,"gpu-run");
    h_add(names,"test-sass");
    h_add(names,"test-sass-float");
    h_add(names,"sass-run");
    h_add(names,"test-gpu-features");
    h_add(names,"graphics-run");
    h_add(names,"ray-run");
    h_add(names,"gpu-info");
    h_add(names,"test-extensions");
    h_add(names,"test-seta-functions");
    h_add(names,"test-shaders");
    h_add(names,"shader-gpu-run");
    h_add(names,"test-transforms");
    h_add(names,"test-ml");
    h_add(names,"test-pup");
    h_add(names,"mnist-infer");
    h_add(names,"test-lowering");
    h_add(names,"test-native-size");
    h_add(names,"test-cpu-cxx");
    h_add(names,"test-f64");
    h_add(names,"test-f64-math");
    h_add(names,"test-tetris");
    h_add(names,"test-todo");
    h_add(names,"test-http");



    h_add(names,"test-host-zip");














    h_add(names,"test-cdp-http");









































    h_add(names,"test-ui-desktop");
    h_add(names,"test-ui");
    h_add(names,"ui-assets");


    h_add(names,"test-harness");
    h_add(names,"install");
    h_add(names,"test-libraries");
    h_add(names,"autotune");
    h_add(names,"test-autotune");
    h_add(names,"build-monolith");
    h_add(names,"monolith-assets");
    h_add(names,"monolith-build");
    h_add(names,"package-libraries");
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
