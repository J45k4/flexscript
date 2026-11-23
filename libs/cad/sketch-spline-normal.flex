import "spline-normal.flex";
import "sketch-ellipse-normal.flex";

fn cssn_constraint(row,edge,pending) {
    let id=j_string(row,"id");let end=j_string(row,"endpoint");
    if load64(edge+16) || j_get(row,"reference_segment") || j_get(row,"parameter") ||
        (!m_eq(end,"p0") && !m_eq(end,"p1")) {return cg_fail(m_cat("Spline normal needs a straight line endpoint: ",id));}
    let source=pc_spline_data(j_get(row,"curve"));if !source {return 0;}
    let item=m_take(72);store64(item,id);store64(item+8,edge);store64(item+16,15);
    store64(item+56,m_eq(end,"p1"));store64(item+64,cg_v(source,m_take(24+psn_workspace_size()),0));
    cg_push(pending,item);return 1;
}

fn cssn_attach(item,x,y) {
    let edge=load64(item+8);let from=load64(edge);let to=load64(edge+8);
    let foot=from;if load64(item+56) {foot=to;}
    store64(item+8,csm_axis(x,from,to));store64(item+32,csm_axis(y,from,to));
    store64(item+40,csm_axis(x,0,foot));store64(item+48,csm_axis(y,0,foot));return 1;
}

fn cssn_frame(item,x,y,state) {
    let dx=csm_delta(x,load64(item+8));let dy=csm_delta(y,load64(item+32));
    if cg_abs(dx)>1000000000 || cg_abs(dy)>1000000000 {return 0;}
    let length=cg_sqrt(dx*dx+dy*dy);if !length {return 0;}
    let setup=load64(item+64);let point=load64(setup+8);let frame=point+24;
    store64(point,csm_delta(x,load64(item+40)));store64(point+8,csm_delta(y,load64(item+48)));
    let nearest=psn_frame(load64(setup),point,frame);if !nearest {return 0;}
    let tx=load64(frame);let ty=load64(frame+8);let curvature=load64(frame+16);
    let t=load64(nearest+24);
    // An endpoint reached beyond the finite span stays fixed while the
    // nearest-point row brings the follower back onto the curve.
    if (!t || t==f64_from_i64(1)) && f64_lt(f64_from_i64(4),load64(nearest+8)) {curvature=0;}
    let ux=f64_from_i64(dx);let uy=f64_from_i64(dy);
    store64(state,tx);store64(state+8,ty);
    store64(state+16,f64_mul(curvature,f64_sub(f64_mul(uy,tx),f64_mul(ux,ty))));
    store64(state+24,f64_add(f64_mul(ux,tx),f64_mul(uy,ty)));store64(state+32,length);return 1;
}

fn cssn_project(item,x,y,apply,row,state) {
    if !cssn_frame(item,x,y,state) {return 0;}
    return csn_project_frame(item,x,y,apply,row,state);
}
