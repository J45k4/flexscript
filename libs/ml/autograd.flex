// Tensor-level reverse mode, independent of the scalar compiler extension.
import "ops.flex";
fn ml_zero_grad(ctx) {
    let t=load64(ctx+24);while t {
        if ml_requires_grad(t) {let i=0;while i<ml_size(t) {store64(load64(t+40)+i*8,0);i=i+1;}}
        t=load64(t+80);
    }return 0;
}
fn ml_backward_binary(t,a,b,op) {
    let i=0;let cols=ml_cols(t);while i<ml_size(t) {
        let ai=ml_broadcast_index(a,i/cols,i%cols);let bi=ml_broadcast_index(b,i/cols,i%cols);
        let g=ml_grad(t,i);let x=ml_get(a,ai);let y=ml_get(b,bi);let dx=g;let dy=g;
        if op==2 {dy=f64_sub(0,g);}else if op==3 {dx=f64_mul(g,y);dy=f64_mul(g,x);}
        else if op==4 {dx=f64_div(g,y);dy=f64_sub(0,f64_mul(dx,f64_div(x,y)));}
        ml_grad_add(a,ai,dx);ml_grad_add(b,bi,dy);i=i+1;
    }return 0;
}
fn ml_backward_matmul(t,a,b) {
    let i=0;while i<ml_size(t) {
        let row=i/ml_cols(t);let col=i%ml_cols(t);let g=ml_grad(t,i);let k=0;
        while k<ml_cols(a) {
            let ai=row*ml_cols(a)+k;let bi=k*ml_cols(b)+col;
            ml_grad_add(a,ai,f64_mul(g,ml_get(b,bi)));ml_grad_add(b,bi,f64_mul(g,ml_get(a,ai)));k=k+1;
        }i=i+1;
    }return 0;
}
fn ml_backward_node(t) {
    let op=load64(t+56);let a=load64(t+64);let b=load64(t+72);
    if op>=1 && op<=4 {return ml_backward_binary(t,a,b,op);}
    if op==7 {return ml_backward_matmul(t,a,b);}
    let i=0;
    if op==5 {while i<ml_size(t) {if f64_gt(ml_get(a,i),0) {ml_grad_add(a,i,ml_grad(t,i));}i=i+1;}}
    else if op==6 {let g=f64_mul(ml_grad(t,0),load64(t+112));while i<ml_size(a) {ml_grad_add(a,i,g);i=i+1;}}
    else if op==8 {while i<ml_size(a) {ml_grad_add(a,i,ml_grad(t,i%ml_cols(a)*ml_rows(a)+i/ml_cols(a)));i=i+1;}}
    else if op==9 {while i<ml_size(a) {ml_grad_add(a,i,ml_grad(t,i));i=i+1;}}
    return 0;
}
fn ml_backward(loss) {
    if ml_size(loss)!=1 {ml_fail("backward requires a scalar loss");}
    if !ml_requires_grad(loss) {ml_fail("loss does not require gradients");}
    let ctx=load64(loss);let epoch=load64(ctx+40)+1;store64(ctx+40,epoch);
    // Creation order is topological: parents always precede their result.
    // Mark only ancestors so unrelated graphs cannot poison this backward pass.
    store64(loss+120,epoch);let t=load64(ctx+24);
    while t {
        if load64(t+120)==epoch && load64(t+56) {
            let a=load64(t+64);let b=load64(t+72);
            if load64(a+104)!=load64(t+88) || (b && load64(b+104)!=load64(t+96)) {ml_fail("tensor changed after forward evaluation");}
            if ml_requires_grad(a) {store64(a+120,epoch);}
            if b && ml_requires_grad(b) {store64(b+120,epoch);}
        }t=load64(t+80);
    }
    ml_zero_grad(ctx);store64(load64(loss+40),0x3ff0000000000000);t=load64(ctx+24);
    while t {if load64(t+120)==epoch && load64(t+56) {ml_backward_node(t);}t=load64(t+80);}
    return 0;
}
