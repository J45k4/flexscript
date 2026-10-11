import "optim.flex";
// Dense layer: context, [inputs,outputs] weights, [1,outputs] bias.
fn ml_linear(ctx,inputs,outputs) {
    let layer=ml_alloc(ctx,24);let weights=ml_tensor(ctx,inputs,outputs,1);
    let bias=ml_tensor(ctx,1,outputs,1);store64(layer,ctx);store64(layer+8,weights);store64(layer+16,bias);
    let scale=f64_sqrt(f64_div(f64_from_i64(6),f64_from_i64(inputs+outputs)));let i=0;
    while i<ml_size(weights) {
        ml_set(weights,i,f64_mul(f64_sub(f64_mul(f64_from_i64(2),ml_random(ctx)),0x3ff0000000000000),scale));i=i+1;
    }return layer;
}
fn ml_weight(layer) {return load64(layer+8);}
fn ml_bias(layer) {return load64(layer+16);}
fn ml_linear_forward(layer,input) {return ml_add(ml_matmul(input,ml_weight(layer)),ml_bias(layer));}
fn ml_linear_step(layer,learning_rate) {ml_sgd(ml_weight(layer),learning_rate);ml_sgd(ml_bias(layer),learning_rate);return 0;}
