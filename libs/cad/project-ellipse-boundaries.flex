// Analytic finite contacts measured on an ellipse's supporting curve.
import "project-arc-boundaries.flex";
import "project-spline-bounds.flex";

fn pbe_support(center,rx,ry,rotation,start,sweep) {
    if rx<=0 || ry<=0 || cg_error {return cg_fail("Invalid ellipse axes");}
    let data=m_take(72);let minor=rx;if ry<minor {minor=ry;}
    store64(data,center);store64(data+8,minor);store64(data+16,start);store64(data+24,sweep);
    store64(data+32,rx);store64(data+40,ry);store64(data+48,rotation);
    store64(data+56,f64_cos(rotation));store64(data+64,f64_sin(rotation));return data;
}

fn pbe_data(node) {
    let geometry=pc_curve_geometry(node);let center=pc_uv(j_get(geometry,"center"));
    let start=0;let sweep=0;let rotation=0;let rx=0;let ry=0;
    if pc_finite_arc(node) {
        start=pab_wrap(pc_serial_number(j_get(geometry,"startAngle"),12,1000000000000,1000000));
        sweep=pc_serial_number(j_get(geometry,"sweep"),12,1000000000000,7);
        if !sweep || cg_abs(sweep)>6283185307180 {return cg_fail("Invalid boundary arc sweep");}
    }
    if pc_sketch_circle(node) || pc_circular_arc(node) {
        rx=pc_pose_number(j_get(geometry,"radius"));ry=rx;
    }else {
        rx=pc_pose_number(j_get(geometry,"width"))/2;ry=pc_pose_number(j_get(geometry,"height"))/2;
        rotation=pc_ellipse_rotation(geometry);
    }
    return pbe_support(center,rx,ry,rotation,start,sweep);
}

fn pbe_axes(ellipse,x,y) {
    let c=load64(ellipse+56);let s=load64(ellipse+64);
    return cg_v(f64_div(pls_linear(x,y,c,s),f64_from_i64(load64(ellipse+32))),
        f64_div(pls_linear(y,x,c,f64_math_neg(s)),f64_from_i64(load64(ellipse+40))),0);
}

fn pbe_relative(ellipse,point) {
    let center=load64(ellipse);
    return pbe_axes(ellipse,f64_from_i64(load64(point)-load64(center)),f64_from_i64(load64(point+8)-load64(center+8)));
}

fn pbe_segment(out,target,a,b) {
    let length=pc_line_span(a,b);if !length {return 1;}
    let cuts=cg_array();
    plb_ellipse(cuts,a,b,load64(target),load64(target+32),load64(target+40),load64(target+48),0,0);
    let origin=pbe_relative(target,a);
    let stride=pbe_axes(target,f64_from_i64(load64(b)-load64(a)),f64_from_i64(load64(b+8)-load64(a+8)));
    let margin=f64_div(f64_from_i64(1),f64_from_i64(length));
    let low=f64_math_neg(margin);let high=f64_add(f64_from_i64(1),margin);let i=0;
    while i<cg_count(cuts) && !cg_error {
        let t=cg_at(cuts,i);
        if f64_le(low,t) && f64_le(t,high) {
            let x=f64_add(load64(origin),f64_mul(load64(stride),t));
            let y=f64_add(load64(origin+8),f64_mul(load64(stride+8),t));
            cg_push(out,pab_angle(x,y)+1);
        }
        i=i+1;
    }
    return !cg_error;
}

fn pbe_same_support(target,boundary) {
    let a=load64(target);let b=load64(boundary);
    if load64(a)!=load64(b) || load64(a+8)!=load64(b+8) {return 0;}
    let rx=load64(target+32);let ry=load64(target+40);
    let sx=load64(boundary+32);let sy=load64(boundary+40);
    let radians=f64_sub(load64(target+48),load64(boundary+48));
    let degrees=f64_div(f64_mul(radians,f64_from_i64(180000000)),0x400921fb54442d18);
    let turn=cg_abs(f64_to_i64_round(degrees))%180000000;
    if rx==sx && ry==sy {return !turn || rx==ry;}
    return rx==sy && ry==sx && turn==90000000;
}

// Express the boundary center and both semi-axis vectors in the target's
// unit-circle space. Each half-angle chart gives a quartic with finite roots.
fn pbe_conic(out,target,boundary) {
    if !boundary {return 0;}
    if pbe_same_support(target,boundary) {return 1;}
    let scale=load64(target+32);if load64(target+40)>scale {scale=load64(target+40);}
    let max_other=load64(boundary+32);if load64(boundary+40)>max_other {max_other=load64(boundary+40);}
    if pc_line_span(load64(target),load64(boundary))>scale+max_other+1 {return 1;}
    let origin=pbe_relative(target,load64(boundary));let x=load64(origin);let y=load64(origin+8);
    let bx=f64_from_i64(load64(boundary+32));let by=f64_from_i64(load64(boundary+40));
    let cosine=load64(boundary+56);let sine=load64(boundary+64);
    let u=pbe_axes(target,f64_mul(bx,cosine),f64_mul(bx,sine));
    let v=pbe_axes(target,f64_math_neg(f64_mul(by,sine)),f64_mul(by,cosine));
    let ux=load64(u);let uy=load64(u+8);let vx=load64(v);let vy=load64(v+8);
    let one=f64_from_i64(1);let two=f64_from_i64(2);
    let xs=m_take(24);let ys=m_take(24);let values=m_take(40);let roots=m_take(32);
    let path=m_take(32);store64(path,xs);store64(path+8,ys);store64(path+16,3);store64(path+24,one);
    let pass=0;while pass<2 && !cg_error {
        store64(xs,f64_add(x,ux));store64(xs+8,f64_mul(two,vx));store64(xs+16,f64_sub(x,ux));
        store64(ys,f64_add(y,uy));store64(ys+8,f64_mul(two,vy));store64(ys+16,f64_sub(y,uy));
        pab_coefficients(values,xs,ys,3);
        store64(values,f64_sub(load64(values),one));store64(values+16,f64_sub(load64(values+16),two));
        store64(values+32,f64_sub(load64(values+32),one));
        let n=pab_radial_roots(roots,values,5,path,f64_math_neg(one),one,f64_from_i64(scale));
        let i=0;while i<n && !cg_error {
            let t=load64(roots+i*8);
            let local_x=f64_sub(one,f64_mul(t,t));let local_y=f64_mul(two,t);
            if pass {local_x=f64_math_neg(local_x);local_y=f64_math_neg(local_y);}
            if plb_sweep_hit(local_x,local_y,load64(boundary+16),load64(boundary+24)) {
                cg_push(out,pab_angle(pab_polynomial(xs,3,t),pab_polynomial(ys,3,t))+1);
            }
            i=i+1;
        }
        ux=f64_math_neg(ux);uy=f64_math_neg(uy);vx=f64_math_neg(vx);vy=f64_math_neg(vy);pass=pass+1;
    }
    return !cg_error;
}

fn pbe_slot(out,target,shape) {
    let data=plb_capsule_data(shape);if !data {return 0;}
    let from=load64(data);let to=load64(data+8);let radius=load64(data+16);let turn=load64(data+24);
    let offset=load64(data+32);let nx=load64(offset);let ny=load64(offset+8);
    let ax=load64(from);let ay=load64(from+8);let bx=load64(to);let by=load64(to+8);
    return pbe_segment(out,target,cg_v(ax+nx,ay+ny,0),cg_v(bx+nx,by+ny,0))
        && pbe_segment(out,target,cg_v(ax-nx,ay-ny,0),cg_v(bx-nx,by-ny,0))
        && pbe_conic(out,target,pbe_support(from,radius,radius,0,turn+1570796326795,3141592653590))
        && pbe_conic(out,target,pbe_support(to,radius,radius,0,turn-1570796326795,3141592653590));
}

fn pbe_spline(out,target,row) {
    let source=pc_spline_data(row);if !source {return 0;}
    let hits=cg_array();
    if !psb_oval_contacts(hits,source,load64(target),load64(target+32),load64(target+40),load64(target+48),0,0) {return 0;}
    let i=0;while i<cg_count(hits) && !cg_error {cg_push(out,load64(cg_at(hits,i)+8)+1);i=i+1;}
    return !cg_error;
}

fn pbe_ellipse_contacts(out,target,row) {
    let type=j_string(row,"type");
    if m_eq(type,"sketchLine") {return pbe_segment(out,target,pc_uv(j_get(row,"p0")),pc_uv(j_get(row,"p1")));}
    if m_eq(type,"sketchSpline") {return pbe_spline(out,target,row);}
    if pc_ellipse_entity(row) || pc_circular_arc(row) || pc_sketch_circle(row) {return pbe_conic(out,target,pbe_data(row));}
    if pc_capsule_entity(row) {return pbe_slot(out,target,j_get(row,"primitive"));}
    if m_eq(type,"sketchCornerRectangle") || pc_rectangular_entity(row) || pc_polygon_entity(row) {
        let points=pc_primitive_loop(row);if !points {return 0;}
        let n=cg_count(points);let i=0;
        while i<n && !cg_error {pbe_segment(out,target,cg_at(points,i),cg_at(points,(i+1)%n));i=i+1;}
    }
    return !cg_error;
}
