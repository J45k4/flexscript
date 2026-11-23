import "cad/project-pattern-author.flex";
import "cad/project-access.flex";
fn node(p,id) {return pc_find(pc_nodes(cad_project_part(p)),id);}
fn xy(p,id,field,x,y) {
    let n=node(p,id);if m_eq(field,"center") {n=pc_curve_geometry(n);}let at=pc_uv(j_get(n,field));
    return cg_abs(load64(at)-x*1000000)<20 && cg_abs(load64(at+8)-y*1000000)<20;
}
fn main() {
    let p=cad_project_open(m_read_file("libs/cad/tests/fixtures/patterns.pcad"));let sk="native-sketch-1";
    let grid="linear-pattern-1";let ring="circular-pattern-1";
    let report=cad_project_line_sketch(p,sk);m_assert(report,cg_error);
    m_assert(j_integer(report,"degrees_of_freedom")==9 && cg_j_count(j_get(report,"patterns"))==2,"Only the line, point and source circle are free");
    p=cad_project_set_circle_dimension(p,sk,"native-entity-1","radius","5");m_assert(p,cg_error);
    m_assert(pc_circle_measure(node(p,"native-entity-6"),"radius")==5000000,"Radius drives all six disks");
    let original=j_encode(p);m_assert(!cad_project_set_circle_dimension(p,sk,"native-entity-2","radius","8"),"A copy cannot drive its source");
    m_assert(!cad_project_set_pattern(p,sk,grid,j_parse("{\"columns\":32,\"rows\":2}")) && m_eq(j_encode(p),original),"Oversized edit is atomic");
    p=cad_project_set_pattern(p,sk,grid,j_parse("{\"columns\":2,\"rows\":3,\"step\":{\"x\":25,\"y\":0},\"rowStep\":{\"x\":0,\"y\":12}}"));m_assert(p,cg_error);
    m_assert(xy(p,"native-entity-4","center",10,22) && xy(p,"native-entity-5","center",35,22) && !node(p,"native-entity-3"),"Grid keeps surviving row/column IDs");
    p=cad_project_move_pattern_center(p,sk,ring,j_parse("{\"x\":10,\"y\":55}"));m_assert(p,cg_error);
    m_assert(xy(p,"native-entity-9","p0",35,45) && xy(p,"native-entity-9","p1",35,55),"Circular pattern follows center anchor");
    p=cad_project_set_pattern(p,sk,ring,j_parse("{\"count\":3,\"angle\":-180}"));m_assert(p,cg_error);
    m_assert(xy(p,"native-entity-10","p0",20,80) && !node(p,"native-entity-11"),"Partial turn includes its last angle");
    let q=cad_project_new("New grid");cad_project_add_primitive(q,sk,"line",cg_v(10000000,0,0),cg_v(20000000,0,0));
    q=cad_project_add_pattern(q,sk,j_parse("[\"native-entity-1\"]"),j_parse("{\"type\":\"circularPattern\",\"count\":3,\"angle\":90}"));m_assert(q,cg_error);
    m_assert(xy(q,"native-entity-3","p1",0,20),"Create an open circular pattern");
    q=cad_project_move_line_endpoint(q,sk,"native-entity-1","p1",j_parse("{\"x\":24,\"y\":2}"));m_assert(q,cg_error);
    m_assert(xy(q,"native-entity-3","p1",-2,24),"Line edit rotates through to copy");
    let path=cg_array();cg_push(path,cg_v(0,0,0));cg_push(path,cg_v(0,8000000,0));cg_push(path,cg_v(4000000,10000000,0));
    m_assert(cad_project_add_curve(q,sk,"fit",path),cg_error);
    let anchored=cad_project_set_pattern(q,sk,ring,j_parse("{\"centerAnchor\":{\"entityId\":\"native-entity-4\",\"point\":\"point1\"}}"));m_assert(anchored,cg_error);
    let before=j_encode(anchored);
    anchored=cad_project_move_pattern_center(anchored,sk,ring,j_parse("{\"x\":5,\"y\":6}"));m_assert(anchored,cg_error);
    m_assert(xy(anchored,"native-entity-3","p1",9,25),"Circular copies rotate around the moved fit point");
    let rr=pc_find(j_get(node(anchored,sk),"relations"),ring);let center=pp_anchor(pc_nodes(cad_project_part(anchored)),sk,j_get(rr,"centerAnchor"));
    m_assert(pc_pose_number(j_get(center,"x"))==5000000 && pc_pose_number(j_get(center,"y"))==6000000 && !m_eq(j_encode(anchored),before),"Retain the spline anchor and its new coordinates");
    before=j_encode(anchored);m_assert(!cad_project_move_pattern_center(anchored,sk,ring,j_parse("{\"x\":0,\"y\":0}")) && m_eq(before,j_encode(anchored)),"Coincident adjacent fit points reject the edit atomically");
    let damaged=j_parse(j_encode(q));cg_j_int(j_get(node(damaged,"native-entity-3"),"p1"),"x",5);
    m_assert(j_get(cad_project_inspect_source(j_encode(damaged)),"readOnly"),"Stale pattern copy opens read-only");
    return 0;
}
