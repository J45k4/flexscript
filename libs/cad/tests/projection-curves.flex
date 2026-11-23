import "cad/projection-author.flex";

fn projection_curve_frame() {
    let frame=m_take(32);store64(frame,cg_v(0,0,0));store64(frame+8,cg_v(1000000000,0,0));
    store64(frame+16,cg_v(0,1000000000,0));store64(frame+24,cg_v(0,0,1000000000));return frame;
}

fn projection_curve_edge(edges,a,b,straight) {
    let edge=m_take(56);store64(edge,a);store64(edge+8,b);store64(edge+48,straight);
    cg_push(edges,edge);return edge;
}

fn projection_curve_loop(edges,points,straight) {
    let i=0;while i<cg_count(points) {
        projection_curve_edge(edges,cg_at(points,i),cg_at(points,(i+1)%cg_count(points)),straight);i=i+1;
    }
    return 1;
}

fn projection_curve_cap() {
    let project=cad_project_new("D prism");let source="native-sketch-1";
    let left=cg_v(-20000000,0,0);let right=cg_v(20000000,0,0);
    m_assert(cad_project_add_primitive(project,source,"line",left,right),cg_error);
    let points=cg_array();cg_push(points,right);cg_push(points,cg_v(0,20000000,0));cg_push(points,left);
    m_assert(cad_project_add_curve(project,source,"arc",points),cg_error);
    project=cad_project_add_extrusion(project,source,1,10000000,"newBody");m_assert(project,cg_error);
    let face=cad_project_pick_face(project,cg_v(0,10000000,50000000),cg_v(0,0,-1000000000));m_assert(face,cg_error);
    project=cad_project_add_face_sketch(project,face);m_assert(project,cg_error);
    let sketch="native-sketch-2";
    project=cad_project_project_face_edges(project,sketch);m_assert(project,cg_error);
    let nodes=pc_nodes(cad_project_part(project));let view=pc_find(nodes,sketch);let links=j_get(view,"relations");
    m_assert(cg_j_count(links)==2,"Project both components of the D-shaped cap");
    let link=pc_first(links);let lines=0;let arcs=0;
    while link {
        let target=pc_find(nodes,j_string(link,"entityId"));
        if m_eq(j_string(target,"type"),"sketchLine") {lines=lines+1;}
        if pc_circular_arc(target) {
            arcs=arcs+1;
            let path=pc_curve_path(target);m_assert(path && cg_count(path)==65,"Preserve 64 chords at half-turn sweep");
        }
        link=load64(link+24);
    }
    m_assert(lines==1 && arcs==1,"The projected profile has one line and one arc");
    m_assert(cad_project_add_extrusion(project,sketch,1,2000000,"newBody"),cg_error);
    return 1;
}

fn main() {
    cg_begin();let frame=projection_curve_frame();let edges=cg_array();
    let center=cg_v(3000000,-4000000,0);let radius=10000000;
    let corners=pc_ellipse_samples(center,30000000,30000000,0,0,6283185307180,16,0);
    projection_curve_loop(edges,corners,1);
    let rim=pc_ellipse_samples(center,radius,radius,0,0,6283185307180,32,0);
    projection_curve_loop(edges,rim,0);
    let candidates=pc_projection_face_curves(edges,frame);m_assert(candidates,cg_error);
    m_assert(cg_count(candidates)==17,"Keep all 16 straight polygon sides and recover one circular rim");
    let i=0;while i<16 {
        let segment=cg_at(candidates,i);
        m_assert(load64(segment+32)==1 && load64(segment+16)==cg_at(edges,i),"Preserve straight edge order");
        m_assert(cg_distance2(load64(segment),cg_at(corners,i))==0,"Preserve straight edge orientation");i=i+1;
    }
    let circle=cg_at(candidates,16);
    m_assert(load64(circle+32)==2 && load64(circle+56)==32,"Recover a closed loop of 32 curved chords");
    m_assert(pc_line_span(load64(circle+40),center)<=2 && cg_abs(load64(circle+48)-radius)<=2,"Fit circle center and radius");

    let arc=pc_ellipse_samples(cg_v(0,0,0),radius,radius,0,0,3141592653590,12,1);
    edges=cg_array();i=12;while i>0 {
        projection_curve_edge(edges,cg_at(arc,i),cg_at(arc,i-1),0);i=i-1;
    }
    candidates=pc_projection_face_curves(edges,frame);m_assert(candidates,cg_error);
    m_assert(cg_count(candidates)==1,"Join an open circular run");
    let candidate=cg_at(candidates,0);
    m_assert(load64(candidate+32)==3 && load64(candidate+56)==12,"Preserve circular arc chord count");
    m_assert(cg_distance2(load64(candidate),cg_at(arc,12))==0 && cg_distance2(load64(candidate+8),cg_at(arc,0))==0,"Preserve source arc winding");
    m_assert(cg_abs(f64_to_i64_round(f64_mul(load64(candidate+72),f64_from_i64(1000000)))+3141593)<=1,"Report negative radian sweep");

    let ellipse=pc_ellipse_samples(center,radius,radius/2,0,0,6283185307180,24,0);
    edges=cg_array();projection_curve_loop(edges,ellipse,0);
    candidates=pc_projection_face_curves(edges,frame);m_assert(candidates,cg_error);
    m_assert(cg_count(candidates)==24,"Keep the source chords when they do not form a circle");
    projection_curve_cap();
    return 0;
}
