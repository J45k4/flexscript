import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-point-on-curve-author.flex";

fn poc_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn poc_center(project,id) {return j_get(pc_curve_geometry(poc_node(project,id)),"center");}
fn poc_relations(project,sk) {return j_get(poc_node(project,sk),"relations");}
fn poc_expect(row,x,y) {m_assert(pc_line_span(pc_uv(row),cg_v(x,y,0))<=1,"The follower lies on the curve");return 1;}
fn poc_reopen(source) {
    let inspected=cad_project_inspect_source(source);m_assert(inspected,cg_error);
    m_assert(!j_get(inspected,"readOnly"),j_string(inspected,"readOnly"));return j_get(inspected,"document");
}
fn poc_mobility(project,sk) {
    let report=cad_project_line_sketch(project,sk);m_assert(report,cg_error);
    return m_assert(j_integer(report,"degrees_of_freedom")==1 && !j_get(report,"degrees_of_freedom_is_upper_bound"),"A point can slide on its fixed curve");
}

fn poc_circle() {
    let sk="native-sketch-1";let rim="rim";let probe="probe";let id="ring-contact-from-web";
    let base=poc_reopen(m_read_file("libs/cad/tests/fixtures/point-on-circle.pcad"));let saved=j_encode(base);
    poc_mobility(base,sk);
    let solid=cad_project_add_extrusion(base,sk,1,10000000,"newBody");m_assert(solid,cg_error);
    let edited=cad_project_set_circle_dimension(solid,sk,rim,"diameter","50 mm");m_assert(edited,cg_error);
    poc_expect(poc_center(edited,rim),0,0);poc_expect(poc_center(edited,probe),25000000,0);
    let dragged=cad_project_move_point(edited,sk,probe,j_parse("{\"x\":0,\"y\":-30}"));m_assert(dragged,cg_error);
    dragged=poc_reopen(j_encode(dragged));poc_expect(poc_center(dragged,probe),0,-25000000);poc_mobility(dragged,sk);
    m_assert(m_eq(j_encode(pc_find(poc_relations(dragged,sk),id)),j_encode(pc_find(poc_relations(base,sk),id))),"Reopen preserves the original relation ID and operands");
    let mesh=cad_project_mesh(dragged);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    m_assert(m_eq(j_encode(j_get(pc_first(j_get(mesh,"parts")),"bounds")),"[[-25.000000,-25.000000,0.000000],[25.000000,25.000000,10.000000]]"),"The edited radius rebuilds the dependent solid");
    let stale=j_parse(j_encode(dragged));pc_line_write_xy(poc_center(stale,probe),cg_v(0,-26000000,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved point is outside its curve: ring-contact-from-web"),"Manufacturing rejects stale source contact");

    let parametric=cad_project_edit_line_variable(dragged,sk,"","size","50 mm");m_assert(parametric,cg_error);
    parametric=cad_project_set_circle_dimension(parametric,sk,rim,"diameter","#size");m_assert(parametric,cg_error);
    parametric=cad_project_edit_line_variable(parametric,sk,"size","size","60 mm");m_assert(parametric,cg_error);
    poc_expect(poc_center(parametric,probe),0,-30000000);

    let unlocked=j_parse(saved);let rows=poc_relations(unlocked,sk);
    pc_line_unlink(rows,pc_find(rows,"ring-origin"),"");
    let shifted=cad_project_move_point(unlocked,sk,rim,j_parse("{\"x\":10,\"y\":5}"));m_assert(shifted,cg_error);
    poc_expect(poc_center(shifted,rim),10000000,5000000);
    let slid=cad_project_move_point(shifted,sk,probe,j_parse("{\"x\":10,\"y\":30}"));m_assert(slid,cg_error);
    poc_expect(poc_center(slid,rim),10000000,5000000);poc_expect(poc_center(slid,probe),10000000,25000000);

    let anchor=j_parse("{\"entityId\":\"probe\",\"point\":\"center\"}");
    let free=cad_project_toggle_point_on_curve(base,sk,rim,anchor);m_assert(free,cg_error);
    m_assert(!pc_find(poc_relations(free,sk),id),"Toggle removes an existing imported relation");
    free=cad_project_move_point(free,sk,probe,j_parse("{\"x\":0,\"y\":0}"));m_assert(free,cg_error);
    let projected=cad_project_toggle_point_on_curve(free,sk,rim,anchor);m_assert(projected,cg_error);
    poc_expect(poc_center(projected,probe),20000000,0);
    m_assert(m_eq(j_encode(pc_find(poc_relations(projected,sk),"native-point-on-curve-probe-rim")),"{\"id\":\"native-point-on-curve-probe-rim\",\"type\":\"pointOnCurve\",\"a\":{\"entityId\":\"probe\",\"point\":\"center\"},\"b\":\"rim\"}"),"Authoring saves the same v4 representation");
    j_add(poc_relations(free,sk),0,j_parse("{\"id\":\"probe-fixed\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"probe\",\"point\":\"center\"},\"position\":{\"x\":0,\"y\":0}}"));
    let before=j_encode(free);
    m_assert(!cad_project_toggle_point_on_curve(free,sk,rim,anchor) && cg_error,"An incompatible fixed probe rejects contact");
    m_assert(m_eq(j_encode(free),before) && m_eq(j_encode(base),saved),"Accepted and rejected edits preserve their inputs");
    return 1;
}

fn poc_line() {
    let project=cad_project_new("Finite guide contact");let sk="native-sketch-1";let line="native-entity-1";let probe="guide-probe";
    m_assert(cad_project_add_primitive(project,sk,"line",cg_v(0,0,0),cg_v(20000000,0,0)),cg_error);
    j_add(pc_nodes(cad_project_part(project)),0,j_parse("{\"id\":\"guide-probe\",\"type\":\"sketchPrimitive\",\"sketchId\":\"native-sketch-1\",\"primitive\":{\"id\":\"guide-probe\",\"type\":\"point\",\"center\":{\"x\":8,\"y\":4},\"construction\":true}}"));
    let rows=poc_relations(project,sk);
    j_add(rows,0,j_parse("{\"id\":\"guide-start\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"p0\"},\"position\":{\"x\":0,\"y\":0}}"));
    j_add(rows,0,j_parse("{\"id\":\"guide-horizontal\",\"type\":\"horizontal\",\"entityId\":\"native-entity-1\"}"));
    j_add(rows,0,j_parse("{\"id\":\"guide-length\",\"type\":\"length\",\"entityId\":\"native-entity-1\",\"value\":20}"));
    let anchor=j_parse("{\"entityId\":\"guide-probe\",\"point\":\"center\"}");
    let linked=cad_project_toggle_point_on_curve(project,sk,line,anchor);m_assert(linked,cg_error);
    poc_expect(poc_center(linked,probe),8000000,0);poc_mobility(linked,sk);
    let end=cad_project_move_point(linked,sk,probe,j_parse("{\"x\":30,\"y\":4}"));m_assert(end,cg_error);
    poc_expect(poc_center(end,probe),20000000,0);poc_mobility(end,sk);
    let start=cad_project_move_point(end,sk,probe,j_parse("{\"x\":-6,\"y\":-3}"));m_assert(start,cg_error);
    poc_expect(poc_center(start,probe),0,0);poc_mobility(start,sk);
    let interior=cad_project_move_point(start,sk,probe,j_parse("{\"x\":18,\"y\":3}"));m_assert(interior,cg_error);
    poc_expect(poc_center(interior,probe),18000000,0);
    let shorter=cad_project_set_line_length(interior,sk,line,12000000);m_assert(shorter,cg_error);
    shorter=poc_reopen(j_encode(shorter));poc_expect(j_get(poc_node(shorter,line),"p1"),12000000,0);
    poc_expect(poc_center(shorter,probe),12000000,0);
    let malformed=j_parse(j_encode(shorter));pc_line_write_xy(poc_center(malformed,probe),cg_v(16000000,0,0));
    let inspected=cad_project_inspect_source(j_encode(malformed));
    m_assert(m_eq(j_string(inspected,"readOnly"),"Saved point is outside its curve: native-point-on-curve-guide-probe-native-entity-1"),"The saved infinite supporting line cannot substitute for the finite guide");
    return 1;
}

fn main() {return !(poc_circle() && poc_line());}
