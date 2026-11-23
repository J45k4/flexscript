import "author.flex";
import "project-lines.flex";

fn pc_append_symmetry(sketch,nodes,kind,axis) {
    let rows=j_get(sketch,"relations");if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    if j_kind(rows)!=3 {return cg_fail("Expected sketch relations");}
    let prefix=m_cat(kind,"-");let index=pc_free_index(rows,prefix);let id=m_cat(prefix,m_int(index));
    while pc_find(nodes,id) || pc_find(rows,id) {index=index+1;id=m_cat(prefix,m_int(index));}
    let rel=j_object();cg_j_text(rel,"id",id);cg_j_text(rel,"type",kind);cg_j_text(rel,"symmetryLine",axis);
    j_add(rows,0,rel);return rel;
}
fn pc_mirror_axis(nodes,sk,id) {
    let row=pc_find(nodes,id);
    if pc_mirror_kind(row)!=3 || !m_eq(j_string(row,"sketchId"),sk) {return cg_fail("Select a straight line in this sketch");}
    return row;
}
fn pc_reflect_anchor(from,to,axis) {
    let image=pc_reflect_uv(pc_uv(from),pc_uv(j_get(axis,"p0")),pc_uv(j_get(axis,"p1")));
    if !image {return 0;}return pc_line_write_xy(to,image);
}
fn cad_project_mirror_entity(project,sk,id,axis_id) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));
    let sketch=pc_find(nodes,sk);let source=pc_find(nodes,id);let axis=pc_mirror_axis(nodes,sk,axis_id);
    if !axis || !pc_line_access(nodes,sketch) {return cg_fail("Select an editable sketch and a mirror line");}
    let kind=pc_mirror_kind(source);
    if !kind || source==axis || !m_eq(j_string(source,"sketchId"),sk) {return cg_fail("Choose a different point, line, circle or arc to mirror");}
    let copy=j_parse(j_encode(source));let name=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));
    cg_j_text(copy,"id",name);
    if kind==3 {
        if !pc_reflect_anchor(j_get(source,"p0"),j_get(copy,"p0"),axis) || !pc_reflect_anchor(j_get(source,"p1"),j_get(copy,"p1"),axis) {return 0;}
    }else {
        let geom=pc_curve_geometry(copy);cg_j_text(geom,"id",name);
        let original=pc_curve_geometry(source);
        if !pc_reflect_anchor(j_get(original,"center"),j_get(geom,"center"),axis) {return 0;}
        if kind==4 {
            let start=pma_reflected_start(pma_start(original),pc_uv(j_get(axis,"p0")),pc_uv(j_get(axis,"p1")));
            pma_sweep(original);if cg_error {return 0;}
            pma_write_angle(geom,"startAngle",start);cg_j_set(geom,"sweep",pma_sweep_value(original,-1));
        }
    }
    let rel=pc_append_symmetry(sketch,nodes,"mirror",axis_id);if !rel {return 0;}
    cg_j_text(rel,"a",id);cg_j_text(rel,"b",name);j_add(nodes,0,copy);
    if !pc_line_access(nodes,sketch) {return cg_fail("Mirrored geometry exceeds sketch limits");}
    return pc_finish_circle_sketch(project,result,pc_line_entities(nodes,sketch));
}
fn cad_project_toggle_point_symmetry(project,sk,a,b,axis_id) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));
    let sketch=pc_find(nodes,sk);let axis=pc_mirror_axis(nodes,sk,axis_id);
    if !axis || !pc_line_access(nodes,sketch) {return cg_fail("Select an editable sketch and a mirror line");}
    let from=pc_saved_anchor(nodes,sk,a);let to=pc_saved_anchor(nodes,sk,b);
    if !from || !to || from==to || m_eq(j_string(a,"entityId"),axis_id) || m_eq(j_string(b,"entityId"),axis_id) {return cg_fail("Choose two different anchors off the mirror line");}
    let rows=j_get(sketch,"relations");let rel=pc_first(rows);
    while rel {
        if m_eq(j_string(rel,"type"),"symmetric") && m_eq(j_string(rel,"symmetryLine"),axis_id) {
            let x=pc_saved_anchor(nodes,sk,j_get(rel,"a"));let y=pc_saved_anchor(nodes,sk,j_get(rel,"b"));
            if (from==x && to==y) || (from==y && to==x) {pc_line_unlink(rows,rel,"");return result;}
        }
        rel=load64(rel+24);
    }
    let records=pc_line_records(nodes,sketch);let lines=pc_line_entities(nodes,sketch);
    if !pc_reflect_anchor(from,to,axis) {return 0;}
    rel=pc_append_symmetry(sketch,nodes,"symmetric",axis_id);if !rel {return 0;}
    j_add(rel,"a",j_parse(j_encode(a)));j_add(rel,"b",j_parse(j_encode(b)));cg_push(records,cg_v(rel,j_string(rel,"id"),0));
    if !pc_solve_lines(lines,records,pc_line_index(lines,j_string(a,"entityId")),j_string(a,"point"),from,0) || !pc_line_access(nodes,sketch) {return 0;}
    return pc_finish_circle_sketch(project,result,lines);
}
