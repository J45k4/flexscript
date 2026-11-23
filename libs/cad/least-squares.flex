// Damped normal equations, using portable IEEE binary64 values.
import "../../lib/f64.flex";
import "math.flex";

fn ls_clear(p,n) {
    let i=0;
    while i<n {store64(p+i*8,0);i=i+1;}
    return p;
}
fn ls_zero(n) {return ls_clear(m_take(n*8),n);}
// Solve (JᵀJ + lambda I) step = -Jᵀr. Inputs are reusable across damping trials.
fn ls_step(normal,rhs,n,lambda,step,matrix) {
    let stride=(n+1)*8;let i=0;
    while i<n {
        let row=matrix+i*stride;m_copy(row,normal+i*n*8,n*8);
        store64(row+i*8,f64_add(load64(row+i*8),lambda));store64(row+n*8,load64(rhs+i*8));i=i+1;
    }
    let col=0;
    while col<n {
        let row=matrix+col*stride;let best=row;i=col+1;
        while i<n {
            let candidate=matrix+i*stride;
            if f64_magnitude(load64(candidate+col*8))>f64_magnitude(load64(best+col*8)) {best=candidate;}
            i=i+1;
        }
        if !f64_magnitude(load64(best+col*8)) {return 0;}
        let k=col;
        if best!=row {
            while k<=n {let old=load64(row+k*8);store64(row+k*8,load64(best+k*8));store64(best+k*8,old);k=k+1;}
        }
        i=col+1;
        while i<n {
            let target=matrix+i*stride;let factor=f64_div(load64(target+col*8),load64(row+col*8));
            if f64_magnitude(factor) {
                k=col+1;
                while k<=n {
                    if !cg_step() {return 0;}
                    store64(target+k*8,f64_sub(load64(target+k*8),f64_mul(factor,load64(row+k*8))));k=k+1;
                }
            }
            i=i+1;
        }
        col=col+1;
    }
    i=n;
    while i>0 {
        i=i-1;let row=matrix+i*stride;let sum=0;let k=i+1;
        while k<n {sum=f64_add(sum,f64_mul(load64(row+k*8),load64(step+k*8)));k=k+1;}
        let x=f64_div(f64_sub(load64(row+n*8),sum),load64(row+i*8));
        if !f64_is_finite(x) {return 0;}store64(step+i*8,x);
    }
    return 1;
}
