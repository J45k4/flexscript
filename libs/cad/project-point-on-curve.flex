import "project-mirror-arc.flex";
import "circular-arc-contact.flex";
import "elliptic-contact.flex";
import "spline-contact.flex";

fn pc_point_on_curve_kind(node) {
    if m_eq(j_string(node,"type"),"sketchLine") {return 1;}
    if pc_sketch_circle(node) {return 2;}
    if pc_circular_arc(node) {return 3;}
    if pc_elliptic_arc(node) {return 5;}
    if pc_ellipse_entity(node) {return 4;}
    if m_eq(j_string(node,"type"),"sketchSpline") {return 6;}
    return 0;
}

// Curves without editable affine anchors carry their saved source geometry
// with this adapter record. The pointer is never stored in the document.
fn pc_point_on_curve_entry(row,id,source) {
    let entry=m_take(32);store64(entry,row);store64(entry+8,id);store64(entry+16,0);
    store64(entry+24,source);return entry;
}

fn pc_elliptic_contact_fields(node,kind) {
    let geometry=pc_curve_geometry(node);
    let rx=pc_pose_number(j_get(geometry,"width"))/2;let ry=pc_pose_number(j_get(geometry,"height"))/2;
    let rotation=pc_serial_number(j_get(geometry,"rotation"),6,1000000,1000000)%360000000;
    let start=0;let sweep=0;
    if kind==5 {
        start=pma_start(geometry);sweep=pc_serial_number(j_get(geometry,"sweep"),12,1000000000000,7);
        if !sweep || cg_abs(sweep)>6283185307180 {return cg_fail("Point on an elliptic arc needs a finite sweep");}
    }
    if cg_error || rx<=0 || ry<=0 {return cg_fail("Point on an ellipse needs positive axes");}
    let fields=m_take(40);store64(fields,rx);store64(fields+8,ry);store64(fields+16,rotation);
    store64(fields+24,start);store64(fields+32,sweep);return fields;
}
fn pc_elliptic_contact_geometry(fields) {
    let angle=f64_mul(f64_div(f64_from_i64(load64(fields+16)),f64_from_i64(180000000)),0x400921fb54442d18);
    return cso_range(load64(fields),load64(fields+8),angle,load64(fields+24),load64(fields+32));
}
fn pc_model_elliptic_contact(row,fields) {
    cg_j_int(row,"rx_nm",load64(fields));cg_j_int(row,"ry_nm",load64(fields+8));
    cg_j_int(row,"rotation_microdegrees",load64(fields+16));
    cg_j_int(row,"start_picorad",load64(fields+24));cg_j_int(row,"sweep_picorad",load64(fields+32));
    return 1;
}
fn pc_model_round_contact(row,curve,kind) {
    cg_j_int(row,"radius_nm",pc_circle_measure(curve,"radius"));
    if kind==3 {
        let arc=pc_curve_geometry(curve);
        cg_j_int(row,"start_picorad",pma_start(arc));cg_j_int(row,"sweep_picorad",pma_sweep(arc));
        return "point-on-arc";
    }
    return "point-on-circle";
}

fn pc_point_on_curve_position(curve,kind,point) {
    if kind==6 {
        let source=pc_spline_data(curve);if !source {return 0;}
        let hit=psb_nearest(source,point,0);if !hit {return 0;}
        return psb_contact_point(hit,point);
    }
    if kind==1 {
        let a=pc_uv(j_get(curve,"p0"));let b=pc_uv(j_get(curve,"p1"));
        let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
        let length=dx*dx+dy*dy;
        if cg_error || !length {return cg_fail("Point on curve needs a nonzero line");}
        let along=(load64(point)-load64(a))*dx+(load64(point+8)-load64(a+8))*dy;
        if along<=0 {return a;}
        if along>=length {return b;}
        let t=f64_div(f64_from_i64(along),f64_from_i64(length));
        return cg_v(load64(a)+f64_to_i64_round(f64_mul(t,f64_from_i64(dx))),load64(a+8)+f64_to_i64_round(f64_mul(t,f64_from_i64(dy))),0);
    }
    let geometry=pc_curve_geometry(curve);let center=pc_uv(j_get(geometry,"center"));
    let x=load64(point)-load64(center);let y=load64(point+8)-load64(center+8);
    if kind==4 || kind==5 {
        let fields=pc_elliptic_contact_fields(curve,kind);if !fields {return 0;}
        let offset=cso_nearest(pc_elliptic_contact_geometry(fields),x,y);
        return cg_v(load64(center)+load64(offset),load64(center+8)+load64(offset+8),0);
    }
    if kind!=2 && kind!=3 {return cg_fail("Unsupported point on curve geometry");}
    let radius=pc_pose_number(j_get(geometry,"radius"));
    if cg_error || radius<=0 {return cg_fail("Point on a circular curve needs a positive radius");}
    if kind==3 {
        let start=pma_start(geometry);let sweep=pma_sweep(geometry);if cg_error {return 0;}
        let endpoint=csp_arc_limit(csp_arc_range(radius,start,sweep),x,y);
        if endpoint {return cg_v(load64(center)+load64(endpoint),load64(center+8)+load64(endpoint+8),0);}
    }
    if !x && !y {return cg_v(load64(center)+radius,load64(center+8),0);}
    let t=f64_div(f64_from_i64(radius),f64_sqrt(f64_from_i64(x*x+y*y)));
    return cg_v(load64(center)+f64_to_i64_round(f64_mul(t,f64_from_i64(x))),load64(center+8)+f64_to_i64_round(f64_mul(t,f64_from_i64(y))),0);
}

fn pc_check_point_on_curve(nodes,sk,entry,edited_spline) {
    let row=load64(entry);let id=load64(entry+8);let anchor=j_get(row,"a");
    let source=pc_find(nodes,j_string(row,"b"));let target=pc_find(nodes,j_string(anchor,"entityId"));
    if !m_len(id) || load64(entry+16) || !source || !target || source==target ||
       !m_eq(j_string(source,"sketchId"),sk) || !m_eq(j_string(target,"sketchId"),sk) ||
       j_get(row,"expression") || j_value(j_get(row,"reference")) || j_get(row,"value") {
        return cg_fail(m_cat("Invalid point on curve relation: ",id));
    }
    let kind=pc_point_on_curve_kind(source);let follower=pc_saved_anchor(nodes,sk,anchor);
    // Other curve and anchor families still use their existing reference geometry.
    if !kind {return 1;}
    let point=0;
    if follower {
        point=pc_uv(follower);if cg_error {return 0;}
        // The source was edited on a scratch graph. Its old follower position
        // supplies the initial guess until the combined constraints solve.
        if kind==6 && source==edited_spline {return 1;}
    }
    else if kind==6 && m_eq(j_string(target,"type"),"sketchSpline") {
        point=ps_coincident_point(nodes,sk,anchor);
        if !point {return cg_fail(m_cat("Invalid point on curve anchor: ",id));}
    }else {
        if pc_sketch_point(target) || pc_sketch_circle(target) || m_eq(j_string(target,"type"),"sketchLine") {return cg_fail(m_cat("Invalid point on curve anchor: ",id));}
        return 1;
    }
    let nearest=pc_point_on_curve_position(source,kind,point);
    if !nearest || cg_error {return 0;}
    if pc_line_span(point,nearest)>=1000 {return cg_fail(m_cat("Saved point is outside its curve: ",id));}
    return 1;
}
