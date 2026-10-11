// Portable, contiguous row-major binary64 tensors. All values are f64 bit words.
import "../../lib/f64.flex";
// Context: arena, capacity, used, tensor head, recording, backward epoch, RNG.
// Tensor (128 bytes): context, rows, columns, size, data, gradient, requires-grad,
// op, left, right, previous, saved left/right versions, version, aux, active epoch.
fn ml_fail(message) {
    let n=0;while load8(message+n) {n=n+1;}
    syscall(1,2,"ml: ",4,0,0,0);syscall(1,2,message,n,0,0,0);
    syscall(1,2,"\n",1,0,0,0);syscall(60,1,0,0,0,0,0);return 0;
}
fn ml_context(bytes) {
    if bytes<256 || bytes>1073741824 {ml_fail("invalid arena capacity");}
    let ctx=alloc(bytes+64);if ctx<=0 {ml_fail("arena allocation failed");}
    store64(ctx,ctx+64);store64(ctx+8,bytes);store64(ctx+32,1);store64(ctx+48,42);
    return ctx;
}
fn ml_alloc(ctx,bytes) {
    if bytes<0 || bytes>load64(ctx+8)-7 {ml_fail("arena exhausted");}
    bytes=(bytes+7)&(-8);let used=load64(ctx+16);
    if bytes>load64(ctx+8)-used {ml_fail("arena exhausted");}
    let p=load64(ctx)+used;store64(ctx+16,used+bytes);
    let i=0;while i<bytes {store64(p+i,0);i=i+8;}return p;
}
fn ml_used(ctx) {return load64(ctx+16);}
// Keep parameters/data before a mark, then reset temporary graphs each step.
fn ml_mark(ctx) {
    let mark=ml_alloc(ctx,32);store64(mark,ctx);store64(mark+8,ml_used(ctx));
    store64(mark+16,load64(ctx+24));store64(mark+24,load64(ctx+32));return mark;
}
fn ml_reset(mark) {
    let ctx=load64(mark);let used=load64(mark+8);
    if used>ml_used(ctx) {ml_fail("invalid arena mark");}
    store64(ctx+16,used);store64(ctx+24,load64(mark+16));
    store64(ctx+32,load64(mark+24));return 0;
}
fn ml_record(ctx,enabled) {
    let old=load64(ctx+32);store64(ctx+32,enabled!=0);return old;
}
fn ml_rows(t) {return load64(t+8);}
fn ml_cols(t) {return load64(t+16);}
fn ml_size(t) {return load64(t+24);}
fn ml_data(t) {return load64(t+32);}
fn ml_requires_grad(t) {return load64(t+48);}
fn ml_tensor(ctx,rows,cols,requires_grad) {
    if rows<=0 || cols<=0 {ml_fail("tensor dimensions must be positive");}
    if rows>load64(ctx+8)/16/cols {ml_fail("tensor shape exceeds arena capacity");}
    let n=rows*cols;let t=ml_alloc(ctx,128);
    store64(t,ctx);store64(t+8,rows);store64(t+16,cols);store64(t+24,n);
    store64(t+32,ml_alloc(ctx,n*8));store64(t+48,requires_grad!=0);
    if requires_grad {store64(t+40,ml_alloc(ctx,n*8));}
    store64(t+80,load64(ctx+24));store64(ctx+24,t);return t;
}
fn ml_check_index(t,i) {if i<0 || i>=ml_size(t) {ml_fail("tensor index out of bounds");}return 0;}
fn ml_get(t,i) {ml_check_index(t,i);return load64(ml_data(t)+i*8);}
fn ml_grad(t,i) {
    ml_check_index(t,i);if !ml_requires_grad(t) {ml_fail("tensor does not require gradients");}
    return load64(load64(t+40)+i*8);
}
fn ml_leaf(t) {if load64(t+56) {ml_fail("only leaf tensors may be mutated");}return 0;}
fn ml_set(t,i,value) {
    ml_leaf(t);ml_check_index(t,i);store64(ml_data(t)+i*8,value);
    store64(t+104,load64(t+104)+1);return value;
}
fn ml_fill(t,value) {
    ml_leaf(t);let i=0;while i<ml_size(t) {store64(ml_data(t)+i*8,value);i=i+1;}
    store64(t+104,load64(t+104)+1);return t;
}
fn ml_scalar(ctx,value,requires_grad) {return ml_fill(ml_tensor(ctx,1,1,requires_grad),value);}
fn ml_item(t) {if ml_size(t)!=1 {ml_fail("expected a scalar tensor");}return ml_get(t,0);}
fn ml_same_context(a,b) {if load64(a)!=load64(b) {ml_fail("tensors belong to different contexts");}return 0;}
fn ml_node(a,b,rows,cols,op,aux) {
    let ctx=load64(a);if b {ml_same_context(a,b);}
    let requires_grad=load64(ctx+32) && (ml_requires_grad(a) || (b && ml_requires_grad(b)));
    let t=ml_tensor(ctx,rows,cols,requires_grad);
    if requires_grad {
        store64(t+56,op);store64(t+64,a);store64(t+72,b);store64(t+112,aux);
        store64(t+88,load64(a+104));if b {store64(t+96,load64(b+104));}
    }return t;
}
fn ml_grad_add(t,i,value) {
    if ml_requires_grad(t) {let p=load64(t+40)+i*8;store64(p,f64_add(load64(p),value));}return 0;
}
fn ml_seed(ctx,seed) {store64(ctx+48,seed&2147483647);return 0;}
fn ml_random(ctx) {
    let state=(load64(ctx+48)*1103515245+12345)&2147483647;store64(ctx+48,state);
    return f64_div(f64_from_i64(state),f64_from_i64(2147483648));
}
