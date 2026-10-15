// Cross-platform tests for the one shared physics engine implementation.
import "lib/build.flex";
fn main(argc,argv) {
    h_environment(argc,argv);
    // The Wasm software-arithmetic reference now includes thin curved stacks.
    h_timeout=120000;
    let compiler=b_option(argc,argv,"--compiler","build/flex");
    let gpu=0;
    let i=1;
    while i<argc {
        if h_equal(load64(argv+i*8),"--gpu") {
            gpu=1;
        }
        i=i+1;
    }
    h_mkdir("build/physics");
    let core="libs/physics/tests/core.flex";
    h_ok(h_args(compiler,core,"-o","build/physics/test-core",0,0));
    let native=h_ok(h_args("build/physics/test-core",0,0,0,0,0));
    h_print(1,h_out(native));
    h_ok(h_args(compiler,"--target","wasm32",core,"-o","build/physics/test-core.wasm"));
    let request=j_object();
    j_set(request,"module",j_string(h_real("build/physics/test-core.wasm")));
    j_save("build/physics/wasm.json",request);
    let wasm=j_parse(h_out(h_ok(h_args("bun","scripts/wasm-runner.js","build/physics/wasm.json",0,0,0))));
    h_assert(j_n(wasm,"valid") && !j_get(wasm,"error") && h_equal(j_s(wasm,"result"),"0") && h_equal(j_s(wasm,"stdout"),h_out(native)),"physics native/Wasm checks differ");
    h_print(1,"Native and WebAssembly physics agree\n");
    if gpu {
        h_ok(h_args(compiler,"libs/physics/tests/gpu.flex","-o","build/physics/test-gpu",0,0));
        let targets=h_args("hip","rdna-gfx1201",0,0,0,0);
        i=0;
        while i<h_count(targets) {
            let target=h_at(targets,i);
            let image=h_cat("build/physics/rollout-",target);
            h_ok(h_args(compiler,"--target",target,"libs/physics/kernels/rollout.flex","-o",image));
            let result=h_ok(h_args("build/physics/test-gpu",image,0,0,0,0));
            h_print(1,h_cat3(target,": ",h_out(result)));
            i=i+1;
        }
    }
    return 0;
}
