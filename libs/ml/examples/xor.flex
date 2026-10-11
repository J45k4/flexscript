import "../ml.flex";
fn xor_print(label,value) {
    let n=0;while load8(label+n) {n=n+1;}syscall(1,1,label,n,0,0,0);
    let buffer=alloc(32);let end=31;store8(buffer+end,10);
    let i=end;while value>0 || i==end {i=i-1;store8(buffer+i,48+value%10);value=value/10;}
    syscall(1,1,buffer+i,32-i,0,0,0);return 0;
}
fn main() {
    let ctx=ml_context(262144);ml_seed(ctx,42);
    let x=ml_tensor(ctx,4,2,0);let y=ml_tensor(ctx,4,1,0);let one=f64_from_i64(1);
    ml_set(x,3,one);ml_set(x,4,one);ml_set(x,6,one);ml_set(x,7,one);
    ml_set(y,1,one);ml_set(y,2,one);
    let hidden=ml_linear(ctx,2,8);let output=ml_linear(ctx,8,1);let mark=ml_mark(ctx);
    let rate=f64_div(one,f64_from_i64(20));let first=0;let last=0;let step=0;
    while step<1200 {
        ml_reset(mark);let prediction=ml_linear_forward(output,ml_relu(ml_linear_forward(hidden,x)));
        let loss=ml_mse(prediction,y);last=ml_item(loss);if step==0 {first=last;}
        ml_backward(loss);ml_linear_step(hidden,rate);ml_linear_step(output,rate);step=step+1;
    }
    ml_reset(mark);ml_record(ctx,0);let prediction=ml_linear_forward(output,ml_relu(ml_linear_forward(hidden,x)));
    last=ml_item(ml_mse(prediction,y));let million=f64_from_i64(1000000);
    xor_print("Initial MSE (millionths): ",f64_to_i64_nearest(f64_mul(first,million)));
    xor_print("Final MSE (millionths): ",f64_to_i64_nearest(f64_mul(last,million)));
    if !f64_is_finite(last) || !f64_lt(last,f64_div(one,f64_from_i64(1000))) || !f64_lt(last,f64_div(first,f64_from_i64(100))) {return 1;}
    let i=0;while i<4 {
        if f64_gt(ml_get(prediction,i),f64_div(one,f64_from_i64(2)))!=(i==1 || i==2) {return 2;}i=i+1;
    }
    syscall(1,1,"XOR: 4/4 correct\n",17,0,0,0);return 0;
}
