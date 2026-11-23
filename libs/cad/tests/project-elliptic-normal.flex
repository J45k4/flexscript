import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-normal-author.flex";

fn en_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn en_rows(project) {return j_get(en_node(project,"native-sketch-1"),"relations");}
fn en_reopen(text) {
    let report=cad_project_inspect_source(text);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    return j_get(report,"document");
}
fn en_select(source,index) {
    let project=j_parse(source);let path=j_array();j_add(path,0,j_number(index));cg_j_set(project,"selectedPath",path);
    return en_reopen(j_encode(project));
}
fn en_set(project,field,value) {
    let edited=cad_project_set_curve_dimension(project,"native-sketch-1","oval-guide",field,value);m_assert(edited,cg_error);
    return en_reopen(j_encode(edited));
}
fn en_expect(project,x0,y0,x1,y1,tolerance) {
    let row=en_node(project,"normal-line");let first=pc_uv(j_get(row,"p0"));let last=pc_uv(j_get(row,"p1"));
    return m_assert(pc_line_span(first,cg_v(x0,y0,0))<=tolerance && pc_line_span(last,cg_v(x1,y1,0))<=tolerance,
        m_cat("Normal differs from the TypeScript witness: ",j_encode(row)));
}
fn en_verify(project) {
    let sketch="native-sketch-1";let nodes=pc_nodes(cad_project_part(project));
    m_assert(pc_line_access(nodes,en_node(project,sketch)),cg_error);
    let mesh=cad_project_mesh(project);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    return mesh;
}
fn en_remove(project,id) {
    let rows=en_rows(project);let row=pc_find(rows,id);if row {pc_line_unlink(rows,row,"");}return 1;
}
fn en_vertical(source) {
    let base=en_select(source,0);let saved=j_encode(base);
    let first=en_verify(base);en_expect(base,0,5000000,0,10000000,1);
    let edited=en_set(base,"height","20 mm");en_expect(edited,0,10000000,0,15000000,1);
    m_assert(m_eq(j_encode(pc_find(en_rows(base),"normal-from-web")),j_encode(pc_find(en_rows(edited),"normal-from-web"))),"Normal retains the saved relation and operand IDs");
    m_assert(m_eq(j_encode(first),j_encode(en_verify(edited))),"Editing a guide preserves the exact independent part mesh");
    m_assert(m_eq(j_encode(base),saved),"A successful source edit preserves its input");
    return 1;
}
fn en_signed(source) {
    let base=en_select(source,1);en_verify(base);en_expect(base,9088787,10604496,9342484,22601814,1);
    let tall=en_set(base,"height","14 mm");en_expect(tall,8263825,11782664,11778370,23256459,80);
    let rotated=en_set(base,"rotation","55 deg");en_expect(rotated,6462717,12288684,2597790,23649245,80);
    let narrowed=en_set(base,"arcSweep","-30 deg");en_expect(narrowed,8857463,10604476,8611044,22601945,80);
    let longer=cad_project_set_line_length(base,"native-sketch-1","normal-line",15000000);m_assert(longer,cg_error);
    en_expect(longer,9088787,10604496,9405908,25601144,80);en_verify(longer);

    let translated=j_parse(j_encode(base));en_remove(translated,"oval-center");
    translated=cad_project_move_point(translated,"native-sketch-1","oval-guide",j_parse("{\"x\":1,\"y\":6}"));m_assert(translated,cg_error);
    en_expect(translated,7088787,12604496,7342484,24601814,80);en_verify(translated);

    let alias=j_parse(j_encode(base));let curve=en_node(alias,"oval-guide");let arc=j_parse(j_encode(pc_curve_geometry(curve)));
    pc_remove_field(curve,"arc");cg_j_text(curve,"type","sketchPrimitive");j_add(curve,"primitive",arc);
    let resized=en_set(en_reopen(j_encode(alias)),"height","14 mm");en_expect(resized,8263825,11782664,11778370,23256459,80);
    m_assert(m_eq(j_string(en_node(resized,"oval-guide"),"type"),"sketchPrimitive"),"A driven older elliptic arc retains its wrapper");

    let stale=j_parse(j_encode(base));en_remove(stale,"normal-contact-midpoint");let line=en_node(stale,"normal-line");
    pc_line_write_xy(j_get(line,"p0"),cg_v(-3088787,-2604496,0));pc_line_write_xy(j_get(line,"p1"),cg_v(-3342484,-14601814,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved line disagrees with normal relation: normal-from-web"),"A normal to the removed supporting ellipse does not count as finite contact");
    en_remove(stale,"normal-from-web");
    let reattached=cad_project_toggle_normal(stale,"native-sketch-1","oval-guide",j_parse("{\"entityId\":\"normal-line\",\"point\":\"p0\"}"));m_assert(reattached,cg_error);
    line=en_node(reattached,"normal-line");curve=en_node(reattached,"oval-guide");let contact=pc_uv(j_get(line,"p0"));
    m_assert(pc_line_span(contact,load64(ps_endpoint(curve,"p0")))<=2 || pc_line_span(contact,load64(ps_endpoint(curve,"p1")))<=2,"Normal authoring clamps a pick outside the sweep to its retained endpoint");
    en_verify(reattached);
    let fixed=j_parse(j_encode(base));let f=j_object();cg_j_text(f,"id","fixed-normal-tip");cg_j_text(f,"type","fixed");
    j_add(f,"anchor",j_parse("{\"entityId\":\"normal-line\",\"point\":\"p1\"}"));j_add(f,"position",j_parse(j_encode(j_get(en_node(base,"normal-line"),"p1"))));
    j_add(en_rows(fixed),0,f);let before=j_encode(fixed);
    m_assert(!cad_project_set_curve_dimension(fixed,"native-sketch-1","oval-guide","height","14 mm") && cg_error && m_eq(j_encode(fixed),before),"An incompatible fixed tip rejects the edit atomically");
    return 1;
}
fn en_closed(source) {
    let base=en_select(source,2);let aid=j_parse("{\"entityId\":\"normal-line\",\"point\":\"p1\"}");
    en_verify(base);en_expect(base,7861401,22051031,11052503,12573855,1);
    let taller=en_set(base,"height","16 mm");let mesh=en_verify(taller);
    m_assert(!m_eq(j_encode(j_get(mesh,"vertices")),j_encode(j_get(en_verify(base),"vertices"))),"An edited Normal follows the active ellipse manufacturing profile");
    let free=cad_project_toggle_normal(base,"native-sketch-1","oval-guide",aid);m_assert(free,cg_error);
    let line=en_node(free,"normal-line");
    pc_line_write_xy(j_get(line,"p0"),cg_v(21000000,8000000,0));pc_line_write_xy(j_get(line,"p1"),cg_v(11000000,8000000,0));
    let linked=cad_project_toggle_normal(free,"native-sketch-1","oval-guide",aid);m_assert(linked,cg_error);
    en_verify(en_reopen(j_encode(linked)));
    m_assert(m_eq(j_encode(pc_find(en_rows(linked),"native-normal-normal-line-oval-guide")),"{\"id\":\"native-normal-normal-line-oval-guide\",\"type\":\"normal\",\"a\":{\"entityId\":\"normal-line\",\"point\":\"p1\"},\"b\":\"oval-guide\"}"),"The authoring entry point uses the TypeScript v4 schema");
    m_assert(m_eq(j_encode(en_node(base,"oval-guide")),j_encode(en_node(linked,"oval-guide"))),"Line authoring retains the closed ellipse source");
    return 1;
}
fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/elliptic-normal.pcad");
    return !(en_vertical(source) && en_signed(source) && en_closed(source));
}
