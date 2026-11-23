import "cad/author.flex";

fn main() {
    let p=cad_project_new("Arcs");let id="native-sketch-1";
    let points=cg_array();cg_push(points,cg_v(10000000,0,0));cg_push(points,cg_v(-10000000,0,0));cg_push(points,cg_v(0,10000000,0));
    let arc=cad_project_add_curve(p,id,"arc",points);m_assert(arc,cg_error);
    let meta=j_get(arc,"arc");let samples=pc_curve_path(arc);
    m_assert(pc_pose_number(j_get(meta,"sweep"))< -4700000 && cg_count(samples)==97,"Three clicks select the clockwise major arc");
    let end=cg_at(samples,96);m_assert(load64(end)==0 && load64(end+8)==10000000,"The arc terminates on its last pick");
    let original=j_encode(p);let bad=cg_array();cg_push(bad,cg_v(0,0,0));cg_push(bad,cg_v(1,1,0));cg_push(bad,cg_v(2,2,0));
    m_assert(!cad_project_add_curve(p,id,"arc",bad) && cg_error && m_eq(original,j_encode(p)),"Rejected arc preserves drawing");
    m_assert(!cad_project_add_curve(p,id,"control",points) && cg_error && m_eq(original,j_encode(p)),"Rejected control spline preserves drawing");
    cg_begin();let fixture=j_parse("{\"id\":\"curve\",\"type\":\"sketchSpline\",\"spline\":{\"id\":\"curve\",\"type\":\"spline\",\"mode\":\"fit\",\"closed\":false,\"points\":[{\"x\":2.25e1,\"y\":0},{\"x\":31.123456789,\"y\":10},{\"x\":40,\"y\":0}]}}");
    let path=pc_curve_path(fixture);m_assert(path,cg_error);let i=0;let knot=0;
    while i<cg_count(path) {let pt=cg_at(path,i);if load64(pt)==31123457 && load64(pt+8)==10000000 {knot=1;}i=i+1;}
    m_assert(knot && load64(cg_at(path,0))==22500000 && load64(cg_at(path,cg_count(path)-1))==40000000,"Natural spline passes through all serialized knots");
    cad_project_add_primitive(p,id,"line",cg_at(points,2),cg_at(points,0));
    let extruded=cad_project_add_extrusion(p,id,1,5000000,"newBody");m_assert(extruded,cg_error);
    let mesh=cad_project_mesh(extruded);m_assert(j_value(j_get(mesh,"closed")),"A major arc and its chord close a solid");
    return 0;
}
