import "project-curves.flex";

fn pc_midpoint_kind(node) {
    let kind=j_string(node,"type");
    if m_eq(kind,"sketchLine") {return 1;}
    if pc_circular_arc(node) {return 2;}
    if pc_elliptic_arc(node) {return 3;}
    return 0;
}

fn pc_arc_midpoint_offset(node,kind) {
    let geometry=pc_curve_geometry(node);
    let start=pc_serial_number(j_get(geometry,"startAngle"),12,1000000000000,1000000)%6283185307180;
    let sweep=pc_serial_number(j_get(geometry,"sweep"),12,1000000000000,7);
    let rx=0;let ry=0;let rotation=0;
    if kind==2 {rx=pc_pose_number(j_get(geometry,"radius"));ry=rx;}
    else {
        rx=pc_pose_number(j_get(geometry,"width"))/2;ry=pc_pose_number(j_get(geometry,"height"))/2;
        rotation=pc_ellipse_rotation(geometry);
    }
    if cg_error || !sweep || cg_abs(sweep)>6283185307180 || rx<=0 || ry<=0 {return cg_fail("Invalid midpoint arc");}
    return cg_at(pc_ellipse_samples(cg_v(0,0,0),rx,ry,rotation,start+sweep/2,0,1,0),0);
}

fn pc_curve_midpoint(node,kind) {
    if kind==1 {
        let start=pc_uv(j_get(node,"p0"));let end=pc_uv(j_get(node,"p1"));
        if cg_error || !pc_line_span(start,end) {return cg_fail("Midpoint needs a nonzero line");}
        return cg_v((load64(start)+load64(end))/2,(load64(start+8)+load64(end+8))/2,0);
    }
    if !kind {return cg_fail("Midpoint requires a line or an arc");}
    let offset=pc_arc_midpoint_offset(node,kind);if !offset {return 0;}
    let center=pc_uv(j_get(pc_curve_geometry(node),"center"));if cg_error {return 0;}
    return cg_v(load64(center)+load64(offset),load64(center+8)+load64(offset+8),0);
}

fn pc_check_midpoint(nodes,sk,entry) {
    let row=load64(entry);let id=load64(entry+8);let anchor=j_get(row,"a");let curve=j_string(row,"b");
    let source=pc_find(nodes,curve);let kind=pc_midpoint_kind(source);
    let follower=pc_saved_anchor(nodes,sk,anchor);
    if !m_len(id) || load64(entry+16) || !kind || !follower || m_eq(j_string(anchor,"entityId"),curve) ||
        !m_eq(j_string(source,"sketchId"),sk) || j_get(row,"expression") || j_value(j_get(row,"reference")) || j_get(row,"value") {
        return cg_fail(m_cat("Invalid midpoint relation: ",id));
    }
    let midpoint=pc_curve_midpoint(source,kind);if !midpoint {return 0;}
    if pc_line_span(pc_uv(follower),midpoint)>=1000 {return cg_fail(m_cat("Saved midpoint disagrees with geometry: ",id));}
    return !cg_error;
}

fn pc_curve_anchor_source(records,id,type) {
    let i=0;
    while i<cg_count(records) {
        let relation=load64(cg_at(records,i));
        if m_eq(j_string(relation,"type"),type) && m_eq(j_string(relation,"b"),id) {return 1;}
        i=i+1;
    }
    return 0;
}
