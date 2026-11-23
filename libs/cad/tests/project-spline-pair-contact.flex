import "cad/project-access.flex";
import "cad/project-point-on-curve-author.flex";
import "cad/project-smooth-author.flex";

fn spc_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn spc_rows(project) {return j_get(spc_node(project,"native-sketch-1"),"relations");}
fn spc_reopen(project) {
    let report=cad_project_inspect_source(j_encode(project));m_assert(!j_get(report,"readOnly"),j_string(report,"readOnly"));
    let result=j_get(report,"document");m_assert(result,"Reopen the resolved intersection");return result;
}
fn spc_select(text,index) {
    let project=j_parse(text);let selected=j_array();j_add(selected,0,j_number(index));cg_j_set(project,"selectedPath",selected);
    return spc_reopen(project);
}
fn spc_expect(project,x,y) {
    let point=j_get(pc_curve_geometry(spc_node(project,"crossing-marker")),"center");
    return m_assert(cg_distance2(pc_uv(point),cg_v(x,y,0))<=4,m_cat("Marker differs from the TypeScript finite crossing: ",j_encode(point)));
}
fn spc_mesh(project) {
    let mesh=cad_project_mesh(project);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));return j_encode(mesh);
}
fn spc_refit(source) {
    let sk="native-sketch-1";let base=spc_select(source,0);let unchanged=j_encode(base);
    let anchor=ps_anchor("fit-crossing","point1");let target=j_parse("{\"x\":90,\"y\":0.3}");
    let moved=cad_project_move_smooth_point(base,sk,anchor,target);m_assert(moved,cg_error);moved=spc_reopen(moved);
    spc_expect(moved,38571429,128571);
    m_assert(m_eq(j_encode(spc_rows(moved)),j_encode(spc_rows(base))) && m_eq(j_encode(spc_node(moved,"control-crossing")),j_encode(spc_node(base,"control-crossing"))),"Both saved spline relation IDs and the independent control chain survive the refit");
    m_assert(m_eq(spc_mesh(base),spc_mesh(moved)),"Reshaping construction curves preserves the unrelated closed extrusion");
    m_assert(!cad_project_move_smooth_point(base,sk,anchor,j_parse("{\"x\":90,\"y\":-5}")) && cg_error && m_eq(j_encode(base),unchanged),"Disjoint finite sources reject the edit atomically");
    let locked=j_parse(unchanged);j_add(spc_rows(locked),0,j_parse("{\"id\":\"fixed-marker\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"crossing-marker\",\"point\":\"center\"},\"position\":{\"x\":45,\"y\":0}}"));
    let saved=j_encode(locked);
    m_assert(!cad_project_move_smooth_point(locked,sk,anchor,target) && cg_error && m_eq(j_encode(locked),saved),"Analytic seeding cannot move an independently fixed marker");
    return 1;
}
fn spc_choose_branch(source) {
    let base=spc_select(source,1);let sk="native-sketch-1";let marker="crossing-marker";spc_expect(base,19019238,0);
    let target=j_parse("{\"x\":80,\"y\":0.8}");
    let moved=cad_project_move_point(base,sk,marker,target);m_assert(moved,cg_error);moved=spc_reopen(moved);
    spc_expect(moved,70980762,0);
    m_assert(m_eq(j_encode(spc_rows(base)),j_encode(spc_rows(moved))),"Selecting the other finite crossing keeps both authored relations");
    let curve="control-crossing";let anchor=ps_anchor(marker,"center");
    let detached=cad_project_toggle_point_on_curve(base,sk,curve,anchor);m_assert(detached,cg_error);
    let free=cad_project_move_point(detached,sk,marker,target);m_assert(free,cg_error);spc_expect(free,80000000,0);
    let attached=cad_project_toggle_point_on_curve(free,sk,curve,anchor);m_assert(attached,cg_error);attached=spc_reopen(attached);
    spc_expect(attached,70980762,0);
    let saved=pc_find(spc_rows(attached),"native-point-on-curve-crossing-marker-control-crossing");
    m_assert(m_eq(j_string(saved,"b"),curve) && m_eq(j_encode(j_get(saved,"a")),j_encode(anchor)),"Attaching the other curve writes the ordinary v4 Point on curve schema");
    return 1;
}
fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/spline-pair-contact.pcad");
    return !(spc_refit(source) && spc_choose_branch(source));
}
