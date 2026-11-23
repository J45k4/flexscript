import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-tangent-author.flex";

fn ellipse_tangent_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn ellipse_tangent_geometry(project,id) {return pc_curve_geometry(ellipse_tangent_node(project,id));}
fn ellipse_tangent_rows(project,id) {return j_get(ellipse_tangent_node(project,id),"relations");}
fn ellipse_tangent_expect(row,x,y) {
    return m_assert(pc_line_span(pc_uv(row),cg_v(x,y,0))<=2,"Position follows the analytic elliptic support");
}
fn ellipse_tangent_reopen(source) {
    let inspected=cad_project_inspect_source(source);m_assert(inspected,cg_error);
    m_assert(!j_get(inspected,"readOnly"),j_string(inspected,"readOnly"));return j_get(inspected,"document");
}
fn ellipse_tangent_closed() {
    let sk="tangent-sketch";let guide="guide-line";let roller="roller-ellipse";let imported="tangent-imported-from-web";
    let project=ellipse_tangent_reopen(m_read_file("libs/cad/tests/fixtures/line-tangent-ellipse.pcad"));let saved=j_encode(project);
    let report=cad_project_line_sketch(project,sk);m_assert(report,cg_error);
    m_assert(j_integer(report,"degrees_of_freedom")==1 && !j_get(report,"degrees_of_freedom_is_upper_bound"),"Driven axes and rotation leave one sliding degree of freedom");
    let wider=cad_project_set_curve_dimension(project,sk,roller,"width","48 mm");m_assert(wider,cg_error);
    ellipse_tangent_expect(j_get(ellipse_tangent_geometry(wider,roller),"center"),0,14798649);
    m_assert(m_eq(j_encode(ellipse_tangent_node(wider,guide)),j_encode(ellipse_tangent_node(project,guide))),"Width edit preserves the fixed guide");
    let bound=cad_project_edit_line_variable(wider,sk,"","turn","30 deg");m_assert(bound,cg_error);
    bound=cad_project_set_curve_dimension(bound,sk,roller,"rotation","#turn");m_assert(bound,cg_error);
    let turned=cad_project_edit_line_variable(bound,sk,"turn","turn","45 deg");m_assert(turned,cg_error);
    ellipse_tangent_expect(j_get(ellipse_tangent_geometry(turned,roller),"center"),0,18384776);
    turned=ellipse_tangent_reopen(j_encode(turned));
    let row=pc_find(ellipse_tangent_rows(turned,sk),imported);
    m_assert(m_eq(j_encode(row),j_encode(pc_find(ellipse_tangent_rows(project,sk),imported))),"The existing v4 tangent keeps its original ID and two operands");
    let loose=cad_project_toggle_curve_reference(turned,sk,roller,"rotation");m_assert(loose,cg_error);
    m_assert(j_value(j_get(cad_project_line_sketch(loose,sk),"degrees_of_freedom_is_upper_bound")),"Reference orientation changes the mobility estimate");
    let after=cad_project_add_extrusion(turned,sk,1,10000000,"newBody");m_assert(after,cg_error);
    let mesh=cad_project_mesh(after);m_assert(mesh && j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let stale=j_parse(j_encode(after));pc_line_write_xy(j_get(ellipse_tangent_geometry(stale,roller),"center"),cg_v(0,19000000,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved line tangent disagrees with geometry: tangent-imported-from-web"),"Manufacturing validates the same imported contact");

    let unlinked=cad_project_toggle_curve_tangent(project,sk,roller,guide);m_assert(unlinked,cg_error);
    m_assert(!pc_find(ellipse_tangent_rows(unlinked,sk),imported),"Removal works in reverse pick order");
    unlinked=cad_project_move_point(unlinked,sk,roller,j_parse("{\"x\":0,\"y\":30}"));m_assert(unlinked,cg_error);
    let linked=cad_project_toggle_curve_tangent(unlinked,sk,guide,roller);m_assert(linked,cg_error);
    ellipse_tangent_expect(j_get(ellipse_tangent_geometry(linked,roller),"center"),0,13228757);
    let expected="{\"id\":\"native-external-tangent-guide-line-roller-ellipse\",\"type\":\"tangent\",\"a\":\"guide-line\",\"b\":\"roller-ellipse\"}";
    m_assert(m_eq(j_encode(pc_find(ellipse_tangent_rows(linked,sk),"native-external-tangent-guide-line-roller-ellipse")),expected),"Authoring uses the standard tangent record");
    j_add(ellipse_tangent_rows(unlinked,sk),0,j_parse("{\"id\":\"lock-roller\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"roller-ellipse\",\"point\":\"center\"},\"position\":{\"x\":0,\"y\":30}}"));
    let before=j_encode(unlinked);
    m_assert(!cad_project_toggle_curve_tangent(unlinked,sk,guide,roller) && cg_error,"An incompatible fixed center rejects contact");
    m_assert(m_eq(j_encode(unlinked),before) && m_eq(j_encode(project),saved),"Contact authoring and rejection preserve the original graph");
    return 1;
}

fn ellipse_tangent_finite() {
    let p=cad_project_new("Clockwise elliptic tangent");let sk="native-sketch-1";let line="native-entity-1";let arc="upper-contact-arc";
    m_assert(cad_project_add_primitive(p,sk,"line",cg_v(-40000000,-15000000,0),cg_v(40000000,-15000000,0)),cg_error);
    j_add(pc_nodes(cad_project_part(p)),0,j_parse("{\"id\":\"upper-contact-arc\",\"type\":\"sketchPrimitive\",\"sketchId\":\"native-sketch-1\",\"primitive\":{\"id\":\"upper-contact-arc\",\"type\":\"ellipticArc\",\"center\":{\"x\":0,\"y\":0},\"width\":40,\"height\":20,\"rotation\":30,\"startAngle\":0.8,\"sweep\":-0.16,\"segments\":128}}"));
    let relations=ellipse_tangent_rows(p,sk);
    j_add(relations,0,j_parse("{\"id\":\"arc-center\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"upper-contact-arc\",\"point\":\"center\"},\"position\":{\"x\":0,\"y\":0}}"));
    j_add(relations,0,j_parse("{\"id\":\"rail-level\",\"type\":\"horizontal\",\"entityId\":\"native-entity-1\"}"));
    let joined=cad_project_toggle_curve_tangent(p,sk,arc,line);m_assert(joined,cg_error);
    ellipse_tangent_expect(j_get(ellipse_tangent_node(joined,line),"p0"),-40000000,13228757);
    m_assert(m_eq(j_encode(ellipse_tangent_geometry(joined,arc)),j_encode(ellipse_tangent_geometry(p,arc))),"Reversed authoring finds the opposite visible support while holding the arc");
    let larger=cad_project_set_curve_dimension(joined,sk,arc,"width","42 mm");m_assert(larger,cg_error);
    ellipse_tangent_expect(j_get(ellipse_tangent_node(larger,line),"p1"),40000000,13610658);
    larger=ellipse_tangent_reopen(j_encode(larger));let saved=j_encode(larger);
    m_assert(!cad_project_set_curve_dimension(larger,sk,arc,"arcSweep","-1 deg") && cg_error,"The visible arc cannot lose the tangent contact");
    m_assert(m_eq(j_encode(larger),saved),"The rejected finite sweep edit is atomic");
    let stale=j_parse(saved);cg_j_set(ellipse_tangent_geometry(stale,arc),"startAngle",j_number(0));
    let inspected=cad_project_inspect_source(j_encode(stale));
    m_assert(m_eq(j_string(inspected,"readOnly"),"Line tangent contact is outside the finite arc: native-external-tangent-upper-contact-arc-native-entity-1"),"The validator uses the ellipse parameter and reports the named relation");

    relations=ellipse_tangent_rows(larger,sk);pc_line_unlink(relations,pc_find(relations,"rail-level"),"");
    let edited=cad_project_move_line_endpoint(larger,sk,line,"p1",j_parse("{\"x\":42,\"y\":12.5}"));m_assert(edited,cg_error);
    edited=ellipse_tangent_reopen(j_encode(edited));
    let straight=ellipse_tangent_node(edited,line);let frame=pct_line_frame(straight,pct_shape(ellipse_tangent_node(edited,arc)));
    m_assert(pc_line_span(pc_uv(j_get(straight,"p0")),pc_uv(j_get(ellipse_tangent_node(larger,line),"p0")))<=1,"The opposite endpoint stays pinned");
    m_assert(cg_abs(f64_to_i64_round(f64_sub(f64_magnitude(load64(frame+16)),load64(frame+24))))<=200,"A free line endpoint solves the direction-dependent support");
    return 1;
}

fn main() {return !(ellipse_tangent_closed() && ellipse_tangent_finite());}
