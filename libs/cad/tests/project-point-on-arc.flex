import "cad/author.flex";
import "cad/project-access.flex";
import "cad/project-point-on-curve-author.flex";

fn poa_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn poa_geometry(project,id) {return pc_curve_geometry(poa_node(project,id));}
fn poa_center(project,id) {return j_get(poa_geometry(project,id),"center");}
fn poa_relations(project) {return j_get(poa_node(project,"native-sketch-1"),"relations");}
fn poa_expect(row,x,y) {return m_assert(pc_line_span(pc_uv(row),cg_v(x,y,0))<=2,"The point follows the retained sweep");}

fn poa_reopen(source) {
    let report=cad_project_inspect_source(source);m_assert(report,cg_error);
    m_assert(!j_get(report,"readOnly"),j_string(report,"readOnly"));return j_get(report,"document");
}

fn poa_check_dof(project,sketch) {
    let report=cad_project_line_sketch(project,sketch);m_assert(report,cg_error);
    // One free arc orientation and one slider, including at either endpoint.
    return m_assert(j_integer(report,"degrees_of_freedom")==2 && !j_get(report,"degrees_of_freedom_is_upper_bound"),"A finite endpoint still allows sliding into its arc");
}

fn poa_clockwise(base,sk,guide,probe) {
    let saved=j_encode(base);let id="probe-on-sweep-from-web";
    poa_check_dof(base,sk);
    let shorter=cad_project_set_curve_dimension(base,sk,guide,"arcSweep","-30 deg");m_assert(shorter,cg_error);
    poa_expect(poa_center(shorter,probe),17320508,-10000000);
    let wider=cad_project_set_curve_dimension(shorter,sk,guide,"radius","25 mm");m_assert(wider,cg_error);
    poa_expect(poa_center(wider,probe),21650635,-12500000);
    let at_end=poa_reopen(j_encode(wider));poa_check_dof(at_end,sk);
    m_assert(m_eq(j_encode(pc_find(poa_relations(at_end),id)),j_encode(pc_find(poa_relations(base),id))),"Original v4 relation ID and anchors survive the dimension edit and reopen");

    let at_start=cad_project_move_point(at_end,sk,probe,j_parse("{\"x\":30,\"y\":4}"));m_assert(at_start,cg_error);
    poa_expect(poa_center(at_start,probe),25000000,0);poa_check_dof(at_start,sk);
    let interior=cad_project_move_point(at_start,sk,probe,j_parse("{\"x\":40,\"y\":-20}"));m_assert(interior,cg_error);
    poa_expect(poa_center(interior,probe),22360680,-11180340);
    let clamped=cad_project_move_point(interior,sk,probe,j_parse("{\"x\":0,\"y\":-30}"));m_assert(clamped,cg_error);
    poa_expect(poa_center(clamped,probe),21650635,-12500000);
    let solid=cad_project_add_extrusion(clamped,sk,1,10000000,"newBody");m_assert(solid,cg_error);
    let mesh=cad_project_mesh(solid);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    m_assert(m_eq(j_encode(j_get(pc_first(j_get(mesh,"parts")),"bounds")),"[[40.000000,-5.000000,0.000000],[50.000000,5.000000,10.000000]]"),"The sketch exports only its closed profile");
    let stale=j_parse(j_encode(solid));pc_line_write_xy(poa_center(stale,probe),cg_v(0,-25000000,0));
    m_assert(m_eq(j_string(cad_project_mesh(stale),"error"),"Saved point is outside its curve: probe-on-sweep-from-web"),"Off-sweep geometry is stale even on the supporting circle");

    let rows=poa_relations(at_end);pc_line_unlink(rows,pc_find(rows,"guide-center"),"");
    let moved=cad_project_move_point(at_end,sk,guide,j_parse("{\"x\":10,\"y\":5}"));m_assert(moved,cg_error);
    poa_expect(poa_center(moved,guide),10000000,5000000);poa_expect(poa_center(moved,probe),31650635,-7500000);
    let dragged=cad_project_move_point(moved,sk,probe,j_parse("{\"x\":40,\"y\":6}"));m_assert(dragged,cg_error);
    poa_expect(poa_center(dragged,guide),10000000,5000000);poa_expect(poa_center(dragged,probe),35000000,5000000);
    m_assert(m_eq(j_encode(base),saved),"A successful edit does not mutate the source document");
    return 1;
}

fn poa_branches(base,sk,guide,probe) {
    let increasing=csp_arc_range(20000000,6108652381980,349065850399);
    let decreasing=csp_arc_range(20000000,174532925199,-349065850399);
    m_assert(!csp_arc_limit(increasing,20000000,0) && !csp_arc_limit(decreasing,20000000,0),"Both signed sweeps include contact crossing angle zero");
    let counter=j_parse(j_encode(base));let rows=poa_relations(counter);
    cg_j_set(poa_geometry(counter,guide),"sweep",j_parse("1.570796326795"));
    cg_j_set(pc_find(rows,"guide-sweep"),"value",j_number(90));
    pc_line_write_xy(poa_center(counter,probe),cg_v(10000000,17320508,0));
    let upper=cad_project_set_curve_dimension(counter,sk,guide,"arcSweep","30 deg");m_assert(upper,cg_error);
    poa_expect(poa_center(upper,probe),17320508,10000000);

    let one_axis=j_parse(j_encode(base));let constraints=poa_relations(one_axis);
    j_add(constraints,0,j_parse("{\"id\":\"probe-column\",\"type\":\"distance\",\"axis\":\"x\",\"a\":{\"entityId\":\"sweep-guide\",\"point\":\"center\"},\"b\":{\"entityId\":\"probe\",\"point\":\"center\"},\"value\":10}"));
    let opposite=cad_project_set_curve_dimension(one_axis,sk,guide,"arcSweep","90 deg");m_assert(opposite,cg_error);
    poa_expect(poa_center(opposite,probe),10000000,17320508);

    let blocked=j_parse(j_encode(base));j_add(poa_relations(blocked),0,j_parse("{\"id\":\"probe-lock\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"probe\",\"point\":\"center\"},\"position\":{\"x\":10,\"y\":-17.320508}}"));
    let before=j_encode(blocked);
    m_assert(!cad_project_set_curve_dimension(blocked,sk,guide,"arcSweep","-30 deg") && cg_error,"A fixed probe outside the shortened sweep rejects the edit");
    m_assert(m_eq(j_encode(blocked),before),"A rejected edit keeps the previous sweep and point");

    let anchor=j_parse("{\"entityId\":\"probe\",\"point\":\"center\"}");
    let free=cad_project_toggle_point_on_curve(counter,sk,guide,anchor);m_assert(free,cg_error);
    free=cad_project_move_point(free,sk,probe,j_parse("{\"x\":-6,\"y\":-1}"));m_assert(free,cg_error);
    let attached=cad_project_toggle_point_on_curve(free,sk,guide,anchor);m_assert(attached,cg_error);
    poa_expect(poa_center(attached,probe),0,20000000);
    m_assert(m_eq(j_encode(pc_find(poa_relations(attached),"native-point-on-curve-probe-sweep-guide")),"{\"id\":\"native-point-on-curve-probe-sweep-guide\",\"type\":\"pointOnCurve\",\"a\":{\"entityId\":\"probe\",\"point\":\"center\"},\"b\":\"sweep-guide\"}"),"The writer uses the standard saved relation");
    return 1;
}

fn main() {
    let base=poa_reopen(m_read_file("libs/cad/tests/fixtures/point-on-arc.pcad"));
    return !(poa_clockwise(base,"native-sketch-1","sweep-guide","probe") && poa_branches(base,"native-sketch-1","sweep-guide","probe"));
}
