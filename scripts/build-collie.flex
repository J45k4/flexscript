import "../apps/collie/tooling.flex";

fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=h_real(b_option(argc,argv,"--compiler","build/flex"));
    return collie_build(compiler);
}
