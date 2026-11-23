import "cad/project-mirror-author.flex";
import "cad/project-access.flex";
fn pos(p,id,field) {
    let node=pc_find(pc_nodes(cad_project_part(p)),id);
    if m_eq(field,"center") {node=pc_curve_geometry(node);}return pc_uv(j_get(node,field));
}
fn near(p,x,y) {return cg_abs(load64(p)-x*1000000)<500 && cg_abs(load64(p+8)-y*1000000)<500;}
fn main() {
    let p=cad_project_open(m_read_file("libs/cad/tests/fixtures/mirror-symmetry.pcad"));let sk="native-sketch-1";
    let axis="native-entity-1";let left="native-entity-2";let right="native-entity-3";let dot="native-entity-4";let line="native-entity-5";
    let report=cad_project_line_sketch(p,sk);m_assert(report,cg_error);
    m_assert(j_integer(report,"degrees_of_freedom")==11,"Mirror and symmetry remove five of sixteen degrees of freedom");
    p=cad_project_move_point(p,sk,left,j_parse("{\"x\":35,\"y\":13}"));m_assert(p,cg_error);
    m_assert(near(pos(p,right,"center"),-35,13) && near(pos(p,axis,"p0"),0,-60),"Copy follows source");
    p=cad_project_move_point(p,sk,right,j_parse("{\"x\":-40,\"y\":15}"));m_assert(p,cg_error);
    m_assert(near(pos(p,left,"center"),40,15),"Source follows copy");
    p=cad_project_move_line_endpoint(p,sk,line,"p0",j_parse("{\"x\":-23,\"y\":-26}"));m_assert(p,cg_error);
    m_assert(near(pos(p,dot,"center"),23,-26) && near(pos(p,line,"p1"),-40,-45),"Point follows reflected endpoint");
    p=cad_project_move_line_endpoint(p,sk,axis,"p1",j_parse("{\"x\":120,\"y\":60}"));m_assert(p,cg_error);
    m_assert(near(pos(p,axis,"p1"),120,60) && near(pos(p,left,"center"),40,15) && near(pos(p,right,"center"),75,-20),"Changing axis preserves source");
    p=cad_project_edit_line_variable(p,sk,"","bore","12 mm");m_assert(p,cg_error);
    p=cad_project_set_circle_dimension(p,sk,right,"radius","#bore + 2 mm");m_assert(p,cg_error);
    p=cad_project_toggle_circle_reference(p,sk,left,"diameter");m_assert(p,cg_error);
    p=cad_project_edit_line_variable(p,sk,"bore","bore","14 mm");m_assert(p,cg_error);
    report=cad_project_line_sketch(p,sk);m_assert(j_integer(report,"degrees_of_freedom")==10,"Mirror group has a single driving radius");
    let nodes=pc_nodes(cad_project_part(p));m_assert(pc_circle_measure(pc_find(nodes,left),"radius")==16000000,"Mirrored radius follows variable");
    let r=pc_circle_relation(pc_line_records(nodes,pc_find(nodes,sk)),left,"diameter");
    m_assert(pc_pose_number(j_get(r,"value"))==32000000 && j_value(j_get(r,"reference")),"Reference on opposite circle follows");
    let bad=cad_project_set_circle_dimension(p,sk,left,"radius","20");m_assert(!bad,"Opposing driver rejects incompatible edit");
    let fresh=cad_project_new("Links");let src=cad_project_add_primitive(fresh,sk,"line",cg_v(20000000,0,0),cg_v(20000000,20000000,0));
    let construction=cad_project_add_primitive(fresh,sk,"line",cg_v(0,0,0),cg_v(0,50000000,0));
    cg_j_set(construction,"construction",j_new(5,1));let axis_id=j_string(construction,"id");
    let saved=j_encode(fresh);fresh=cad_project_mirror_entity(fresh,sk,j_string(src,"id"),axis_id);m_assert(fresh,cg_error);
    m_assert(near(pos(fresh,"native-entity-3","p1"),-20,20),"Reflected both endpoints");
    fresh=cad_project_move_line_endpoint(fresh,sk,"native-entity-3","p1",j_parse("{\"x\":-24,\"y\":25}"));m_assert(fresh,cg_error);
    m_assert(near(pos(fresh,"native-entity-1","p1"),24,25),"Source line follows copy endpoint");
    fresh=j_parse(saved);let point=cad_project_add_primitive(fresh,sk,"point",cg_v(-30000000,0,0),0);
    let anchor=j_parse("{\"entityId\":\"native-entity-1\",\"point\":\"p1\"}");
    let other=j_parse("{\"entityId\":\"native-entity-3\",\"point\":\"center\"}");
    fresh=cad_project_toggle_point_symmetry(fresh,sk,anchor,other,axis_id);m_assert(fresh,cg_error);
    m_assert(near(pos(fresh,j_string(point,"id"),"center"),-20,20),"Creates reflected point pair");
    fresh=cad_project_toggle_point_symmetry(fresh,sk,other,anchor,axis_id);m_assert(fresh,cg_error);
    m_assert(!pc_first(j_get(pc_find(pc_nodes(cad_project_part(fresh)),sk),"relations")),"Same pair toggles off");
    let edge=cad_project_new("At the edge");
    let boundary=cad_project_add_primitive(edge,sk,"line",cg_v(480000000,0,0),cg_v(480000000,50000000,0));
    let disk=cad_project_add_primitive(edge,sk,"circle",cg_v(465000000,20000000,0),cg_v(485000000,20000000,0));
    let original=j_encode(edge);
    m_assert(!cad_project_mirror_entity(edge,sk,j_string(disk,"id"),j_string(boundary,"id")),"Reject an out-of-bounds reflected rim even before extrusion");
    m_assert(m_eq(j_encode(edge),original),"Out-of-range copy does not append a node or relation");
    return 0;
}
