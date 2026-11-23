import "cad/project-access.flex";
import "cad/project-smooth-author.flex";

fn esj_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn esj_rows(project) {return j_get(esj_node(project,"native-sketch-1"),"relations");}
fn esj_open(text) {
    let report=cad_project_inspect_source(text);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    return j_get(report,"document");
}
fn esj_edit(base,field,value) {
    let result=cad_project_set_curve_dimension(base,"native-sketch-1","arc-guide",field,value);m_assert(result,cg_error);
    return esj_open(j_encode(result));
}
fn esj_point(point,x,y) {
    return m_assert(pc_line_span(point,cg_v(x,y,0))<=5,m_cat("Expected the TypeScript endpoint, got ",j_encode(pc_json_point(point))));
}
fn esj_line(project,x0,y0,x1,y1) {
    let line=esj_node(project,"tangent-line");let first=pc_uv(j_get(line,"p0"));let last=pc_uv(j_get(line,"p1"));
    esj_point(first,x0,y0);esj_point(last,x1,y1);
    return m_assert(cg_abs(pc_line_span(first,last)-12000000)<=5,"Alignment preserves the driving line length");
}
fn esj_mesh(project) {
    let mesh=cad_project_mesh(project);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));return mesh;
}
fn esj_select(source,index) {
    let project=j_parse(source);let path=j_array();j_add(path,0,j_number(index));cg_j_set(project,"selectedPath",path);
    return esj_open(j_encode(project));
}
fn esj_raw_arc(project) {return pc_curve_geometry(esj_node(project,"arc-guide"));}
fn esj_remove(project,id) {
    let rows=esj_rows(project);let row=pc_find(rows,id);if row {pc_line_unlink(rows,row,"");}return 1;
}
fn esj_members(project,arc_end,line_end) {
    return ps_matches(ps_endpoint(esj_node(project,"arc-guide"),arc_end),ps_endpoint(esj_node(project,"tangent-line"),line_end));
}

fn esj_driven(base) {
    let original=j_encode(base);let saved=j_encode(pc_find(esj_rows(base),"smooth-from-web"));
    esj_line(base,9585732,301755,-41911,-6861239);
    let taller=esj_edit(base,"height","18 mm");esj_line(taller,11398348,-2837787,2459747,-10844123);
    m_assert(m_eq(j_encode(pc_find(esj_rows(taller),"smooth-from-web")),saved),"The authored ID and arc endpoint are unchanged after dimension edit and reopen");
    m_assert(m_eq(j_string(esj_node(taller,"arc-guide"),"type"),"sketchArc") && !j_get(esj_node(taller,"arc-guide"),"primitive"),"The canonical wrapper is retained");
    let shorter=esj_edit(base,"arcSweep","-70 deg");esj_line(shorter,16754257,7233087,10430244,-2965288);
    m_assert(m_eq(j_encode(esj_mesh(base)),j_encode(esj_mesh(taller))),"The construction edit preserves the closed manufactured part");
    let variable=cad_project_edit_line_variable(base,"native-sketch-1","","span","10 mm");m_assert(variable,cg_error);
    variable=esj_edit(variable,"height","#span");
    variable=cad_project_edit_line_variable(variable,"native-sketch-1","span","span","16 mm");m_assert(variable,cg_error);
    esj_line(esj_open(j_encode(variable)),10945194,-2052902,1829248,-9856716);
    let free=j_parse(original);esj_remove(free,"arc-center");
    let lifted=cad_project_move_point(free,"native-sketch-1","arc-guide",j_parse("{\"x\":2,\"y\":-3}"));m_assert(lifted,cg_error);
    esj_line(lifted,11585732,-2698245,1958089,-9861239);
    m_assert(m_eq(j_encode(base),original),"Driving an elliptic join leaves the input snapshot unchanged");
    return 1;
}

fn esj_author(base) {
    let sk="native-sketch-1";let arc=ps_anchor("arc-guide","p1");let line=ps_anchor("tangent-line","p0");
    let detached=cad_project_toggle_smooth_join(base,sk,arc,line);m_assert(detached,cg_error);
    m_assert(!pc_find(esj_rows(detached),"smooth-from-web"),"The saved relation toggles off by its actual endpoints");
    let row=esj_node(detached,"tangent-line");pc_line_write_xy(j_get(row,"p0"),cg_v(7000000,9000000,0));pc_line_write_xy(j_get(row,"p1"),cg_v(7000000,21000000,0));
    let authored=cad_project_toggle_smooth_join(detached,sk,arc,line);m_assert(authored,cg_error);
    authored=esj_open(j_encode(authored));esj_line(authored,9585732,301755,-41911,-6861239);
    m_assert(m_eq(j_encode(esj_raw_arc(authored)),j_encode(esj_raw_arc(base))),"Authoring keeps the selected elliptic source unchanged");
    m_assert(m_eq(j_encode(pc_find(esj_rows(authored),"native-smooth-join-tangent-line-p0")),"{\"type\":\"smoothJoin\",\"id\":\"native-smooth-join-tangent-line-p0\",\"a\":{\"entityId\":\"arc-guide\",\"point\":\"p1\"},\"b\":{\"entityId\":\"tangent-line\",\"point\":\"p0\"}}"),"New joins use the standard saved relation");

    let circle=cad_project_add_tangent_arc(authored,sk,ps_anchor("arc-guide","p0"),j_parse("{\"x\":17,\"y\":20}"));m_assert(circle,cg_error);
    let new_arc=esj_node(circle,"native-entity-1");
    m_assert(pc_circular_arc(new_arc) && cad_sketch_is_construction(new_arc) && ps_matches(ps_endpoint(esj_node(circle,"arc-guide"),"p0"),ps_endpoint(new_arc,"p0")),"Tangent Arc uses the other elliptic endpoint and inherits construction");
    m_assert(m_eq(j_encode(esj_mesh(base)),j_encode(esj_mesh(circle))),"A tangent construction arc leaves the body unchanged");

    esj_remove(detached,"arc-center");esj_remove(detached,"arc-rotation");
    let reverse=cad_project_toggle_smooth_join(detached,sk,line,arc);m_assert(reverse,cg_error);
    m_assert(esj_members(reverse,"p1","p0") && pc_circle_measure(esj_node(reverse,"arc-guide"),"width")==40000000 && pc_circle_measure(esj_node(reverse,"arc-guide"),"height")==10000000,"The follower ellipse rotates and translates without changing its axes");
    m_assert(m_eq(j_encode(esj_node(reverse,"tangent-line")),j_encode(esj_node(detached,"tangent-line"))),"Reverse authoring preserves its selected line driver");

    let movable=j_parse(j_encode(base));esj_remove(movable,"arc-center");esj_remove(movable,"arc-rotation");esj_remove(movable,"arc-width");esj_remove(movable,"arc-height");
    let moved=cad_project_move_smooth_point(movable,sk,ps_anchor("arc-guide","p0"),j_parse("{\"x\":15,\"y\":9}"));m_assert(moved,cg_error);
    let shape=esj_node(moved,"arc-guide");esj_point(load64(ps_endpoint(shape,"p0")),15000000,9000000);esj_point(load64(ps_endpoint(shape,"p1")),9585732,301755);
    m_assert(esj_members(moved,"p1","p0") && pc_circle_measure(shape,"arcSweep")==-110000000,"Endpoint drag preserves the opposite endpoint, signed sweep and tangent continuation");
    return 1;
}

fn esj_compatibility(source,base) {
    let ccw=esj_select(source,1);esj_line(ccw,7650305,-13564764,-3540030,-9231589);
    let turned=esj_edit(ccw,"rotation","20 deg");esj_line(turned,11516037,-9767940,539258,-14616685);
    let alias=j_parse(j_encode(base));let node=esj_node(alias,"arc-guide");let geometry=j_parse(j_encode(esj_raw_arc(alias)));
    pc_remove_field(node,"arc");cg_j_text(node,"type","sketchPrimitive");j_add(node,"primitive",geometry);
    let changed=esj_edit(esj_open(j_encode(alias)),"height","18 mm");esj_line(changed,11398348,-2837787,2459747,-10844123);
    m_assert(m_eq(j_string(esj_node(changed,"arc-guide"),"type"),"sketchPrimitive") && j_get(esj_node(changed,"arc-guide"),"primitive"),"Legacy wrapper is retained through export and editing");
    let full=j_parse(j_encode(base));esj_remove(full,"arc-sweep");cg_j_set(esj_raw_arc(full),"sweep",j_new(6,"6.283185307179586"));
    m_assert(m_eq(j_string(cad_project_mesh(full),"error"),"A full-turn elliptic arc has no endpoints"),"A valid full turn cannot own a smooth endpoint");

    let blocked=j_parse(j_encode(base));let line=esj_node(blocked,"tangent-line");let fixed=j_object();
    cg_j_text(fixed,"id","p0-fixed");cg_j_text(fixed,"type","fixed");j_add(fixed,"anchor",ps_anchor("tangent-line","p0"));
    j_add(fixed,"position",j_parse(j_encode(j_get(line,"p0"))));j_add(esj_rows(blocked),0,fixed);let original=j_encode(blocked);
    m_assert(!cad_project_set_curve_dimension(blocked,"native-sketch-1","arc-guide","height","18 mm") && cg_error
        && m_eq(j_encode(blocked),original),"An incompatible fixed follower rejects the changed driver atomically");
    let stale=j_parse(j_encode(base));line=esj_node(stale,"tangent-line");let first=pc_uv(j_get(line,"p0"));let last=pc_uv(j_get(line,"p1"));
    pc_line_write_xy(j_get(line,"p1"),cg_v(2*load64(first)-load64(last),2*load64(first+8)-load64(last+8),0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved endpoints disagree with smooth join: smooth-from-web"),"The opposite tangent direction matters even on the same line");
    return 1;
}

fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/elliptic-smooth-join.pcad");let base=esj_select(source,0);
    return !(esj_driven(base) && esj_author(base) && esj_compatibility(source,base));
}
