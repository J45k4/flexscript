import "lib/build.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=h_real(b_option(argc,argv,"--compiler","build/flexscript"));h_mkdir("build");
    h_compile(compiler,"scripts/monolith-assets.flex","build/monolith-assets");h_ok(h_args(h_real("build/monolith-assets"),0,0,0,0,0));
    h_compile(compiler,"examples/monolith/todo.flex","build/monolith-todo");
    h_compile(compiler,"examples/monolith/counter.flex","build/monolith-counter");
    h_compile(compiler,"tests/monolith/declarative.flex","build/monolith-fixture");
    h_compile(compiler,"scripts/monolith-build.flex","build/monolith-builder");
    h_compile(compiler,"tests/monolith/integration.flex","build/test-monolith-integration");
    h_compile(compiler,"tests/monolith/browser.flex","build/test-monolith-browser");
    h_compile(compiler,"scripts/test-monolith-syntax.flex","build/test-monolith-syntax");
    h_print(1,"Built declarative Monolith examples, schema builder, syntax, integration and browser tests.\n");return 0;
}
