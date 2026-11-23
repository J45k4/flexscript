// Symmetry records use the metric solver for their position and rank.
// Seed a drag with the exact reflected position so a free mirror line stays
// put and the opposite member follows the cursor, as in the v4 editor.
import "project-line-records.flex";

fn pc_symmetry_uv(row) {
    let v=pc_first(j_get(row,"at"));return cg_v(pc_pose_number(v),pc_pose_number(load64(v+24)),0);
}
fn pc_seed_symmetries(model,picked) {
    let rows=j_get(model,"constraints");let row=pc_first(rows);let points=j_get(model,"points");
    let edges=j_get(model,"segments");let touched=j_object();cg_j_int(touched,picked,1);
    let changed=1;while changed {
        changed=0;row=pc_first(rows);while row {
            if m_eq(j_string(row,"type"),"symmetry") {
                let edge=pc_find(edges,j_string(row,"axis"));let a=j_string(edge,"from");let b=j_string(edge,"to");
                let from=j_string(row,"from");let to=j_string(row,"to");
                if j_get(touched,to) {let swap=from;from=to;to=swap;}
                if !j_get(touched,to) && (j_get(touched,from) || j_get(touched,a) || j_get(touched,b)) {
                    let p=pc_reflect_uv(pc_symmetry_uv(pc_find(points,from)),pc_symmetry_uv(pc_find(points,a)),pc_symmetry_uv(pc_find(points,b)));
                    if !p {return 0;}
                    let pair=j_array();j_add(pair,0,cg_json_number(load64(p)));j_add(pair,0,cg_json_number(load64(p+8)));
                    cg_j_set(pc_find(points,to),"at",pair);cg_j_int(touched,to,1);changed=1;
                }
            }
            row=load64(row+24);
        }
    }return 1;
}
fn pc_mirror_circles(records,id) {
    let members=j_array();j_add(members,0,j_text(id));let seen=j_object();cg_j_int(seen,id,1);
    let p=pc_first(members);while p {
        let i=0;while i<cg_count(records) {
            let r=load64(cg_at(records,i));if m_eq(j_string(r,"type"),"mirror") {
                let next=0;let a=j_string(r,"a");let b=j_string(r,"b");
                if m_eq(j_value(p),a) {next=b;}else if m_eq(j_value(p),b) {next=a;}
                if next && !j_get(seen,next) {cg_j_int(seen,next,1);j_add(members,0,j_text(next));}
            }
            i=i+1;
        }p=load64(p+24);
    }return members;
}
fn pc_projection_records(records) {
    let projected=j_object();let i=0;
    while i<cg_count(records) {
        let row=load64(cg_at(records,i));
        if m_eq(j_string(row,"type"),"projected") {cg_j_int(projected,j_string(row,"entityId"),1);}
        i=i+1;
    }
    return projected;
}
fn pc_mirror_radial_freedom(records,id,counted,projected) {
    if j_get(counted,id) {return 0;}
    let members=pc_mirror_circles(records,id);let p=pc_first(members);let free=1;while p {
        let name=j_value(p);cg_j_int(counted,name,1);
        let r=pc_circle_relation(records,name,"radius");let d=pc_circle_relation(records,name,"diameter");
        if j_get(projected,name) || r && !j_value(j_get(r,"reference")) || d && !j_value(j_get(d,"reference")) {free=0;}
        p=load64(p+24);
    }return free;
}
fn pc_mirror_resize(nodes,records,source) {
    let radius=pc_circle_measure(source,"radius");
    let projected=pc_projection_records(records);
    let member=pc_first(pc_mirror_circles(records,j_string(source,"id")));while member {
        let id=j_value(member);let target=pc_find(nodes,id);
        if target!=source && pc_circle_measure(target,"radius")!=radius {
            if j_get(projected,id) {return cg_fail("Projected edges follow their source geometry");}
            cg_j_set(pc_curve_geometry(target),"radius",cg_json_number(radius));
        }
        let i=0;while i<2 {
            let field="radius";if i {field="diameter";}
            let rel=pc_circle_relation(records,id,field);
            if rel && j_value(j_get(rel,"reference")) {cg_j_set(rel,"value",cg_json_number(pc_circle_measure(target,field)));}
            i=i+1;
        }member=load64(member+24);
    }return 1;
}

// Mirror links are bidirectional for dimensions. A negative parity reverses
// the signed sweep without altering the radius.
fn pc_mirror_arc_members(records,id) {
    let members=j_object();cg_j_int(members,id,1);let member=load64(members+16);
    while member && !cg_error {
        let name=load64(member+32);let sign=-j_value(member);let i=0;
        while i<cg_count(records) {
            let rel=load64(cg_at(records,i));
            if m_eq(j_string(rel,"type"),"mirror") {
                let a=j_string(rel,"a");let b=j_string(rel,"b");let next=0;
                if m_eq(a,name) {next=b;}else if m_eq(b,name) {next=a;}
                if next {
                    let seen=j_get(members,next);
                    if !seen {cg_j_int(members,next,sign);}
                    else if j_value(seen)!=sign {return cg_fail("Circular arc mirror links disagree on signed sweep");}
                }
            }
            i=i+1;
        }
        member=load64(member+24);
    }
    return members;
}

fn pc_mirror_arc_freedom(records,id,counted,projected) {
    if j_get(counted,id) {return 0;}
    let members=pc_mirror_arc_members(records,id);if !members {return 0;}
    let member=load64(members+16);let radius=1;let sweep=1;let start=1;
    while member {
        let name=load64(member+32);cg_j_int(counted,name,1);
        let r=pc_circle_relation(records,name,"radius");let s=pc_circle_relation(records,name,"arcSweep");
        if r && !j_value(j_get(r,"reference")) {radius=0;}
        if s && !j_value(j_get(s,"reference")) {sweep=0;}
        if j_get(projected,name) {radius=0;sweep=0;start=0;}
        member=load64(member+24);
    }
    return start+radius+sweep;
}

fn pc_mirror_arc_resize(nodes,records,source,field) {
    let id=j_string(source,"id");let members=pc_mirror_arc_members(records,id);if !members {return 0;}
    let angular=m_eq(field,"arcSweep");let arc=j_get(source,"arc");
    let value=pc_pose_number(j_get(arc,"radius"));if angular {value=pma_sweep(arc);}
    let projected=pc_projection_records(records);let member=load64(members+16);
    while member && !cg_error {
        let name=load64(member+32);let node=pc_find(nodes,name);let geometry=j_get(node,"arc");
        if !pc_circular_arc(node) {return cg_fail("Circular arc mirror needs circular arc members");}
        let expected=value;let old=pc_pose_number(j_get(geometry,"radius"));
        if angular {expected=value*j_value(member);old=pma_sweep(geometry);}
        if old!=expected {
            if j_get(projected,name) {return cg_fail("Projected edges follow their source geometry");}
            if angular {cg_j_set(geometry,"sweep",pma_sweep_value(arc,j_value(member)));}
            else {cg_j_set(geometry,"radius",cg_json_number(expected));}
        }
        let ref=pc_circle_relation(records,name,field);
        if ref && j_value(j_get(ref,"reference")) {cg_j_set(ref,"value",cg_json_number(pc_circle_measure(node,field)));}
        member=load64(member+24);
    }
    return !cg_error;
}

fn pc_mirror_arc_entity(entities,id) {
    let i=0;
    while i<cg_count(entities) {
        let row=cg_at(entities,i);if m_eq(j_string(row,"id"),id) {return row;}i=i+1;
    }
    return 0;
}

// A positional solve can turn the axis. Update the copied start angles in
// dependency order while keeping the original start direction as the driver.
fn pc_mirror_arc_refresh(entities,records,projected) {
    let links=cg_array();let i=0;
    while i<cg_count(records) && !cg_error {
        let rel=load64(cg_at(records,i));
        if m_eq(j_string(rel,"type"),"mirror") {
            let from=pc_mirror_arc_entity(entities,j_string(rel,"a"));
            if pc_circular_arc(from) {
                let to=pc_mirror_arc_entity(entities,j_string(rel,"b"));
                let axis=pc_mirror_arc_entity(entities,j_string(rel,"symmetryLine"));
                if !pc_circular_arc(to) || pc_mirror_kind(axis)!=3 {return cg_fail("Missing circular arc mirror members");}
                cg_push(links,cg_v(from,to,axis));
            }
        }
        i=i+1;
    }
    let steps=0;let changed=1;
    while changed && steps<=cg_count(links) && !cg_error {
        changed=0;i=0;
        while i<cg_count(links) && !cg_error {
            let link=cg_at(links,i);let source=j_get(load64(link),"arc");let node=load64(link+8);
            let target=j_get(node,"arc");let axis=load64(link+16);
            let expected=pma_reflected_start(pma_start(source),pc_uv(j_get(axis,"p0")),pc_uv(j_get(axis,"p1")));
            if cg_abs(pma_wrap(expected-pma_start(target)))>2 {
                if j_get(projected,j_string(node,"id")) {return cg_fail("Projected edges follow their source geometry");}
                pma_write_angle(target,"startAngle",expected);changed=1;
            }
            i=i+1;
        }
        steps=steps+1;
    }
    if changed && !cg_error {return cg_fail("Circular arc mirror angles cannot follow this axis change");}
    return !cg_error;
}
