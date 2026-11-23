import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-line-directions.flex";

fn direction_rows(p,sk) {
    let sketch=pc_find(pc_nodes(cad_project_part(p)),sk);let rows=j_get(sketch,"relations");
    if !rows {rows=j_array();j_add(sketch,"relations",rows);}return rows;
}
fn direction_node(p,id) {return pc_find(pc_nodes(cad_project_part(p)),id);}
fn direction_point(p,id,end) {return pc_uv(j_get(direction_node(p,id),end));}
fn direction_reopen(p) {
    let report=cad_project_inspect_source(j_encode(p));m_assert(report,cg_error);
    m_assert(!j_get(report,"readOnly"),j_string(report,"readOnly"));return j_get(report,"document");
}
fn main() {
    let p=cad_project_new("Right triangle");let sk="native-sketch-1";
    let a="native-entity-1";let b="native-entity-2";let key="native-perpendicular-native-entity-1-native-entity-2";
    m_assert(cad_project_add_primitive(p,sk,"line",cg_v(0,0,0),cg_v(20000000,0,0)),cg_error);
    m_assert(cad_project_add_primitive(p,sk,"line",cg_v(20000000,0,0),cg_v(26000000,8000000,0)),cg_error);
    let rows=direction_rows(p,sk);
    j_add(rows,0,j_parse("{\"id\":\"keep-start\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"p0\"},\"position\":{\"x\":0,\"y\":0}}"));
    j_add(rows,0,j_parse("{\"id\":\"keep-corner\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"position\":{\"x\":20,\"y\":0}}"));
    j_add(rows,0,j_parse("{\"id\":\"corner\",\"type\":\"coincident\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"b\":{\"entityId\":\"native-entity-2\",\"point\":\"p0\"}}"));
    p=cad_project_set_line_expression(p,sk,b,"10 mm");m_assert(p,cg_error);
    let original=j_encode(p);
    let right=cad_project_toggle_line_direction(p,sk,a,b,"perpendicular");m_assert(right,cg_error);
    m_assert(m_eq(j_encode(p),original),"Authoring direction preserves the previous document");
    m_assert(pc_line_span(direction_point(right,b,"p1"),cg_v(20000000,10000000,0))==0,"Perpendicular keeps the corner and driving length");
    let rel=pc_find(direction_rows(right,sk),key);
    m_assert(m_eq(j_string(rel,"a"),a) && m_eq(j_string(rel,"b"),b),"Direction stores original stable entity IDs");
    let report=cad_project_line_sketch(right,sk);m_assert(report,cg_error);
    m_assert(j_integer(report,"degrees_of_freedom")==0,"Fixed source, coincidence, length and perpendicular close the remaining freedom");
    right=direction_reopen(right);
    right=cad_project_set_line_expression(right,sk,b,"15 mm");m_assert(right,cg_error);
    m_assert(pc_line_span(direction_point(right,b,"p1"),cg_v(20000000,15000000,0))==0,"Driving length changes the perpendicular line to 15 mm");
    right=direction_reopen(right);

    let blocked=j_parse(original);rows=direction_rows(blocked,sk);
    j_add(rows,0,j_parse("{\"id\":\"lock-follower\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-2\",\"point\":\"p1\"},\"position\":{\"x\":26,\"y\":8}}"));
    let locked=j_encode(blocked);
    m_assert(!cad_project_toggle_line_direction(blocked,sk,a,b,"perpendicular") && cg_error,"Perpendicular conflicts with fixed off-axis follower");
    m_assert(m_eq(j_encode(blocked),locked),"Conflicting addition preserves the original");
    let removed=cad_project_toggle_line_direction(right,sk,a,b,"perpendicular");m_assert(removed,cg_error);
    m_assert(!pc_find(direction_rows(removed,sk),key) && pc_find(direction_rows(removed,sk),"corner"),"Toggle removes the direction alone");

    m_assert(cad_project_add_primitive(right,sk,"line",direction_point(right,b,"p1"),direction_point(right,a,"p0")),cg_error);
    let finished=cad_project_add_extrusion(right,sk,1,10000000,"newBody");m_assert(finished,cg_error);
    let mesh=cad_project_mesh(finished);m_assert(j_value(j_get(mesh,"closed")) && !j_get(mesh,"error"),j_string(mesh,"error"));
    let part=pc_first(j_get(mesh,"parts"));let volume=pc_serial_number(j_get(part,"volume_mm3"),6,1000000,1000000);
    m_assert(cg_abs(volume-1500000000)<=1000 && cg_stl(mesh),"The 20 by 15 mm right triangle exports as a 1500 mm³ prism");
    let changed=j_encode(finished);
    m_assert(!cad_project_set_line_expression(finished,sk,b,"16 mm") && cg_error,"Edit cannot detach the chord of an active extrusion");
    m_assert(m_eq(j_encode(finished),changed),"Failed rebuild preserves the saved solid");
    let stale=j_parse(changed);let damaged=j_get(direction_node(stale,b),"p1");
    pc_line_write_xy(damaged,cg_v(29000000,12000000,0));
    m_assert(j_get(cad_project_inspect_source(j_encode(stale)),"readOnly"),"Open rejects geometry inconsistent with the direction");
    m_assert(j_get(cad_project_mesh(stale),"error"),"Manufacturing also rejects stale direction geometry");

    let parallel=cad_project_new("Reverse direction");
    m_assert(cad_project_add_primitive(parallel,sk,"line",cg_v(0,0,0),cg_v(20000000,0,0)),cg_error);
    m_assert(cad_project_add_primitive(parallel,sk,"line",cg_v(10000000,30000000,0),cg_v(4000000,38000000,0)),cg_error);
    parallel=cad_project_toggle_line_direction(parallel,sk,a,b,"parallel");m_assert(parallel,cg_error);
    m_assert(pc_line_span(direction_point(parallel,a,"p1"),cg_v(20000000,0,0))==0,"Creation preserves a free source line");
    m_assert(pc_line_span(direction_point(parallel,b,"p1"),cg_v(0,30000000,0))==0,"The nearest parallel orientation can be reversed");
    direction_reopen(parallel);
    return 0;
}
