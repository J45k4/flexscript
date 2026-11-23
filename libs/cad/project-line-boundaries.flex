// Intersections of an infinite target line with finite sketch boundaries.
import "profile.flex";
import "project-line-spline.flex";

fn plb_segment(a,b,c,d) {
    let rx=load64(b)-load64(a);let ry=load64(b+8)-load64(a+8);
    let sx=load64(d)-load64(c);let sy=load64(d+8)-load64(c+8);
    let cross=rx*sy-ry*sx;if !cross {return 0;}
    let x=load64(c)-load64(a);let y=load64(c+8)-load64(a+8);
    let u=x*ry-y*rx;
    if cross>0 && (u<0 || u>cross) || cross<0 && (u>0 || u<cross) {return 0;}
    return f64_div(f64_from_i64(x*sy-y*sx),f64_from_i64(cross));
}

fn plb_sweep_hit(x,y,start,sweep) {
    if !sweep {return 1;}
    let tau=6283185307180;
    let angle=f64_to_i64_round(f64_mul(f64_atan2(y,x),f64_from_i64(1000000000000)));
    let delta=angle-start;if sweep<0 {delta=-delta;}
    delta=(delta+3*tau)%tau;
    // Permit a few nanometres of angle rounding at each closed endpoint.
    return delta<=cg_abs(sweep)+10000 || tau-delta<=10000;
}

fn plb_add_parameter(out,parameter) {
    if !parameter {parameter=f64_math_neg(0);}
    return cg_push(out,parameter);
}

// Stretch the rotated ellipse to a unit circle, then project the center onto
// the stretched line. Compute endpoint angles from the perpendicular and
// along-line offsets to avoid cancellation with a distant line origin.
fn plb_ellipse(out,a,b,center,rx,ry,rotation,start,sweep) {
    let u=f64_from_i64(rx);let v=f64_from_i64(ry);
    let c=f64_cos(rotation);let s=f64_sin(rotation);
    let x=f64_from_i64(load64(a)-load64(center));let y=f64_from_i64(load64(a+8)-load64(center+8));
    let dx=f64_from_i64(load64(b)-load64(a));let dy=f64_from_i64(load64(b+8)-load64(a+8));
    let ox=f64_div(f64_add(f64_mul(x,c),f64_mul(y,s)),u);
    let oy=f64_div(f64_sub(f64_mul(y,c),f64_mul(x,s)),v);
    let ux=f64_div(f64_add(f64_mul(dx,c),f64_mul(dy,s)),u);
    let uy=f64_div(f64_sub(f64_mul(dy,c),f64_mul(dx,s)),v);
    let length=f64_sqrt(f64_add(f64_mul(ux,ux),f64_mul(uy,uy)));
    ux=f64_div(ux,length);uy=f64_div(uy,length);
    let along=f64_add(f64_mul(ox,ux),f64_mul(oy,uy));
    let perpendicular=f64_sub(f64_mul(ox,uy),f64_mul(oy,ux));
    let disc=f64_sub(f64_from_i64(1),f64_mul(perpendicular,perpendicular));
    let roundoff=f64_div(f64_from_i64(1),f64_from_i64(1000000000000));
    if f64_lt(disc,f64_math_neg(roundoff)) {return 1;}
    let half=0;if f64_lt(0,disc) {half=f64_sqrt(disc);}
    let near_x=f64_mul(perpendicular,uy);let near_y=f64_math_neg(f64_mul(perpendicular,ux));
    let stride_x=f64_mul(half,ux);let stride_y=f64_mul(half,uy);
    if plb_sweep_hit(f64_sub(near_x,stride_x),f64_sub(near_y,stride_y),start,sweep) {
        plb_add_parameter(out,f64_div(f64_math_neg(f64_add(along,half)),length));
    }
    if half && plb_sweep_hit(f64_add(near_x,stride_x),f64_add(near_y,stride_y),start,sweep) {
        plb_add_parameter(out,f64_div(f64_sub(half,along),length));
    }
    return 1;
}

fn plb_oval(out,a,b,geometry,circular,finite) {
    let center=pc_uv(j_get(geometry,"center"));let rx=0;let ry=0;let rotation=0;
    if circular {rx=pc_pose_number(j_get(geometry,"radius"));ry=rx;}
    else {
        rx=pc_pose_number(j_get(geometry,"width"))/2;ry=pc_pose_number(j_get(geometry,"height"))/2;
        rotation=pc_ellipse_rotation(geometry);
    }
    let start=0;let sweep=0;
    if finite {
        let tau=6283185307180;let scale=1000000000000;
        start=pc_serial_number(j_get(geometry,"startAngle"),12,scale,1000000)%tau;
        sweep=pc_serial_number(j_get(geometry,"sweep"),12,scale,7);
        if !sweep || cg_abs(sweep)>tau {return cg_fail("Invalid boundary arc sweep");}
    }
    if cg_error || rx<=0 || ry<=0 {return cg_fail("Invalid line edit boundary axes");}
    return plb_ellipse(out,a,b,center,rx,ry,rotation,start,sweep);
}

fn plb_capsule_data(geometry) {
    let from=pc_uv(j_get(geometry,"from"));let to=pc_uv(j_get(geometry,"to"));
    let radius=pc_pose_number(j_get(geometry,"width"))/2;
    let dx=load64(to)-load64(from);let dy=load64(to+8)-load64(from+8);
    if cg_error || radius<=0 || !(dx || dy) {return cg_fail("Invalid capsule boundary");}
    let angle=f64_atan2(f64_from_i64(dy),f64_from_i64(dx));
    let r=f64_from_i64(radius);let nx=-f64_to_i64_round(f64_mul(r,f64_sin(angle)));
    let ny=f64_to_i64_round(f64_mul(r,f64_cos(angle)));
    let turn=f64_to_i64_round(f64_mul(angle,f64_from_i64(1000000000000)));
    let data=m_take(40);store64(data,from);store64(data+8,to);store64(data+16,radius);
    store64(data+24,turn);store64(data+32,cg_v(nx,ny,0));return data;
}

fn plb_capsule(out,a,b,geometry) {
    let data=plb_capsule_data(geometry);if !data {return 0;}
    let from=load64(data);let to=load64(data+8);let radius=load64(data+16);let turn=load64(data+24);
    let offset=load64(data+32);let nx=load64(offset);let ny=load64(offset+8);
    let gx=load64(from);let gy=load64(from+8);let hx=load64(to);let hy=load64(to+8);
    cg_push(out,plb_segment(a,b,cg_v(gx+nx,gy+ny,0),cg_v(hx+nx,hy+ny,0)));
    cg_push(out,plb_segment(a,b,cg_v(gx-nx,gy-ny,0),cg_v(hx-nx,hy-ny,0)));
    plb_ellipse(out,a,b,from,radius,radius,0,turn+1570796326795,3141592653590);
    return plb_ellipse(out,a,b,to,radius,radius,0,turn-1570796326795,3141592653590);
}

fn plb_parameters(out,a,b,row) {
    let type=j_string(row,"type");
    if m_eq(type,"sketchLine") {
        cg_push(out,plb_segment(a,b,pc_uv(j_get(row,"p0")),pc_uv(j_get(row,"p1"))));return !cg_error;
    }
    if pc_finite_arc(row) {return plb_oval(out,a,b,pc_curve_geometry(row),pc_circular_arc(row),1);}
    if m_eq(type,"sketchArc") {return cg_fail("Invalid sketch arc");}
    if m_eq(type,"sketchSpline") {return plb_spline(out,a,b,row);}
    if !m_eq(type,"sketchPrimitive") && !m_eq(type,"sketchCornerRectangle") {return 1;}
    let shape=j_get(row,"primitive");let kind=j_string(shape,"type");
    if m_eq(kind,"circle") || m_eq(kind,"ellipse") {
        return plb_oval(out,a,b,shape,m_eq(kind,"circle"),0);
    }
    if m_eq(kind,"capsule") {return plb_capsule(out,a,b,shape);}
    if m_eq(type,"sketchCornerRectangle") || m_eq(kind,"rectangle") || m_eq(kind,"polygon") {
        let points=pc_primitive_loop(row);if !points {return 0;}
        let i=0;let n=cg_count(points);
        while i<n {
            cg_push(out,plb_segment(a,b,cg_at(points,i),cg_at(points,(i+1)%n)));i=i+1;
        }
    }
    return 1;
}
