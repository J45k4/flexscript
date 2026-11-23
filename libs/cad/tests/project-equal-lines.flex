import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-line-directions.flex";

fn equal_node(p,id) {return pc_find(pc_nodes(cad_project_part(p)),id);}
fn equal_point(p,id,end) {return pc_uv(j_get(equal_node(p,id),end));}
fn equal_rows(p,sk) {return j_get(equal_node(p,sk),"relations");}
fn equal_reopen(text) {
    let report=cad_project_inspect_source(text);m_assert(report,cg_error);
    m_assert(!j_get(report,"readOnly"),j_string(report,"readOnly"));return j_get(report,"document");
}
fn equal_check(p,sk,a,b,length,dof) {
    m_assert(pc_line_span(equal_point(p,a,"p0"),cg_v(0,0,0))==0,"Source start holds");
    m_assert(pc_line_span(equal_point(p,b,"p0"),cg_v(0,30000000,0))==0,"Follower remains joined to its own datum");
    m_assert(pc_line_span(equal_point(p,a,"p1"),cg_v(length,0,0))<=400,"Source follows common length");
    m_assert(pc_line_span(equal_point(p,b,"p1"),cg_v(0,30000000+length,0))<=400,"Perpendicular follower follows common length");
    let report=cad_project_line_sketch(p,sk);m_assert(report,cg_error);
    m_assert(j_integer(report,"degrees_of_freedom")==dof,"Only shared length freedom is consumed");
    return 1;
}
fn main() {
    let sk="native-sketch-1";let a="native-entity-1";let b="native-entity-2";let key="native-equal-native-entity-1-native-entity-2";
    let before=equal_reopen(m_read_file("libs/cad/tests/fixtures/equal-lines.pcad"));
    let original=j_encode(before);
    m_assert(j_integer(cad_project_line_sketch(before,sk),"degrees_of_freedom")==2,"Two independent lengths before Equal");
    let same=cad_project_toggle_equal_lines(before,sk,a,b);m_assert(same,cg_error);
    m_assert(m_eq(j_encode(before),original),"Adding Equal edits a copy");
    equal_check(same,sk,a,b,20000000,1);
    let rel=pc_find(equal_rows(same,sk),key);
    m_assert(m_eq(j_string(rel,"type"),"equal") && m_eq(j_string(rel,"a"),a) && m_eq(j_string(rel,"b"),b),"Keep the reference PCAD relation and entity IDs");
    same=equal_reopen(j_encode(same));

    let from_a=cad_project_set_line_expression(same,sk,a,"3 cm");m_assert(from_a,cg_error);
    from_a=equal_reopen(j_encode(from_a));equal_check(from_a,sk,a,b,30000000,0);
    let bound=cad_project_edit_line_variable(same,sk,"","span","25 mm");m_assert(bound,cg_error);
    let from_b=cad_project_set_line_expression(bound,sk,b,"#span");m_assert(from_b,cg_error);
    from_b=equal_reopen(j_encode(from_b));equal_check(from_b,sk,a,b,25000000,0);
    let conflict=j_encode(from_b);
    m_assert(!cad_project_set_line_expression(from_b,sk,a,"26 mm") && cg_error,"Conflicting independent lengths are rejected");
    m_assert(m_eq(j_encode(from_b),conflict),"Conflict preserves both dimensions and geometry");
    from_b=cad_project_edit_line_variable(from_b,sk,"span","span","27 mm");m_assert(from_b,cg_error);
    from_b=equal_reopen(j_encode(from_b));equal_check(from_b,sk,a,b,27000000,0);
    let removed=cad_project_toggle_equal_lines(same,sk,b,a);m_assert(removed,cg_error);
    m_assert(!pc_find(equal_rows(removed,sk),key) && pc_find(equal_rows(removed,sk),"upright"),"Removing Equal preserves the direction relation");
    m_assert(j_integer(cad_project_line_sketch(removed,sk),"degrees_of_freedom")==2,"Removing Equal restores independent lengths");

    let fixed=j_parse(original);let rows=equal_rows(fixed,sk);
    j_add(rows,0,j_parse("{\"type\":\"fixed\",\"id\":\"end\",\"anchor\":{\"entityId\":\"native-entity-2\",\"point\":\"p1\"},\"position\":{\"x\":0,\"y\":40}}"));
    let locked=j_encode(fixed);
    m_assert(!cad_project_toggle_equal_lines(fixed,sk,a,b) && cg_error,"Fixed mismatched lengths cannot be made Equal");
    m_assert(m_eq(j_encode(fixed),locked),"Rejected relation adds no geometry or relation");

    let chord=cad_project_add_primitive(from_a,sk,"line",equal_point(from_a,a,"p1"),equal_point(from_a,b,"p1"));m_assert(chord,cg_error);
    m_assert(cad_project_add_primitive(from_a,sk,"line",equal_point(from_a,b,"p0"),equal_point(from_a,a,"p0")),cg_error);
    let closed=cad_project_add_extrusion(from_a,sk,1,5000000,"newBody");m_assert(closed,cg_error);
    let mesh=cad_project_mesh(closed);m_assert(mesh && j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let edited=j_encode(closed);
    m_assert(!cad_project_set_line_expression(closed,sk,a,"32 mm") && cg_error,"The driving edit cannot detach the dependent solid boundary");
    m_assert(m_eq(j_encode(closed),edited),"A failed rebuild leaves the solid intact");
    let broken=j_parse(edited);let at=cg_v(0,61000000,0);
    pc_line_write_xy(j_get(equal_node(broken,b),"p1"),at);
    pc_line_write_xy(j_get(equal_node(broken,j_string(chord,"id")),"p1"),at);
    let stale=cad_project_mesh(broken);
    m_assert(m_eq(j_string(stale,"error"),m_cat("Saved equal length disagrees with geometry: ",key)),"Manufacturing detects stale Equal even on a closed profile");

    let curves=cad_project_new("Retained curve Equal");
    m_assert(cad_project_add_primitive(curves,sk,"circle",cg_v(0,0,0),cg_v(5000000,0,0)),cg_error);
    m_assert(cad_project_add_primitive(curves,sk,"circle",cg_v(20000000,0,0),cg_v(25000000,0,0)),cg_error);
    let x=40000000;while x<=60000000 {
        let picks=cg_array();cg_push(picks,cg_v(x,0,0));cg_push(picks,cg_v(x+5000000,0,0));cg_push(picks,cg_v(x,3000000,0));
        m_assert(cad_project_add_curve(curves,sk,"ellipse",picks),cg_error);x=x+20000000;
    }
    rows=equal_rows(curves,sk);
    j_add(rows,0,j_parse("{\"type\":\"equal\",\"id\":\"bore-radius\",\"a\":\"native-entity-1\",\"b\":\"native-entity-2\"}"));
    j_add(rows,0,j_parse("{\"type\":\"equal\",\"id\":\"ellipse-axes\",\"a\":\"native-entity-3\",\"b\":\"native-entity-4\"}"));
    curves=cad_project_add_extrusion(curves,sk,1,5000000,"newBody");m_assert(curves,cg_error);
    m_assert(j_value(j_get(cad_project_mesh(curves),"closed")),"Existing circle and ellipse Equal keep their export behavior");
    m_assert(j_get(cad_project_inspect_source(j_encode(curves)),"readOnly"),"Curved Equal is not interpreted as straight-line length equality");
    return 0;
}
