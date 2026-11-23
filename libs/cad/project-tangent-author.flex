import "project-lines.flex";

fn pc_tangent_shift(point,dx,dy) {
    let x=load64(point)+dx;let y=load64(point+8)+dy;
    if cg_abs(x)>500000000 || cg_abs(y)>500000000 {return 0;}
    return cg_v(x,y,0);
}

fn pc_seed_line_tangent(source,target) {
    let line=source;let curve=target;let move_line=pct_line(target);
    if move_line {line=target;curve=source;}
    let shape=pct_shape(curve);if !shape {return 0;}
    let frame=pct_line_frame(line,shape);if !frame {return 0;}
    let side=pct_line_side(frame);let attempt=0;
    while attempt<2 {
        if pct_line_arc_covered(shape,frame,side) {
            let correction=f64_sub(f64_mul(f64_from_i64(side),load64(frame+24)),load64(frame+16));
            let dx=f64_to_i64_round(f64_mul(correction,load64(frame)));let dy=f64_to_i64_round(f64_mul(correction,load64(frame+8)));
            if move_line {
                let p0=j_get(target,"p0");let p1=j_get(target,"p1");
                let a=pc_tangent_shift(pc_uv(p0),-dx,-dy);let b=pc_tangent_shift(pc_uv(p1),-dx,-dy);
                if a && b && !cg_error {pc_line_write_xy(p0,a);return pc_line_write_xy(p1,b);}
            }else {
                let at=pc_tangent_shift(load64(shape),dx,dy);
                if at {return pc_line_write_xy(j_get(pc_curve_geometry(target),"center"),at);}
            }
        }
        side=-side;attempt=attempt+1;
    }
    return 0;
}

fn pc_toggle_tangent(project,sk,source_id,target_id,internal,allow_line) {
    cg_begin();
    let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !pc_line_access(nodes,sketch) {if cg_error {return 0;}return cg_fail("Select an editable sketch");}
    let source=pc_find(nodes,source_id);let target=pc_find(nodes,target_id);
    let line_contact=allow_line && !internal && pct_line_contact_pair(source,target);
    if (!line_contact && (!pct_circular(source) || !pct_circular(target))) || source==target ||
       !m_eq(j_string(source,"sketchId"),sk) || !m_eq(j_string(target,"sketchId"),sk) {
        return cg_fail("Choose two supported curves in the sketch");
    }
    let kind="tangent";let prefix="native-external-tangent-";
    if internal {kind="internalTangent";prefix="native-internal-tangent-";}
    let rows=j_get(sketch,"relations");let rel=pc_first(rows);
    while rel {
        let a=j_string(rel,"a");let b=j_string(rel,"b");
        if m_eq(j_string(rel,"type"),kind) && (m_eq(a,source_id) && m_eq(b,target_id) || (!internal && m_eq(a,target_id) && m_eq(b,source_id))) {
            pc_line_unlink(rows,rel,"");return result;
        }
        rel=load64(rel+24);
    }
    let lines=pc_line_entities(nodes,sketch);let driver=pc_line_index(lines,source_id);
    if driver>=cg_count(lines) || pc_line_index(lines,target_id)>=cg_count(lines) {return cg_fail("Use the source of a linked pattern");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    if pc_line_projection(sketch,target_id) || po_owner(records,target_id) {return cg_fail("Use the source of the linked follower geometry");}

    let base=m_cat(prefix,m_cat(source_id,m_cat("-",target_id)));let id=base;let n=2;
    while pc_find(nodes,id) || pc_find(rows,id) {id=m_cat(base,m_cat("-",m_int(n)));n=n+1;}
    if line_contact {
        if !pc_seed_line_tangent(source,target) {return cg_fail(m_cat("No valid line tangent contact: ",id));}
    }else {
        let a=pct_shape(source);let b=pct_shape(target);if !a || !b {return 0;}
        let distance=pct_distance(a,b,internal,id);if !distance {return 0;}
        let desired=pct_contact_center(a,b,internal,distance);
        if !desired {return cg_fail(m_cat("No valid contact on both curves: ",id));}
        pc_line_write_xy(j_get(pc_curve_geometry(target),"center"),desired);
    }

    if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    rel=j_object();cg_j_text(rel,"id",id);cg_j_text(rel,"type",kind);cg_j_text(rel,"a",source_id);cg_j_text(rel,"b",target_id);
    j_add(rows,0,rel);cg_push(records,cg_v(rel,id,0));
    if pct_line(source) {
        if !pc_solve_lines_with_source(lines,records,0,0,0,0,driver+1) {return 0;}
    }else if !pc_solve_lines(lines,records,driver,"center",j_get(pc_curve_geometry(source),"center"),0) {return 0;}
    return pc_finish_circle_sketch(project,result,lines);
}

fn cad_project_toggle_circular_tangent(project,sk,source_id,target_id,internal) {
    return pc_toggle_tangent(project,sk,source_id,target_id,internal,0);
}
fn cad_project_toggle_curve_tangent(project,sk,source_id,target_id) {
    return pc_toggle_tangent(project,sk,source_id,target_id,0,1);
}
