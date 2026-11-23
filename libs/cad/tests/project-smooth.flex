import "cad/project-access.flex";
import "cad/project-smooth-author.flex";
fn main(){
    let data=m_read_file("libs/cad/tests/fixtures/tangent-arc.pcad");let report=cad_project_inspect_source(data);
    m_assert(report,"Read tangent arc fixture");if j_get(report,"readOnly") {m_print(2,j_string(report,"readOnly"));return 1;}
    let p=j_get(report,"document");let sk="native-sketch-1";let line="native-entity-1";let arc="native-entity-2";let spline="native-entity-3";
    let a=ps_anchor(line,"p1");let b=ps_anchor(arc,"p0");let end=ps_anchor(spline,"point2");
    let shifted=cad_project_move_smooth_point(p,sk,a,j_parse("{\"x\":50,\"y\":0}"));m_assert(shifted,cg_error);
    let moved=pc_nodes(cad_project_part(shifted));let f=ps_endpoint(pc_find(moved,spline),"point0");
    m_assert(pc_line_span(load64(f),cg_v(70000000,20000000,0))<5,"Moving a line carries both downstream curves");
    shifted=cad_project_move_smooth_point(shifted,sk,ps_anchor(spline,"point1"),j_parse("{\"x\":65,\"y\":42}"));m_assert(shifted,cg_error);
    shifted=cad_project_move_smooth_point(shifted,sk,ps_anchor(arc,"p1"),j_parse("{\"x\":62,\"y\":18}"));m_assert(shifted,cg_error);
    f=ps_endpoint(pc_find(pc_nodes(cad_project_part(shifted)),arc),"p1");m_assert(pc_line_span(load64(f),cg_v(62000000,18000000,0))<10,"Arc endpoint tracks target while preserving both joins");
    let original=j_encode(p);let invalid=cad_project_add_tangent_arc(p,sk,a,j_parse("{\"x\":50,\"y\":0}"));m_assert(!invalid && m_eq(j_encode(p),original),"Reject tangent-line target atomically");
    cg_begin();let line_node=pc_find(pc_nodes(cad_project_part(p)),line);let axis=ps_endpoint(line_node,"p0");
    let side=-1;while side<=1 {
        let geom=ps_tangent_arc("test",axis,cg_v(-10000000,side*10000000,0));m_assert(geom,cg_error);
        let arc_node=j_object();cg_j_text(arc_node,"type","sketchArc");j_add(arc_node,"arc",geom);
        m_assert(ps_matches(axis,ps_endpoint(arc_node,"p0")),"Either sweep is tangent at its start");
        m_assert(pc_line_span(load64(ps_endpoint(arc_node,"p1")),cg_v(-10000000,side*10000000,0))<5,"Both sweep directions end at their target");
        side=side+2;
    }
    let control=j_parse("{\"type\":\"sketchSpline\",\"spline\":{\"mode\":\"control\",\"points\":[{\"x\":0,\"y\":0},{\"x\":1,\"y\":0},{\"x\":2,\"y\":2},{\"x\":2,\"y\":3}]}}");
    let begin=ps_endpoint(control,"point0");let finish=ps_endpoint(control,"point3");
    m_assert(load64(begin+8)==f64_from_i64(-1) && !load64(begin+16),"Control start follows first handle");
    m_assert(!load64(finish+8) && load64(finish+16)==f64_from_i64(1),"Control end follows last handle");
    cg_j_int(load64(pc_first(j_get(j_get(control,"spline"),"points"))+24),"x",0);
    m_assert(!ps_endpoint(control,"point0"),"Stationary spline endpoint cannot define a tangent");
    let added=cad_project_add_tangent_arc(p,sk,end,j_parse("{\"x\":35,\"y\":67}"));m_assert(added,cg_error);
    let nodes=pc_nodes(cad_project_part(added));let frame=ps_endpoint(pc_find(nodes,"native-entity-4"),"p1");
    m_assert(pc_line_span(load64(frame),cg_v(35000000,67000000,0))<5,"New tangent arc lands on target");
    let detached=cad_project_toggle_smooth_join(p,sk,a,b);m_assert(detached,cg_error);nodes=pc_nodes(cad_project_part(detached));
    m_assert(cg_j_count(j_get(pc_find(nodes,sk),"relations"))==1,"Remove join without deleting curves");
    let other=ps_anchor(line,"p0");let joined=cad_project_toggle_smooth_join(detached,sk,other,b);m_assert(joined,cg_error);
    nodes=pc_nodes(cad_project_part(joined));let at=pc_uv(j_get(j_get(pc_find(nodes,arc),"arc"),"center"));
    m_assert(cg_abs(load64(at))<2 && cg_abs(load64(at+8)+20000000)<2,"Follower chain rotates about the chosen line end");
    let damaged=j_parse(j_encode(joined));nodes=pc_nodes(cad_project_part(damaged));let points=j_get(j_get(pc_find(nodes,spline),"spline"),"points");
    cg_j_int(load64(pc_first(points)+24),"x",15);
    m_assert(j_get(cad_project_inspect_source(j_encode(damaged)),"readOnly"),"Disagreeing spline tangent cannot open for editing");
    return 0;
}
