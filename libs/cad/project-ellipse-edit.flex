// Trim the selected elliptic interval or extend a finite arc on its ellipse.
import "project-ellipse-boundaries.flex";
import "project-ellipse-split.flex";
import "project-arc-edit.flex";

fn pbe_point(data,angle) {
    let center=load64(data);let c=load64(data+56);let s=load64(data+64);
    let t=f64_div(f64_from_i64(angle),f64_from_i64(1000000000000));
    let x=f64_mul(f64_from_i64(load64(data+32)),f64_cos(t));
    let y=f64_mul(f64_from_i64(load64(data+40)),f64_sin(t));
    return cg_v(load64(center)+f64_to_i64_round(pls_linear(x,y,c,f64_math_neg(s))),
        load64(center+8)+f64_to_i64_round(pls_linear(x,y,s,c)),0);
}

fn pbe_pick_data(data,point,tolerance) {
    let uv=pbe_relative(data,point);let x=load64(uv);let y=load64(uv+8);
    if !f64_magnitude(x) && !f64_magnitude(y) {return 0;}
    let angle=pab_angle(x,y);let sweep=load64(data+24);let length=cg_abs(sweep);
    let progress=angle;if sweep {progress=pca_progress(data,angle);}
    if !sweep || progress<=length {
        let distance=pc_line_span(point,pbe_point(data,angle));
        if distance<=tolerance {return cg_v(progress,distance,0);}
        return 0;
    }
    let first=pc_line_span(point,pbe_point(data,load64(data+16)));
    let last=pc_line_span(point,pbe_point(data,load64(data+16)+sweep));
    if first<=last && first<=tolerance {return cg_v(0,first,0);}
    if last<=tolerance {return cg_v(length,last,0);}
    return 0;
}

fn cad_sketch_elliptic_pick(node,point,tolerance) {
    if !pc_ellipse_entity(node) {return 0;}
    let data=pbe_data(node);if !data {return 0;}
    return pbe_pick_data(data,point,tolerance);
}

fn pbe_write(node,piece) {
    let shape=pc_curve_geometry(node);let start=0;
    if load64(piece+16) {start=j_parse(j_encode(j_get(shape,"startAngle")));}
    pe_piece(shape,load64(piece),load64(piece+8));
    if start {cg_j_set(shape,"startAngle",start);}
    return pc_arc_path(node)!=0;
}

// Deleting a linked fragment must not detach its surviving siblings or
// discard a dimension of their shared supporting ellipse.
fn pbe_shared_survivor(records,id) {
    let child="";let i=0;
    while i<cg_count(records) {
        let row=load64(cg_at(records,i));
        if m_eq(j_string(row,"type"),"sameEllipse") {
            let a=j_string(row,"a");let b=j_string(row,"b");
            if m_eq(b,id) {return a;}
            if !m_len(child) && m_eq(a,id) {child=b;}
        }
        i=i+1;
    }
    return child;
}

fn pbe_relation(record,edit,survives) {
    let id=load64(edit);let kind=j_string(record,"type");
    if m_eq(kind,"sameEllipse") {
        let origin=j_string(record,"a");let follower=j_string(record,"b");
        if survives {return 1;}
        if m_eq(follower,id) {return 0;}
        if m_eq(origin,id) {
            let replacement=load64(edit+8);
            if !m_len(replacement) || m_eq(replacement,follower) {return 0;}
            cg_j_text(record,"a",replacement);
        }
        return 1;
    }
    if m_eq(j_string(record,"entityId"),id) {
        if pc_axis_field(kind) || m_eq(kind,"rectangleWidth") || m_eq(kind,"rectangleHeight") {
            let target=load64(edit+8);if !m_len(target) {return 0;}
            if !survives {cg_j_text(record,"entityId",target);}
            return 1;
        }
        if m_eq(kind,"arcSweep") && !survives {return 0;}
    }
    return pca_relation(record,edit);
}

fn pbe_update_relations(part,sketch,rows,graph,edit,survives) {
    if !rows {return 1;}
    let link=rows+16;
    while load64(link) && !cg_error {
        if !cg_step() {return 0;}
        let row=load64(link);let record=row;
        if graph {
            record=0;
            if m_eq(j_string(row,"type"),"sketchConstraint") && m_eq(j_string(row,"sketchId"),j_string(sketch,"id")) {
                record=j_get(row,"constraint");
            }
        }
        if record && !pbe_relation(record,edit,survives) {
            if cg_error {return 0;}
            store64(link,load64(row+24));
            if graph {ple_graph_indices(part,j_string(row,"id"),"");}
        }else {link=row+24;}
    }
    return !cg_error;
}

fn pbe_reshape(project,revised,part,sketch,node,pieces,keep_end,extend,records) {
    let nodes=pc_nodes(part);let id=j_string(node,"id");
    let first=cg_at(pieces,0);let last=cg_at(pieces,cg_count(pieces)-1);
    let center="";let start="";let end="";let end_id=id;
    if ple_mentions(j_get(sketch,"dimensions"),id) {return cg_fail("The edit cannot preserve legacy dimensions on this ellipse");}
    if first {
        center=id;if load64(first+16) {start=id;}
        if first!=last {
            end_id=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));
            let second=j_parse(j_encode(node));cg_j_text(second,"id",end_id);cg_j_text(pc_curve_geometry(second),"id",end_id);
            if !pbe_write(second,last) {return 0;}
            store64(second+24,load64(node+24));store64(node+24,second);
            ple_graph_indices(part,id,end_id);
            let groups=pe_groups(records);if cg_error {return 0;}
            let root=pe_root(groups,id);let rows=j_get(sketch,"relations");
            if !rows {rows=j_array();j_add(sketch,"relations",rows);}
            pe_add_join(rows,nodes,"sameEllipse",m_cat("native-same-ellipse-",m_cat(root,m_cat("-",end_id))),j_text(root),j_text(end_id));
        }
        if keep_end {end=end_id;}
        if !pbe_write(node,first) {return 0;}
    }else {center=pbe_shared_survivor(records,id);}
    let edit=m_take(56);store64(edit,id);store64(edit+8,center);store64(edit+16,start);store64(edit+24,end);
    store64(edit+32,extend);store64(edit+40,0);store64(edit+48,node);
    if !pbe_update_relations(part,sketch,j_get(sketch,"relations"),0,edit,first)
        || !pbe_update_relations(part,sketch,nodes,1,edit,first) {return 0;}
    if !first {pc_line_unlink(nodes,node,id);ple_graph_indices(part,id,"");}
    if !pc_line_records(nodes,sketch) {return 0;}
    return pc_checked_feature_edit(project,revised);
}

fn pbe_boundaries(nodes,sketch,node,data,clicked,extend) {
    let choices=pca_cut_choices(data);let hits=cg_array();let boundary=pc_first(nodes);
    while boundary && !cg_error {
        if !cg_step() {return 0;}
        if boundary!=node && m_eq(j_string(boundary,"sketchId"),sketch) {
            store64(hits,0);if !pbe_ellipse_contacts(hits,data,boundary) {return 0;}
            pca_consider_angles(data,choices,hits,clicked,extend);
        }
        boundary=load64(boundary+24);
    }
    if cg_error {return 0;}
    return pca_chosen_pieces(data,choices,clicked,extend);
}

fn pbe_edit(project,sketch_id,curve_id,click,tolerance,extend) {
    cg_begin();
    if !click || tolerance<1 || tolerance>500000000 || cg_abs(load64(click))>500000000
        || cg_abs(load64(click+8))>500000000 {return cg_fail("Choose a point on an elliptic curve");}
    let revised=cad_project_rebuild_projections(project);if !revised {return 0;}
    if revised==project {revised=j_parse(j_encode(project));}
    let part=cad_project_part(revised);let nodes=pc_nodes(part);let sketch=pc_find(nodes,sketch_id);
    let node=pc_find(nodes,curve_id);
    if !m_eq(j_string(sketch,"type"),"sketch") || !pc_ellipse_entity(node) || !m_eq(j_string(node,"sketchId"),sketch_id) {
        return cg_fail("Select an ellipse or elliptic arc in this sketch");
    }
    if pc_line_projection(sketch,curve_id) {return cg_fail("Projected edges follow their source geometry");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let data=pbe_data(node);if !data {return 0;}
    let sweep=cg_abs(load64(data+24));
    if extend && (!sweep || sweep>=6283185307180) {return cg_fail("A closed ellipse has no endpoint to extend");}
    let picked=pbe_pick_data(data,click,tolerance);
    if !picked {return cg_fail("Choose a point on the selected elliptic curve");}
    let edit=pbe_boundaries(nodes,sketch_id,node,data,load64(picked),extend);if !edit {return 0;}
    return pbe_reshape(project,revised,part,sketch,node,load64(edit),load64(edit+8),extend,records);
}

fn cad_project_trim_elliptic_curve(project,sketch_id,curve_id,click,tolerance) {
    return pbe_edit(project,sketch_id,curve_id,click,tolerance,0);
}

fn cad_project_extend_elliptic_arc(project,sketch_id,curve_id,click,tolerance) {
    return pbe_edit(project,sketch_id,curve_id,click,tolerance,1);
}
