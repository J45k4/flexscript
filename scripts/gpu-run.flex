// Run the vector example's PTX or cubin and compare every word against the CPU.
import "lib/gpu-harness.flex";
import "../examples/gpu/vector.flex";
fn main(argc,argv) {
    h_environment(argc,argv);
    h_assert(argc==2,"usage: gpu-run vector.ptx|vector.cubin");
    return gpu_run(load64(argv+8),4099);
}
