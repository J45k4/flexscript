import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-normal-author.flex";

fn ln_find(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn ln_rows(project) {return j_get(ln_find(project,"native-sketch-1"),"relations");}
fn ln_drop(project,id) {let rows=ln_rows(project);return pc_line_unlink(rows,pc_find(rows,id),"");}
fn ln_reopen(project) {
    let report=cad_project_inspect_source(j_encode(project));m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    return j_get(report,"document");
}
fn ln_unset(project,key) {let clone=j_parse(j_encode(project));ln_drop(clone,key);return clone;}
fn ln_endpoint(project,id,end,x,y) {
    let row=ln_find(project,id);let point=pc_uv(j_get(row,end));
    return m_assert(pc_line_span(point,cg_v(x,y,0))<25,m_cat("Line normal differs from the TypeScript witness: ",j_encode(row)));
}
fn ln_rank(project,dof) {
    let report=cad_project_line_sketch(project,"native-sketch-1");m_assert(report,cg_error);
    return m_assert(j_integer(report,"degrees_of_freedom")==dof && !j_get(report,"degrees_of_freedom_is_upper_bound"),j_encode(report));
}
fn ln_edit(project,base) {
    let sk="native-sketch-1";let normal="normal-from-web";ln_rank(project,0);
    let free=ln_unset(project,"normal-midpoint");ln_rank(free,1);ln_drop(free,"follower-length");ln_rank(free,2);
    let longer=cad_project_set_line_length(project,sk,"normal-source",15000000);m_assert(longer,cg_error);
    longer=ln_reopen(longer);ln_endpoint(longer,"normal-source","p1",15000000,0);
    ln_endpoint(longer,"normal-line","p0",7500000,0);ln_endpoint(longer,"normal-line","p1",7500000,5000000);ln_rank(longer,0);
    m_assert(m_eq(j_encode(pc_find(ln_rows(longer),normal)),j_encode(pc_find(ln_rows(project),normal))),"The saved TypeScript relation is preserved across edit and reopen");
    let original=cad_project_mesh(project);let rebuilt=cad_project_mesh(longer);
    m_assert(j_value(j_get(rebuilt,"closed")) && m_eq(j_encode(original),j_encode(rebuilt)) && cg_stl(rebuilt),"Normal guide edits preserve the independent manufactured solid");
    let blocked=j_parse(base);let fixed=j_parse("{\"id\":\"fixed-tip\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"normal-line\",\"point\":\"p1\"},\"position\":{\"x\":5,\"y\":5}}");
    j_add(ln_rows(blocked),0,fixed);let saved=j_encode(blocked);
    m_assert(!cad_project_set_line_length(blocked,sk,"normal-source",15000000) && cg_error && m_eq(j_encode(blocked),saved),"An independent fixed tip rejects the incompatible source length atomically");
    return 1;
}
fn ln_validation(project) {
    let stale=ln_unset(project,"normal-midpoint");let line=ln_find(stale,"normal-line");
    pc_line_write_xy(j_get(line,"p0"),cg_v(12000000,0,0));pc_line_write_xy(j_get(line,"p1"),cg_v(12000000,5000000,0));
    let saved_error="Saved line disagrees with normal relation: normal-from-web";
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),saved_error),"A normal on the perpendicular extension must be rejected");
    pc_line_write_xy(j_get(line,"p0"),cg_v(5000000,0,0));pc_line_write_xy(j_get(line,"p1"),cg_v(10000000,0,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),saved_error),"Incidence without perpendicular direction must be rejected");
    return 1;
}
fn ln_author(project) {
    let sk="native-sketch-1";let source="normal-source";let line="normal-line";
    let original=ln_unset(project,"normal-midpoint");ln_drop(original,"normal-from-web");let edited=ln_find(original,line);
    pc_line_write_xy(j_get(edited,"p0"),cg_v(12000000,5000000,0));pc_line_write_xy(j_get(edited,"p1"),cg_v(12000000,0,0));
    let anchor=j_parse("{\"entityId\":\"normal-line\",\"point\":\"p1\"}");let unchanged=j_encode(original);
    m_assert(!cad_project_toggle_normal(original,sk,line,anchor) && m_eq(unchanged,j_encode(original)),"Normal rejects the same line in both roles");
    let linked=cad_project_toggle_normal(original,sk,source,anchor);m_assert(linked,cg_error);linked=ln_reopen(linked);
    ln_endpoint(linked,line,"p1",10000000,0);ln_endpoint(linked,line,"p0",10000000,5000000);
    let relation=pc_find(ln_rows(linked),"native-normal-normal-line-normal-source");
    m_assert(m_eq(j_encode(relation),"{\"id\":\"native-normal-normal-line-normal-source\",\"type\":\"normal\",\"a\":{\"entityId\":\"normal-line\",\"point\":\"p1\"},\"b\":\"normal-source\"}"),"Authoring stores the unchanged v4 schema");
    let without=cad_project_toggle_normal(linked,sk,source,anchor);m_assert(without && !pc_find(ln_rows(without),j_string(relation,"id")),cg_error);
    m_assert(m_eq(j_encode(original),unchanged),"Normal authoring preserves its source document");
    return 1;
}
fn main() {
    let project=cad_project_open(m_read_file("libs/cad/tests/fixtures/linear-normal.pcad"));m_assert(project,cg_error);
    let saved=j_encode(project);return !(ln_edit(project,saved) && ln_validation(project) && ln_author(project) && m_eq(j_encode(project),saved));
}
