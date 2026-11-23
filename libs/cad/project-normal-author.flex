import "project-lines.flex";

fn cad_project_toggle_normal(project,sk,curve_id,anchor) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !pc_line_access(nodes,sketch) {if cg_error {return 0;}return cg_fail("Select an editable sketch");}
    let entity=j_string(anchor,"entityId");let end=j_string(anchor,"point");
    let curve=pc_find(nodes,curve_id);let line=pc_find(nodes,entity);
    if !pc_normal_curve(curve) || line==curve || !m_eq(j_string(line,"type"),"sketchLine") || !pc_normal_end(anchor) ||
        !m_eq(j_string(line,"sketchId"),sk) || !m_eq(j_string(curve,"sketchId"),sk) {
        return cg_fail("Pick a line endpoint and a separate line, circle, ellipse, arc or spline in this sketch");
    }
    let rows=j_get(sketch,"relations");let row=pc_first(rows);
    while row {
        let a=j_get(row,"a");
        if m_eq(j_string(row,"type"),"normal") && m_eq(j_string(row,"b"),curve_id) &&
           m_eq(j_string(a,"entityId"),entity) && m_eq(j_string(a,"point"),end) {
            pc_line_unlink(rows,row,"");return result;
        }
        row=load64(row+24);
    }
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let lines=pc_line_entities(nodes,sketch);let driver=pc_line_index(lines,curve_id);
    let spline=m_eq(j_string(curve,"type"),"sketchSpline");
    if j_get(pp_targets(sketch),curve_id) || !spline && driver>=cg_count(lines) || pc_line_index(lines,entity)>=cg_count(lines) ||
        pc_line_projection(sketch,entity) || po_owner(records,entity) {
        return cg_fail("Use the source of the linked normal line");
    }
    if !pc_seed_normal(curve,line,end) {return 0;}
    let base=m_cat("native-normal-",m_cat(entity,m_cat("-",curve_id)));let id=base;let n=2;
    while pc_find(rows,id) || pc_find(nodes,id) {id=m_cat(base,m_cat("-",m_int(n)));n=n+1;}
    let a=j_object();cg_j_text(a,"entityId",entity);cg_j_text(a,"point",end);
    row=j_object();cg_j_text(row,"id",id);cg_j_text(row,"type","normal");j_add(row,"a",a);cg_j_text(row,"b",curve_id);
    if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    j_add(rows,0,row);cg_push(records,pc_point_on_curve_entry(row,id,curve));
    if spline {
        if !pc_apply_line_constraints(lines,records) {return 0;}
    }else if m_eq(j_string(curve,"type"),"sketchLine") {
        if !pc_solve_lines_with_source(lines,records,0,0,0,0,driver+1) {return 0;}
    }else if !pc_solve_lines(lines,records,driver,"center",j_get(pc_curve_geometry(curve),"center"),0) {return 0;}
    return pc_finish_circle_sketch(project,result,lines);
}
