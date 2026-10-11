import "../ml.flex";
global mlt_checks=0;
fn mlt_assert(ok,message) {if !ok {ml_fail(message);}mlt_checks=mlt_checks+1;return 0;}
fn mlt_near(actual,expected) {
    let tolerance=f64_div(f64_from_i64(1),f64_from_i64(100000));
    tolerance=f64_mul(tolerance,f64_add(f64_from_i64(1),f64_magnitude(expected)));
    mlt_assert(f64_is_finite(actual) && f64_le(f64_magnitude(f64_sub(actual,expected)),tolerance),"gradient/value mismatch");return 0;
}
fn mlt_int(t,i,value) {return ml_set(t,i,f64_from_i64(value));}
fn mlt_objective(a,b,kind) {
    if kind<0 {let swap=a;a=b;b=swap;kind=-kind;}
    let t=0;
    if kind==1 {t=ml_add(a,b);}else if kind==2 {t=ml_sub(a,b);}
    else if kind==3 {t=ml_mul(a,b);}else if kind==4 {t=ml_div(a,b);}
    else if kind==5 {t=ml_relu(a);}else if kind==6 {t=ml_mean(a);}
    else if kind==7 {t=ml_matmul(a,b);}else if kind==8 {t=ml_transpose(a);}
    else if kind==9 {t=ml_reshape(a,3,2);}
    let weights=ml_tensor(load64(a),ml_rows(t),ml_cols(t),0);let i=0;
    while i<ml_size(t) {ml_set(weights,i,f64_div(f64_from_i64(i+1),f64_from_i64(7)));i=i+1;}
    return ml_mean(ml_mul(ml_square(t),weights));
}
fn mlt_finite_difference(kind,rows,cols) {
    let ctx=ml_context(65536);let a=ml_tensor(ctx,2,3,1);let b=ml_tensor(ctx,rows,cols,1);
    let i=0;while i<ml_size(a) {mlt_int(a,i,i+1);i=i+1;}
    i=0;while i<ml_size(b) {mlt_int(b,i,i+2);i=i+1;}
    let ga=ml_alloc(ctx,ml_size(a)*8);let gb=ml_alloc(ctx,ml_size(b)*8);let mark=ml_mark(ctx);
    ml_backward(mlt_objective(a,b,kind));
    i=0;while i<ml_size(a) {store64(ga+i*8,ml_grad(a,i));i=i+1;}
    i=0;while i<ml_size(b) {store64(gb+i*8,ml_grad(b,i));i=i+1;}
    let epsilon=f64_div(f64_from_i64(1),f64_from_i64(1000000));let side=0;
    while side<2 {
        let tensor=a;let saved=ga;if side {tensor=b;saved=gb;}
        i=0;while i<ml_size(tensor) {
            ml_reset(mark);let value=ml_get(tensor,i);ml_set(tensor,i,f64_add(value,epsilon));
            let plus=ml_item(mlt_objective(a,b,kind));ml_reset(mark);ml_set(tensor,i,f64_sub(value,epsilon));
            let minus=ml_item(mlt_objective(a,b,kind));ml_set(tensor,i,value);
            let numerical=f64_div(f64_sub(plus,minus),f64_mul(f64_from_i64(2),epsilon));
            mlt_near(load64(saved+i*8),numerical);i=i+1;
        }side=side+1;
    }return 0;
}
fn mlt_suite() {
    let ctx=ml_context(65536);let a=ml_tensor(ctx,2,3,1);let b=ml_tensor(ctx,3,2,1);let i=0;
    while i<6 {mlt_int(a,i,i+1);mlt_int(b,i,i+1);i=i+1;}
    let product=ml_matmul(a,b);mlt_near(ml_get(product,0),f64_from_i64(22));
    mlt_near(ml_get(product,1),f64_from_i64(28));mlt_near(ml_get(product,2),f64_from_i64(49));mlt_near(ml_get(product,3),f64_from_i64(64));
    let transposed=ml_transpose(a);let reshaped=ml_reshape(a,3,2);
    mlt_near(ml_get(transposed,1),f64_from_i64(4));mlt_near(ml_get(transposed,4),f64_from_i64(3));
    mlt_near(ml_get(reshaped,3),f64_from_i64(4));mlt_assert(ml_rows(reshaped)==3 && ml_cols(reshaped)==2,"reshape dimensions");
    let x=ml_scalar(ctx,f64_from_i64(3),1);let square=ml_square(x);let branch=ml_add(square,square);
    ml_backward(branch);mlt_near(ml_grad(x,0),f64_from_i64(12));
    ml_backward(branch);mlt_near(ml_grad(x,0),f64_from_i64(12));
    ml_sgd(x,f64_div(f64_from_i64(1),f64_from_i64(4)));mlt_near(ml_get(x,0),0);
    // A stale unrelated graph must not prevent differentiation of this leaf.
    ml_backward(x);mlt_near(ml_grad(x,0),f64_from_i64(1));mlt_near(ml_grad(a,0),0);
    ml_zero_grad(ctx);mlt_near(ml_grad(x,0),0);
    let r=ml_tensor(ctx,1,3,1);mlt_int(r,0,-2);mlt_int(r,1,0);mlt_int(r,2,2);
    let relu=ml_relu(r);ml_backward(ml_sum(relu));mlt_near(ml_get(relu,0),0);mlt_near(ml_get(relu,2),f64_from_i64(2));
    mlt_near(ml_grad(r,0),0);mlt_near(ml_grad(r,1),0);mlt_near(ml_grad(r,2),f64_from_i64(1));
    ml_record(ctx,0);let detached=ml_square(r);mlt_assert(!ml_requires_grad(detached),"no-grad recording");ml_record(ctx,1);
    let mark=ml_mark(ctx);let used=ml_used(ctx);let head=load64(ctx+24);i=0;
    while i<50 {ml_reset(mark);ml_square(r);ml_record(ctx,0);i=i+1;}
    ml_reset(mark);mlt_assert(ml_used(ctx)==used && load64(ctx+24)==head && load64(ctx+32)==1,"arena and recording restored");
    let seed_ctx=ml_context(4096);ml_seed(seed_ctx,7);let random=ml_random(seed_ctx);ml_seed(seed_ctx,7);
    mlt_assert(random==ml_random(seed_ctx) && f64_ge(random,0) && f64_lt(random,f64_from_i64(1)),"deterministic uniform initialization");
    let layer=ml_linear(seed_ctx,2,2);mlt_assert(ml_rows(ml_weight(layer))==2 && ml_cols(ml_bias(layer))==2,"dense parameter dimensions");
    mlt_assert(ml_requires_grad(ml_weight(layer)) && ml_requires_grad(ml_bias(layer)),"dense trainable parameters");
    let kind=1;while kind<=4 {
        mlt_finite_difference(kind,2,3);mlt_finite_difference(kind,1,3);
        mlt_finite_difference(kind,2,1);mlt_finite_difference(kind,1,1);
        mlt_finite_difference(-kind,1,3);mlt_finite_difference(-kind,2,1);mlt_finite_difference(-kind,1,1);kind=kind+1;
    }
    mlt_finite_difference(5,1,1);mlt_finite_difference(6,1,1);mlt_finite_difference(7,3,2);
    mlt_finite_difference(8,1,1);mlt_finite_difference(9,1,1);
    return mlt_checks;
}
