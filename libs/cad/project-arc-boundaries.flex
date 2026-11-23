// Intersections of a supporting circle with finite sketch boundaries.
// Angles are normalized picoradians, stored at +1 so angle zero is an entry.
import "project-line-boundaries.flex";
import "bounded-polynomial.flex";

fn pab_wrap(angle) {return (angle%6283185307180+6283185307180)%6283185307180;}
fn pab_angle(x,y) {return pab_wrap(f64_to_i64_round(f64_mul(f64_atan2(y,x),f64_from_i64(1000000000000))));}

fn pab_line(out,circle,a,b) {
    if !pc_line_span(a,b) {return 1;}
    let cuts=cg_array();let center=load64(circle);let radius=load64(circle+8);
    plb_ellipse(cuts,a,b,center,radius,radius,0,0,0);
    let x=f64_from_i64(load64(a)-load64(center));let y=f64_from_i64(load64(a+8)-load64(center+8));
    let dx=f64_from_i64(load64(b)-load64(a));let dy=f64_from_i64(load64(b+8)-load64(a+8));
    let margin=f64_div(f64_from_i64(1),f64_from_i64(pc_line_span(a,b)));
    let i=0;while i<cg_count(cuts) {
        let t=cg_at(cuts,i);
        if f64_le(f64_math_neg(margin),t) && f64_le(t,f64_add(f64_from_i64(1),margin)) {
            let at_x=f64_add(x,f64_mul(t,dx));let at_y=f64_add(y,f64_mul(t,dy));
            cg_push(out,pab_angle(at_x,at_y)+1);
        }
        i=i+1;
    }
    return !cg_error;
}

fn pab_circle_contact(out,x,y,dx,dy,start,sweep) {
    if plb_sweep_hit(f64_sub(x,dx),f64_sub(y,dy),start,sweep) {cg_push(out,pab_angle(x,y)+1);}
    return !cg_error;
}

fn pab_circle(out,circle,other,radius,start,sweep) {
    let center=load64(circle);let r=load64(circle+8);
    let x=load64(other)-load64(center);let y=load64(other+8)-load64(center+8);
    let square=x*x+y*y;let far=r+radius;let near=r-radius;
    if !square || square>far*far || square<near*near {return 1;}
    let distance=f64_sqrt(f64_from_i64(square));let dx=f64_from_i64(x);let dy=f64_from_i64(y);
    let axis_x=f64_div(dx,distance);let axis_y=f64_div(dy,distance);
    let a=f64_div(f64_from_i64(r*r-radius*radius+square),f64_add(distance,distance));
    let h=0;let h2=f64_sub(f64_from_i64(r*r),f64_mul(a,a));
    if f64_lt(0,h2) {h=f64_sqrt(h2);}
    let cx=f64_mul(a,axis_x);let cy=f64_mul(a,axis_y);
    let px=f64_mul(h,axis_y);let py=f64_mul(h,axis_x);
    pab_circle_contact(out,f64_sub(cx,px),f64_add(cy,py),dx,dy,start,sweep);
    if h {pab_circle_contact(out,f64_add(cx,px),f64_sub(cy,py),dx,dy,start,sweep);}
    return !cg_error;
}

fn pab_radial_error(path,t) {
    let count=load64(path+16);let radius=load64(path+24);
    let x=pab_polynomial(load64(path),count,t);let y=pab_polynomial(load64(path+8),count,t);
    let distance=f64_sqrt(pls_linear(x,y,x,y));
    if count==3 {distance=f64_div(distance,f64_add(f64_from_i64(1),f64_mul(t,t)));}
    return f64_sub(distance,radius);
}

// Isolate distance roots with the polynomial's extrema, but evaluate the
// distance from the original coordinates. Squared polynomial cancellation
// otherwise misclassifies small circles near long boundaries as tangent.
fn pab_radial_roots(out,values,count,path,min,max,scale) {
    let tiny=f64_div(f64_from_i64(1),f64_from_i64(100000000000000));
    let magnitude=0;let i=0;
    while i<count {let v=f64_magnitude(load64(values+i*8));if v>magnitude {magnitude=v;}i=i+1;}
    if magnitude<tiny {return 0;}
    let derivative=m_take((count-1)*8);i=1;
    while i<count {store64(derivative+(i-1)*8,f64_mul(load64(values+i*8),f64_from_i64(i)));i=i+1;}
    let critical=m_take((count-2)*8);let n=pab_roots(critical,derivative,count-1,min,max);
    let epsilon=f64_div(f64_from_i64(1),f64_mul(scale,f64_from_i64(1000)));
    let lo=min;let low=pab_radial_error(path,lo);let roots=0;
    if f64_magnitude(low)<=epsilon {store64(out,lo);roots=1;}
    i=0;while i<=n && roots<count-1 {
        let hi=max;if i<n {hi=load64(critical+i*8);}
        if f64_lt(lo,hi) {
            let high=pab_radial_error(path,hi);
            if f64_magnitude(high)<=epsilon {store64(out+roots*8,hi);roots=roots+1;}
            else if f64_magnitude(low)>epsilon && f64_lt(low,0)!=f64_lt(high,0) {
                let a=lo;let b=hi;let mid=0;let j=0;let negative=f64_lt(low,0);
                while j<54 {
                    mid=f64_mul(f64_add(a,b),0x3fe0000000000000);
                    let error=pab_radial_error(path,mid);
                    if f64_eq(error,0) {j=54;}
                    else if f64_lt(error,0)==negative {a=mid;}else {b=mid;}
                    j=j+1;
                }
                store64(out+roots*8,mid);roots=roots+1;
            }
            lo=hi;low=high;
        }
        i=i+1;
    }
    return roots;
}

fn pab_spline(out,circle,row) {
    let source=pc_spline_data(row);if !source {return 0;}
    let center=load64(circle);let r=f64_from_i64(load64(circle+8));let one=f64_from_i64(1);
    let cubic=m_take(48);let x=m_take(32);let y=m_take(32);let values=m_take(56);let cuts=m_take(48);
    let path=m_take(32);store64(path,x);store64(path+8,y);store64(path+16,4);
    let i=0;while i<load64(source+8) && !cg_error {
        if !cg_step() || !pc_spline_segment(source,i,cubic) {return 0;}
        pls_controls(x,cubic,center,one,0);pls_controls(y,cubic,center,0,one);
        let scale=r;let j=0;while j<32 {
            let u=f64_magnitude(load64(x+j));let v=f64_magnitude(load64(y+j));
            if u>scale {scale=u;}if v>scale {scale=v;}j=j+8;
        }
        pls_coefficients(x,scale);pls_coefficients(y,scale);pab_coefficients(values,x,y,4);
        let radius=f64_div(r,scale);store64(values,f64_sub(load64(values),f64_mul(radius,radius)));
        store64(path+24,radius);let n=pab_radial_roots(cuts,values,7,path,0,one,scale);j=0;
        while j<n && !cg_error {
            let t=load64(cuts+j*8);cg_push(out,pab_angle(pls_polynomial(x,t),pls_polynomial(y,t))+1);j=j+1;
        }
        i=i+1;
    }
    return !cg_error;
}

fn pab_ellipse(out,circle,geometry,start,sweep) {
    let origin=pc_uv(j_get(geometry,"center"));let cx=load64(circle);let r=load64(circle+8);
    let rx=pc_pose_number(j_get(geometry,"width"))/2;let ry=pc_pose_number(j_get(geometry,"height"))/2;
    if cg_error || rx<=0 || ry<=0 {return cg_fail("Invalid elliptic boundary axes");}
    let rotation=pc_ellipse_rotation(geometry);let c=f64_cos(rotation);let s=f64_sin(rotation);
    let dx=f64_from_i64(load64(origin)-load64(cx));let dy=f64_from_i64(load64(origin+8)-load64(cx+8));
    let scale=rx;if ry>scale {scale=ry;}if r>scale {scale=r;}
    let length=pc_line_span(origin,cx);let largest=rx;if ry>largest {largest=ry;}
    if length>largest+r+1 {return !cg_error;}
    if length>scale {scale=length;}
    let normal=f64_from_i64(scale);
    let u=f64_div(f64_from_i64(rx),normal);let v=f64_div(f64_from_i64(ry),normal);
    let x=f64_div(pls_linear(dx,dy,c,s),normal);let y=f64_div(pls_linear(dy,dx,c,f64_math_neg(s)),normal);
    let radius=f64_div(f64_from_i64(r),normal);let rr=f64_mul(radius,radius);
    let one=f64_from_i64(1);let two=f64_from_i64(2);
    let values=m_take(40);let xs=m_take(24);let ys=m_take(24);let roots=m_take(32);let pass=0;
    let path=m_take(32);store64(path,xs);store64(path+8,ys);store64(path+16,3);store64(path+24,radius);
    // Two half-angle charts cover the full ellipse with parameters in [-1,1].
    while pass<2 && !cg_error {
        store64(xs,f64_add(x,u));store64(xs+8,0);store64(xs+16,f64_sub(x,u));
        store64(ys,y);store64(ys+8,f64_mul(two,v));store64(ys+16,y);
        pab_coefficients(values,xs,ys,3);
        store64(values,f64_sub(load64(values),rr));store64(values+16,f64_sub(load64(values+16),f64_mul(two,rr)));
        store64(values+32,f64_sub(load64(values+32),rr));
        let n=pab_radial_roots(roots,values,5,path,f64_math_neg(one),one,normal);let i=0;
        while i<n && !cg_error {
            let t=load64(roots+i*8);let square=f64_mul(t,t);let den=f64_add(one,square);
            let local_x=f64_div(f64_sub(one,square),den);let local_y=f64_div(f64_mul(two,t),den);
            let test_x=local_x;let test_y=local_y;
            if pass {test_x=f64_math_neg(test_x);test_y=f64_math_neg(test_y);}
            if plb_sweep_hit(test_x,test_y,start,sweep) {
                let px=f64_add(x,f64_mul(u,local_x));let py=f64_add(y,f64_mul(v,local_y));
                cg_push(out,pab_angle(pls_linear(px,py,c,f64_math_neg(s)),pls_linear(px,py,s,c))+1);
            }
            i=i+1;
        }
        u=f64_math_neg(u);v=f64_math_neg(v);pass=pass+1;
    }
    return !cg_error;
}

fn pab_capsule(out,circle,geometry) {
    let data=plb_capsule_data(geometry);if !data {return 0;}
    let from=load64(data);let to=load64(data+8);let radius=load64(data+16);let turn=load64(data+24);
    let offset=load64(data+32);let nx=load64(offset);let ny=load64(offset+8);
    let gx=load64(from);let gy=load64(from+8);let hx=load64(to);let hy=load64(to+8);
    pab_line(out,circle,cg_v(gx+nx,gy+ny,0),cg_v(hx+nx,hy+ny,0));
    pab_line(out,circle,cg_v(gx-nx,gy-ny,0),cg_v(hx-nx,hy-ny,0));
    return pab_circle(out,circle,from,radius,turn+1570796326795,3141592653590)
        && pab_circle(out,circle,to,radius,turn-1570796326795,3141592653590);
}

fn pab_parameters(out,circle,row) {
    let type=j_string(row,"type");
    if m_eq(type,"sketchLine") {return pab_line(out,circle,pc_uv(j_get(row,"p0")),pc_uv(j_get(row,"p1")));}
    if m_eq(type,"sketchSpline") {return pab_spline(out,circle,row);}
    let geometry=pc_curve_geometry(row);let kind=j_string(geometry,"type");
    let arc=pc_circular_arc(row);let start=0;let sweep=0;
    if m_eq(type,"sketchArc") && !pc_finite_arc(row) {return cg_fail("Invalid sketch arc");}
    if arc || m_eq(kind,"ellipticArc") {
        start=pc_serial_number(j_get(geometry,"startAngle"),12,1000000000000,1000000)%6283185307180;
        sweep=pc_serial_number(j_get(geometry,"sweep"),12,1000000000000,7);
        if cg_error || !sweep || cg_abs(sweep)>6283185307180 {return cg_fail("Invalid boundary arc sweep");}
    }
    if arc || m_eq(kind,"circle") {
        let radius=pc_pose_number(j_get(geometry,"radius"));let center=pc_uv(j_get(geometry,"center"));
        if cg_error || radius<=0 {return cg_fail("Invalid circular boundary radius");}
        return pab_circle(out,circle,center,radius,start,sweep);
    }
    if m_eq(kind,"ellipse") || m_eq(kind,"ellipticArc") {return pab_ellipse(out,circle,geometry,start,sweep);}
    if m_eq(kind,"capsule") {return pab_capsule(out,circle,geometry);}
    if m_eq(type,"sketchCornerRectangle") || m_eq(kind,"rectangle") || m_eq(kind,"polygon") {
        let points=pc_primitive_loop(row);if !points {return 0;}
        let n=cg_count(points);let i=0;
        while i<n && !cg_error {pab_line(out,circle,cg_at(points,i),cg_at(points,(i+1)%n));i=i+1;}
    }
    return !cg_error;
}
