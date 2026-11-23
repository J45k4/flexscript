import "cad/project-access.flex";
import "cad/project-point-on-curve-author.flex";

fn ecp_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn ecp_geometry(project,id) {return pc_curve_geometry(ecp_node(project,id));}
fn ecp_center(project,id) {return j_get(ecp_geometry(project,id),"center");}
fn ecp_relations(project) {return j_get(ecp_node(project,"native-sketch-1"),"relations");}
fn ecp_reopen(text) {
    let info=cad_project_inspect_source(text);m_assert(info && !j_get(info,"readOnly"),j_string(info,"readOnly"));
    return j_get(info,"document");
}
fn ecp_expect(project,x,y) {
    let p=pc_uv(ecp_center(project,"probe"));
    if pc_line_span(p,cg_v(x,y,0))>3 {m_print(2,m_cat(j_encode(ecp_center(project,"probe")),"\n"));}
    return m_assert(pc_line_span(p,cg_v(x,y,0))<=3,"Contact agrees with the TypeScript nearest point");
}
fn ecp_dof(project,expected) {
    let report=cad_project_line_sketch(project,"native-sketch-1");m_assert(report,cg_error);
    return m_assert(j_integer(report,"degrees_of_freedom")==expected && !j_get(report,"degrees_of_freedom_is_upper_bound"),"One normal constraint preserves tangential sliding");
}
fn ecp_edit(project,curve,field,text) {
    let result=cad_project_set_curve_dimension(project,"native-sketch-1",curve,field,text);m_assert(result,cg_error);return result;
}
fn ecp_drag(project,id,text) {
    let result=cad_project_move_point(project,"native-sketch-1",id,j_parse(text));m_assert(result,cg_error);return result;
}
fn ecp_mesh(project) {
    let mesh=cad_project_mesh(project);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));return mesh;
}

fn ecp_closed_ellipse(base) {
    let sketch="native-sketch-1";let shape="ellipse-guide";let id="ellipse-guide-contact";let before=j_encode(base);
    ecp_expect(base,8726940,11705780);ecp_dof(base,1);
    let initial=ecp_mesh(base);
    let wider=ecp_edit(base,shape,"width","46 mm");ecp_expect(wider,8640774,11892268);
    let taller=ecp_edit(wider,shape,"height","16 mm");ecp_expect(taller,7973888,13536200);
    let rotated=ecp_edit(taller,shape,"rotation","45 deg");ecp_expect(rotated,6779712,15389003);
    let reopened=ecp_reopen(j_encode(rotated));ecp_dof(reopened,1);
    m_assert(m_eq(j_encode(pc_find(ecp_relations(reopened),id)),j_encode(pc_find(ecp_relations(base),id))),"The saved ellipse contact keeps its relation and anchor IDs");
    m_assert(!m_eq(j_encode(j_get(initial,"vertices")),j_encode(j_get(ecp_mesh(reopened),"vertices"))),"The driven ellipse supplies the rebuilt extrusion outline");

    // Keep the horizontal distance fixed and select the near intersection
    // of the rotated ellipse and the anchor's column.
    let locked=j_parse(before);let rows=ecp_relations(locked);
    j_add(rows,0,j_parse("{\"id\":\"fixed-column\",\"type\":\"distance\",\"axis\":\"x\",\"a\":{\"entityId\":\"ellipse-guide\",\"point\":\"center\"},\"b\":{\"entityId\":\"probe\",\"point\":\"center\"},\"value\":5.726940}"));
    let column=ecp_edit(locked,shape,"height","16 mm");ecp_expect(column,8726940,13476182);ecp_dof(column,0);

    let variable=cad_project_edit_line_variable(base,sketch,"","span","12 mm");m_assert(variable,cg_error);
    variable=ecp_edit(variable,shape,"height","#span");
    variable=cad_project_edit_line_variable(variable,sketch,"span","span","16 mm");m_assert(variable,cg_error);
    ecp_expect(ecp_reopen(j_encode(variable)),8197299,13305727);

    let anchor=j_parse("{\"entityId\":\"probe\",\"point\":\"center\"}");
    let free=cad_project_toggle_point_on_curve(base,sketch,shape,anchor);m_assert(free,cg_error);
    free=ecp_drag(free,"probe","{\"x\":3,\"y\":2}");ecp_dof(free,2);
    let attached=cad_project_toggle_point_on_curve(free,sketch,shape,anchor);m_assert(attached,cg_error);
    ecp_expect(attached,-179516,7088289);ecp_dof(attached,1);
    m_assert(pc_find(ecp_relations(attached),"native-point-on-curve-probe-ellipse-guide"),"The authoring API persists a normal v4 relation");
    m_assert(m_eq(j_encode(base),before),"Edits preserve their input graph");
    return 1;
}

fn ecp_finite_arc(drawing) {
    let sketch="native-sketch-1";let shape="swept-guide";let id="swept-guide-contact";
    cg_j_set(drawing,"selectedPath",j_parse("[1]"));let base=ecp_reopen(j_encode(drawing));let before=j_encode(base);
    ecp_expect(base,3833869,-11315616);ecp_dof(base,2);
    let shortened=ecp_edit(base,shape,"arcSweep","-60 deg");ecp_expect(shortened,16218547,-13492040);ecp_dof(shortened,2);
    let start=ecp_drag(shortened,"probe","{\"x\":43,\"y\":23}");ecp_expect(start,19176875,-7147886);
    let interior=ecp_drag(start,"probe","{\"x\":17,\"y\":-13}");ecp_expect(interior,17071717,-13363203);
    let end=ecp_drag(interior,"probe","{\"x\":0,\"y\":-27}");ecp_expect(end,16218547,-13492040);
    let reopened=ecp_reopen(j_encode(end));ecp_dof(reopened,2);
    m_assert(m_eq(j_string(ecp_node(reopened,shape),"type"),"sketchArc") && m_eq(j_string(ecp_geometry(reopened,shape),"id"),shape),"Canonical elliptic arc remains in its authored wrapper");
    m_assert(m_eq(j_encode(pc_find(ecp_relations(reopened),id)),j_encode(pc_find(ecp_relations(base),id))),"Signed-sweep changes preserve the authored relation and anchors");
    m_assert(m_eq(j_encode(ecp_mesh(base)),j_encode(ecp_mesh(reopened))),"A construction elliptic arc leaves the manufactured profile unchanged");

    let blocked=j_parse(before);let rows=ecp_relations(blocked);
    j_add(rows,0,j_parse("{\"id\":\"point-fixed\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"probe\",\"point\":\"center\"},\"position\":{\"x\":3.833869,\"y\":-11.315616}}"));
    let locked=j_encode(blocked);
    m_assert(!cad_project_set_curve_dimension(blocked,sketch,shape,"arcSweep","-60 deg") && cg_error && m_eq(j_encode(blocked),locked),"A locked out-of-sweep follower rejects the edit atomically");

    let stale=j_parse(j_encode(shortened));
    pc_line_write_xy(ecp_center(stale,"probe"),cg_v(-4501091,6720382,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved point is outside its curve: swept-guide-contact"),"A point on the supporting ellipse but off the arc invalidates manufacturing");

    let locked_axis=j_parse(before);
    j_add(ecp_relations(locked_axis),0,j_parse("{\"id\":\"probe-column\",\"type\":\"distance\",\"axis\":\"x\",\"a\":{\"entityId\":\"swept-guide\",\"point\":\"center\"},\"b\":{\"entityId\":\"probe\",\"point\":\"center\"},\"value\":1.833869}"));
    let flipped=ecp_edit(locked_axis,shape,"arcSweep","120 deg");ecp_expect(flipped,3833869,3853771);ecp_dof(flipped,1);

    rows=ecp_relations(reopened);pc_line_unlink(rows,pc_find(rows,"swept-guide-center"),"");
    let moved=ecp_drag(reopened,shape,"{\"x\":9,\"y\":4}");ecp_expect(moved,23218547,-6492040);
    m_assert(pc_line_span(pc_uv(ecp_center(moved,shape)),cg_v(9000000,4000000,0))==0,"Changing the source center keeps the center edit and follows the new arc");

    let alias=j_parse(before);let entity=ecp_node(alias,shape);let geometry=j_parse(j_encode(j_get(entity,"arc")));
    pc_remove_field(entity,"arc");cg_j_text(entity,"type","sketchPrimitive");j_add(entity,"primitive",geometry);
    let legacy=ecp_edit(ecp_reopen(j_encode(alias)),shape,"arcSweep","-60 deg");ecp_expect(legacy,16218547,-13492040);
    m_assert(m_eq(j_string(ecp_node(legacy,shape),"type"),"sketchPrimitive"),"The existing Rust-style source wrapper is also retained");
    return 1;
}

fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/point-on-ellipse.pcad");
    let base=ecp_reopen(source);ecp_closed_ellipse(base);ecp_finite_arc(j_parse(source));return 0;
}
