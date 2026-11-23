import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-normal-author.flex";

fn rn_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn rn_rows(project) {return j_get(rn_node(project,"native-sketch-1"),"relations");}
fn rn_reopen(text) {
    let report=cad_project_inspect_source(text);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    return j_get(report,"document");
}
fn rn_select(source,index) {
    let project=j_parse(source);let path=j_array();j_add(path,0,j_number(index));cg_j_set(project,"selectedPath",path);
    return rn_reopen(j_encode(project));
}
fn rn_set(project,field,value) {
    let edited=cad_project_set_curve_dimension(project,"native-sketch-1","round-guide",field,value);m_assert(edited,cg_error);
    return rn_reopen(j_encode(edited));
}
fn rn_expect(project,x0,y0,x1,y1,tolerance) {
    let row=rn_node(project,"normal-line");let first=pc_uv(j_get(row,"p0"));let last=pc_uv(j_get(row,"p1"));
    return m_assert(pc_line_span(first,cg_v(x0,y0,0))<=tolerance && pc_line_span(last,cg_v(x1,y1,0))<=tolerance,
        m_cat("Normal differs from the TypeScript witness: ",j_encode(row)));
}
fn rn_mesh(project) {
    let sketch="native-sketch-1";let nodes=pc_nodes(cad_project_part(project));
    m_assert(pc_line_access(nodes,rn_node(project,sketch)),cg_error);
    let mesh=cad_project_mesh(project);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));return mesh;
}
fn rn_remove(project,id) {
    let rows=rn_rows(project);let row=pc_find(rows,id);if row {pc_line_unlink(rows,row,"");}return 1;
}
fn rn_dof(project,expected) {
    let report=cad_project_line_sketch(project,"native-sketch-1");m_assert(report,cg_error);
    return m_assert(j_integer(report,"degrees_of_freedom")==expected && !j_get(report,"degrees_of_freedom_is_upper_bound"),"Normal has distinct incidence and direction ranks");
}
fn rn_circle(source) {
    let base=rn_select(source,0);let saved=j_encode(base);let before=rn_mesh(base);rn_dof(base,1);
    let unmeasured=j_parse(saved);rn_remove(unmeasured,"line-length");rn_dof(unmeasured,2);
    let wider=rn_set(base,"radius","25 mm");rn_expect(wider,0,25000000,0,30000000,1);
    m_assert(m_eq(j_encode(pc_find(rn_rows(wider),"normal-from-web")),j_encode(pc_find(rn_rows(base),"normal-from-web"))),"Circle radius editing keeps the saved web relation unchanged");
    m_assert(!m_eq(j_encode(j_get(before,"vertices")),j_encode(j_get(rn_mesh(wider),"vertices"))),"Circle editing rebuilds the active solid");
    let var=cad_project_edit_line_variable(base,"native-sketch-1","","size","20 mm");m_assert(var,cg_error);
    var=rn_set(var,"radius","#size");var=cad_project_edit_line_variable(var,"native-sketch-1","size","size","26 mm");m_assert(var,cg_error);
    rn_expect(rn_reopen(j_encode(var)),0,26000000,0,31000000,1);
    let free=j_parse(saved);rn_remove(free,"round-center");
    let moved=cad_project_move_point(free,"native-sketch-1","round-guide",j_parse("{\"x\":0,\"y\":5}"));m_assert(moved,cg_error);
    rn_expect(moved,0,25000000,0,30000000,1);
    let wrong=j_parse(saved);pc_line_write_xy(j_get(rn_node(wrong,"normal-line"),"p1"),cg_v(5000000,20000000,0));
    m_assert(m_eq(j_string(cad_project_mesh(wrong),"error"),"Saved line disagrees with normal relation: normal-from-web"),"Contact alone cannot satisfy Normal");
    m_assert(m_eq(j_encode(base),saved),"Circle edits preserve their source document");
    return 1;
}
fn rn_arc(source) {
    let base=rn_select(source,1);let before=j_encode(base);rn_dof(base,1);let mesh=rn_mesh(base);
    let resized=rn_set(base,"radius","25 mm");rn_expect(resized,17677670,-17677670,26162951,-26162951,80);
    let shrunk=rn_set(base,"arcSweep","-30 deg");rn_expect(shrunk,19318517,-5176381,30909626,-8282209,80);
    m_assert(m_eq(j_encode(mesh),j_encode(rn_mesh(shrunk))),"A finite guide edit keeps the independent body unchanged");
    let longer=cad_project_set_line_length(base,"native-sketch-1","normal-line",15000000);m_assert(longer,cg_error);
    rn_expect(longer,14142136,-14142136,24748737,-24748737,80);
    let flipped=rn_set(base,"arcSweep","90 deg");rn_mesh(flipped);
    let line=rn_node(flipped,"normal-line");let contact=pc_uv(j_get(line,"p0"));
    m_assert(pc_line_span(contact,cg_v(14142136,14142136,0))<=2,"A sign change places the midpoint on the newly retained side");

    let stale=j_parse(before);rn_remove(stale,"normal-midpoint");line=rn_node(stale,"normal-line");
    pc_line_write_xy(j_get(line,"p0"),cg_v(-12000000,-16000000,0));pc_line_write_xy(j_get(line,"p1"),cg_v(-19200000,-25600000,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved line disagrees with normal relation: normal-from-web"),"A radial line on the discarded half of the circle is stale");
    rn_remove(stale,"normal-from-web");let sk="native-sketch-1";
    let linked=cad_project_toggle_normal(stale,sk,"round-guide",j_parse("{\"entityId\":\"normal-line\",\"point\":\"p0\"}"));m_assert(linked,cg_error);
    rn_expect(linked,0,-20000000,0,-32000000,1);rn_mesh(rn_reopen(j_encode(linked)));
    m_assert(m_eq(j_encode(pc_find(rn_rows(linked),"native-normal-normal-line-round-guide")),"{\"id\":\"native-normal-normal-line-round-guide\",\"type\":\"normal\",\"a\":{\"entityId\":\"normal-line\",\"point\":\"p0\"},\"b\":\"round-guide\"}"),"Normal authoring uses the unchanged v4 relation schema");

    let blocked=j_parse(before);let fixed=j_object();cg_j_text(fixed,"id","fixed-normal-tip");cg_j_text(fixed,"type","fixed");
    j_add(fixed,"anchor",j_parse("{\"entityId\":\"normal-line\",\"point\":\"p1\"}"));j_add(fixed,"position",j_parse(j_encode(j_get(rn_node(base,"normal-line"),"p1"))));
    j_add(rn_rows(blocked),0,fixed);let saved=j_encode(blocked);
    m_assert(!cad_project_set_curve_dimension(blocked,sk,"round-guide","arcSweep","-30 deg") && cg_error && m_eq(j_encode(blocked),saved),"An incompatible fixed tip rejects the sweep edit without changing its input");
    m_assert(m_eq(j_encode(base),before),"Arc edits preserve their source document");
    return 1;
}
fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/round-normal.pcad");
    return !(rn_circle(source) && rn_arc(source));
}
