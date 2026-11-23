import "author.flex";
import "project-lines.flex";

fn ps_anchor(id,point) {
    let a=j_object();cg_j_text(a,"entityId",id);cg_j_text(a,"point",point);return a;
}
fn ps_can_edit(nodes,sketch) {
    if !m_eq(j_string(sketch,"type"),"sketch") || pc_first(j_get(sketch,"dimensions")) {return cg_fail("Choose a sketch with editable smooth joins");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    if ps_only(nodes,sketch) {return 1;}
    let i=0;while i<cg_count(records) {
        let entry=cg_at(records,i);
        if load64(entry+16) || !ps_is_join(load64(entry)) {
            if pc_line_access_records(nodes,sketch,pc_line_entities(nodes,sketch),pc_affine_records(nodes,records)) {return 1;}
            if cg_error {return 0;}return cg_fail("Other constraints in this sketch need a combined solve");
        }
        i=i+1;
    }return 1;
}
fn ps_add_relation(nodes,sketch,a,b) {
    let rows=j_get(sketch,"relations");if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    let id=m_cat("native-smooth-join-",m_cat(j_string(b,"entityId"),m_cat("-",j_string(b,"point"))));let base=id;let n=2;
    while pc_find(rows,id) || pc_find(nodes,id) {id=m_cat(base,m_cat("-",m_int(n)));n=n+1;}
    let rel=j_object();cg_j_text(rel,"type","smoothJoin");cg_j_text(rel,"id",id);
    j_add(rel,"a",j_parse(j_encode(a)));j_add(rel,"b",j_parse(j_encode(b)));j_add(rows,0,rel);return 1;
}
fn ps_finish(project,result,nodes,sketch) {
    if !ps_can_edit(nodes,sketch) || !cad_sketch_paths(nodes,j_string(sketch,"id")) {return 0;}
    return pc_checked_feature_edit(project,result);
}
// The center lies on the source normal and on the chord's perpendicular bisector.
fn ps_tangent_arc(id,frame,target) {
    let start=load64(frame);let dx=f64_from_i64(load64(target)-load64(start));let dy=f64_from_i64(load64(target+8)-load64(start+8));
    let nx=f64_sub(0,load64(frame+16));let ny=load64(frame+8);let projection=f64_add(f64_mul(dx,nx),f64_mul(dy,ny));
    let squared=f64_add(f64_mul(dx,dx),f64_mul(dy,dy));
    let small=f64_div(f64_sqrt(squared),f64_from_i64(1000000));if f64_lt(small,f64_from_i64(1)) {small=f64_from_i64(1);}
    if !squared || !f64_lt(small,f64_magnitude(projection)) {return cg_fail("Choose an endpoint away from the tangent line");}
    let offset=f64_div(squared,f64_add(projection,projection));let radius=f64_magnitude(offset);
    if f64_lt(f64_from_i64(500000000),radius) {return cg_fail("Arc radius exceeds coordinate range");}
    let cx=f64_mul(nx,offset);let cy=f64_mul(ny,offset);let a=f64_atan2(f64_sub(0,cy),f64_sub(0,cx));
    let b=f64_atan2(f64_sub(dy,cy),f64_sub(dx,cx));let sweep=f64_sub(b,a);
    if f64_lt(0,offset) && f64_lt(sweep,0) {sweep=f64_add(sweep,0x401921fb54442d18);}
    if f64_lt(offset,0) && f64_lt(0,sweep) {sweep=f64_sub(sweep,0x401921fb54442d18);}
    let geom=j_object();cg_j_text(geom,"type","arc");cg_j_text(geom,"id",id);
    j_add(geom,"center",pc_json_point(cg_v(load64(start)+f64_to_i64_round(cx),load64(start+8)+f64_to_i64_round(cy),0)));
    j_add(geom,"radius",cg_json_number(f64_to_i64_round(radius)));cg_j_int(geom,"segments",128);
    j_add(geom,"startAngle",pc_arc_json_angle(a));j_add(geom,"sweep",pc_arc_json_angle(sweep));return geom;
}
fn cad_project_add_tangent_arc(project,sk,anchor,target) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !ps_can_edit(nodes,sketch) {return 0;}let frame=ps_anchor_frame(nodes,sk,anchor);let at=pc_uv(target);if !frame || cg_error {return 0;}
    let id=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));let geom=ps_tangent_arc(id,frame,at);if !geom {return 0;}
    let node=j_object();cg_j_text(node,"id",id);cg_j_text(node,"type","sketchArc");cg_j_text(node,"sketchId",sk);j_add(node,"arc",geom);
    let src=pc_find(nodes,j_string(anchor,"entityId"));
    if cad_sketch_is_construction(src) {j_add(geom,"construction",j_new(5,1));}
    j_add(nodes,0,node);ps_add_relation(nodes,sketch,anchor,ps_anchor(id,"p0"));return ps_finish(project,result,nodes,sketch);
}
// Rigidly align the follower's connected curves. Preserve every existing join
// in that component and the geometry of the selected source.
fn ps_align(nodes,sketch,a,b,source,follower,skip) {
    if ps_matches(source,follower) {return 1;}
    let connected=j_object();cg_j_int(connected,j_string(b,"entityId"),1);let changed=1;
    while changed {
        changed=0;let row=pc_first(j_get(sketch,"relations"));while row {
            if row!=skip && ps_is_join(row) {
                if !cg_step() {return 0;}let left=j_string(j_get(row,"a"),"entityId");let right=j_string(j_get(row,"b"),"entityId");
                if j_get(connected,left) && !j_get(connected,right) {cg_j_int(connected,right,1);changed=1;}
                if j_get(connected,right) && !j_get(connected,left) {cg_j_int(connected,left,1);changed=1;}
            }
            row=load64(row+24);
        }
    }
    if j_get(connected,j_string(a,"entityId")) {return cg_fail("Closing this smooth chain requires deforming its curves");}
    let alignment=ps_alignment(source,follower);let c=load64(alignment);let s=load64(alignment+8);
    let node=pc_first(nodes);while node {
        if j_get(connected,j_string(node,"id")) && (!ps_movable(sketch,node) || !ps_transform(node,load64(follower),load64(source),c,s)) {return 0;}node=load64(node+24);
    }return 1;
}
fn cad_project_toggle_smooth_join(project,sk,a,b) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !ps_can_edit(nodes,sketch) {return 0;}
    let source=ps_anchor_frame(nodes,sk,a);let follower=ps_anchor_frame(nodes,sk,b);if !source || !follower || cg_error {return 0;}
    let first=j_string(a,"entityId");let second=j_string(b,"entityId");if m_eq(first,second) {return cg_fail("Select two distinct curves");}
    let rows=j_get(sketch,"relations");let row=pc_first(rows);let removed=0;
    while row {
        let next=load64(row+24);let left=j_string(j_get(row,"a"),"entityId");let right=j_string(j_get(row,"b"),"entityId");
        if ps_is_join(row) && (m_eq(left,first) && m_eq(right,second) || m_eq(left,second) && m_eq(right,first)) {
            pc_line_unlink(rows,row,j_string(row,"id"));removed=1;
        }row=next;
    }
    if !removed {
        if !ps_align(nodes,sketch,a,b,source,follower,0) {return 0;}ps_add_relation(nodes,sketch,a,b);
    }
    return ps_finish(project,result,nodes,sketch);
}
fn cad_project_toggle_smooth_curves(project,sk,source_id,follower_id) {
    cg_begin();let nodes=pc_nodes(cad_project_part(project));let source=pc_find(nodes,source_id);let follower=pc_find(nodes,follower_id);
    let best=-1;let a=0;let b=0;let i=0;
    while i<2 {
        let name=ps_end_name(source,i);if !name {return cg_fail("Choose a line, finite arc or open spline");}
        let src=ps_endpoint(source,name);if !src {cg_error=0;}else {
            let j=0;while j<2 {
                let target=ps_end_name(follower,j);if !target {return cg_fail("Choose a line, finite arc or open spline");}
                let dst=ps_endpoint(follower,target);if !dst {cg_error=0;}else {
                    let d=pc_line_span(load64(src),load64(dst));if best<0 || d<best {best=d;a=ps_anchor(source_id,name);b=ps_anchor(follower_id,target);}
                }j=j+1;
            }
        }i=i+1;
    }
    if !a {return cg_fail("Smooth join needs nonzero endpoint tangents");}
    return cad_project_toggle_smooth_join(project,sk,a,b);
}

// Either end of an arc can move about its opposite end. The
// similarity preserves its signed sweep, construction flag and segment count.
fn ps_move_arc(node,end,target) {
    let arc=pc_curve_geometry(node);if m_eq(end,"center") {return po_position(j_get(arc,"center"),target,1);}
    let other="p0";if m_eq(end,"p0") {other="p1";}
    let first=ps_endpoint(node,end);let last=ps_endpoint(node,other);if !first || !last {return 0;}
    let fixed=load64(last);let old=load64(first);
    let x=f64_from_i64(load64(old)-load64(fixed));let y=f64_from_i64(load64(old+8)-load64(fixed+8));
    let u=f64_from_i64(load64(target)-load64(fixed));let v=f64_from_i64(load64(target+8)-load64(fixed+8));
    let norm=f64_add(f64_mul(x,x),f64_mul(y,y));let size=f64_add(f64_mul(u,u),f64_mul(v,v));
    if !norm || !size {return cg_fail("Arc endpoints must be distinct");}
    let c=f64_div(f64_add(f64_mul(x,u),f64_mul(y,v)),norm);let s=f64_div(f64_sub(f64_mul(x,v),f64_mul(y,u)),norm);
    let scale=f64_sqrt(f64_div(size,norm));
    if pc_elliptic_arc(node) {
        let width=f64_to_i64_round(f64_mul(f64_from_i64(pc_pose_number(j_get(arc,"width"))),scale));
        let height=f64_to_i64_round(f64_mul(f64_from_i64(pc_pose_number(j_get(arc,"height"))),scale));
        if cg_error || width<2 || height<2 || width>500000000 || height>500000000 {return cg_fail("Elliptic arc axes exceed range");}
        cg_j_set(arc,"width",cg_json_number(width));cg_j_set(arc,"height",cg_json_number(height));
    }else {
        let radius=f64_mul(f64_from_i64(pc_pose_number(j_get(arc,"radius"))),scale);
        if f64_lt(f64_from_i64(500000000),radius) {return cg_fail("Arc radius exceeds coordinate range");}
        cg_j_set(arc,"radius",cg_json_number(f64_to_i64_round(radius)));
    }
    return ps_transform(node,fixed,fixed,c,s);
}
fn ps_translate_normal_seed(source,line,end) {
    let other="p1";if m_eq(end,"p1") {other="p0";}
    let foot=j_get(line,end);let tip=j_get(line,other);let a=pc_uv(foot);let b=pc_uv(tip);
    let frame=pc_normal_frame(source,a);if !frame {return 0;}
    let tangent=load64(frame+8);let length=pc_line_span(a,b);
    let along=pls_linear(f64_from_i64(load64(b)-load64(a)),f64_from_i64(load64(b+8)-load64(a+8)),load64(tangent),load64(tangent+8));
    if f64_lt(f64_from_i64(length/1000000+1),f64_magnitude(along)) {return 1;}
    let contact=load64(frame);
    let x=load64(b)+load64(contact)-load64(a);let y=load64(b+8)+load64(contact+8)-load64(a+8);
    if cg_abs(x)>500000000 || cg_abs(y)>500000000 {return 1;}
    return po_position(foot,contact,1) && po_position(tip,cg_v(x,y,0),1);
}
fn ps_seed_spline_normals(nodes,sketch,source,records) {
    let id=j_string(source,"id");let row=pc_first(j_get(sketch,"relations"));
    while row {
        if m_eq(j_string(row,"type"),"normal") && m_eq(j_string(row,"b"),id) {
            let anchor=j_get(row,"a");let line_id=j_string(anchor,"entityId");
            // Translate an already normal chord onto its new contact. A chord
            // requiring rotation keeps the original coupled starting pose.
            if !pc_line_projection(sketch,line_id) && !po_owner(records,line_id) &&
                !ps_translate_normal_seed(source,pc_find(nodes,line_id),j_string(anchor,"point")) {return 0;}
        }
        row=load64(row+24);
    }
    return 1;
}
fn ps_rebuild_spline_contacts(nodes,sketch,source) {
    let id=j_string(source,"id");let row=pc_first(j_get(sketch,"relations"));
    while row {
        let kind=j_string(row,"type");
        if (m_eq(kind,"pointOnCurve") || m_eq(kind,"normal")) && m_eq(j_string(row,"b"),id) {
            let records=pc_line_records_after_spline_edit(nodes,sketch,source);if !records {return 0;}
            let lines=pc_line_entities(nodes,sketch);if !lines {return cg_fail("Spline followers need editable sketch anchors");}
            if !ps_seed_spline_normals(nodes,sketch,source,records) {return 0;}
            let affine=pc_affine_records(nodes,records);if !affine {return 0;}
            return pc_apply_line_constraints(lines,affine);
        }
        row=load64(row+24);
    }
    return 1;
}
fn cad_project_move_smooth_point(project,sk,anchor,position) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !ps_can_edit(nodes,sketch) {return 0;}let id=j_string(anchor,"entityId");let key=j_string(anchor,"point");
    let node=pc_find(nodes,id);if !node || !m_eq(j_string(node,"sketchId"),sk) {return cg_fail("Missing curve to edit");}
    if !ps_movable(sketch,node) {return 0;}
    let xy=pc_uv(position);if cg_error {return 0;}
    let spline=m_eq(j_string(node,"type"),"sketchSpline");
    if pc_finite_arc(node) {if !ps_move_arc(node,key,xy) {return 0;}}
    else {
        let point=pp_anchor(nodes,sk,anchor);
        if !point || !(spline || ps_end_name(node,0)) || !po_position(point,xy,1) {
            return cg_fail("Choose a line endpoint or spline point");
        }
    }
    let rel=pc_first(j_get(sketch,"relations"));while rel {
        let a=j_get(rel,"a");let b=j_get(rel,"b");if m_eq(j_string(b,"entityId"),id) {let swap=a;a=b;b=swap;}
        if ps_is_join(rel) && m_eq(j_string(a,"entityId"),id) {
            let source=ps_anchor_frame(nodes,sk,a);let follower=ps_anchor_frame(nodes,sk,b);
            if !source || !follower || !ps_align(nodes,sketch,a,b,source,follower,rel) {return 0;}
        }rel=load64(rel+24);
    }
    if spline && !ps_rebuild_spline_contacts(nodes,sketch,node) {return 0;}
    return ps_finish(project,result,nodes,sketch);
}
