// Whole-curve tangency. Every finite arc must contain the contact point.
// Angles use picoradians and center distances use nanometres.
import "project-mirror-arc.flex";
import "sketch-ellipse-support.flex";

fn pct_kind(kind) {return m_eq(kind,"tangent") || m_eq(kind,"internalTangent");}
fn pct_circular(node) {
    return pc_circular_arc(node) ||
        (m_eq(j_string(node,"type"),"sketchPrimitive") && m_eq(j_string(j_get(node,"primitive"),"type"),"circle"));
}
fn pct_line(node) {return m_eq(j_string(node,"type"),"sketchLine");}
fn pct_line_curve(node) {return pct_circular(node) || pc_ellipse_entity(node);}
fn pct_line_contact_pair(a,b) {return (pct_line(a) && pct_line_curve(b)) || (pct_line(b) && pct_line_curve(a));}
fn pct_shape(node) {
    let arc=pc_circular_arc(node);let geometry=pc_curve_geometry(node);
    let center=pc_uv(j_get(geometry,"center"));let radius=0;let oval=0;let start=0;let sweep=0;
    if pc_ellipse_entity(node) {
        let rx=pc_pose_number(j_get(geometry,"width"))/2;let ry=pc_pose_number(j_get(geometry,"height"))/2;
        if rx<=0 || ry<=0 {return cg_fail("Elliptic tangency needs positive axes");}
        radius=rx;if ry<radius {radius=ry;}
        oval=cse_support_axes(rx,ry,pc_ellipse_rotation(geometry));
        if m_eq(j_string(geometry,"type"),"ellipticArc") {
            start=pma_start(geometry);sweep=pc_serial_number(j_get(geometry,"sweep"),12,1000000000000,7);
            if !sweep || cg_abs(sweep)>6283185307180 {return cg_fail("Invalid elliptic arc sweep");}
        }
    }else {
        radius=pc_pose_number(j_get(geometry,"radius"));
        if arc {start=pma_start(geometry);sweep=pma_sweep(geometry);}
    }
    if cg_error {return 0;}
    if radius<=0 {return cg_fail("Circular tangency needs positive radii");}
    let shape=m_take(40);store64(shape,center);store64(shape+8,radius);store64(shape+16,start);store64(shape+24,sweep);store64(shape+32,oval);
    return shape;
}
fn pct_distance(a,b,internal,id) {
    let first=load64(a+8);let second=load64(b+8);let distance=first+second;
    if internal {distance=first-second;}
    if distance<10000 || distance>500000000 {return cg_fail(m_cat("Circular tangent center separation must be 0.01 to 500 mm: ",id));}
    return distance;
}
fn pct_angle(a,b) {
    let x=f64_from_i64(load64(b)-load64(a));let y=f64_from_i64(load64(b+8)-load64(a+8));
    return f64_to_i64_round(f64_mul(f64_atan2(y,x),f64_from_i64(1000000000000)));
}
fn pct_on_arc(circle,angle) {
    let sweep=load64(circle+24);if !sweep {return 1;}
    let tau=6283185307180;let delta=angle-load64(circle+16);
    if sweep<0 {delta=-delta;}
    delta=(delta%tau+tau)%tau;
    return delta<=cg_abs(sweep)+10000000 || tau-delta<=10000000;
}
// Normal and signed center distance for the oriented supporting line. The
// projected contact may lie beyond the endpoints of the stored segment.
fn pct_line_frame(line,shape) {
    let start=pc_uv(j_get(line,"p0"));let end=pc_uv(j_get(line,"p1"));let center=load64(shape);
    if cg_error {return 0;}
    let dx=load64(end)-load64(start);let dy=load64(end+8)-load64(start+8);
    if !dx && !dy {return cg_fail("Line tangent requires a nonzero line");}
    let length=f64_sqrt(f64_from_i64(dx*dx+dy*dy));
    let nx=f64_div(f64_from_i64(-dy),length);let ny=f64_div(f64_from_i64(dx),length);
    let cx=f64_from_i64(load64(center)-load64(start));let cy=f64_from_i64(load64(center+8)-load64(start+8));
    let frame=m_take(40);let extent=f64_from_i64(load64(shape+8));let tx=nx;let ty=ny;
    let oval=load64(shape+32);
    if oval {
        let support=cse_support(oval,nx,ny,m_take(40));
        extent=load64(support);tx=load64(support+24);ty=load64(support+32);
    }
    store64(frame,nx);store64(frame+8,ny);store64(frame+16,f64_add(f64_mul(cx,nx),f64_mul(cy,ny)));
    store64(frame+24,extent);store64(frame+32,f64_to_i64_round(f64_mul(f64_atan2(ty,tx),f64_from_i64(1000000000000))));
    return frame;
}
fn pct_line_side(frame) {if f64_lt(load64(frame+16),0) {return -1;}return 1;}
fn pct_line_arc_covered(shape,frame,side) {
    let angle=load64(frame+32);if side>0 {angle=angle+3141592653590;}
    return pct_on_arc(shape,angle);
}
fn pct_covered(a,b,internal,angle) {
    let other=angle;if !internal {other=other+3141592653590;}
    return pct_on_arc(a,angle) && pct_on_arc(b,other);
}
fn pct_center_at(center,angle,distance) {
    let radians=f64_div(f64_from_i64(angle),f64_from_i64(1000000000000));let delta=f64_from_i64(distance);
    let x=load64(center)+f64_to_i64_round(f64_mul(f64_cos(radians),delta));
    let y=load64(center+8)+f64_to_i64_round(f64_mul(f64_sin(radians),delta));
    if cg_abs(x)>500000000 || cg_abs(y)>500000000 {return 0;}
    return cg_v(x,y,0);
}
fn pct_contact_center(a,b,internal,distance) {
    let center=load64(a);let preferred=pct_angle(center,load64(b));
    if pct_covered(a,b,internal,preferred) {return pct_center_at(center,preferred,distance);}
    // If the nearest direction misses a finite arc, the closest common
    // direction lies at an endpoint of one of the intervals.
    let candidates=cg_array();let i=0;
    while i<2 {
        let arc=a;let offset=0;if i {arc=b;if !internal {offset=-3141592653590;}}
        let sweep=load64(arc+24);let start=load64(arc+16)+offset;
        if sweep {
            cg_push(candidates,cg_v(start,0,0));cg_push(candidates,cg_v(start+sweep,0,0));
            cg_push(candidates,cg_v(start+sweep/2,0,0));
        }
        i=i+1;
    }
    let best=-1;let result=0;i=0;
    while i<cg_count(candidates) {
        let angle=load64(cg_at(candidates,i));let cost=cg_abs(pma_wrap(angle-preferred));
        if (best<0 || cost<best) && pct_covered(a,b,internal,angle) {
            let at=pct_center_at(center,angle,distance);if at {best=cost;result=at;}
        }
        i=i+1;
    }
    return result;
}
