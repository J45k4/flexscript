import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-tangent-author.flex";

fn line_tangent_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn line_tangent_rows(project,sk) {return j_get(line_tangent_node(project,sk),"relations");}
fn line_tangent_geometry(project,id) {return pc_curve_geometry(line_tangent_node(project,id));}
fn line_tangent_reopen(source) {
    let report=cad_project_inspect_source(source);m_assert(report,cg_error);
    m_assert(!j_get(report,"readOnly"),j_string(report,"readOnly"));return j_get(report,"document");
}
fn line_tangent_center(project,id,x,y) {
    let xy=pc_uv(j_get(line_tangent_geometry(project,id),"center"));
    return m_assert(pc_line_span(xy,cg_v(x,y,0))<=1,"Circle center follows the supporting line");
}
fn line_tangent_arc_fixture() {
    let p=cad_project_new("Directed line tangent");let sk="native-sketch-1";let line="native-entity-1";let arc="contact-arc";
    m_assert(cad_project_add_primitive(p,sk,"line",cg_v(-20000000,0,0),cg_v(20000000,0,0)),cg_error);
    let nodes=pc_nodes(cad_project_part(p));
    j_add(nodes,0,j_parse("{\"id\":\"contact-arc\",\"type\":\"sketchArc\",\"sketchId\":\"native-sketch-1\",\"arc\":{\"id\":\"contact-arc\",\"type\":\"arc\",\"center\":{\"x\":0,\"y\":20},\"radius\":10,\"startAngle\":-2.356194490192,\"sweep\":1.570796326795,\"segments\":64}}"));
    let clockwise=j_parse(j_encode(p));let geometry=line_tangent_geometry(clockwise,arc);
    cg_j_set(geometry,"startAngle",j_parse("2.356194490192"));cg_j_set(geometry,"sweep",j_parse("-1.570796326795"));
    let opposite=cad_project_toggle_curve_tangent(clockwise,sk,line,arc);m_assert(opposite,cg_error);
    line_tangent_center(opposite,arc,0,-10000000);
    m_assert(m_eq(j_encode(line_tangent_node(opposite,line)),j_encode(line_tangent_node(clockwise,line))),"A clockwise arc chooses the contact side that is within its sweep");
    line_tangent_reopen(j_encode(opposite));
    let standoff=line_tangent_rows(p,sk);
    j_add(standoff,0,j_parse("{\"id\":\"arc-center\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"contact-arc\",\"point\":\"center\"},\"position\":{\"x\":0,\"y\":20}}"));
    let joined=cad_project_toggle_curve_tangent(p,sk,arc,line);m_assert(joined,cg_error);
    line_tangent_center(joined,arc,0,20000000);
    m_assert(pc_line_span(pc_uv(j_get(line_tangent_node(joined,line),"p0")),cg_v(-20000000,10000000,0))<=1,"Reversed authoring moves the line follower");
    joined=cad_project_set_curve_dimension(joined,sk,arc,"radius","12 mm");m_assert(joined,cg_error);
    line_tangent_center(joined,arc,0,20000000);
    m_assert(pc_line_span(pc_uv(j_get(line_tangent_node(joined,line),"p1")),cg_v(20000000,8000000,0))<=1,"Curve source radius moves its line follower");
    joined=line_tangent_reopen(j_encode(joined));
    let saved=j_encode(joined);
    m_assert(!cad_project_set_curve_dimension(joined,sk,arc,"arcSweep","-45 deg") && cg_error,"Clipping the contact from the finite arc fails");
    m_assert(m_eq(j_encode(joined),saved),"Failed contact preserves both entities");
    let malformed=j_parse(saved);cg_j_set(line_tangent_geometry(malformed,arc),"startAngle",j_number(0));
    let inspected=cad_project_inspect_source(j_encode(malformed));
    m_assert(m_eq(j_string(inspected,"readOnly"),"Line tangent contact is outside the finite arc: native-external-tangent-contact-arc-native-entity-1"),"Report the named finite tangent, even when the supporting circle touches");

    let rotated=cad_project_move_line_endpoint(joined,sk,line,"p1",j_parse("{\"x\":25,\"y\":4}"));m_assert(rotated,cg_error);
    rotated=line_tangent_reopen(j_encode(rotated));
    let frame=pct_line_frame(line_tangent_node(rotated,line),pct_shape(line_tangent_node(rotated,arc)));
    m_assert(cg_abs(f64_to_i64_round(load64(frame+16))-12000000)<=200,"Movable line endpoint solves the supporting-line contact");
    return 1;
}

fn main() {
    let sk="tangent-sketch";let line="guide-line";let circle="roller-circle";let imported="imported-guide-tangent";
    let base=line_tangent_reopen(m_read_file("libs/cad/tests/fixtures/line-tangent-circle.pcad"));let original=j_encode(base);
    let report=cad_project_line_sketch(base,sk);m_assert(report,cg_error);
    m_assert(j_integer(report,"degrees_of_freedom")==1 && !j_get(report,"degrees_of_freedom_is_upper_bound"),"One ranked equation leaves contact free along the fixed guide");
    let resized=cad_project_set_circle_dimension(base,sk,circle,"diameter","24 mm");m_assert(resized,cg_error);
    line_tangent_center(resized,circle,0,12000000);
    m_assert(m_eq(j_encode(line_tangent_node(base,line)),j_encode(line_tangent_node(resized,line))),"The driver guides the radius without moving");
    let moved=cad_project_move_point(resized,sk,circle,j_parse("{\"x\":35,\"y\":18}"));m_assert(moved,cg_error);
    moved=line_tangent_reopen(j_encode(moved));line_tangent_center(moved,circle,35000000,12000000);
    m_assert(m_eq(j_encode(pc_find(line_tangent_rows(moved,sk),imported)),j_encode(pc_find(line_tangent_rows(base,sk),imported))),"Imported relation name and operands persist through editing and reopen");
    let solid=cad_project_add_extrusion(moved,sk,1,10000000,"newBody");m_assert(solid,cg_error);
    let mesh=cad_project_mesh(solid);m_assert(j_get(mesh,"closed") && cg_stl(mesh),j_string(mesh,"error"));
    m_assert(m_eq(j_encode(j_get(pc_first(j_get(mesh,"parts")),"bounds")),"[[23.000000,0.000000,0.000000],[47.000000,24.000000,10.000000]]"),"Contact beyond the guide endpoint exports on its supporting line");
    let stale=j_parse(j_encode(solid));pc_line_write_xy(j_get(line_tangent_geometry(stale,circle),"center"),cg_v(35000000,13000000,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved line tangent disagrees with geometry: imported-guide-tangent"),"Manufacturing rejects stale imported contact");

    let free=cad_project_toggle_curve_tangent(base,sk,circle,line);m_assert(free,cg_error);
    m_assert(!pc_find(line_tangent_rows(free,sk),imported),"Removing a tangent works with opposite pick order");
    free=cad_project_move_point(free,sk,circle,j_parse("{\"x\":0,\"y\":20}"));m_assert(free,cg_error);
    let authored=cad_project_toggle_curve_tangent(free,sk,line,circle);m_assert(authored,cg_error);
    line_tangent_center(authored,circle,0,10000000);
    let row=pc_find(line_tangent_rows(authored,sk),"native-external-tangent-guide-line-roller-circle");
    m_assert(m_eq(j_string(row,"type"),"tangent") && m_eq(j_string(row,"a"),line) && m_eq(j_string(row,"b"),circle),"Writer retains the v4 relation and operand IDs");
    j_add(line_tangent_rows(free,sk),0,j_parse("{\"id\":\"roller-lock\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"roller-circle\",\"point\":\"center\"},\"position\":{\"x\":0,\"y\":20}}"));
    let blocked=j_encode(free);
    m_assert(!cad_project_toggle_curve_tangent(free,sk,line,circle) && cg_error,"An incompatible fixed circle rejects the tangent");
    m_assert(m_eq(j_encode(free),blocked) && m_eq(j_encode(base),original),"Rejection and authoring do not mutate the inputs");
    return !line_tangent_arc_fixture();
}
