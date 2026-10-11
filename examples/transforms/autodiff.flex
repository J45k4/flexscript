import "../../lib/gpu.flex";
extend "../../extensions/autodiff.flex" with "f64:loss";
fn loss(x) {
    let square=gpu_f64_mul(x,x);
    return gpu_f64_add(square,gpu_f64_mul(gpu_f64_from_i64(3),x));
}
fn kernel(i,input,output,count) {
    store64(output+i*8,loss_grad(gpu_f64_from_i64(i-128)));return 0;
}
fn main() {return gpu_f64_to_i64(loss_grad(gpu_f64_from_i64(2)));}
