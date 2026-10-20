import "../apps/collie/tooling.flex";

fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=h_real(b_option(argc,argv,"--compiler","build/flex"));
    let with_vm=0;let i=1;while i<argc {
        if h_equal(load64(argv+i*8),"--vm") {with_vm=1;}i=i+1;
    }
    return collie_test(compiler,with_vm);
}
