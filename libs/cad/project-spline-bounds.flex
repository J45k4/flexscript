// Exact cubic coordinates and finite contacts for sketch spline edits.
// Parameters are measured in trillionths of one input spline segment.
import "project-arc-boundaries.flex";
import "spline-contact.flex";

fn psb_split(curve,t,left,right) {
    let axis=0;
    while axis<16 {
        let a=load64(curve+axis);let b=load64(curve+16+axis);
        let c=load64(curve+32+axis);let d=load64(curve+48+axis);
        let ab=psb_mix(a,b,t);let bc=psb_mix(b,c,t);let cd=psb_mix(c,d,t);
        let abc=psb_mix(ab,bc,t);let bcd=psb_mix(bc,cd,t);let cut=psb_mix(abc,bcd,t);
        if left {
            store64(left+axis,a);store64(left+16+axis,ab);
            store64(left+32+axis,abc);store64(left+48+axis,cut);
        }
        if right {
            store64(right+axis,cut);store64(right+16+axis,bcd);
            store64(right+32+axis,cd);store64(right+48+axis,d);
        }
        axis=axis+8;
    }
    return 1;
}

fn psb_line_segment(out,cubic,index,a,b) {
    let dx=f64_from_i64(load64(b)-load64(a));let dy=f64_from_i64(load64(b+8)-load64(a+8));
    let squared=pls_linear(dx,dy,dx,dy);if !squared {return 1;}
    let length=f64_sqrt(squared);let one=f64_from_i64(1);let margin=f64_div(one,length);
    let side=m_take(32);let along=m_take(32);let roots=m_take(24);
    pls_controls(side,cubic,a,f64_math_neg(dy),dx);pls_controls(along,cubic,a,dx,dy);
    let scale=0;let i=0;
    while i<32 {
        let magnitude=f64_magnitude(load64(side+i));if magnitude>scale {scale=magnitude;}
        i=i+8;
    }
    // Coincident spans have no isolated cut parameters.
    if f64_lt(scale,f64_div(length,f64_from_i64(100000))) {return 1;}
    pls_coefficients(side,scale);pls_coefficients(along,squared);
    let count=pab_roots(roots,side,4,0,one);i=0;
    while i<count && !cg_error {
        let t=load64(roots+i*8);let u=pls_polynomial(along,t);
        if f64_le(f64_math_neg(margin),u) && f64_le(u,f64_add(one,margin)) {cg_push(out,psb_parameter(index,t)+1);}
        i=i+1;
    }
    return !cg_error;
}

fn psb_line(out,source,a,b) {
    let cubic=m_take(48);let i=0;
    while i<load64(source+8) && !cg_error {
        if !cg_step() || !pc_spline_segment(source,i,cubic) || !psb_line_segment(out,cubic,i,a,b) {return 0;}
        i=i+1;
    }
    return !cg_error;
}

// Each contact contains the spline parameter and the local ellipse angle.
fn psb_oval_contacts(out,source,center,rx,ry,rotation,start,sweep) {
    if cg_error || rx<=0 || ry<=0 {return cg_fail("Invalid spline edit boundary axes");}
    let one=f64_from_i64(1);let u=f64_from_i64(rx);let v=f64_from_i64(ry);let scale=u;if ry>rx {scale=v;}
    let c=f64_cos(rotation);let s=f64_sin(rotation);
    let cubic=m_take(48);let x=m_take(32);let y=m_take(32);let values=m_take(56);let roots=m_take(48);
    let path=m_take(32);store64(path,x);store64(path+8,y);store64(path+16,4);store64(path+24,one);
    let index=0;
    while index<load64(source+8) && !cg_error {
        if !cg_step() || !pc_spline_segment(source,index,cubic) {return 0;}
        pls_controls(x,cubic,center,c,s);pls_controls(y,cubic,center,f64_math_neg(s),c);
        pls_coefficients(x,u);pls_coefficients(y,v);pab_coefficients(values,x,y,4);
        store64(values,f64_sub(load64(values),one));
        let count=pab_radial_roots(roots,values,7,path,0,one,scale);let i=0;
        while i<count && !cg_error {
            let t=load64(roots+i*8);let px=pls_polynomial(x,t);let py=pls_polynomial(y,t);
            if plb_sweep_hit(px,py,start,sweep) {cg_push(out,cg_v(psb_parameter(index,t),pab_angle(px,py),0));}
            i=i+1;
        }
        index=index+1;
    }
    return !cg_error;
}

fn psb_oval(out,source,center,rx,ry,rotation,start,sweep) {
    let hits=cg_array();if !psb_oval_contacts(hits,source,center,rx,ry,rotation,start,sweep) {return 0;}
    let i=0;while i<cg_count(hits) && !cg_error {cg_push(out,load64(cg_at(hits,i))+1);i=i+1;}
    return !cg_error;
}

fn psb_capsule(out,source,geometry) {
    let data=plb_capsule_data(geometry);if !data {return 0;}
    let a=load64(data);let b=load64(data+8);let radius=load64(data+16);let turn=load64(data+24);
    let offset=load64(data+32);let nx=load64(offset);let ny=load64(offset+8);
    return psb_line(out,source,cg_v(load64(a)+nx,load64(a+8)+ny,0),cg_v(load64(b)+nx,load64(b+8)+ny,0))
        && psb_line(out,source,cg_v(load64(a)-nx,load64(a+8)-ny,0),cg_v(load64(b)-nx,load64(b+8)-ny,0))
        && psb_oval(out,source,a,radius,radius,0,turn+1570796326795,3141592653590)
        && psb_oval(out,source,b,radius,radius,0,turn-1570796326795,3141592653590);
}

fn psb_box(out,curve) {
    let axis=0;
    while axis<16 {
        let low=load64(curve+axis);let high=low;let i=16;
        while i<64 {
            let value=load64(curve+i+axis);
            if f64_lt(value,low) {low=value;}if f64_lt(high,value) {high=value;}i=i+16;
        }
        store64(out+axis,low);store64(out+16+axis,high);axis=axis+8;
    }
    return 1;
}

fn psb_overlap(a,b,margin) {
    return !(f64_lt(f64_add(load64(a+16),margin),load64(b)) || f64_lt(f64_add(load64(b+16),margin),load64(a))
        || f64_lt(f64_add(load64(a+24),margin),load64(b+8)) || f64_lt(f64_add(load64(b+24),margin),load64(a+8)));
}

fn psb_box_span(box) {
    let x=f64_sub(load64(box+16),load64(box));let y=f64_sub(load64(box+24),load64(box+8));
    if f64_lt(x,y) {return y;}return x;
}

fn psb_unit(t) {
    let one=f64_from_i64(1);if f64_lt(t,0) {return 0;}if f64_lt(one,t) {return one;}return t;
}

fn psb_cross(ax,ay,bx,by) {return f64_sub(f64_mul(ax,by),f64_mul(ay,bx));}

fn psb_refine_pair(state,t,u) {
    let a=load64(state+8);let b=load64(state+16);let i=0;
    let threshold=f64_div(f64_from_i64(1),f64_from_i64(1000000));
    let max_step=f64_div(f64_from_i64(1),f64_from_i64(10));
    while i<16 {
        let ax=psb_velocity(a,0,t);let ay=psb_velocity(a,8,t);
        let bx=psb_velocity(b,0,u);let by=psb_velocity(b,8,u);
        let det=psb_cross(ax,ay,bx,by);
        if f64_magnitude(det)<threshold {i=16;}
        else {
            let x=f64_sub(psb_coordinate(b,0,u),psb_coordinate(a,0,t));
            let y=f64_sub(psb_coordinate(b,8,u),psb_coordinate(a,8,t));
            let dt=f64_div(psb_cross(x,y,bx,by),det);let du=f64_div(psb_cross(x,y,ax,ay),det);
            if f64_magnitude(dt)>max_step || f64_magnitude(du)>max_step {i=16;}
            else {
                let next_t=psb_unit(f64_add(t,dt));let next_u=psb_unit(f64_add(u,du));
                if f64_eq(next_t,t) && f64_eq(next_u,u) {i=16;}
                t=next_t;u=next_u;
            }
        }
        i=i+1;
    }
    let x=f64_sub(psb_coordinate(b,0,u),psb_coordinate(a,0,t));
    let y=f64_sub(psb_coordinate(b,8,u),psb_coordinate(a,8,t));
    if f64_le(pls_linear(x,y,x,y),f64_from_i64(1)) {
        let out=load64(state);let hit=psb_parameter(load64(state+24),t)+1;i=0;
        while i<cg_count(out) {
            if cg_abs(cg_at(out,i)-hit)<=10000000 {return 1;}
            i=i+1;
        }
        return cg_push(out,hit);
    }
    return 1;
}

// Split the wider convex hull until a contact is isolated, then refine on
// the original cubics. The scratch frames are reused across branches.
fn psb_search_pair(state,a,b,t0,t1,u0,u1,depth) {
    if !cg_step() {return 0;}
    let visits=load64(state+32)+1;store64(state+32,visits);
    if visits>100000 {return cg_fail("Spline intersections exceed subdivision limit");}
    let frame=load64(state+40)+depth*192;let x=frame;let y=frame+32;
    psb_box(x,a);psb_box(y,b);
    if !psb_overlap(x,y,f64_from_i64(1)) {return 1;}
    let da=psb_box_span(x);let db=psb_box_span(y);let leaf=f64_from_i64(32);
    let half=0x3fe0000000000000;
    let t=f64_mul(f64_add(t0,t1),half);let u=f64_mul(f64_add(u0,u1),half);
    if depth>=52 || (f64_le(da,leaf) && f64_le(db,leaf)) {return psb_refine_pair(state,t,u);}
    let left=frame+64;let right=frame+128;
    if f64_le(db,da) {
        psb_split(a,half,left,right);
        return psb_search_pair(state,left,b,t0,t,u0,u1,depth+1) && psb_search_pair(state,right,b,t,t1,u0,u1,depth+1);
    }
    psb_split(b,half,left,right);
    return psb_search_pair(state,a,left,t0,t1,u0,u,depth+1) && psb_search_pair(state,a,right,t0,t1,u,u1,depth+1);
}

fn psb_same_controls(a,b) {
    let same=1;let reverse=1;let i=0;
    while i<64 && (same || reverse) {
        if !f64_eq(load64(a+i),load64(b+i)) {same=0;}
        if !f64_eq(load64(a+i),load64(b+48-(i/16)*16+i%16)) {reverse=0;}
        i=i+8;
    }
    return same || reverse;
}

fn psb_straight(curve) {
    let dx=f64_sub(load64(curve+48),load64(curve));let dy=f64_sub(load64(curve+56),load64(curve+8));
    let length=pls_linear(dx,dy,dx,dy);if !length {return 0;}
    let limit=f64_div(f64_sqrt(length),f64_from_i64(100000));let previous=0;let i=16;
    while i<48 {
        let x=f64_sub(load64(curve+i),load64(curve));let y=f64_sub(load64(curve+i+8),load64(curve+8));
        let along=pls_linear(dx,dy,x,y);
        if f64_lt(length,along) || f64_lt(along,previous) || f64_lt(limit,f64_magnitude(psb_cross(dx,dy,x,y))) {return 0;}
        previous=along;i=i+16;
    }
    return 1;
}

fn psb_controls_point(controls) {
    return cg_v(f64_to_i64_round(load64(controls)),f64_to_i64_round(load64(controls+8)),0);
}

fn psb_spline(out,source,node) {
    let other=pc_spline_data(node);if !other {return 0;}
    return psb_spline_pair_hits(out,source,other);
}

fn psb_spline_pair_hits(out,source,other) {
    let n=load64(other+8);let controls=m_take(n*64);let boxes=m_take(n*32);let i=0;
    while i<n && !cg_error {
        if !cg_step() || !psb_store_controls(controls+i*64,other,i) {return 0;}
        psb_box(boxes+i*32,controls+i*64);i=i+1;
    }
    let state=m_take(48);let a=m_take(64);let raw=m_take(48);let box=m_take(32);
    store64(state,out);store64(state+8,a);store64(state+32,0);store64(state+40,m_take(53*192));
    let candidates=0;let one=f64_from_i64(1);i=0;
    while i<load64(source+8) && !cg_error {
        if !psb_store_controls(a,source,i) || !pc_spline_segment(source,i,raw) {return 0;}
        psb_box(box,a);store64(state+24,i);let j=0;
        while j<n && !cg_error {
            if !cg_step() {return 0;}
            let b=controls+j*64;
            if psb_overlap(box,boxes+j*32,one) && !psb_same_controls(a,b) {
                candidates=candidates+1;if candidates>4096 {return cg_fail("Spline intersections exceed candidate-pair limit");}
                if psb_straight(b) {
                    if !psb_line_segment(out,raw,i,psb_controls_point(b),psb_controls_point(b+48)) {return 0;}
                }else {
                    store64(state+16,b);if !psb_search_pair(state,a,b,0,one,0,one,0) {return 0;}
                }
            }
            j=j+1;
        }
        i=i+1;
    }
    return !cg_error;
}

fn psb_parameters(out,source,row) {
    let type=j_string(row,"type");
    if m_eq(type,"sketchLine") {return psb_line(out,source,pc_uv(j_get(row,"p0")),pc_uv(j_get(row,"p1")));}
    if m_eq(type,"sketchSpline") {return psb_spline(out,source,row);}
    let geometry=pc_curve_geometry(row);let kind=j_string(geometry,"type");
    let arc=pc_circular_arc(row);let start=0;let sweep=0;
    if m_eq(type,"sketchArc") && !pc_finite_arc(row) {return cg_fail("Invalid sketch arc");}
    if arc || m_eq(kind,"ellipticArc") {
        start=pc_serial_number(j_get(geometry,"startAngle"),12,1000000000000,1000000)%6283185307180;
        sweep=pc_serial_number(j_get(geometry,"sweep"),12,1000000000000,7);
        if cg_error || !sweep || cg_abs(sweep)>6283185307180 {return cg_fail("Invalid boundary arc sweep");}
    }
    if arc || m_eq(kind,"circle") {
        let radius=pc_pose_number(j_get(geometry,"radius"));
        return psb_oval(out,source,pc_uv(j_get(geometry,"center")),radius,radius,0,start,sweep);
    }
    if m_eq(kind,"ellipse") || m_eq(kind,"ellipticArc") {
        let rx=pc_pose_number(j_get(geometry,"width"))/2;let ry=pc_pose_number(j_get(geometry,"height"))/2;
        return psb_oval(out,source,pc_uv(j_get(geometry,"center")),rx,ry,pc_ellipse_rotation(geometry),start,sweep);
    }
    if m_eq(kind,"capsule") {return psb_capsule(out,source,geometry);}
    if m_eq(type,"sketchCornerRectangle") || m_eq(kind,"rectangle") || m_eq(kind,"polygon") {
        let points=pc_primitive_loop(row);if !points {return 0;}
        let count=cg_count(points);let i=0;
        while i<count && !cg_error {
            if !psb_line(out,source,cg_at(points,i),cg_at(points,(i+1)%count)) {return 0;}
            i=i+1;
        }
    }
    return !cg_error;
}
