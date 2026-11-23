import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-concentric.flex";

fn coaxial_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn coaxial_shape(project,id) {return pc_curve_geometry(coaxial_node(project,id));}
fn coaxial_center(project,id) {return pc_uv(j_get(coaxial_shape(project,id),"center"));}
fn coaxial_rows(project,sk) {return j_get(coaxial_node(project,sk),"relations");}
fn coaxial_open(source) {
    let report=cad_project_inspect_source(source);m_assert(report,cg_error);
    m_assert(!j_get(report,"readOnly"),j_string(report,"readOnly"));return j_get(report,"document");
}
fn coaxial_centers(project,a,b,x,y) {
    let at=cg_v(x,y,0);
    m_assert(!pc_line_span(coaxial_center(project,a),at) && !pc_line_span(coaxial_center(project,b),at),"Both curves retain the common center");
    return 1;
}
fn coaxial_check_form(project,outer,inner,height) {
    m_assert(pc_circle_measure(coaxial_node(project,outer),"diameter")==30000000,"Diameter remains independent");
    let oval=coaxial_node(project,inner);
    m_assert(pc_circle_measure(oval,"width")==12000000 && pc_circle_measure(oval,"height")==height,"Ellipse axes remain independent");
    m_assert(pc_circle_measure(oval,"rotation")==30000000,"Ellipse rotation is preserved");
    return 1;
}

fn coaxial_arc_test() {
    let p=cad_project_new("Concentric finite arcs");let sk="native-sketch-1";let a="circular";let b="elliptic";
    let nodes=pc_nodes(cad_project_part(p));
    j_add(nodes,0,j_parse("{\"id\":\"circular\",\"type\":\"sketchArc\",\"sketchId\":\"native-sketch-1\",\"arc\":{\"id\":\"circular\",\"type\":\"arc\",\"center\":{\"x\":5,\"y\":2},\"radius\":6,\"startAngle\":0,\"sweep\":-1.570796326795,\"segments\":64}}"));
    j_add(nodes,0,j_parse("{\"id\":\"elliptic\",\"type\":\"sketchPrimitive\",\"sketchId\":\"native-sketch-1\",\"primitive\":{\"id\":\"elliptic\",\"type\":\"ellipticArc\",\"center\":{\"x\":12,\"y\":5},\"width\":18,\"height\":8,\"rotation\":15,\"startAngle\":1.0,\"sweep\":-1.2,\"segments\":64}}"));
    let shared=cad_project_toggle_concentric(p,sk,a,b);m_assert(shared,cg_error);
    coaxial_centers(shared,a,b,5000000,2000000);
    shared=cad_project_move_point(shared,sk,b,j_parse("{\"x\":7,\"y\":-3}"));m_assert(shared,cg_error);
    shared=coaxial_open(j_encode(shared));coaxial_centers(shared,a,b,7000000,-3000000);
    let arc=coaxial_node(shared,a);let ellipse=coaxial_node(shared,b);
    m_assert(pc_circle_measure(arc,"arcSweep")==-90000000 && pc_circle_measure(arc,"radius")==6000000,"Circular arc keeps signed sweep and radius");
    m_assert(m_eq(j_value(j_get(pc_curve_geometry(ellipse),"sweep")),"-1.2") && pc_circle_measure(ellipse,"rotation")==15000000 && pc_circle_measure(ellipse,"width")==18000000,"Elliptic arc keeps its shape and interval");
    return 1;
}

fn main() {
    let sk="seat-sketch";let outer="outer-bore";let inner="ellipse-seat";let imported="imported-coaxial-seat";
    let base=coaxial_open(m_read_file("libs/cad/tests/fixtures/concentric.pcad"));let original=j_encode(base);
    let relation=j_encode(pc_find(coaxial_rows(base,sk),imported));
    let initial=cad_project_line_sketch(base,sk);m_assert(initial,cg_error);
    m_assert(j_integer(initial,"degrees_of_freedom")==1,"The named relation and dimensions leave only center height free");

    let translated=cad_project_set_distance_expression(base,sk,"station-center-x","1.6 cm");m_assert(translated,cg_error);
    translated=coaxial_open(j_encode(translated));coaxial_centers(translated,outer,inner,16000000,0);
    coaxial_check_form(translated,outer,inner,6000000);
    m_assert(m_eq(j_encode(pc_find(coaxial_rows(translated,sk),imported)),relation),"Preserve imported relation ID and curve IDs");
    let offset=pc_find(coaxial_rows(translated,sk),"station-center-x");
    m_assert(m_eq(j_string(offset,"expression"),"1.6 cm") && pc_pose_number(j_get(offset,"value"))==16000000,"Datum expression survives reopening");
    let moved=cad_project_move_point(translated,sk,inner,j_parse("{\"x\":16,\"y\":-5}"));m_assert(moved,cg_error);
    coaxial_centers(moved,outer,inner,16000000,-5000000);coaxial_check_form(moved,outer,inner,6000000);

    let solid=cad_project_add_extrusion(translated,sk,1,10000000,"newBody");m_assert(solid,cg_error);
    let mesh=cad_project_mesh(solid);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let bounds=j_get(pc_first(j_get(mesh,"parts")),"bounds");
    m_assert(m_eq(j_encode(bounds),"[[1.000000,-15.000000,0.000000],[31.000000,15.000000,10.000000]]"),"Extrusion follows shared datum center");
    let resized=cad_project_set_curve_dimension(solid,sk,inner,"height","8 mm");m_assert(resized,cg_error);
    coaxial_check_form(resized,outer,inner,8000000);coaxial_centers(resized,outer,inner,16000000,0);

    let malformed=j_parse(j_encode(solid));cg_j_text(pc_find(coaxial_rows(malformed,sk),imported),"b","missing-seat");
    let issue=cad_project_inspect_source(j_encode(malformed));
    m_assert(m_eq(j_string(issue,"readOnly"),"Invalid concentric relation: imported-coaxial-seat"),"Reader names the bad imported relation");
    m_assert(m_eq(j_string(cad_project_mesh(malformed),"error"),"Invalid concentric relation: imported-coaxial-seat"),"Export names the bad imported relation");
    let stale=j_parse(j_encode(solid));pc_line_write_xy(j_get(coaxial_shape(stale,inner),"center"),cg_v(17000000,0,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved concentric relation disagrees with centers: imported-coaxial-seat"),"Reject stale saved centers at export");

    let separate=cad_project_toggle_concentric(base,sk,inner,outer);m_assert(separate,cg_error);
    m_assert(!pc_find(coaxial_rows(separate,sk),imported),"Toggle removes the named pair");
    separate=cad_project_move_point(separate,sk,inner,j_parse("{\"x\":13,\"y\":2}"));m_assert(separate,cg_error);
    let authored=cad_project_toggle_concentric(separate,sk,outer,inner);m_assert(authored,cg_error);
    authored=coaxial_open(j_encode(authored));coaxial_centers(authored,outer,inner,10000000,0);
    m_assert(pc_find(coaxial_rows(authored,sk),"native-concentric-outer-bore-ellipse-seat"),"Writer uses canonical v4 relation");
    m_assert(m_eq(j_encode(base),original),"All edits leave the input drawing untouched");

    let rows=coaxial_rows(separate,sk);
    j_add(rows,0,j_parse("{\"id\":\"fixed-outer\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"outer-bore\",\"point\":\"center\"},\"position\":{\"x\":10,\"y\":0}}"));
    j_add(rows,0,j_parse("{\"id\":\"fixed-seat\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"ellipse-seat\",\"point\":\"center\"},\"position\":{\"x\":13,\"y\":2}}"));
    let conflict=j_encode(separate);
    m_assert(!cad_project_toggle_concentric(separate,sk,outer,inner) && cg_error,"Concentric cannot combine distinct fixed centers");
    m_assert(m_eq(j_encode(separate),conflict),"Failed addition leaves constraints and centers intact");
    return !coaxial_arc_test();
}
