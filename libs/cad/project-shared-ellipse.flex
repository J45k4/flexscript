// Shared ellipse fragments retain individual start/sweep parameters.
fn pe_root(groups,id) {let root=j_string(groups,id);if m_len(root) {return root;}return id;}
fn pe_groups(records) {
    let parents=0;let i=0;
    while i<cg_count(records) {
        let entry=cg_at(records,i);let r=load64(entry);
        if m_eq(j_string(r,"type"),"sameEllipse") {
            if !parents {parents=j_object();}
            let a=j_string(r,"a");let b=j_string(r,"b");
            if !m_len(a) || !m_len(b) || j_get(parents,b) || !m_len(j_string(r,"id")) || load64(entry+16)
                || j_value(j_get(r,"reference")) || j_get(r,"expression") {return cg_fail("Invalid shared ellipse relation");}
            cg_j_text(parents,b,a);
        }i=i+1;
    }
    if !parents {return 0;}let groups=j_object();let link=load64(parents+16);
    while link {
        let id=load64(link+32);let root=j_value(link);let depth=0;
        while j_get(parents,root) {
            if !cg_step() || depth>=cg_count(records) {return cg_fail("Cyclic shared ellipse relation");}
            root=j_string(parents,root);depth=depth+1;
        }
        cg_j_text(groups,id,root);link=load64(link+24);
    }return groups;
}
fn pe_check(nodes,sk,records,groups) {
    let drivers=j_object();let i=0;while i<cg_count(records) {
        let entry=cg_at(records,i);let r=load64(entry);let field=pc_record_field(entry);
        if m_eq(field,"sameEllipse") {
            let a=pc_find(nodes,j_string(r,"a"));let b=pc_find(nodes,j_string(r,"b"));
            if !pc_ellipse_entity(a) || !pc_ellipse_entity(b) || !m_eq(j_string(a,"sketchId"),sk) || !m_eq(j_string(b,"sketchId"),sk) {
                return cg_fail("Shared ellipse members must be ellipses in the same sketch");
            }
            let angle=cg_abs(pc_circle_measure(a,"rotation")-pc_circle_measure(b,"rotation"))%360000000;
            if pc_line_span(pc_uv(j_get(pc_curve_geometry(a),"center")),pc_uv(j_get(pc_curve_geometry(b),"center")))>=1000
                || cg_abs(pc_circle_measure(a,"width")-pc_circle_measure(b,"width"))>=2000
                || cg_abs(pc_circle_measure(a,"height")-pc_circle_measure(b,"height"))>=2000
                || (angle>57295 && angle<360000000-57295) {return cg_fail("Shared ellipse members disagree");}
        }else if pe_seam(groups,r) {
            let a=pe_end_position(nodes,j_get(r,"a"));let b=pe_end_position(nodes,j_get(r,"b"));
            if !a || !b || pc_line_span(a,b)>1000 {return cg_fail("Shared elliptic arc endpoints disagree");}
        }else if pc_axis_field(field) && !j_value(j_get(r,"reference")) {
            let root=pe_root(groups,j_string(r,"entityId"));let seen=j_get(drivers,root);
            if !seen {seen=j_object();j_add(drivers,root,seen);}
            if j_get(seen,field) {return cg_fail("Multiple dimensions drive the same ellipse axis");}cg_j_int(seen,field,1);
        }i=i+1;
    }return !cg_error;
}
fn pe_driver(records,groups,id,field) {
    let root=pe_root(groups,id);let i=0;while i<cg_count(records) {
        let entry=cg_at(records,i);let r=load64(entry);
        if m_eq(pc_record_field(entry),field) && !j_value(j_get(r,"reference")) && m_eq(pe_root(groups,j_string(r,"entityId")),root) {return entry;}
        i=i+1;
    }return 0;
}
fn pe_set_group_field(nodes,records,groups,id,field,value) {
    if !groups {return 1;}let root=pe_root(groups,id);let node=pc_first(nodes);
    while node {
        if m_eq(pe_root(groups,j_string(node,"id")),root) && pc_ellipse_entity(node) {
            cg_j_set(pc_curve_geometry(node),field,cg_json_number(value));
        }node=load64(node+24);
    }
    let i=0;while i<cg_count(records) {
        let entry=cg_at(records,i);let r=load64(entry);
        if m_eq(pc_record_field(entry),field) && j_value(j_get(r,"reference")) && m_eq(pe_root(groups,j_string(r,"entityId")),root) {
            cg_j_set(r,"value",cg_json_number(value));
        }i=i+1;
    }return 1;
}

// Web-authored splits may also constrain the two cut endpoints. On the
// common ellipse those joins equate scalar angles; their centers already
// share the ordinary 2D coincidence constraint.
fn pe_seam(groups,r) {
    if !groups || !m_eq(j_string(r,"type"),"coincident") {return 0;}
    let a=j_get(r,"a");let b=j_get(r,"b");let first=j_string(a,"entityId");let last=j_string(b,"entityId");
    let pa=j_string(a,"point");let pb=j_string(b,"point");
    return !m_eq(first,last) && m_eq(pe_root(groups,first),pe_root(groups,last))
        && (m_eq(pa,"p0") || m_eq(pa,"p1")) && (m_eq(pb,"p0") || m_eq(pb,"p1"));
}
fn pe_end_key(id,point) {return m_cat(point,id);}
fn pe_angle_root(links,key) {
    let next=j_string(links,key);while m_len(next) {key=next;next=j_string(links,key);}return key;
}
fn pe_angle_union(links,a,b) {
    let left=pe_angle_root(links,a);let right=pe_angle_root(links,b);
    if m_eq(left,right) {return 0;}cg_j_text(links,right,left);return 1;
}
fn pe_angle_links(records,groups,skip) {
    let links=j_object();let i=0;while i<cg_count(records) {
        let r=load64(cg_at(records,i));let id=j_string(r,"entityId");
        if m_eq(j_string(r,"type"),"arcSweep") && !m_eq(id,skip) && !j_value(j_get(r,"reference")) {
            pe_angle_union(links,pe_end_key(id,"p0"),pe_end_key(id,"p1"));
        }i=i+1;
    }
    let rank=0;i=0;while i<cg_count(records) {
        let r=load64(cg_at(records,i));
        if pe_seam(groups,r) {
            let a=j_get(r,"a");let b=j_get(r,"b");
            rank=rank+pe_angle_union(links,pe_end_key(j_string(a,"entityId"),j_string(a,"point")),pe_end_key(j_string(b,"entityId"),j_string(b,"point")));
        }i=i+1;
    }return cg_v(links,rank,0);
}
fn pe_end_position(nodes,anchor) {
    let shape=pc_find(nodes,j_string(anchor,"entityId"));if !pc_finite_arc(shape) || !pc_ellipse_entity(shape) {return cg_fail("Shared endpoint needs an elliptic arc");}
    let g=pc_curve_geometry(shape);let tau=6283185307180;let angle=pc_serial_number(j_get(g,"startAngle"),12,1000000000000,1000000)%tau;
    if m_eq(j_string(anchor,"point"),"p1") {angle=angle+pc_serial_number(j_get(g,"sweep"),12,1000000000000,7);}
    let pts=pc_ellipse_samples(pc_uv(j_get(g,"center")),pc_pose_number(j_get(g,"width"))/2,pc_pose_number(j_get(g,"height"))/2,pc_ellipse_rotation(g),angle,0,1,0);
    return cg_at(pts,0);
}
fn pe_adjust_sweep(nodes,records,groups,node,new_value) {
    if !groups || !pc_ellipse_entity(node) {return 1;}
    let id=j_string(node,"id");let links=load64(pe_angle_links(records,groups,id));let moving=pe_angle_root(links,pe_end_key(id,"p1"));
    let g=pc_curve_geometry(node);let scale=f64_from_i64(1000000000000);let tau=6283185307180;
    let old=pc_serial_number(j_get(g,"sweep"),12,1000000000000,7);
    let rad=f64_mul(f64_div(f64_from_i64(new_value),f64_from_i64(180000000)),0x400921fb54442d18);
    let delta=(f64_to_i64_round(f64_mul(rad,scale))-old)%tau;
    if cg_abs(delta)<=1 {return 1;}
    if m_eq(pe_angle_root(links,pe_end_key(id,"p0")),moving) {return cg_fail("Other driving sweeps fix both ends of this arc");}
    let part=pc_first(nodes);while part {
        let key=j_string(part,"id");
        if part!=node && pc_ellipse_entity(part) && pc_finite_arc(part) && m_eq(pe_root(groups,key),pe_root(groups,id)) {
            let a=m_eq(pe_angle_root(links,pe_end_key(key,"p0")),moving);let b=m_eq(pe_angle_root(links,pe_end_key(key,"p1")),moving);
            let geom=pc_curve_geometry(part);
            if a {
                let start=pc_serial_number(j_get(geom,"startAngle"),12,1000000000000,1000000)%tau;
                cg_j_set(geom,"startAngle",pc_arc_json_angle(f64_div(f64_from_i64((start+delta)%tau),scale)));
            }
            if a!=b {
                let previous=pc_serial_number(j_get(geom,"sweep"),12,1000000000000,7);
                let sweep=(previous+(b-a)*delta)%tau;
                if previous>0 && sweep<0 {sweep=sweep+tau;}if previous<0 && sweep>0 {sweep=sweep-tau;}
                if cg_abs(sweep)<1000 || cg_abs(sweep)>tau-1000 {return cg_fail("The shared endpoint would collapse an arc");}
                cg_j_set(geom,"sweep",pc_arc_json_angle(f64_div(f64_from_i64(sweep),scale)));
                let reference=pc_circle_relation(records,key,"arcSweep");
                if reference && j_value(j_get(reference,"reference")) {cg_j_set(reference,"value",cg_json_number(pc_circle_measure(part,"arcSweep")));}
            }
        }part=load64(part+24);
    }return !cg_error;
}
