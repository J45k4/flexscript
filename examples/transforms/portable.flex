import "../../lib/f64.flex";
extend "../../extensions/autodiff.flex" with "f64:square";
fn square(x) {return f64_mul(x,x);}
fn main() {return f64_to_i64_trunc(square_grad(f64_from_i64(21)));}
