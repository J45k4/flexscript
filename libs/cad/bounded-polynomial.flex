// Isolate real polynomial roots on a finite parameter interval.
import "../../lib/f64-math.flex";

fn pab_polynomial(coefficients,count,t) {
    let value=0;
    while count {count=count-1;value=f64_add(f64_mul(value,t),load64(coefficients+count*8));}
    return value;
}

fn pab_bisect(coefficients,count,lo,hi,negative) {
    let n=0;let mid=0;
    while n<54 {
        mid=f64_mul(f64_add(lo,hi),0x3fe0000000000000);
        let value=pab_polynomial(coefficients,count,mid);
        if f64_eq(value,0) {return mid;}
        if f64_lt(value,0)==negative {lo=mid;}else {hi=mid;}
        n=n+1;
    }
    return mid;
}

fn pab_roots(out,coefficients,count,min,max) {
    return pab_roots_with_workspace(out,coefficients,count,min,max,m_take(pab_root_workspace_size(count)));
}

fn pab_root_workspace_size(count) {
    let words=0;
    while count>2 {words=words+3*count-3;count=count-1;}
    return (words+count)*8;
}

// A degree-n polynomial is monotone between adjacent derivative roots.
// Retain this level's values, derivative and critical points in disjoint
// slices, then reuse the same buffer when another segment is evaluated.
fn pab_roots_with_workspace(out,coefficients,count,min,max,workspace) {
    let scale=0;let i=0;
    while i<count {let v=f64_magnitude(load64(coefficients+i*8));if v>scale {scale=v;}i=i+1;}
    let tiny=f64_div(f64_from_i64(1),f64_from_i64(100000000000000));
    if scale<tiny {return 0;}
    let values=workspace;i=0;
    while i<count {store64(values+i*8,f64_div(load64(coefficients+i*8),scale));i=i+1;}
    while count>1 && f64_magnitude(load64(values+(count-1)*8))<tiny {count=count-1;}
    if count<2 {return 0;}
    if count==2 {
        let root=f64_div(f64_math_neg(load64(values)),load64(values+8));
        if f64_le(min,root) && f64_le(root,max) {store64(out,root);return 1;}
        return 0;
    }
    let derivative=values+count*8;i=1;
    while i<count {store64(derivative+(i-1)*8,f64_mul(load64(values+i*8),f64_from_i64(i)));i=i+1;}
    let critical=derivative+(count-1)*8;
    let n=pab_roots_with_workspace(critical,derivative,count-1,min,max,critical+(count-2)*8);
    let lo=min;let low=pab_polynomial(values,count,lo);let roots=0;
    let epsilon=f64_div(f64_from_i64(1),f64_from_i64(1000000000000));
    if f64_magnitude(low)<=epsilon {store64(out,lo);roots=1;}
    i=0;while i<=n && roots<count-1 {
        let hi=max;if i<n {hi=load64(critical+i*8);}
        if f64_lt(lo,hi) {
            let high=pab_polynomial(values,count,hi);
            if f64_magnitude(high)<=epsilon {store64(out+roots*8,hi);roots=roots+1;}
            else if f64_magnitude(low)>epsilon && f64_lt(low,0)!=f64_lt(high,0) {
                store64(out+roots*8,pab_bisect(values,count,lo,hi,f64_lt(low,0)));roots=roots+1;
            }
            lo=hi;low=high;
        }
        i=i+1;
    }
    return roots;
}

fn pab_square(out,coefficients,count) {
    let i=0;while i<count {
        let j=0;while j<count {
            let at=out+(i+j)*8;
            store64(at,f64_add(load64(at),f64_mul(load64(coefficients+i*8),load64(coefficients+j*8))));j=j+1;
        }
        i=i+1;
    }
    return 1;
}

fn pab_coefficients(out,polynomial_x,polynomial_y,count) {
    let i=0;while i<count*2-1 {store64(out+i*8,0);i=i+1;}
    pab_square(out,polynomial_x,count);pab_square(out,polynomial_y,count);return 1;
}
