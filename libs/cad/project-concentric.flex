import "project-lines.flex";

fn cad_project_toggle_concentric(project,sk,source_id,target_id) {
    cg_begin();
    let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !pc_line_access(nodes,sketch) {if cg_error {return 0;}return cg_fail("Select an editable sketch");}
    let source=pc_concentric_curve(nodes,sk,source_id);let target=pc_concentric_curve(nodes,sk,target_id);
    if !source || !target || source==target {return cg_fail("Choose two distinct circles, arcs or ellipses in the sketch");}

    let rows=j_get(sketch,"relations");let rel=pc_first(rows);
    while rel {
        let a=j_string(rel,"a");let b=j_string(rel,"b");
        if m_eq(j_string(rel,"type"),"concentric") && (m_eq(a,source_id) && m_eq(b,target_id) || m_eq(a,target_id) && m_eq(b,source_id)) {
            pc_line_unlink(rows,rel,"");return result;
        }
        rel=load64(rel+24);
    }
    let lines=pc_line_entities(nodes,sketch);let driver=pc_line_index(lines,source_id);
    if driver>=cg_count(lines) || pc_line_index(lines,target_id)>=cg_count(lines) {return cg_fail("Use the source of a linked pattern");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    if !rows {rows=j_array();j_add(sketch,"relations",rows);}

    let base=m_cat("native-concentric-",m_cat(source_id,m_cat("-",target_id)));let id=base;let n=2;
    while pc_find(nodes,id) || pc_find(rows,id) {id=m_cat(base,m_cat("-",m_int(n)));n=n+1;}
    rel=j_object();cg_j_text(rel,"id",id);cg_j_text(rel,"type","concentric");cg_j_text(rel,"a",source_id);cg_j_text(rel,"b",target_id);
    j_add(rows,0,rel);cg_push(records,cg_v(rel,id,0));
    if !pc_solve_lines(lines,records,driver,"center",j_get(pc_curve_geometry(source),"center"),0) {return 0;}
    return pc_finish_circle_sketch(project,result,lines);
}
