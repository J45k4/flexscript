// Analytic line intersections with the stored cubic spline segments.
import "project-curves.flex";

fn pls_linear(x,y,u,v) {return f64_add(f64_mul(x,u),f64_mul(y,v));}

fn pls_controls(out,cubic,origin,x,y) {
    let a=load64(cubic);let d=load64(cubic+8);
    let ax=f64_from_i64(load64(a)-load64(origin));let ay=f64_from_i64(load64(a+8)-load64(origin+8));
    let dx=f64_from_i64(load64(d)-load64(origin));let dy=f64_from_i64(load64(d+8)-load64(origin+8));
    let first=pls_linear(ax,ay,x,y);let last=pls_linear(dx,dy,x,y);
    store64(out,first);store64(out+24,last);
    store64(out+8,f64_add(first,pls_linear(load64(cubic+16),load64(cubic+24),x,y)));
    store64(out+16,f64_sub(last,pls_linear(load64(cubic+32),load64(cubic+40),x,y)));
    return 1;
}

fn pls_coefficients(values,divisor) {
    let a=f64_div(load64(values),divisor);let b=f64_div(load64(values+8),divisor);
    let c=f64_div(load64(values+16),divisor);let d=f64_div(load64(values+24),divisor);
    let three=f64_from_i64(3);let ab=f64_sub(b,a);let bc=f64_sub(c,b);
    store64(values,a);store64(values+8,f64_mul(three,ab));
    store64(values+16,f64_mul(three,f64_sub(bc,ab)));
    store64(values+24,f64_add(f64_sub(d,a),f64_mul(three,f64_math_neg(bc))));
    return 1;
}

fn pls_polynomial(values,t) {
    let out=load64(values+24);let axis=16;
    while axis>=0 {out=f64_add(f64_mul(out,t),load64(values+axis));axis=axis-8;}
    return out;
}

// Two derivative roots at most. The stable quadratic form avoids losing
// the smaller critical parameter near a segment endpoint.
fn pls_critical(points,values) {
    let a=f64_mul(f64_from_i64(3),load64(values+24));
    let b=f64_mul(f64_from_i64(2),load64(values+16));let c=load64(values+8);
    let epsilon=f64_div(f64_from_i64(1),f64_from_i64(100000000000000));
    let first=0;let second=0;
    if f64_lt(epsilon,f64_magnitude(a)) {
        let disc=f64_sub(f64_mul(b,b),f64_mul(f64_from_i64(4),f64_mul(a,c)));
        if !f64_lt(disc,0) {
            let root=f64_sqrt(disc);if f64_lt(b,0) {root=f64_math_neg(root);}
            let q=f64_mul(f64_math_neg(f64_add(b,root)),0x3fe0000000000000);
            if !f64_eq(q,0) {first=f64_div(q,a);second=f64_div(c,q);}
        }
    }else if f64_lt(epsilon,f64_magnitude(b)) {first=f64_div(f64_math_neg(c),b);}
    if f64_lt(second,first) {let swap=first;first=second;second=swap;}
    let one=f64_from_i64(1);let count=1;store64(points,0);
    if f64_lt(0,first) && f64_lt(first,one) {store64(points+8,first);count=2;}
    if f64_lt(0,second) && f64_lt(second,one) && f64_lt(epsilon,f64_magnitude(f64_sub(second,first))) {
        store64(points+count*8,second);count=count+1;
    }
    store64(points+count*8,one);return count+1;
}

fn pls_bisect(values,low,high,negative) {
    let i=0;let middle=0;
    while i<50 {
        middle=f64_mul(f64_add(low,high),0x3fe0000000000000);
        let value=pls_polynomial(values,middle);
        if f64_eq(value,0) {return middle;}
        if f64_lt(value,0)==negative {low=middle;}else {high=middle;}
        i=i+1;
    }
    return middle;
}

fn pls_hit(hits,along,u) {
    let parameter=pls_polynomial(along,u);
    // cg_push reserves integer zero as its missing-entry sentinel.
    if !parameter {parameter=f64_math_neg(0);}
    return cg_push(hits,parameter);
}

fn pls_contacts(hits,perpendicular,along,divisions,length_squared,length) {
    let scale=0;let positive=0;let negative=0;let i=0;
    while i<32 {
        let value=load64(perpendicular+i);let magnitude=f64_magnitude(value);
        if magnitude>scale {scale=magnitude;}
        if f64_lt(0,value) {positive=positive+1;}
        if f64_lt(value,0) {negative=negative+1;}
        i=i+8;
    }
    // A plane-side convex hull excludes crossings. Coincident spans supply
    // no isolated intersection, including roundoff from fit handles.
    let minimum=f64_div(length,f64_from_i64(100000));
    if positive==4 || negative==4 || f64_lt(scale,minimum) {return 1;}
    pls_coefficients(perpendicular,scale);pls_coefficients(along,length_squared);
    let n=pls_critical(divisions,perpendicular);let low=0;let low_value=load64(perpendicular);
    let epsilon=f64_div(f64_from_i64(1),f64_from_i64(1000000000000));
    if f64_magnitude(low_value)<=epsilon {pls_hit(hits,along,low);}
    i=1;while i<n && !cg_error {
        let high=load64(divisions+i*8);let high_value=pls_polynomial(perpendicular,high);
        if f64_magnitude(high_value)<=epsilon {pls_hit(hits,along,high);}
        else if f64_magnitude(low_value)>epsilon && f64_lt(low_value,0)!=f64_lt(high_value,0) {
            pls_hit(hits,along,pls_bisect(perpendicular,low,high,f64_lt(low_value,0)));
        }
        low=high;low_value=high_value;i=i+1;
    }
    return !cg_error;
}

fn pls_sort(values,scratch,start,end) {
    if end-start<2 {return 1;}
    let middle=(start+end)/2;
    pls_sort(values,scratch,start,middle);pls_sort(values,scratch,middle,end);
    let left=start;let right=middle;let i=start;
    while i<end {
        if right>=end || (left<middle && f64_le(load64(values+left*8),load64(values+right*8))) {
            store64(scratch+i*8,load64(values+left*8));left=left+1;
        }else {store64(scratch+i*8,load64(values+right*8));right=right+1;}
        i=i+1;
    }
    i=start;while i<end {store64(values+i*8,load64(scratch+i*8));i=i+1;}
    return 1;
}

fn plb_spline(out,a,b,row) {
    let source=pc_spline_data(row);if !source {return 0;}
    let dx=f64_from_i64(load64(b)-load64(a));let dy=f64_from_i64(load64(b+8)-load64(a+8));
    let squared=pls_linear(dx,dy,dx,dy);if !squared {return 1;}
    let length=f64_sqrt(squared);let hits=cg_array();
    let cubic=m_take(48);let perpendicular=m_take(32);let along=m_take(32);let divisions=m_take(32);
    let i=0;while i<load64(source+8) && !cg_error {
        if !cg_step() || !pc_spline_segment(source,i,cubic) {return 0;}
        pls_controls(perpendicular,cubic,a,f64_math_neg(dy),dx);
        pls_controls(along,cubic,a,dx,dy);
        if !pls_contacts(hits,perpendicular,along,divisions,squared,length) {return 0;}
        i=i+1;
    }
    let count=cg_count(hits);if !count {return !cg_error;}
    pls_sort(load64(hits+16),m_take(count*8),0,count);
    let previous=cg_at(hits,0);cg_push(out,previous);i=1;
    let tolerance=f64_div(f64_from_i64(1),length);
    while i<count && !cg_error {
        let hit=cg_at(hits,i);
        if f64_lt(tolerance,f64_sub(hit,previous)) {cg_push(out,hit);previous=hit;}
        i=i+1;
    }
    return !cg_error;
}
