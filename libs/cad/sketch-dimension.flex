// Axis-aligned rectangle dimensions in a v4 sketch. Solves the two endpoint
// coordinates with the same midpoint/fixed-endpoint rules as the native editor.
import "project.flex";

fn pc_field_axis(field) {
    if m_eq(field,"width") {return "x";}
    if m_eq(field,"height") {return "y";}
    return 0;
}
fn cad_rectangle_dimension(rect,field) {
    let axis=pc_field_axis(field);
    if !axis {return cg_fail("Select width or height");}
    return cg_abs(pc_pose_number(j_get(j_get(rect,"p1"),axis))-pc_pose_number(j_get(j_get(rect,"p0"),axis)));
}
fn pc_rect_relation(row,id,field,state) {
    let type=j_string(row,"type");
    if pp_kind(row) {return 1;}
    if po_kind(row) {
        if po_target(row,id) {return cg_fail("Edit the source rectangle or its offset distance");}return 1;
    }
    if m_eq(type,"fixed") {
        let anchor=j_get(row,"anchor");
        if !m_eq(j_string(anchor,"entityId"),id) {return 1;}
        let corner=j_string(anchor,"point");
        if m_eq(corner,"p0") {store64(state,1);}
        else if m_eq(corner,"p1") {store64(state+8,1);}
        else {return cg_fail("Unsupported fixed rectangle anchor");}
        return 1;
    }
    let width=m_eq(type,"width") || m_eq(type,"rectangleWidth");
    let height=m_eq(type,"height") || m_eq(type,"rectangleHeight");
    if !width && !height {return cg_fail("This sketch relation needs the general constraint solver");}
    if !m_eq(j_string(row,"entityId"),id) {return 1;}
    if (width && m_eq(field,"width")) || (height && m_eq(field,"height")) {
        if j_get(row,"expression") || j_value(j_get(row,"reference")) {return cg_fail("Select an independent driving dimension");}
        if load64(state+16) {return cg_fail("Multiple constraints drive this dimension");}
        store64(state+16,row);
    }
    return 1;
}
fn cad_project_dimension(project,entity,field,value) {
    cg_begin();let nodes=pc_nodes(cad_project_part(project));let sketch=pc_find(nodes,j_string(pc_find(nodes,entity),"sketchId"));
    if pc_linked_sketch(sketch) {
        if j_get(pp_targets(sketch),entity) {return cg_fail("Edit the pattern source rectangle");}
        if !pc_evaluate_links(nodes,sketch,0) {return 0;}
        let copy=j_parse(j_encode(project));let mesh=pc_resize_rectangle(copy,entity,field,value);
        if mesh {store64(project+16,load64(copy+16));}return mesh;
    }
    return pc_resize_rectangle(project,entity,field,value);
}
fn pc_resize_rectangle(project,entity,field,value) {
    let axis=pc_field_axis(field);
    if !axis {return cg_fail("Unknown rectangle dimension");}
    let nodes=pc_nodes(cad_project_part(project));let rect=pc_find(nodes,entity);
    if !m_eq(j_string(rect,"type"),"sketchCornerRectangle") {return cg_fail("Select a rectangular sketch entity");}
    let sketch=pc_find(nodes,j_string(rect,"sketchId"));let relations=j_get(sketch,"relations");
    if !sketch || (relations && j_kind(relations)!=3) {return cg_fail("Invalid sketch relations");}
    let state=m_take(24);store64(state,0);store64(state+8,0);store64(state+16,0);
    let row=pc_first(relations);
    while row {if !pc_rect_relation(row,entity,field,state) {return 0;}row=load64(row+24);}
    row=pc_first(nodes);
    while row {
        if m_eq(j_string(row,"sketchId"),j_string(sketch,"id")) && m_eq(j_string(row,"type"),"sketchConstraint") {
            if !pc_rect_relation(j_get(row,"constraint"),entity,field,state) {return 0;}
        }
        row=load64(row+24);
    }
    if load64(state) && load64(state+8) {return cg_fail("Both rectangle corners are fixed");}
    let p0=j_get(rect,"p0");let p1=j_get(rect,"p1");let a0=j_get(p0,axis);let b0=j_get(p1,axis);
    let a=pc_pose_number(a0);let b=pc_pose_number(b0);let span=pc_pose_number(value);
    if cg_error || span<=0 {return cg_fail("Dimension must be a positive length");}
    if a>b {span=-span;}
    let new_a=(a+b-span)/2;
    if load64(state) {new_a=a;}else if load64(state+8) {new_a=b-span;}
    let old_a=j_new(j_kind(a0),j_value(a0));let old_b=j_new(j_kind(b0),j_value(b0));
    cg_j_set(p0,axis,cg_json_number(new_a));cg_j_set(p1,axis,cg_json_number(new_a+span));
    if pc_linked_sketch(sketch) && !pc_evaluate_links(nodes,sketch,1) {return 0;}
    let mesh=cad_project_mesh(project);
    if j_get(mesh,"error") {cg_j_set(p0,axis,old_a);cg_j_set(p1,axis,old_b);return 0;}
    let relation=load64(state+16);
    if !relation {
        if !relations {relations=j_array();j_add(sketch,"relations",relations);}
        let base=m_cat("native-dimension-",m_cat(entity,m_cat("-",field)));let id=base;let n=2;
        while pc_find(relations,id) {id=m_cat(base,m_cat("-",m_int(n)));n=n+1;}
        relation=j_object();cg_j_text(relation,"id",id);cg_j_text(relation,"type",field);
        cg_j_text(relation,"entityId",entity);j_add(relations,0,relation);
    }
    cg_j_set(relation,"value",value);
    return mesh;
}
