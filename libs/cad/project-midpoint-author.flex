import "project-lines.flex";

fn cad_project_toggle_midpoint(project,sk,curve_id,anchor) {
    return pc_toggle_curve_anchor_relation(project,sk,curve_id,anchor,"midpoint");
}

fn pc_toggle_curve_anchor_relation(project,sk,curve_id,anchor,type) {
    cg_begin();
    let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !pc_line_access(nodes,sketch) {if cg_error {return 0;}return cg_fail("Select an editable sketch");}
    let entity=j_string(anchor,"entityId");let point=j_string(anchor,"point");
    let source=pc_find(nodes,curve_id);let kind=0;let incidence=m_eq(type,"pointOnCurve");
    if incidence {kind=pc_point_on_curve_kind(source);}else {kind=pc_midpoint_kind(source);}
    let follower=pc_saved_anchor(nodes,sk,anchor);
    if !kind || !follower || m_eq(entity,curve_id) || !m_eq(j_string(source,"sketchId"),sk) {
        if incidence {return cg_fail("Pick a line, circle, ellipse, arc or spline and a distinct sketch anchor");}
        return cg_fail("Pick a line or arc and a distinct sketch anchor");
    }
    let rows=j_get(sketch,"relations");let row=pc_first(rows);
    while row {
        let saved=j_get(row,"a");
        if m_eq(j_string(row,"type"),type) && m_eq(j_string(row,"b"),curve_id) &&
            m_eq(j_string(saved,"entityId"),entity) && m_eq(j_string(saved,"point"),point) {
            pc_line_unlink(rows,row,"");return result;
        }
        row=load64(row+24);
    }
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let lines=pc_line_entities(nodes,sketch);let driver=pc_line_index(lines,curve_id);
    if (kind!=6 && driver>=cg_count(lines)) || pc_line_index(lines,entity)>=cg_count(lines) || pc_line_projection(sketch,entity) || po_owner(records,entity) {
        return cg_fail("Use the source of the linked follower geometry");
    }
    let prefix="native-midpoint-";
    if incidence {
        prefix="native-point-on-curve-";
        let next=pc_point_on_curve_position(source,kind,pc_uv(follower));
        if !next || !pc_line_write_xy(follower,next) {return 0;}
    }else if !pc_curve_midpoint(source,kind) {return 0;}
    let base=m_cat(prefix,m_cat(entity,m_cat("-",curve_id)));let id=base;let n=2;
    while pc_find(nodes,id) || pc_find(rows,id) {id=m_cat(base,m_cat("-",m_int(n)));n=n+1;}
    if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    let a=j_object();cg_j_text(a,"entityId",entity);cg_j_text(a,"point",point);
    row=j_object();cg_j_text(row,"id",id);cg_j_text(row,"type",type);j_add(row,"a",a);cg_j_text(row,"b",curve_id);
    j_add(rows,0,row);
    if incidence {cg_push(records,pc_point_on_curve_entry(row,id,source));}
    else {cg_push(records,cg_v(row,id,0));}
    if kind==6 {
        if !pc_apply_line_constraints(lines,records) {return 0;}
    }else if kind==1 {
        if !pc_solve_lines_with_source(lines,records,0,0,0,0,driver+1) {return 0;}
    }else if !pc_solve_lines(lines,records,driver,"center",j_get(pc_curve_geometry(source),"center"),0) {return 0;}
    return pc_finish_circle_sketch(project,result,lines);
}
