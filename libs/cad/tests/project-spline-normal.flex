import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-normal-author.flex";
import "cad/project-smooth-author.flex";

fn sn_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn sn_rows(project) {return j_get(sn_node(project,"native-sketch-1"),"relations");}
fn sn_drop(project,id) {let rows=sn_rows(project);let row=pc_find(rows,id);if row {pc_line_unlink(rows,row,"");}return 1;}
fn sn_reopen(project) {
    let report=cad_project_inspect_source(j_encode(project));m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    return j_get(report,"document");
}
fn sn_select(source,index) {
    let project=j_parse(source);let selection=j_array();j_add(selection,0,j_number(index));cg_j_set(project,"selectedPath",selection);
    return sn_reopen(project);
}
fn sn_expect(project,x0,y0,x1,y1) {
    let line=sn_node(project,"normal-line");let a=pc_uv(j_get(line,"p0"));let b=pc_uv(j_get(line,"p1"));
    return m_assert(pc_line_span(a,cg_v(x0,y0,0))<=80 && pc_line_span(b,cg_v(x1,y1,0))<=80,m_cat("Spline Normal differs from TypeScript: ",j_encode(line)));
}
fn sn_rank(project,count,bound) {
    let result=cad_project_line_sketch(project,"native-sketch-1");m_assert(result,cg_error);
    return m_assert(j_integer(result,"degrees_of_freedom")==count && !!j_get(result,"degrees_of_freedom_is_upper_bound")==bound,j_encode(result));
}
fn sn_mesh(project) {
    let mesh=cad_project_mesh(project);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));return mesh;
}
fn sn_same_normal(edited,base) {
    return m_assert(m_eq(j_encode(pc_find(sn_rows(edited),"normal-from-web")),j_encode(pc_find(sn_rows(base),"normal-from-web"))),"Preserve the original saved Normal ID and its endpoint/curve operands");
}
fn sn_control(source) {
    let sk="native-sketch-1";let base=sn_select(source,0);let snapshot=j_encode(base);sn_rank(base,1,0);
    let free=j_parse(snapshot);sn_drop(free,"normal-length");sn_rank(free,2,0);
    let resized=cad_project_set_line_length(base,sk,"normal-line",8000000);m_assert(resized,cg_error);resized=sn_reopen(resized);
    sn_expect(resized,5000000,7500000,5000000,15500000);sn_same_normal(resized,base);
    m_assert(m_eq(j_encode(sn_node(resized,"spline-guide")),j_encode(sn_node(base,"spline-guide"))),"Changing Normal length preserves all saved original controls");
    m_assert(m_eq(j_encode(sn_mesh(resized)),j_encode(sn_mesh(base))),"Changing a construction normal preserves the independent solid");
    let moved=cad_project_move_smooth_point(base,sk,ps_anchor("spline-guide","point1"),j_parse("{\"x\":0,\"y\":11}"));
    m_assert(!moved && m_eq(cg_error,"Saved spline disagrees with fixed point: fixed-point-1") && m_eq(j_encode(base),snapshot),"A saved fixed control rejects its edit atomically");
    let removed=cad_project_toggle_normal(base,sk,"spline-guide",ps_anchor("normal-line","p0"));m_assert(removed,cg_error);
    let line=sn_node(removed,"normal-line");pc_line_write_xy(j_get(line,"p0"),cg_v(5000000,8500000,0));pc_line_write_xy(j_get(line,"p1"),cg_v(5000000,13500000,0));
    let authored=cad_project_toggle_normal(removed,sk,"spline-guide",ps_anchor("normal-line","p0"));m_assert(authored,cg_error);authored=sn_reopen(authored);
    sn_expect(authored,5000000,7500000,5000000,12500000);
    m_assert(m_eq(j_encode(pc_find(sn_rows(authored),"native-normal-normal-line-spline-guide")),"{\"id\":\"native-normal-normal-line-spline-guide\",\"type\":\"normal\",\"a\":{\"entityId\":\"normal-line\",\"point\":\"p0\"},\"b\":\"spline-guide\"}"),"Authoring uses the unchanged typed v4 Normal schema");
    return 1;
}
fn sn_fit(source,index) {
    let sk="native-sketch-1";let base=sn_select(source,index);let snapshot=j_encode(base);sn_rank(base,3,1);
    let id="point1";let x=5000000;let y=10250000;let tip=15250000;if index==2 {id="point3";x=0;y=12000000;tip=7000000;}
    let edited=cad_project_move_smooth_point(base,sk,ps_anchor("spline-guide",id),pc_json_point(cg_v(x,y,0)));
    m_assert(edited,cg_error);edited=sn_reopen(edited);sn_expect(edited,x,y,x,tip);sn_same_normal(edited,base);
    m_assert(m_eq(j_encode(sn_mesh(base)),j_encode(sn_mesh(edited)))==(index==1),"The dependent periodic spline solid rebuilds while an independent solid stays the same");
    let fixed=j_object();cg_j_text(fixed,"id","lock-contact");cg_j_text(fixed,"type","fixed");
    j_add(fixed,"anchor",ps_anchor("normal-line","p0"));j_add(fixed,"position",j_parse(j_encode(j_get(sn_node(base,"normal-line"),"p0"))));
    j_add(sn_rows(base),0,fixed);let blocked=j_encode(base);
    m_assert(!cad_project_move_smooth_point(base,sk,ps_anchor("spline-guide",id),pc_json_point(cg_v(x,y,0))) && cg_error && m_eq(j_encode(base),blocked),"Incompatible fixed contact rejects the spline change atomically");
    m_assert(m_eq(j_encode(sn_select(source,index)),snapshot),"Reshaping the source leaves the original graph unchanged");
    return 1;
}
fn sn_invalid(source) {
    let base=sn_select(source,0);let line=sn_node(base,"normal-line");
    let end=j_get(line,"p1");pc_line_write_xy(end,cg_v(10000000,7500000,0));
    m_assert(m_eq(j_string(cad_project_mesh(base),"error"),"Saved line disagrees with normal relation: normal-from-web"),"Stale direction blocks manufacturing");
    pc_line_write_xy(j_get(line,"p0"),cg_v(5000000,8500000,0));pc_line_write_xy(end,cg_v(5000000,13500000,0));
    m_assert(m_eq(j_string(cad_project_mesh(base),"error"),"Saved line disagrees with normal relation: normal-from-web"),"Stale contact blocks manufacturing");
    let i=0;while i<4 {sn_drop(base,m_cat("fixed-point-",m_int(i)));i=i+1;}
    let curve=j_get(sn_node(base,"spline-guide"),"spline");
    cg_j_set(curve,"points",j_parse("[{\"x\":0,\"y\":0},{\"x\":1,\"y\":0},{\"x\":2,\"y\":0},{\"x\":3,\"y\":0},{\"x\":3,\"y\":1},{\"x\":3,\"y\":2},{\"x\":3,\"y\":3}]"));
    pc_line_write_xy(j_get(line,"p0"),cg_v(3000000,0,0));pc_line_write_xy(end,cg_v(3000000,-5000000,0));
    m_assert(m_eq(j_string(cad_project_mesh(base),"error"),"Normal requires a smooth spline join with a unique tangent"),"A sharp control join has no unique Normal");
    cg_j_set(curve,"points",j_parse("[{\"x\":0,\"y\":0},{\"x\":1,\"y\":0},{\"x\":2,\"y\":0},{\"x\":3,\"y\":0},{\"x\":4,\"y\":0},{\"x\":5,\"y\":1},{\"x\":6,\"y\":1}]"));sn_mesh(base);
    cg_j_set(curve,"points",j_parse("[{\"x\":0,\"y\":0},{\"x\":0,\"y\":0},{\"x\":1,\"y\":1},{\"x\":2,\"y\":1}]"));
    pc_line_write_xy(j_get(line,"p0"),cg_v(0,0,0));pc_line_write_xy(end,cg_v(0,-5000000,0));
    m_assert(m_eq(j_string(cad_project_mesh(base),"error"),"Normal requires a regular spline point with a nonzero tangent"),"A stationary spline contact cannot define a Normal");
    return 1;
}
fn sn_split() {
    let source=m_read_file("libs/cad/tests/fixtures/typescript-split-spline-normal.pcad");
    let sk="native-sketch-1";let base=sn_select(source,0);let before=j_encode(base);
    let edited=cad_project_set_line_length(base,sk,"normal-line",8000000);m_assert(edited,cg_error);
    edited=sn_reopen(edited);sn_same_normal(edited,base);
    let line=sn_node(edited,"normal-line");let start=pc_uv(j_get(line,"p0"));let end=pc_uv(j_get(line,"p1"));
    m_assert(cg_abs(pc_line_span(start,end)-8000000)<=40 && m_eq(j_string(pc_find(sn_rows(edited),"normal-from-web"),"b"),"spline-guide-split-1"),
        "The saved Normal stays with the retained spline when the follower is resized");
    m_assert(m_eq(j_encode(sn_node(base,"spline-guide")),j_encode(sn_node(edited,"spline-guide")))
        && m_eq(j_encode(sn_node(base,"spline-guide-split-1")),j_encode(sn_node(edited,"spline-guide-split-1")))
        && m_eq(j_encode(pc_find(sn_rows(base),"coincident-1")),j_encode(pc_find(sn_rows(edited),"coincident-1")))
        && m_eq(j_encode(sn_mesh(base)),j_encode(sn_mesh(edited))),"Keep the authored split join, controls and independent solid");

    let joined=j_parse(before);let nodes=pc_nodes(cad_project_part(joined));
    j_add(nodes,0,j_parse("{\"id\":\"joined-line\",\"type\":\"sketchLine\",\"sketchId\":\"native-sketch-1\",\"construction\":true,\"p0\":{\"x\":10,\"y\":0},\"p1\":{\"x\":12,\"y\":0}}"));
    j_add(sn_rows(joined),0,j_parse("{\"id\":\"endpoint-on-split\",\"type\":\"coincident\",\"a\":{\"entityId\":\"spline-guide-split-1\",\"point\":\"point3\"},\"b\":{\"entityId\":\"joined-line\",\"point\":\"p0\"}}"));
    let longer=cad_project_set_line_length(joined,sk,"joined-line",4000000);m_assert(longer,cg_error);
    let attached=sn_node(sn_reopen(longer),"joined-line");
    m_assert(pc_line_span(pc_uv(j_get(attached,"p0")),cg_v(10000000,0,0))<=1
        && pc_line_span(pc_uv(j_get(attached,"p1")),cg_v(14000000,0,0))<=1,"An affine endpoint remains coincident with a held spline point");
    pc_line_write_xy(j_get(sn_node(joined,"joined-line"),"p0"),cg_v(9000000,0,0));
    m_assert(!cad_project_line_sketch(joined,sk) && m_eq(cg_error,"Saved spline coincidence anchors do not meet"),
        "A stale saved spline join is rejected before solving");
    return 1;
}
fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/spline-normal.pcad");
    return !(sn_control(source) && sn_fit(source,1) && sn_fit(source,2) && sn_invalid(source) && sn_split());
}
