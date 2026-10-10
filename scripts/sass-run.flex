import "lib/gpu-harness.flex";
import "../examples/gpu/direct.flex";
fn main(argc,argv) {
    h_environment(argc,argv);h_assert(argc==2,"usage: sass-run direct.cubin|direct.ptx");
    return gpu_run(load64(argv+8),4099);
}
