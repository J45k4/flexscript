// A chord is perpendicular to the tangent at its constrained curve contact.
import "sketch-point-on-ellipse.flex";
import "circular-arc-contact.flex";

fn csn_constraint(row,edge,names,pending) {
    let id=j_string(row,"id");let name=j_string(row,"point");let center=j_integer(names,name);
    let end=j_string(row,"endpoint");let first=load64(edge);let last=load64(edge+8);
    if !center || center==first || center==last || load64(edge+16) || j_get(row,"reference_segment") ||
       (!m_eq(end,"p0") && !m_eq(end,"p1")) {return cg_fail(m_cat("Normal needs a straight line endpoint and distinct curve center: ",id));}
    let range=0;let radius=0;
    if m_eq(j_string(row,"type"),"line-circle-normal") {
        radius=j_integer(row,"radius_nm");
        if radius<=0 || radius>500000000 || j_kind(j_get(row,"radius_nm"))!=1 || j_get(row,"parameter") {
            return cg_fail(m_cat("Normal to a circular curve needs a positive radius: ",id));
        }
    }else {range=cso_constraint_range(row,id);if !range {return 0;}}
    let item=m_take(72);store64(item,id);store64(item+8,edge);store64(item+16,13);store64(item+24,radius);
    store64(item+40,center);store64(item+56,m_eq(end,"p1"));store64(item+64,range);
    cg_push(pending,item);return 1;
}

fn csn_attach(item,x,y) {
    let edge=load64(item+8);let from=load64(edge);let to=load64(edge+8);
    let center=load64(item+40);let foot=from;if load64(item+56) {foot=to;}
    store64(item+8,csm_axis(x,from,to));store64(item+32,csm_axis(y,from,to));
    store64(item+40,csm_axis(x,center,foot));store64(item+48,csm_axis(y,center,foot));
    return 1;
}

fn csn_frame(item,x,y,state) {
    let dx=csm_delta(x,load64(item+8));let dy=csm_delta(y,load64(item+32));
    let px=csm_delta(x,load64(item+40));let py=csm_delta(y,load64(item+48));
    if cg_abs(dx)>1000000000 || cg_abs(dy)>1000000000 || cg_abs(px)>1000000000 || cg_abs(py)>1000000000 {return 0;}
    let length=cg_sqrt(dx*dx+dy*dy);if !length {return 0;}
    let range=load64(item+64);let tangent=0;let curvature=0;
    if range {
        let hit=cso_nearest(range,px,py);tangent=cso_tangent(range,load64(hit+16));
        let speed=load64(tangent+16);let axes=load64(range);
        curvature=f64_mul(f64_div(f64_div(load64(axes),speed),speed),f64_div(load64(axes+8),speed));
    }else {
        tangent=csp_radial_tangent(px,py,load64(item+24));curvature=f64_div(f64_from_i64(1),load64(tangent+16));
    }
    let tx=load64(tangent);let ty=load64(tangent+8);let ux=f64_from_i64(dx);let uy=f64_from_i64(dy);
    store64(state,tx);store64(state+8,ty);
    store64(state+16,f64_mul(curvature,f64_sub(f64_mul(uy,tx),f64_mul(ux,ty))));
    store64(state+24,f64_add(f64_mul(ux,tx),f64_mul(uy,ty)));store64(state+32,length);
    return 1;
}

// Along the supporting curve, dT/ds is curvature times the left normal.
// Accumulate that foot derivative and the chord derivative on shared roots.
fn csn_gradient(row,item,state) {
    let beta=load64(state+16);let scale=f64_from_i64(1);
    if f64_lt(scale,f64_magnitude(beta)) {scale=f64_magnitude(beta);}
    let million=f64_from_i64(1000000);let chord=f64_div(million,scale);let foot=f64_mul(chord,beta);
    let tx=load64(state);let ty=load64(state+8);
    csm_gradient(row,load64(item+8),f64_to_i64_round(f64_mul(tx,chord)),0);
    csm_gradient(row,load64(item+32),f64_to_i64_round(f64_mul(ty,chord)),32);
    csm_gradient(row,load64(item+40),f64_to_i64_round(f64_mul(tx,foot)),0);
    csm_gradient(row,load64(item+48),f64_to_i64_round(f64_mul(ty,foot)),32);
    return scale;
}

fn csn_project(item,x,y,apply,row,state) {
    if !csn_frame(item,x,y,state) {return 0;}
    return csn_project_frame(item,x,y,apply,row,state);
}
fn csn_project_frame(item,x,y,apply,row,state) {
    let length=load64(state+32);let residual=load64(state+24);
    if f64_le(f64_magnitude(residual),f64_from_i64(length/1000000+1)) {return 1;}
    if !apply {return 0;}
    csm_clear_gradient(row);let scale=csn_gradient(row,item,state);
    let peak=csm_normalize_gradient(row);if !peak {return 0;}
    let error=f64_to_i64_round(f64_div(f64_mul(f64_div(residual,scale),f64_from_i64(1000000)),f64_from_i64(peak)));
    return csm_displace(row,x,y,error,length/2+1);
}

fn csn_line_frame(item,x,y,state) {
    let dx=csm_delta(x,load64(item+8));let dy=csm_delta(y,load64(item+32));
    let sx=csm_delta(x,load64(item+40));let sy=csm_delta(y,load64(item+48));
    if cg_abs(dx)>1000000000 || cg_abs(dy)>1000000000 || cg_abs(sx)>1000000000 || cg_abs(sy)>1000000000 {return 0;}
    let length=cg_sqrt(dx*dx+dy*dy);let span=f64_sqrt(f64_from_i64(sx*sx+sy*sy));if !length || !span {return 0;}
    let tx=f64_div(f64_from_i64(sx),span);let ty=f64_div(f64_from_i64(sy),span);
    let ux=f64_from_i64(dx);let uy=f64_from_i64(dy);
    let residual=f64_add(f64_mul(ux,tx),f64_mul(uy,ty));
    store64(state,tx);store64(state+8,ty);
    store64(state+16,f64_div(f64_sub(ux,f64_mul(residual,tx)),span));store64(state+24,f64_div(f64_sub(uy,f64_mul(residual,ty)),span));
    store64(state+32,residual);store64(state+40,length);return 1;
}

// The dot product with the source unit tangent varies with either line.
fn csn_line_gradient(row,item,state) {
    let gx=load64(state+16);let gy=load64(state+24);
    let scale=f64_from_i64(1);
    if f64_lt(scale,f64_magnitude(gx)) {scale=f64_magnitude(gx);}
    if f64_lt(scale,f64_magnitude(gy)) {scale=f64_magnitude(gy);}
    let weight=f64_div(f64_from_i64(1000000),scale);
    csm_gradient(row,load64(item+8),f64_to_i64_round(f64_mul(load64(state),weight)),0);
    csm_gradient(row,load64(item+32),f64_to_i64_round(f64_mul(load64(state+8),weight)),32);
    csm_gradient(row,load64(item+40),f64_to_i64_round(f64_mul(gx,weight)),0);
    csm_gradient(row,load64(item+48),f64_to_i64_round(f64_mul(gy,weight)),32);
    return weight;
}

fn csn_line_project(item,x,y,apply,row,state) {
    if !csn_line_frame(item,x,y,state) {return 0;}
    let residual=load64(state+32);let length=load64(state+40);
    if f64_le(f64_magnitude(residual),f64_from_i64(length/1000000+1)) {return 1;}
    if !apply {return 0;}
    csm_clear_gradient(row);let weight=csn_line_gradient(row,item,state);
    let peak=csm_normalize_gradient(row);if !peak {return 0;}
    let error=f64_to_i64_round(f64_div(f64_mul(residual,weight),f64_from_i64(peak)));
    return csm_displace(row,x,y,error,length/2+1);
}
