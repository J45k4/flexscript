import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-tangent-author.flex";

fn tangent_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn tangent_geometry(project,id) {return pc_curve_geometry(tangent_node(project,id));}
fn tangent_center(project,id) {return pc_uv(j_get(tangent_geometry(project,id),"center"));}
fn tangent_rows(project,sk) {return j_get(tangent_node(project,sk),"relations");}
fn tangent_open(source) {
    let report=cad_project_inspect_source(source);m_assert(report,cg_error);
    m_assert(!j_get(report,"readOnly"),j_string(report,"readOnly"));return j_get(report,"document");
}
fn tangent_expect_center(project,id,at) {
    return m_assert(pc_line_span(tangent_center(project,id),at)<=1,"Center follows the circular tangent");
}
fn tangent_internal_fixture() {
    let p=cad_project_new("Internal tangent");let sk="native-sketch-1";let outer="native-entity-1";let inner="inner-arc";
    m_assert(cad_project_add_primitive(p,sk,"circle",cg_v(0,0,0),cg_v(20000000,0,0)),cg_error);
    let nodes=pc_nodes(cad_project_part(p));
    j_add(nodes,0,j_parse("{\"id\":\"inner-arc\",\"type\":\"sketchArc\",\"sketchId\":\"native-sketch-1\",\"arc\":{\"id\":\"inner-arc\",\"type\":\"arc\",\"center\":{\"x\":15,\"y\":0},\"radius\":10,\"startAngle\":0.8,\"sweep\":-1.6,\"segments\":64}}"));
    let pair=cad_project_toggle_circular_tangent(p,sk,outer,inner,1);m_assert(pair,cg_error);
    tangent_expect_center(pair,inner,cg_v(10000000,0,0));
    pair=tangent_open(j_encode(pair));let report=cad_project_line_sketch(pair,sk);m_assert(report,cg_error);
    m_assert(j_value(j_get(report,"degrees_of_freedom_is_upper_bound")),"Unbound radii retain their freedom report limit");
    let saved=j_encode(pair);
    m_assert(!cad_project_set_circle_dimension(pair,sk,outer,"diameter","16 mm") && cg_error,"Internal tangent rejects an inverted outer radius");
    m_assert(m_eq(j_encode(pair),saved),"Radius conflict leaves both circles intact");
    pair=cad_project_edit_line_variable(pair,sk,"","span","50 mm");m_assert(pair,cg_error);
    pair=cad_project_set_circle_dimension(pair,sk,outer,"diameter","#span");m_assert(pair,cg_error);
    tangent_expect_center(pair,inner,cg_v(15000000,0,0));
    pair=cad_project_edit_line_variable(pair,sk,"span","span","52 mm");m_assert(pair,cg_error);
    pair=tangent_open(j_encode(pair));tangent_expect_center(pair,inner,cg_v(16000000,0,0));
    m_assert(m_eq(j_value(j_get(tangent_geometry(pair,inner),"sweep")),"-1.6"),"Clockwise inner sweep is retained");
    return 1;
}

fn tangent_finite_pair() {
    let p=cad_project_new("Finite tangent windows");let sk="native-sketch-1";
    let nodes=pc_nodes(cad_project_part(p));
    j_add(nodes,0,j_parse("{\"id\":\"first\",\"type\":\"sketchArc\",\"sketchId\":\"native-sketch-1\",\"arc\":{\"id\":\"first\",\"type\":\"arc\",\"center\":{\"x\":0,\"y\":0},\"radius\":20,\"startAngle\":-0.785398163397,\"sweep\":1.570796326795,\"segments\":64}}"));
    j_add(nodes,0,j_parse("{\"id\":\"second\",\"type\":\"sketchArc\",\"sketchId\":\"native-sketch-1\",\"arc\":{\"id\":\"second\",\"type\":\"arc\",\"center\":{\"x\":40,\"y\":0},\"radius\":10,\"startAngle\":0.8,\"sweep\":-1.6,\"segments\":64}}"));
    let original=j_encode(p);
    m_assert(!cad_project_toggle_circular_tangent(p,sk,"first","second",0) && cg_error,"Disjoint external sweep windows cannot touch");
    m_assert(m_eq(j_encode(p),original),"No common finite contact leaves both arcs intact");
    cg_j_set(tangent_geometry(p,"second"),"startAngle",j_new(6,"3.94159265359"));
    let contact=cad_project_toggle_circular_tangent(p,sk,"first","second",0);m_assert(contact,cg_error);
    contact=tangent_open(j_encode(contact));tangent_expect_center(contact,"second",cg_v(30000000,0,0));
    return 1;
}

fn main() {
    let sk="tangent-sketch";let guide="guide-arc";let stop="stop-circle";let id="imported-stop-tangent";
    let p=tangent_open(m_read_file("libs/cad/tests/fixtures/circular-tangent.pcad"));let original=j_encode(p);
    let report=cad_project_line_sketch(p,sk);m_assert(report,cg_error);
    m_assert(j_integer(report,"degrees_of_freedom")==2 && !j_get(report,"degrees_of_freedom_is_upper_bound"),"Finite tangent adds one ranked center-distance equation");
    let resized=cad_project_set_curve_dimension(p,sk,guide,"radius","25 mm");m_assert(resized,cg_error);
    tangent_expect_center(resized,guide,cg_v(0,0,0));tangent_expect_center(resized,stop,cg_v(35000000,0,0));
    resized=tangent_open(j_encode(resized));
    m_assert(m_eq(j_encode(pc_find(tangent_rows(resized,sk),id)),j_encode(pc_find(tangent_rows(p,sk),id))),"Imported IDs survive a driving radius edit");
    m_assert(pc_circle_measure(tangent_node(resized,stop),"diameter")==20000000,"Follower diameter remains independent");
    let unchanged=j_encode(resized);
    m_assert(!cad_project_set_curve_dimension(resized,sk,guide,"arcSweep","-45 deg") && cg_error,"Whole-curve contact must stay on the retained sweep");
    m_assert(m_eq(j_encode(resized),unchanged),"Rejected sweep edit is atomic");

    let solid=cad_project_add_extrusion(resized,sk,1,10000000,"newBody");m_assert(solid,cg_error);
    let mesh=cad_project_mesh(solid);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let bounds=j_get(pc_first(j_get(mesh,"parts")),"bounds");
    m_assert(m_eq(j_encode(bounds),"[[25.000000,-10.000000,0.000000],[45.000000,10.000000,10.000000]]"),"Extrusion follows the tangent stop");
    let stale=j_parse(j_encode(solid));pc_line_write_xy(j_get(tangent_geometry(stale,stop),"center"),cg_v(-35000000,0,0));
    let message="Circular tangent contact is outside a finite arc: imported-stop-tangent";
    m_assert(m_eq(j_string(cad_project_inspect_source(j_encode(stale)),"readOnly"),message),"Reader rejects support-only contact and names the relation");
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),message),"Exporter rejects the same invalid finite contact");

    let separate=cad_project_toggle_circular_tangent(p,sk,stop,guide,0);m_assert(separate,cg_error);
    m_assert(!pc_find(tangent_rows(separate,sk),id),"Removing external Tangent recognizes either pick order");
    separate=cad_project_move_point(separate,sk,stop,j_parse("{\"x\":40,\"y\":0}"));m_assert(separate,cg_error);
    let authored=cad_project_toggle_circular_tangent(separate,sk,guide,stop,0);m_assert(authored,cg_error);
    tangent_expect_center(authored,stop,cg_v(30000000,0,0));
    m_assert(pc_find(tangent_rows(authored,sk),"native-external-tangent-guide-arc-stop-circle"),"Writer retains Rust's external tangent schema");
    m_assert(m_eq(j_encode(p),original),"Edits and authoring leave the original intact");

    let rows=tangent_rows(separate,sk);
    j_add(rows,0,j_parse("{\"id\":\"fixed-stop\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"stop-circle\",\"point\":\"center\"},\"position\":{\"x\":40,\"y\":0}}"));
    let conflict=j_encode(separate);
    m_assert(!cad_project_toggle_circular_tangent(separate,sk,guide,stop,0) && cg_error,"Fixed incompatible centers reject the edit");
    m_assert(m_eq(j_encode(separate),conflict),"Conflict cannot add a relation or move a curve");
    return !(tangent_internal_fixture() && tangent_finite_pair());
}
