import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-point-on-curve-author.flex";
import "cad/project-smooth-author.flex";

fn scp_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn scp_rows(project) {return j_get(scp_node(project,"native-sketch-1"),"relations");}
fn scp_anchor(project,field) {
    let probe=scp_node(project,"probe");
    if m_eq(field,"center") {return j_get(pc_curve_geometry(probe),field);}
    return j_get(probe,field);
}
fn scp_reopen(text) {
    let report=cad_project_inspect_source(text);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    return j_get(report,"document");
}
fn scp_select(text,index) {
    let project=j_parse(text);let selected=j_array();j_add(selected,0,j_number(index));
    cg_j_set(project,"selectedPath",selected);return scp_reopen(j_encode(project));
}
fn scp_move(project,field,x,y) {
    let at=pc_json_point(cg_v(x,y,0));let sketch="native-sketch-1";let edited=0;
    if m_eq(field,"center") {edited=cad_project_move_point(project,sketch,"probe",at);}
    else {edited=cad_project_move_line_endpoint(project,sketch,"probe",field,at);}
    m_assert(edited,cg_error);return edited;
}
fn scp_expect(project,field,x,y) {
    let point=scp_anchor(project,field);
    return m_assert(pc_line_span(pc_uv(point),cg_v(x,y,0))<=3,m_cat("Expected the TypeScript spline contact, got ",j_encode(point)));
}
fn scp_freedom(project,count) {
    let report=cad_project_line_sketch(project,"native-sketch-1");m_assert(report,cg_error);
    return m_assert(j_integer(report,"degrees_of_freedom")==count && !j_get(report,"degrees_of_freedom_is_upper_bound"),"Spline contact preserves one sliding direction");
}
fn scp_mesh(project) {
    let mesh=cad_project_mesh(project);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));return mesh;
}
fn scp_check_saved(base,edited,curve,relation) {
    m_assert(m_eq(j_encode(scp_node(base,curve)),j_encode(scp_node(edited,curve))),"The exact saved spline, points, mode, and closure are untouched");
    m_assert(m_eq(j_encode(pc_find(scp_rows(base),relation)),j_encode(pc_find(scp_rows(edited),relation))),"The saved relation ID and anchors are unchanged");
    return 1;
}

fn scp_control(source) {
    let base=scp_select(source,0);let before=j_encode(base);let curve="crossing-spline";let relation="crossing-spline-contact";
    scp_expect(base,"center",0,0);scp_freedom(base,1);
    let data=pc_spline_data(scp_node(base,curve));
    let hit=psb_nearest(data,cg_v(0,0,0),0);
    m_assert(hit && load64(hit+16)==0 && load64(hit)==500000000000,"An exact self intersection uses the first equally near authored span");
    hit=psb_nearest(data,cg_v(8000000,-6000000,0),0);
    m_assert(hit && load64(hit+16)==2,"The lower branch remains available after the crossing");
    let first=scp_move(base,"center",8000000,6000000);scp_expect(first,"center",8307692,5538462);
    let second=scp_move(first,"center",8000000,-6000000);scp_expect(second,"center",8307692,-5538462);
    let crossing=scp_move(second,"center",0,0);scp_expect(crossing,"center",0,0);
    let end=scp_move(crossing,"center",23000000,-19000000);scp_expect(end,"center",18000000,-12000000);
    let reopened=scp_reopen(j_encode(end));scp_freedom(reopened,1);scp_check_saved(base,reopened,curve,relation);
    m_assert(m_eq(j_encode(scp_mesh(base)),j_encode(scp_mesh(reopened))),"Dragging a construction spline follower leaves the solid unchanged");

    let axis=j_parse(j_encode(first));
    j_add(scp_rows(axis),0,j_parse("{\"id\":\"probe-column\",\"type\":\"distance\",\"axis\":\"x\",\"a\":{\"entityId\":\"body-profile\",\"point\":\"center\"},\"b\":{\"entityId\":\"probe\",\"point\":\"center\"},\"value\":-33.692308}"));
    let lower=scp_move(axis,"center",12000000,-10000000);scp_expect(lower,"center",8307692,-5538462);scp_freedom(lower,0);

    let sketch="native-sketch-1";let anchor=j_parse("{\"entityId\":\"probe\",\"point\":\"center\"}");
    let detached=cad_project_toggle_point_on_curve(base,sketch,curve,anchor);m_assert(detached,cg_error);scp_freedom(detached,2);
    let unattached=scp_move(detached,"center",8000000,-6000000);
    let attached=cad_project_toggle_point_on_curve(unattached,sketch,curve,anchor);m_assert(attached,cg_error);
    scp_expect(attached,"center",8307692,-5538462);scp_freedom(attached,1);
    m_assert(m_eq(j_encode(pc_find(scp_rows(attached),"native-point-on-curve-probe-crossing-spline")),"{\"id\":\"native-point-on-curve-probe-crossing-spline\",\"type\":\"pointOnCurve\",\"a\":{\"entityId\":\"probe\",\"point\":\"center\"},\"b\":\"crossing-spline\"}"),"The author API saves the ordinary v4 schema without a branch field");
    m_assert(m_eq(j_encode(scp_node(attached,curve)),j_encode(scp_node(base,curve))),"Authoring leaves every Bezier control unchanged");

    j_add(scp_rows(unattached),0,j_parse("{\"id\":\"fixed-probe\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"probe\",\"point\":\"center\"},\"position\":{\"x\":8,\"y\":-6}}"));
    let locked=j_encode(unattached);
    m_assert(!cad_project_toggle_point_on_curve(unattached,sketch,curve,anchor) && cg_error && m_eq(j_encode(unattached),locked),"Incompatible fixed follower rejects authoring without mutating the input");
    let stale=j_parse(j_encode(first));pc_line_write_xy(scp_anchor(stale,"center"),cg_v(8000000,6000000,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved point is outside its curve: crossing-spline-contact"),"Manufacturing validates the true spline locus");
    m_assert(m_eq(j_encode(base),before),"Editing leaves the loaded graph unchanged");
    return 1;
}

fn scp_open_fit(source) {
    let base=scp_select(source,1);let curve="open-spline";let relation="open-spline-contact";
    scp_freedom(base,3);
    let first=scp_move(base,"p0",-42000000,-8000000);scp_expect(first,"p0",-25000000,1000000);
    let last=scp_move(first,"p0",30000000,9000000);scp_expect(last,"p0",18000000,2000000);
    let interior=scp_move(last,"p0",1000000,4000000);scp_expect(interior,"p0",-223002,2982849);
    let reopened=scp_reopen(j_encode(interior));scp_check_saved(base,reopened,curve,relation);scp_freedom(reopened,3);
    m_assert(m_eq(j_encode(scp_anchor(base,"p1")),j_encode(scp_anchor(reopened,"p1"))),"Dragging the follower endpoint keeps the opposite endpoint fixed");
    scp_mesh(reopened);return 1;
}

fn scp_periodic(source) {
    let base=scp_select(source,2);let curve="periodic-spline";let relation="periodic-spline-contact";
    scp_expect(base,"center",-20000000,0);scp_freedom(base,1);
    let after=scp_move(base,"center",-22000000,5000000);scp_expect(after,"center",-18735713,3038898);
    let before=scp_move(after,"center",-17000000,-5000000);scp_expect(before,"center",-18619286,-6122270);
    let reopened=scp_reopen(j_encode(before));scp_check_saved(base,reopened,curve,relation);scp_freedom(reopened,1);
    m_assert(m_eq(j_encode(scp_mesh(base)),j_encode(scp_mesh(reopened))),"The active periodic spline remains closed and its exported geometry is unchanged");
    return 1;
}

fn scp_move_source(base,id,index,x,y) {
    let at=pc_json_point(cg_v(x,y,0));let field=m_cat("point",m_int(index));
    let edited=cad_project_move_smooth_point(base,"native-sketch-1",ps_anchor(id,field),at);
    m_assert(edited,cg_error);let reopened=scp_reopen(j_encode(edited));
    let expected=j_parse(j_encode(scp_node(base,id)));
    let point=pc_first(j_get(j_get(expected,"spline"),"points"));let i=0;
    while i<index {point=load64(point+24);i=i+1;}
    po_position(point,cg_v(x,y,0),1);
    m_assert(m_eq(j_encode(expected),j_encode(scp_node(reopened,id))),"Moving a source point keeps every other stored control and spline field");
    m_assert(m_eq(j_encode(scp_rows(base)),j_encode(scp_rows(reopened))),"Source editing retains all original relations");
    return reopened;
}

fn scp_source_handles(source) {
    let control=scp_move(scp_select(source,0),"center",8000000,6000000);
    let reshaped=scp_move_source(control,"crossing-spline",2,6000000,8000000);
    scp_expect(reshaped,"center",7523104,6770791);
    m_assert(m_eq(j_encode(scp_mesh(control)),j_encode(scp_mesh(reshaped))),"Changing a construction control leaves the unrelated solid unchanged");

    let fit=scp_select(source,1);
    let refit=scp_move_source(fit,"open-spline",1,-8000000,15000000);
    scp_expect(refit,"p0",-20398935,7660151);
    m_assert(m_eq(j_encode(scp_anchor(fit,"p1")),j_encode(scp_anchor(refit,"p1"))),"The other endpoint of a line follower stays in place");
    let fixed=j_object();cg_j_text(fixed,"id","fixed-contact");cg_j_text(fixed,"type","fixed");
    j_add(fixed,"anchor",ps_anchor("probe","p0"));j_add(fixed,"position",j_parse(j_encode(scp_anchor(fit,"p0"))));
    j_add(scp_rows(fit),0,fixed);let snapshot=j_encode(fit);
    m_assert(!cad_project_move_smooth_point(fit,"native-sketch-1",ps_anchor("open-spline","point1"),j_parse("{\"x\":-8,\"y\":15}"))
        && m_eq(cg_error,"Conflicting or unsolved sketch constraint: open-spline-contact") && m_eq(j_encode(fit),snapshot),"An existing fixed follower rejects an incompatible source edit atomically");

    let periodic=scp_select(source,2);
    let edited=scp_move_source(periodic,"periodic-spline",0,-22000000,1000000);
    scp_expect(edited,"center",-22122922,166616);
    m_assert(!m_eq(j_encode(j_get(scp_mesh(periodic),"vertices")),j_encode(j_get(scp_mesh(edited),"vertices"))),"A changed periodic source rebuilds its active closed extrusion");
    return 1;
}

fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/point-on-spline.pcad");
    return !(scp_control(source) && scp_open_fit(source) && scp_periodic(source) && scp_source_handles(source));
}
