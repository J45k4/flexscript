import "tensor.flex";
// Op codes: add1, sub2, mul3, div4, relu5, reduction6, matmul7,
// transpose8, reshape9. Singleton dimensions broadcast independently.
fn ml_broadcast_dim(a,b) {
    if a==b {return a;}if a==1 {return b;}if b==1 {return a;}
    ml_fail("incompatible broadcast dimensions");return 0;
}
fn ml_broadcast_index(t,row,col) {
    if ml_rows(t)==1 {row=0;}if ml_cols(t)==1 {col=0;}return row*ml_cols(t)+col;
}
fn ml_binary(a,b,op) {
    ml_same_context(a,b);let rows=ml_broadcast_dim(ml_rows(a),ml_rows(b));
    let cols=ml_broadcast_dim(ml_cols(a),ml_cols(b));let t=ml_node(a,b,rows,cols,op,0);
    let i=0;while i<ml_size(t) {
        let x=ml_get(a,ml_broadcast_index(a,i/cols,i%cols));
        let y=ml_get(b,ml_broadcast_index(b,i/cols,i%cols));let value=0;
        if op==1 {value=f64_add(x,y);}else if op==2 {value=f64_sub(x,y);}
        else if op==3 {value=f64_mul(x,y);}else if op==4 {value=f64_div(x,y);}
        store64(ml_data(t)+i*8,value);i=i+1;
    }return t;
}
fn ml_add(a,b) {return ml_binary(a,b,1);}
fn ml_sub(a,b) {return ml_binary(a,b,2);}
fn ml_mul(a,b) {return ml_binary(a,b,3);}
fn ml_div(a,b) {return ml_binary(a,b,4);}
fn ml_square(a) {return ml_mul(a,a);}
fn ml_relu(a) {
    let t=ml_node(a,0,ml_rows(a),ml_cols(a),5,0);let i=0;
    while i<ml_size(a) {let x=ml_get(a,i);if f64_gt(x,0) || f64_is_nan(x) {store64(ml_data(t)+i*8,x);}i=i+1;}return t;
}
fn ml_reduce(a,scale) {
    let t=ml_node(a,0,1,1,6,scale);let value=0;let i=0;
    while i<ml_size(a) {value=f64_add(value,ml_get(a,i));i=i+1;}
    store64(ml_data(t),f64_mul(value,scale));return t;
}
fn ml_sum(a) {return ml_reduce(a,0x3ff0000000000000);}
fn ml_mean(a) {return ml_reduce(a,f64_div(0x3ff0000000000000,f64_from_i64(ml_size(a))));}
fn ml_matmul_shape(a,b) {
    ml_same_context(a,b);if ml_cols(a)!=ml_rows(b) {ml_fail("incompatible matrix dimensions");}return 0;
}
fn ml_matmul(a,b) {
    ml_matmul_shape(a,b);let t=ml_node(a,b,ml_rows(a),ml_cols(b),7,0);let i=0;
    while i<ml_size(t) {
        let row=i/ml_cols(t);let col=i%ml_cols(t);let k=0;let value=0;
        while k<ml_cols(a) {
            value=f64_add(value,f64_mul(ml_get(a,row*ml_cols(a)+k),ml_get(b,k*ml_cols(b)+col)));k=k+1;
        }store64(ml_data(t)+i*8,value);i=i+1;
    }return t;
}
fn ml_transpose(a) {
    let t=ml_node(a,0,ml_cols(a),ml_rows(a),8,0);let i=0;
    while i<ml_size(a) {store64(ml_data(t)+(i%ml_cols(a)*ml_rows(a)+i/ml_cols(a))*8,ml_get(a,i));i=i+1;}return t;
}
fn ml_reshape(a,rows,cols) {
    if rows<=0 || cols<=0 || rows>ml_size(a)/cols || rows*cols!=ml_size(a) {ml_fail("reshape changes element count");}
    let t=ml_node(a,0,rows,cols,9,0);let i=0;
    while i<ml_size(a) {store64(ml_data(t)+i*8,ml_get(a,i));i=i+1;}return t;
}
fn ml_mse(prediction,target) {return ml_mean(ml_square(ml_sub(prediction,target)));}
