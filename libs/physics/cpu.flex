// CPU arena adapter: all contact addresses refer to host memory, never LDS.
// Use in an isolated CPU kernel module, not in a GPU application module.
import "solver-register.flex";
extend "cpu-specialize.flex";

// Contact/order scratch below +2048 is dead after coloring and warm start.
// Sixteen 128-byte weld records fit without touching the solver scratch at
// +2048 or persistent color ranges at +14848. Larger worlds retain the scalar
// solver. All cached coefficients depend only on poses, fixed within a step.
fn ph_cpu_weld_prepare(w){
    if load64(w+32)>16{return 0;}let i=0;
    while i<load64(w+32){ph_weld_prepare_at(w,ph_joint(w,i),ph_scratch(w)+i*128,ph_scratch(w)+2048);i=i+1;}return 0;
}
fn ph_cpu_weld_solve(w,joint){
    if load64(w+32)>16{return ph_weld_solve(w,joint);}
    return ph_weld_solve_prepared(w,joint,ph_scratch(w)+(joint-ph_joint(w,0)),ph_scratch(w)+2048);
}
