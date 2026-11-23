import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-midpoint-author.flex";

fn midpoint_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn midpoint_center(project,id) {return j_get(pc_curve_geometry(midpoint_node(project,id)),"center");}
fn midpoint_relations(project,sk) {return j_get(midpoint_node(project,sk),"relations");}
fn midpoint_expect(at,x,y,tolerance) {
    m_assert(pc_line_span(pc_uv(at),cg_v(x,y,0))<=tolerance,"Follower sits at the curve midpoint");return 1;
}
fn midpoint_reopen(project) {
    let inspected=cad_project_inspect_source(j_encode(project));m_assert(inspected,cg_error);
    m_assert(!j_get(inspected,"readOnly"),j_string(inspected,"readOnly"));return j_get(inspected,"document");
}
fn midpoint_line() {
    let sk="native-sketch-1";let guide="layout-guide";let point="center-mark";let bore="bore";let saved_id="named-guide-midpoint";
    let original=midpoint_reopen(cad_project_open(m_read_file("libs/cad/tests/fixtures/midpoint-guide.pcad")));
    let saved=j_encode(original);let report=cad_project_line_sketch(original,sk);m_assert(report,cg_error);
    m_assert(j_integer(report,"degrees_of_freedom")==2,"The midpoint removes both follower coordinates, leaving the free bore");
    let enlarged=cad_project_set_line_length(original,sk,guide,30000000);m_assert(enlarged,cg_error);
    enlarged=midpoint_reopen(enlarged);
    midpoint_expect(j_get(midpoint_node(enlarged,guide),"p1"),30000000,0,0);
    midpoint_expect(midpoint_center(enlarged,point),15000000,0,0);
    m_assert(m_eq(j_encode(pc_find(midpoint_relations(enlarged,sk),saved_id)),j_encode(pc_find(midpoint_relations(original,sk),saved_id))),"Imported midpoint ID and anchors survive edits and reopen");
    let native_solid=cad_project_add_extrusion(enlarged,sk,1,10000000,"newBody");m_assert(native_solid,cg_error);
    let stale=j_parse(j_encode(native_solid));pc_line_write_xy(midpoint_center(stale,point),cg_v(14000000,0,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved midpoint disagrees with geometry: named-guide-midpoint"),"A stale imported midpoint prevents manufacturing");

    let anchor=j_parse("{\"entityId\":\"bore\",\"point\":\"center\"}");
    let moved=cad_project_toggle_midpoint(original,sk,guide,anchor);m_assert(moved,cg_error);
    midpoint_expect(midpoint_center(moved,bore),10000000,0,1);
    let solid=cad_project_add_extrusion(moved,sk,1,10000000,"newBody");m_assert(solid,cg_error);
    solid=cad_project_set_line_length(solid,sk,guide,30000000);m_assert(solid,cg_error);
    solid=midpoint_reopen(solid);midpoint_expect(midpoint_center(solid,bore),15000000,0,0);
    let mesh=cad_project_mesh(solid);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let bounds=j_get(pc_first(j_get(mesh,"parts")),"bounds");let minimum=pc_first(bounds);let maximum=load64(minimum+24);
    m_assert(pc_pose_number(pc_first(minimum))==10000000 && pc_pose_number(pc_first(maximum))==20000000,"The dependent solid moves with its midpoint-driven center");
    let unlinked=cad_project_toggle_midpoint(moved,sk,guide,anchor);m_assert(unlinked,cg_error);
    m_assert(!pc_find(midpoint_relations(unlinked,sk),"native-midpoint-bore-layout-guide"),"Toggle removes the selected midpoint");

    let blocked=j_parse(saved);
    j_add(midpoint_relations(blocked,sk),0,j_parse("{\"id\":\"bore-lock\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"bore\",\"point\":\"center\"},\"position\":{\"x\":35,\"y\":0}}"));
    let before=j_encode(blocked);
    m_assert(!cad_project_toggle_midpoint(blocked,sk,guide,anchor) && cg_error,"A distinct fixed follower makes the relation unsatisfiable");
    m_assert(m_eq(j_encode(blocked),before) && m_eq(j_encode(original),saved),"Rejected and successful writes leave their inputs intact");
    return 1;
}

fn midpoint_arcs() {
    let p=cad_project_new("Arc midpoints");let sk="native-sketch-1";let line="native-entity-1";let arc="elliptic-guide";let circular="circular-guide";
    m_assert(cad_project_add_primitive(p,sk,"line",cg_v(0,20000000,0),cg_v(30000000,20000000,0)),cg_error);
    let nodes=pc_nodes(cad_project_part(p));
    j_add(nodes,0,j_parse("{\"id\":\"elliptic-guide\",\"type\":\"sketchPrimitive\",\"sketchId\":\"native-sketch-1\",\"primitive\":{\"id\":\"elliptic-guide\",\"type\":\"ellipticArc\",\"center\":{\"x\":0,\"y\":0},\"width\":40,\"height\":10,\"rotation\":30,\"startAngle\":0,\"sweep\":-3.141592653590,\"segments\":64,\"construction\":true}}"));
    j_add(nodes,0,j_parse("{\"id\":\"circular-guide\",\"type\":\"sketchArc\",\"sketchId\":\"native-sketch-1\",\"arc\":{\"id\":\"circular-guide\",\"type\":\"arc\",\"center\":{\"x\":0,\"y\":0},\"radius\":10,\"startAngle\":0,\"sweep\":1.570796326795,\"segments\":64,\"construction\":true}}"));
    let p0=j_parse("{\"entityId\":\"native-entity-1\",\"point\":\"p0\"}");let p1=j_parse("{\"entityId\":\"native-entity-1\",\"point\":\"p1\"}");
    p=cad_project_toggle_midpoint(p,sk,arc,p0);m_assert(p,cg_error);
    midpoint_expect(j_get(midpoint_node(p,line),"p0"),2500000,-4330127,2);
    p=cad_project_toggle_midpoint(p,sk,circular,p1);m_assert(p,cg_error);
    midpoint_expect(j_get(midpoint_node(p,line),"p1"),7071068,7071068,2);
    p=cad_project_set_curve_dimension(p,sk,arc,"height","20 mm");m_assert(p,cg_error);
    midpoint_expect(j_get(midpoint_node(p,line),"p0"),5000000,-8660254,2);
    p=cad_project_set_curve_dimension(p,sk,arc,"arcSweep","-120 deg");m_assert(p,cg_error);
    midpoint_expect(j_get(midpoint_node(p,line),"p0"),12990381,-2500000,2);
    p=cad_project_set_curve_dimension(p,sk,circular,"radius","12 mm");m_assert(p,cg_error);
    p=midpoint_reopen(p);midpoint_expect(j_get(midpoint_node(p,line),"p1"),8485281,8485281,2);
    m_assert(m_eq(j_encode(pc_find(midpoint_relations(p,sk),"native-midpoint-native-entity-1-elliptic-guide")),"{\"id\":\"native-midpoint-native-entity-1-elliptic-guide\",\"type\":\"midpoint\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"p0\"},\"b\":\"elliptic-guide\"}"),"The web line-endpoint anchor reloads without conversion");
    return 1;
}

fn main() {return !(midpoint_line() && midpoint_arcs());}
