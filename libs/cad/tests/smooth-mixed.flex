import "cad/project-access.flex";
import "cad/project-smooth-author.flex";

fn mixed_center(node) {return pc_uv(j_get(pc_curve_geometry(node),"center"));}
fn mixed_document(p) {
    let report=cad_project_inspect_source(j_encode(p));m_assert(report,cg_error);
    m_assert(!j_get(report,"readOnly"),j_string(report,"readOnly"));return j_get(report,"document");
}
fn mixed_check(p,sk,line,arc,circle,x) {
    let nodes=pc_nodes(cad_project_part(p));let source=pc_find(nodes,line);let follower=pc_find(nodes,arc);let independent=pc_find(nodes,circle);
    m_assert(pc_line_span(pc_uv(j_get(source,"p0")),cg_v(-40000000,0,0))==0,"Driving length holds the start of the line");
    m_assert(pc_line_span(pc_uv(j_get(source,"p1")),cg_v(x,0,0))<3,"Horizontal line follows its driving length");
    m_assert(pc_line_span(mixed_center(follower),cg_v(x,10000000,0))<3,"Joined arc center moves with the line");
    m_assert(ps_matches(ps_endpoint(source,"p1"),ps_endpoint(follower,"p0")),"Shared endpoint remains tangent");
    m_assert(pc_circle_measure(follower,"radius")==10000000 && pc_circle_measure(follower,"arcSweep")==90000000,"Arc size and signed sweep stay fixed");
    m_assert(pc_circle_measure(independent,"diameter")==12000000 && pc_line_span(mixed_center(independent),cg_v(0,40000000,0))==0,"Independent driving circle remains solved");
    let sketch=pc_find(nodes,sk);let records=pc_line_records(nodes,sketch);m_assert(records,cg_error);
    m_assert(pc_find(j_get(sketch,"relations"),"native-smooth-join-native-entity-2-p0"),"Smooth relation ID survives the edit");
    let report=cad_project_line_sketch(p,sk);m_assert(report,cg_error);
    m_assert(j_value(j_get(report,"degrees_of_freedom_is_upper_bound")),"Mixed solver reports only an upper bound for DOF");
}
fn main() {
    let p=cad_project_new("Driving tangent");let sk="native-sketch-1";
    let source=cad_project_add_primitive(p,sk,"line",cg_v(-40000000,0,0),cg_v(0,0,0));m_assert(source,cg_error);
    let line=j_string(source,"id");let arc="native-entity-2";
    let nodes=pc_nodes(cad_project_part(p));let rel=j_get(pc_find(nodes,sk),"relations");
    if !rel {rel=j_array();j_add(pc_find(nodes,sk),"relations",rel);}
    j_add(rel,0,j_parse("{\"id\":\"horizontal\",\"type\":\"horizontal\",\"entityId\":\"native-entity-1\"}"));
    p=cad_project_set_line_length(p,sk,line,40000000);m_assert(p,cg_error);
    let a=ps_anchor(line,"p1");let b=ps_anchor(arc,"p0");
    p=cad_project_add_tangent_arc(p,sk,a,j_parse("{\"x\":10,\"y\":10}"));m_assert(p,cg_error);
    let circle=j_string(cad_project_add_primitive(p,sk,"circle",cg_v(0,40000000,0),cg_v(5000000,40000000,0)),"id");m_assert(circle,cg_error);
    p=cad_project_set_circle_dimension(p,sk,circle,"diameter","12 mm");m_assert(p,cg_error);
    p=mixed_document(p);mixed_check(p,sk,line,arc,circle,0);
    let original=j_encode(p);let changed=cad_project_set_line_expression(p,sk,line,"5 cm");m_assert(changed,cg_error);
    m_assert(m_eq(j_encode(p),original),"Edit leaves the previous project intact");
    changed=mixed_document(changed);mixed_check(changed,sk,line,arc,circle,10000000);
    changed=cad_project_edit_line_variable(changed,sk,"","length","5 cm");m_assert(changed,cg_error);
    changed=cad_project_set_line_expression(changed,sk,line,"#length");m_assert(changed,cg_error);
    changed=cad_project_edit_line_variable(changed,sk,"length","length","55 mm");m_assert(changed,cg_error);
    changed=mixed_document(changed);mixed_check(changed,sk,line,arc,circle,15000000);

    let closed=j_parse(j_encode(changed));
    m_assert(cad_project_add_primitive(closed,sk,"line",cg_v(25000000,10000000,0),cg_v(-40000000,0,0)),cg_error);
    closed=cad_project_add_extrusion(closed,sk,2,5000000,"newBody");m_assert(closed,cg_error);
    let ready=j_encode(closed);
    m_assert(!cad_project_set_line_expression(closed,sk,line,"60 mm") && cg_error,"Driving edit cannot break the dependent solid profile");
    m_assert(m_eq(j_encode(closed),ready),"A failing feature rebuild keeps the solid and sketch intact");

    nodes=pc_nodes(cad_project_part(changed));rel=j_get(pc_find(nodes,sk),"relations");
    j_add(rel,0,j_parse("{\"id\":\"fixed-center\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-2\",\"point\":\"center\"},\"position\":{\"x\":15,\"y\":10}}"));
    changed=mixed_document(changed);let locked=j_encode(changed);
    m_assert(!cad_project_set_line_expression(changed,sk,line,"60 mm") && cg_error,"Fixed arc center prevents incompatible driving length");
    m_assert(!cad_project_edit_line_variable(changed,sk,"length","length","6 cm") && cg_error,"Incompatible variable edits fail too");
    m_assert(m_eq(j_encode(changed),locked),"Rejected edits leave both constraints and all geometry unchanged");

    let detached=cad_project_toggle_smooth_join(changed,sk,a,b);m_assert(detached,cg_error);
    nodes=pc_nodes(cad_project_part(detached));rel=j_get(pc_find(nodes,sk),"relations");
    m_assert(!pc_find(rel,"native-smooth-join-native-entity-2-p0") && pc_find(rel,"fixed-center") && pc_find(rel,"horizontal"),"Removing a join preserves independent constraints");
    m_assert(cad_project_set_line_expression(detached,sk,line,"60 mm"),cg_error);
    return 0;
}
