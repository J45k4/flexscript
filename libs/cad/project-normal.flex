// Saved Normal relates one line endpoint to the analytic frame of its curve.
import "project-point-on-curve.flex";
import "spline-normal.flex";

fn pc_normal_end(anchor) {
    let end=j_string(anchor,"point");
    return m_eq(end,"p0") || m_eq(end,"p1");
}
fn pc_normal_curve(row) {
    return pc_point_on_curve_kind(row)!=0;
}
fn pc_normal_frame(source,point) {
    let kind=pc_point_on_curve_kind(source);
    if kind==6 {
        let spline=pc_spline_data(source);if !spline {return 0;}
        let frame=m_take(psn_workspace_size());let nearest=psn_frame(spline,point,frame);if !nearest {return 0;}
        return cg_v(psb_contact_point(nearest,point),frame,0);
    }
    if kind==1 {
        let a=pc_uv(j_get(source,"p0"));let b=pc_uv(j_get(source,"p1"));
        let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
        let span=f64_sqrt(f64_from_i64(dx*dx+dy*dy));if cg_error || !span {return cg_fail("Normal needs a nonzero target line");}
        let nearest=pc_point_on_curve_position(source,kind,point);if !nearest {return 0;}
        let tangent=cg_v(f64_div(f64_from_i64(dx),span),f64_div(f64_from_i64(dy),span),0);
        return cg_v(nearest,tangent,0);
    }
    let center=pc_uv(j_get(pc_curve_geometry(source),"center"));if cg_error {return 0;}
    if kind==2 || kind==3 {
        let nearest=pc_point_on_curve_position(source,kind,point);if !nearest {return 0;}
        let tangent=csp_radial_tangent(load64(nearest)-load64(center),load64(nearest+8)-load64(center+8),0);
        return cg_v(nearest,tangent,0);
    }
    let fields=pc_elliptic_contact_fields(source,kind);if !fields {return 0;}
    let range=pc_elliptic_contact_geometry(fields);
    let nearest=cso_nearest(range,load64(point)-load64(center),load64(point+8)-load64(center+8));
    return cg_v(cg_v(load64(center)+load64(nearest),load64(center+8)+load64(nearest+8),0),cso_tangent(range,load64(nearest+16)),0);
}
fn pc_seed_normal(curve,line,end) {
    let other="p1";if m_eq(end,"p1") {other="p0";}
    let foot=j_get(line,end);let tip=j_get(line,other);let p=pc_uv(foot);let q=pc_uv(tip);
    let length=pc_line_span(p,q);if cg_error || !length {return cg_fail("Normal requires a nonzero line");}
    let frame=pc_normal_frame(curve,p);if !frame {return 0;}
    let tangent=load64(frame+8);let ux=f64_math_neg(load64(tangent+8));let uy=load64(tangent);
    let along=f64_add(f64_mul(f64_from_i64(load64(q)-load64(p)),ux),f64_mul(f64_from_i64(load64(q+8)-load64(p+8)),uy));
    if f64_lt(along,0) {ux=f64_math_neg(ux);uy=f64_math_neg(uy);}
    let actual=load64(frame);let len=f64_from_i64(length);
    let x=load64(actual)+f64_to_i64_round(f64_mul(len,ux));let y=load64(actual+8)+f64_to_i64_round(f64_mul(len,uy));
    if cg_abs(x)>500000000 || cg_abs(y)>500000000 {return cg_fail("Normal line exceeds its coordinate range");}
    return po_position(foot,actual,1) && po_position(tip,cg_v(x,y,0),1);
}

fn pc_check_normal(nodes,sk,entry,edited_spline) {
    let rel=load64(entry);let id=load64(entry+8);let anchor=j_get(rel,"a");
    let line=pc_find(nodes,j_string(anchor,"entityId"));let curve=pc_find(nodes,j_string(rel,"b"));
    if !m_len(id) || !pc_normal_end(anchor) || !line || !curve || line==curve || load64(entry+16) ||
       !m_eq(j_string(line,"type"),"sketchLine") || !pc_normal_curve(curve) ||
       !m_eq(j_string(line,"sketchId"),sk) || !m_eq(j_string(curve,"sketchId"),sk) ||
       j_get(rel,"expression") || j_get(rel,"value") || j_value(j_get(rel,"reference")) {
        return cg_fail(m_cat("Invalid normal relation: ",id));
    }
    if curve==edited_spline {return 1;}
    let first=pc_uv(j_get(line,"p0"));let last=pc_uv(j_get(line,"p1"));let foot=first;
    if m_eq(j_string(anchor,"point"),"p1") {foot=last;}
    let length=pc_line_span(first,last);
    let frame=pc_normal_frame(curve,foot);if !frame || cg_error {return 0;}
    let tangent=load64(frame+8);
    let along=f64_add(f64_mul(f64_from_i64(load64(last)-load64(first)),load64(tangent)),
        f64_mul(f64_from_i64(load64(last+8)-load64(first+8)),load64(tangent+8)));
    if !length || pc_line_span(foot,load64(frame))>=1000 || f64_lt(f64_from_i64(length/1000000+1),f64_magnitude(along)) {
        return cg_fail(m_cat("Saved line disagrees with normal relation: ",id));
    }
    return 1;
}
