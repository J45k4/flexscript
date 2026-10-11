import "autograd.flex";
fn ml_sgd(parameter,learning_rate) {
    ml_leaf(parameter);if !ml_requires_grad(parameter) {ml_fail("SGD requires a trainable leaf tensor");}
    if !f64_is_finite(learning_rate) || f64_lt(learning_rate,0) {ml_fail("invalid learning rate");}
    let i=0;while i<ml_size(parameter) {
        store64(ml_data(parameter)+i*8,f64_sub(ml_get(parameter,i),f64_mul(learning_rate,ml_grad(parameter,i))));i=i+1;
    }store64(parameter+104,load64(parameter+104)+1);return 0;
}
