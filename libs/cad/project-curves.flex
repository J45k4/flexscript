// V4 finite circular/elliptic arcs and uniform cubic splines, in sketch space.
import "project-number.flex";
import "project-nodes.flex";
import "sketch-value.flex";
import "../../lib/f64-math.flex";

// TypeScript stores both arc families in sketchArc.arc. Existing Rust-style
// elliptic arcs use sketchPrimitive.primitive. Keep their original wrappers.
fn pc_curve_geometry(row) {
    if m_eq(j_string(row,"type"),"sketchArc") {return j_get(row,"arc");}
    return j_get(row,"primitive");
}
fn pc_circular_arc(row) {
    return m_eq(j_string(row,"type"),"sketchArc") && m_eq(j_string(j_get(row,"arc"),"type"),"arc");
}
fn pc_elliptic_arc(row) {
    let type=j_string(row,"type");
    return (m_eq(type,"sketchArc") || m_eq(type,"sketchPrimitive")) && m_eq(j_string(pc_curve_geometry(row),"type"),"ellipticArc");
}
fn pc_finite_arc(row) {return pc_circular_arc(row) || pc_elliptic_arc(row);}
fn pc_ellipse_entity(row) {
    return pc_elliptic_arc(row) || (m_eq(j_string(row,"type"),"sketchPrimitive") && m_eq(j_string(j_get(row,"primitive"),"type"),"ellipse"));
}
fn pc_sampled_curve(row) {
    let kind=j_string(row,"type");
    return m_eq(kind,"sketchArc") || m_eq(kind,"sketchSpline") || pc_elliptic_arc(row);
}
fn pc_curve_point(points,x,y) {
    if cg_abs(x)>500000000 || cg_abs(y)>500000000 {return cg_fail("Sketch curve exceeds coordinate range");}
    return cg_push(points,cg_v(x,y,0));
}
fn pc_ellipse_rotation(primitive) {
    let deg=pc_serial_number(j_get(primitive,"rotation"),6,1000000,1000000)%360000000;
    return f64_mul(f64_div(f64_from_i64(deg),f64_from_i64(180000000)),0x400921fb54442d18);
}
// Angles use picoradians. An open path includes its last point, while a
// closed profile wraps directly from its last vertex to the first vertex.
fn pc_ellipse_samples(center,rx,ry,rotation,start,sweep,count,include_end) {
    let scale=1000000000000;
    let cosine=f64_cos(rotation);let sine=f64_sin(rotation);let out=cg_array();let i=0;
    while i<count+include_end && !cg_error {
        let angle=f64_div(f64_from_i64(start+sweep*i/count),f64_from_i64(scale));
        let x=f64_mul(f64_from_i64(rx),f64_cos(angle));let y=f64_mul(f64_from_i64(ry),f64_sin(angle));
        pc_curve_point(out,load64(center)+f64_to_i64_round(f64_sub(f64_mul(x,cosine),f64_mul(y,sine))),
            load64(center+8)+f64_to_i64_round(f64_add(f64_mul(x,sine),f64_mul(y,cosine))));
        i=i+1;
    }
    if cg_error {return 0;}return out;
}
fn pc_web_arc_decimal(mantissa,scale) {
    // Round a saved decimal to binary64 once. Repeated floating-point
    // division can move an exact adaptive chord threshold by one chord.
    if !mantissa || scale>=0 || scale < -26 {
        let literal=pcv_literal_value(mantissa,scale);if !literal {return 0;}
        return load64(literal);
    }
    let denominator=1;let power=-scale;
    while power {denominator=denominator*5;power=power-1;}
    let exponent=1023+scale;
    while mantissa<denominator {mantissa=mantissa*2;exponent=exponent-1;}
    while mantissa>=2*denominator {denominator=denominator*2;exponent=exponent+1;}
    let remainder=mantissa-denominator;let significand=1;let bits=55;
    while bits {
        remainder=remainder*2;significand=significand*2;
        if remainder>=denominator {remainder=remainder-denominator;significand=significand+1;}
        bits=bits-1;
    }
    return f64_pack(0,exponent,significand|(remainder!=0));
}
fn pc_web_geometry_number(row,field,diagnostic) {
    let value=j_get(row,field);let number=0;
    if j_kind(value)==1 {number=f64_from_i64(j_value(value));}
    else if j_kind(value)==6 {
        let raw=j_value(value);let negative=load8(raw)==45;
        let parsed=pcv_literal_parts(cg_v(raw+negative,0,0));if !parsed {return 0;}
        number=pc_web_arc_decimal(load64(parsed),load64(parsed+8));if negative {number=f64_math_neg(number);}
    }else {return cg_fail(diagnostic);}
    return number;
}
fn pc_web_arc_number(row,field,limit) {
    let number=pc_web_geometry_number(row,field,"Expected a finite elliptic arc coordinate or angle");
    if f64_gt(f64_magnitude(number),limit) {return cg_fail("Elliptic arc coordinate or angle exceeds range");}
    return number;
}
// Canonical web arcs use sampleEllipticArc's 0.01 mm chord error. The saved
// segment count is validated but does not determine the web silhouette.
fn pc_web_elliptic_path(arc) {return pc_web_elliptic_samples(arc,0);}
fn pc_web_elliptic_samples(arc,numbered) {
    let tau=0x401921fb54442d18;let mm_limit=f64_from_i64(500);
    let scale=f64_from_i64(1000000);let center=j_get(arc,"center");
    let x=pc_web_arc_number(center,"x",mm_limit);let y=pc_web_arc_number(center,"y",mm_limit);
    let rx=f64_scalbn(pc_web_arc_number(arc,"width",mm_limit),-1);
    let ry=f64_scalbn(pc_web_arc_number(arc,"height",mm_limit),-1);
    let rotation=f64_div(f64_mul(pc_web_arc_number(arc,"rotation",scale),0x400921fb54442d18),f64_from_i64(180));
    let start=pc_web_arc_number(arc,"startAngle",scale);let sweep=pc_web_arc_number(arc,"sweep",tau);
    let stored=j_integer(arc,"segments");
    if cg_error || !f64_gt(rx,0) || !f64_gt(ry,0) || !f64_magnitude(sweep) || stored<8 || stored>4096 {
        return cg_fail("Invalid arc sweep, axes or segment count");
    }
    if f64_lt(start,0) || !f64_lt(start,tau) {
        let turns=f64_to_i64_trunc(f64_div(start,tau));
        start=f64_sub(start,f64_mul(f64_from_i64(turns),tau));
        if f64_lt(start,0) {start=f64_add(start,tau);}
    }
    let radius=rx;if f64_lt(radius,ry) {radius=ry;}
    let eight_times_tolerance=0x3fb47ae147ae147b;
    let estimate=f64_mul(f64_magnitude(sweep),f64_sqrt(f64_div(radius,eight_times_tolerance)));
    if numbered {
        let nearest=f64_from_i64(f64_to_i64_round(estimate));
        // Leave ceil ties uncertified when a browser may round to either
        // neighbouring chord count.
        if f64_lt(f64_magnitude(f64_sub(estimate,nearest)),f64_div(f64_from_i64(1),f64_from_i64(10000000000))) {return 0;}
    }
    let count=f64_to_i64_trunc(estimate);if f64_lt(f64_from_i64(count),estimate) {count=count+1;}
    if count<1 {count=1;}
    let out=cg_array();let cosine=f64_cos(rotation);let sine=f64_sin(rotation);let i=0;
    let key_limit=0;if numbered {key_limit=f64_div(f64_from_i64(4999),f64_from_i64(10000));}
    while i<=count && !cg_error {
        let t=f64_div(f64_from_i64(i),f64_from_i64(count));
        let angle=f64_add(start,f64_mul(t,sweep));
        if i==count && f64_magnitude(sweep)==tau {angle=start;}
        let u=f64_mul(rx,f64_cos(angle));let v=f64_mul(ry,f64_sin(angle));
        let px=f64_sub(f64_add(x,f64_mul(u,cosine)),f64_mul(v,sine));
        let py=f64_add(f64_add(y,f64_mul(u,sine)),f64_mul(v,cosine));
        px=f64_mul(px,scale);py=f64_mul(py,scale);
        let nx=f64_to_i64_round(px);let ny=f64_to_i64_round(py);
        if numbered && (!f64_lt(f64_magnitude(f64_sub(px,f64_from_i64(nx))),key_limit)
            || !f64_lt(f64_magnitude(f64_sub(py,f64_from_i64(ny))),key_limit)) {return 0;}
        pc_curve_point(out,nx,ny);
        i=i+1;
    }
    if cg_error {return 0;}return out;
}
fn pc_arc_path(row) {
    let arc=pc_curve_geometry(row);let circular=pc_circular_arc(row);
    if !circular && !pc_elliptic_arc(row) {return cg_fail("Invalid sketch arc");}
    if !circular && m_eq(j_string(row,"type"),"sketchArc") {return pc_web_elliptic_path(arc);}
    let center=pc_uv(j_get(arc,"center"));let n=j_integer(arc,"segments");
    let rx=0;let ry=0;let rotation=0;
    if circular {
        rx=pc_pose_number(j_get(arc,"radius"));ry=rx;
    }else {
        rx=pc_pose_number(j_get(arc,"width"))/2;ry=pc_pose_number(j_get(arc,"height"))/2;
        rotation=pc_ellipse_rotation(arc);
    }
    let scale=1000000000000;let tau=6283185307180;
    let start=pc_serial_number(j_get(arc,"startAngle"),12,scale,1000000)%tau;
    let sweep=pc_serial_number(j_get(arc,"sweep"),12,scale,7);
    if cg_error || !sweep || circular && (cg_abs(sweep)<1000 || cg_abs(sweep)>=tau) || cg_abs(sweep)>tau || rx<=0 || ry<=0 || n<8 || n>4096 {
        return cg_fail("Invalid arc sweep, axes or segment count");
    }
    // The input radians round to picoradians. Keep exact quarter/half turns
    // on their authored segment boundary across that final rounding.
    let count=(cg_abs(sweep)*n+tau-1-n/2)/tau;if count<2 {count=2;}
    return pc_ellipse_samples(center,rx,ry,rotation,start,sweep,count,1);
}

// Unit off-diagonals. Replace the RHS with the solution of the tridiagonal system.
fn pc_spline_tridiagonal(rhs,n,periodic) {
    let diagonal=m_take(n*8);let i=0;
    while i<n {store64(diagonal+i*8,f64_from_i64(4));i=i+1;}
    if periodic {store64(diagonal,f64_from_i64(8));store64(diagonal+(n-1)*8,0x4011000000000000);}
    i=1;while i<n {
        let d=diagonal+i*8;let r=rhs+i*8;let factor=f64_div(f64_from_i64(1),load64(d-8));
        store64(d,f64_sub(load64(d),factor));store64(r,f64_sub(load64(r),f64_mul(factor,load64(r-8))));i=i+1;
    }
    let next=0;i=n;
    while i {i=i-1;let r=rhs+i*8;next=f64_div(f64_sub(load64(r),next),load64(diagonal+i*8));store64(r,next);}
    return rhs;
}
fn pc_spline_solve_second(second,n,closed) {
    if !closed {
        store64(second,0);store64(second+(n-1)*8,0);
        if n>2 {pc_spline_tridiagonal(second+8,n-2,0);}return second;
    }
    // A rank-one correction restores the two end couplings in a periodic fit.
    pc_spline_tridiagonal(second,n,1);let correction=m_take(n*8);let i=0;
    while i<n {store64(correction+i*8,0);i=i+1;}
    store64(correction,f64_from_i64(-4));store64(correction+(n-1)*8,f64_from_i64(1));
    pc_spline_tridiagonal(correction,n,1);let last=(n-1)*8;let four=f64_from_i64(4);
    let factor=f64_div(f64_sub(load64(second),f64_div(load64(second+last),four)),
        f64_sub(f64_add(f64_from_i64(1),load64(correction)),f64_div(load64(correction+last),four)));
    i=0;while i<n {
        store64(second+i*8,f64_sub(load64(second+i*8),f64_mul(factor,load64(correction+i*8))));i=i+1;
    }
    return second;
}
fn pc_spline_second(points,axis,closed) {
    let n=cg_count(points);let second=m_take(n*8);let i=0;
    while i<n {
        let before=cg_at(points,(i+n-1)%n);let after=cg_at(points,(i+1)%n);
        let delta=load64(before+axis)+load64(after+axis)-2*load64(cg_at(points,i)+axis);
        store64(second+i*8,f64_from_i64(6*delta));i=i+1;
    }
    return pc_spline_solve_second(second,n,closed);
}
fn pc_spline_mid(a,b) {return cg_v((load64(a)+load64(b))/2,(load64(a+8)+load64(b+8))/2,0);}
// Distance to the finite chord handles collinear control points beyond its ends.
fn pc_spline_flat(a,p,b) {
    let dx=f64_from_i64(load64(b)-load64(a));let dy=f64_from_i64(load64(b+8)-load64(a+8));
    let x=f64_from_i64(load64(p)-load64(a));let y=f64_from_i64(load64(p+8)-load64(a+8));
    let len=f64_add(f64_mul(dx,dx),f64_mul(dy,dy));let dot=f64_add(f64_mul(x,dx),f64_mul(y,dy));
    if len && f64_lt(0,dot) {
        let t=f64_from_i64(1);if f64_lt(dot,len) {t=f64_div(dot,len);}
        x=f64_sub(x,f64_mul(t,dx));y=f64_sub(y,f64_mul(t,dy));
    }
    return !f64_lt(f64_from_i64(100000000),f64_add(f64_mul(x,x),f64_mul(y,y)));
}
fn pc_spline_sample(out,a,b,c,d,depth) {
    if pc_spline_flat(a,b,d) && pc_spline_flat(a,c,d) {return pc_curve_point(out,load64(d),load64(d+8));}
    if depth>=20 || !cg_step() {return cg_fail("Spline sampling exceeds tolerance budget");}
    let ab=pc_spline_mid(a,b);let bc=pc_spline_mid(b,c);let cd=pc_spline_mid(c,d);
    let left=pc_spline_mid(ab,bc);let right=pc_spline_mid(bc,cd);let mid=pc_spline_mid(left,right);
    return pc_spline_sample(out,a,ab,left,mid,depth+1) && pc_spline_sample(out,mid,right,cd,d,depth+1);
}
fn pc_spline_record(row) {
    let curve=j_get(row,"spline");
    let flag=j_get(curve,"closed");let closed=j_value(flag);let mode=j_string(curve,"mode");
    let control=m_eq(mode,"control");
    if !m_eq(j_string(curve,"type"),"spline") || !m_eq(j_string(row,"id"),j_string(curve,"id"))
        || flag && j_kind(flag)!=5 || !control && !m_eq(mode,"fit") {return cg_fail("Invalid v4 spline");}
    let list=j_get(curve,"points");let n=cg_j_count(list);
    if j_kind(list)!=3 || n<2 || n>4096 || closed && n<3 || control && (closed || n<4 || (n-1)%3) {
        return cg_fail("Invalid spline point count or closure");
    }
    return cg_v(list,control,closed);
}
fn pc_spline_data(row) {
    let record=pc_spline_record(row);if !record {return 0;}
    let points=cg_array();let next=pc_first(load64(record));
    while next && !cg_error {cg_push(points,pc_uv(next));next=load64(next+24);}
    if cg_error {return 0;}
    let n=cg_count(points);let closed=load64(record+16);
    let data=m_take(40);store64(data,points);
    let count=n-1+closed;let step=1;let sx=0;let sy=0;
    if load64(record+8) {
        count=(n-1)/3;step=3;
    }else {
        sx=pc_spline_second(points,0,closed);sy=pc_spline_second(points,8,closed);
    }
    store64(data+8,count);store64(data+16,step);store64(data+24,sx);store64(data+32,sy);return data;
}

// Keep integer endpoints and the offsets to the inner handles in binary64.
// The first handle is a + offset, the second d - offset. The tessellator
// rounds these offsets just as it did before analytic intersection support.
fn pc_spline_segment(data,index,cubic) {
    let points=load64(data);let step=load64(data+16);
    let i=index*step;let j=(i+step)%cg_count(points);
    let a=cg_at(points,i);let d=cg_at(points,j);
    store64(cubic,a);store64(cubic+8,d);
    if step==3 {
        let b=cg_at(points,i+1);let c=cg_at(points,i+2);
        store64(cubic+16,f64_from_i64(load64(b)-load64(a)));
        store64(cubic+24,f64_from_i64(load64(b+8)-load64(a+8)));
        store64(cubic+32,f64_from_i64(load64(d)-load64(c)));
        store64(cubic+40,f64_from_i64(load64(d+8)-load64(c+8)));
        return 1;
    }
    if load64(a)==load64(d) && load64(a+8)==load64(d+8) {return cg_fail("Adjacent fit points must be distinct");}
    let axis=0;let two=f64_from_i64(2);let three=f64_from_i64(3);let six=f64_from_i64(6);
    while axis<16 {
        let second=load64(data+24+axis);let sa=load64(second+i*8);let sd=load64(second+j*8);
        let delta=f64_from_i64(load64(d+axis)-load64(a+axis));
        let ta=f64_sub(delta,f64_div(f64_add(f64_mul(two,sa),sd),six));
        let td=f64_add(delta,f64_div(f64_add(sa,f64_mul(two,sd)),six));
        store64(cubic+16+axis,f64_div(ta,three));store64(cubic+32+axis,f64_div(td,three));axis=axis+8;
    }
    return 1;
}

fn pc_spline_path(row) {
    let data=pc_spline_data(row);if !data {return 0;}
    let out=cg_array();let cubic=m_take(48);let i=0;
    cg_push(out,cg_at(load64(data),0));
    while i<load64(data+8) && !cg_error {
        if !pc_spline_segment(data,i,cubic) {return 0;}
        let a=load64(cubic);let d=load64(cubic+8);
        let b=cg_v(load64(a)+f64_to_i64_round(load64(cubic+16)),load64(a+8)+f64_to_i64_round(load64(cubic+24)),0);
        let c=cg_v(load64(d)-f64_to_i64_round(load64(cubic+32)),load64(d+8)-f64_to_i64_round(load64(cubic+40)),0);
        pc_spline_sample(out,a,b,c,d,0);i=i+1;
    }
    if cg_error {return 0;}return out;
}

// Legacy TypeScript profile and face IDs depend on the original adaptive
// subdivision. Stay in binary64 millimetres until each sampled point is
// emitted, so rounding a control or midpoint cannot choose an extra chord.
fn pc_web_spline_second(points,axis,closed) {
    let n=cg_count(points);let second=m_take(n*8);let i=0;
    while i<n {
        let previous=load64(cg_at(points,(i+n-1)%n)+axis);
        let point=load64(cg_at(points,i)+axis);let next=load64(cg_at(points,(i+1)%n)+axis);
        let delta=f64_add(f64_sub(next,f64_scalbn(point,1)),previous);
        store64(second+i*8,f64_mul(f64_from_i64(6),delta));i=i+1;
    }
    return pc_spline_solve_second(second,n,closed);
}
fn pc_web_spline_mid(a,b) {
    return cg_v(f64_add(f64_scalbn(load64(a),-1),f64_scalbn(load64(b),-1)),
        f64_add(f64_scalbn(load64(a+8),-1),f64_scalbn(load64(b+8),-1)),0);
}
fn pc_web_spline_flat(a,p,b) {
    let ax=load64(a);let ay=load64(a+8);let dx=f64_sub(load64(b),ax);let dy=f64_sub(load64(b+8),ay);
    let x=load64(p);let y=load64(p+8);
    let length=f64_add(f64_mul(dx,dx),f64_mul(dy,dy));let t=0;
    if length {
        let dot=f64_add(f64_mul(f64_sub(x,ax),dx),f64_mul(f64_sub(y,ay),dy));
        t=f64_div(dot,length);
        if f64_lt(t,0) {t=0;}else if f64_gt(t,f64_from_i64(1)) {t=f64_from_i64(1);}
    }
    return f64_le(f64_hypot(f64_sub(x,f64_add(ax,f64_mul(t,dx))),
        f64_sub(y,f64_add(ay,f64_mul(t,dy)))),0x3f847ae147ae147b);
}
fn pc_web_spline_point(out,p) {
    let scale=f64_from_i64(1000000);
    return pc_curve_point(out,f64_to_i64_round(f64_mul(load64(p),scale)),
        f64_to_i64_round(f64_mul(load64(p+8),scale)));
}
fn pc_web_spline_sample(out,a,b,c,d,depth) {
    if cg_count(out)>=65536 || !cg_step() {return cg_fail("Legacy spline sampling exceeds point budget");}
    if pc_web_spline_flat(a,b,d) && pc_web_spline_flat(a,c,d) {return pc_web_spline_point(out,d);}
    if depth>=20 {return cg_fail("Legacy spline sampling exceeds tolerance budget");}
    let ab=pc_web_spline_mid(a,b);let bc=pc_web_spline_mid(b,c);let cd=pc_web_spline_mid(c,d);
    let left=pc_web_spline_mid(ab,bc);let right=pc_web_spline_mid(bc,cd);let mid=pc_web_spline_mid(left,right);
    return pc_web_spline_sample(out,a,ab,left,mid,depth+1) && pc_web_spline_sample(out,mid,right,cd,d,depth+1);
}
fn pc_web_spline_cubic(out,points,i,j,sx,sy) {
    let a=cg_at(points,i);let d=cg_at(points,j);
    if !sx {return pc_web_spline_sample(out,a,cg_at(points,i+1),cg_at(points,i+2),d,0);}
    if load64(a)==load64(d) && load64(a+8)==load64(d+8) {return cg_fail("Adjacent fit points must be distinct");}
    let b=cg_v(0,0,0);let c=cg_v(0,0,0);let axis=0;let second=sx;
    while axis<16 {
        let x=load64(a+axis);let y=load64(d+axis);let delta=f64_sub(y,x);
        let m0=load64(second+i*8);let m1=load64(second+j*8);
        let ta=f64_sub(delta,f64_div(f64_add(f64_scalbn(m0,1),m1),f64_from_i64(6)));
        let td=f64_add(delta,f64_div(f64_add(m0,f64_scalbn(m1,1)),f64_from_i64(6)));
        store64(b+axis,f64_add(x,f64_div(ta,f64_from_i64(3))));
        store64(c+axis,f64_sub(y,f64_div(td,f64_from_i64(3))));
        axis=axis+8;second=sy;
    }
    return pc_web_spline_sample(out,a,b,c,d,0);
}
fn pc_web_spline_path(row) {
    let record=pc_spline_record(row);if !record {return 0;}
    let points=cg_array();let source=pc_first(load64(record));let limit=f64_from_i64(500);
    let message="Expected a finite legacy spline point";
    while source {
        let x=pc_web_geometry_number(source,"x",message);
        let y=pc_web_geometry_number(source,"y",message);
        if cg_error {return 0;}
        if f64_gt(f64_magnitude(x),limit) || f64_gt(f64_magnitude(y),limit) {return cg_fail("Legacy spline point exceeds coordinate range");}
        cg_push(points,cg_v(x,y,0));source=load64(source+24);
    }
    let n=cg_count(points);let closed=load64(record+16);let step=3;let sx=0;let sy=0;
    if !load64(record+8) {
        step=1;sx=pc_web_spline_second(points,0,closed);sy=pc_web_spline_second(points,8,closed);
    }
    let out=cg_array();let i=0;pc_web_spline_point(out,cg_at(points,0));
    while i+step<n+closed && !cg_error {
        if !pc_web_spline_cubic(out,points,i,(i+step)%n,sx,sy) {return 0;}i=i+step;
    }
    if cg_error {return 0;}return out;
}
fn pc_curve_path(row) {
    if m_eq(j_string(row,"type"),"sketchSpline") {
        if j_value(j_get(row,"legacySplineSampling")) {return pc_web_spline_path(row);}
        return pc_spline_path(row);
    }
    return pc_arc_path(row);
}
