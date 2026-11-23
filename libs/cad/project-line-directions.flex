import "project-lines.flex";

// Keep the target's first anchor when seeding a direction or matching length.
// The solve still enforces all saved constraints.
fn pc_seed_line_pair(source,target,kind) {
    let from=pc_direction_vector(source);let to=pc_direction_vector(target);if !from || !to {return 0;}
    let length=load64(to+16);let direction=from;
    if m_eq(kind,"equal") {length=load64(from+16);direction=to;}
    let x=load64(direction);let y=load64(direction+8);
    if m_eq(kind,"perpendicular") {let swap=x;x=-y;y=swap;}
    if x*load64(to)+y*load64(to+8)<0 {x=-x;y=-y;}
    let ratio=f64_div(f64_from_i64(length),f64_from_i64(load64(direction+16)));
    let start=pc_uv(j_get(target,"p0"));if cg_error {return 0;}
    let end_x=load64(start)+f64_to_i64_round(f64_mul(f64_from_i64(x),ratio));
    let end_y=load64(start+8)+f64_to_i64_round(f64_mul(f64_from_i64(y),ratio));
    if cg_abs(end_x)<=500000000 && cg_abs(end_y)<=500000000 {pc_line_write_xy(j_get(target,"p1"),cg_v(end_x,end_y,0));}
    return 1;
}

fn pc_toggle_line_pair(project,sk,source_id,target_id,kind) {
    cg_begin();
    let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !pc_line_access(nodes,sketch) {if cg_error {return 0;}return cg_fail("Select an editable line sketch");}
    let source=pc_direction_line(nodes,sk,source_id);let target=pc_direction_line(nodes,sk,target_id);
    if !source || !target || source==target {return cg_fail("Choose two distinct lines in the sketch");}
    let rows=j_get(sketch,"relations");let rel=pc_first(rows);
    while rel {
        let a=j_string(rel,"a");let b=j_string(rel,"b");
        if m_eq(j_string(rel,"type"),kind) && (m_eq(a,source_id) && m_eq(b,target_id) || m_eq(a,target_id) && m_eq(b,source_id)) {
            pc_line_unlink(rows,rel,"");return result;
        }
        rel=load64(rel+24);
    }

    let records=pc_line_records(nodes,sketch);let lines=pc_line_entities(nodes,sketch);
    let driver=pc_line_index(lines,source_id);
    if driver>=cg_count(lines) || pc_line_index(lines,target_id)>=cg_count(lines) {return cg_fail("Use the source of a linked pattern");}
    if pc_line_projection(sketch,target_id) || po_owner(records,target_id) {return cg_fail("Use a free line as the follower");}
    if !pc_seed_line_pair(source,target,kind) {return 0;}

    if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    let base=m_cat("native-",m_cat(kind,m_cat("-",m_cat(source_id,m_cat("-",target_id)))));let id=base;let n=2;
    while pc_find(nodes,id) || pc_find(rows,id) {id=m_cat(base,m_cat("-",m_int(n)));n=n+1;}
    rel=j_object();cg_j_text(rel,"id",id);cg_j_text(rel,"type",kind);cg_j_text(rel,"a",source_id);cg_j_text(rel,"b",target_id);
    j_add(rows,0,rel);cg_push(records,cg_v(rel,id,0));
    if !pc_solve_lines_with_source(lines,records,0,0,0,0,driver+1) {return 0;}
    return pc_finish_circle_sketch(project,result,lines);
}

fn cad_project_toggle_line_direction(project,sk,source_id,target_id,kind) {
    if !pc_line_direction(kind) {cg_begin();return cg_fail("Choose Parallel or Perpendicular");}
    return pc_toggle_line_pair(project,sk,source_id,target_id,kind);
}
fn cad_project_toggle_equal_lines(project,sk,source_id,target_id) {
    return pc_toggle_line_pair(project,sk,source_id,target_id,"equal");
}
