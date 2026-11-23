import "cad/projection-author.flex";
import "../project-lines.flex";

fn projection_part() {
    let project=cad_project_new("Projected side");
    let a=cg_v(-80000000,-50000000,0);let b=cg_v(80000000,50000000,0);
    m_assert(cad_project_add_primitive(project,"native-sketch-1","rectangle",a,b),m_cat("Create rectangle: ",cg_error));
    project=cad_project_add_extrusion(project,"native-sketch-1",1,60000000,"newBody");m_assert(project,m_cat("Extrude block: ",cg_error));
    let face=cad_project_pick_face(project,cg_v(0,-200000000,30000000),cg_v(0,1000000000,0));
    m_assert(face,cg_error);m_assert(pc_face_number(face)==1,m_cat("Expected the front side face, got ",m_int(pc_face_number(face))));
    return cad_project_add_face_sketch(project,face);
}

fn projection_relations(project) {
    let sketch=pc_find(pc_nodes(cad_project_part(project)),"native-sketch-2");
    return j_get(sketch,"relations");
}

fn projection_max_height(project) {
    let nodes=pc_nodes(cad_project_part(project));let relation=pc_first(projection_relations(project));let height=0;
    while relation {
        let line=pc_find(nodes,j_string(relation,"entityId"));
        let a=load64(pc_uv(j_get(line,"p0"))+8);let b=load64(pc_uv(j_get(line,"p1"))+8);
        if a>height {height=a;}if b>height {height=b;}
        relation=load64(relation+24);
    }
    return height;
}

fn check_face_projection(project) {
    let sketch="native-sketch-2";let saved=j_encode(project);
    let projected=cad_project_project_face_edges(project,sketch);m_assert(projected,m_cat("Use face edges: ",cg_error));
    m_assert(m_eq(saved,j_encode(project)),"Authoring leaves the input untouched");
    let relations=projection_relations(projected);let row=pc_first(relations);
    m_assert(cg_j_count(relations)==4 && projection_max_height(projected)==60000000,"Four fixed side lines");
    while row {
        m_assert(m_eq(j_string(row,"type"),"projected") && m_eq(j_string(row,"sketchId"),sketch)
            && m_eq(j_string(row,"sourceFaceId"),"native-extrude-1-solid-face-1"),"Rust-compatible face reference");
        row=load64(row+24);
    }
    let report=cad_project_line_sketch(projected,sketch);
    m_assert(report && j_integer(report,"degrees_of_freedom")==0,"Projection endpoints are locked");
    let nodes=pc_nodes(cad_project_part(projected));let face_sketch=pc_find(nodes,sketch);
    let snap=cad_sketch_snap_projected_edges(nodes,face_sketch,cg_v(35000000,60750000,0),1500000);
    m_assert(snap && load64(snap)==35000000 && load64(snap+8)==60000000,"Pick snaps to the projected edge");
    m_assert(!cad_sketch_snap_projected_edges(nodes,face_sketch,cg_v(35000000,60750000,0),500000),"Outside snap tolerance");
    let line=j_string(pc_first(relations),"entityId");
    m_assert(!cad_project_move_line_endpoint(projected,sketch,line,"p0",cg_v(0,1000000,0)),"A projected line cannot be dragged");
    let encoded=j_encode(projected);
    m_assert(!cad_project_project_face_edges(projected,sketch) && m_eq(encoded,j_encode(projected)),"Repeated Use edges is atomic");

    let cut=cad_project_add_extrusion(projected,sketch,1,5000000,"cut");m_assert(cut,m_cat("Cut projected profile: ",cg_error));
    let edit=cad_project_set_extrusion_options(cut,"native-extrude-1",80000000,"newBody","blind",0,"");
    m_assert(edit,m_cat("Change supporting depth: ",cg_error));
    let before_rebuild=j_encode(edit);
    let mesh=cad_project_mesh(edit);m_assert(!j_get(mesh,"error"),m_cat("Rebuild the linked cut: ",cg_error));
    m_assert(m_eq(before_rebuild,j_encode(edit)),"Evaluating a cut never mutates its source document");
    let enlarged=cad_project_rebuild_projections(edit);m_assert(enlarged,cg_error);
    m_assert(projection_max_height(enlarged)==80000000,"Face lines follow the resized source");
    m_assert(m_eq(j_encode(relations),j_encode(projection_relations(enlarged))),"Source edit preserves all face and entity IDs");
    let body=pc_first(j_get(mesh,"parts"));let low=pc_edge_vector(pc_first(j_get(body,"bounds")));
    m_assert(load64(low+8)==-45000000,"The cut removes the original side, without feedback");
    let again=cad_project_rebuild_projections(enlarged);
    m_assert(again && m_eq(j_encode(again),j_encode(enlarged)),"Rebuild is idempotent");
}

fn check_edge_projection(project) {
    let sketch="native-sketch-2";let point=cg_v(80000000,60000000,0);
    let saved=j_encode(project);let guides=cad_project_projection_guides(project,sketch);
    m_assert(guides && cg_count(guides)>=4 && m_eq(saved,j_encode(project)),"Read-only guides show straight body edges");
    let projected=cad_project_project_edge(project,sketch,point,100000);
    m_assert(projected,m_cat("Use one body edge: ",cg_error));
    let old=pc_first(projection_relations(projected));let edge=j_get(old,"sourceEdge");
    m_assert(cg_j_count(projection_relations(projected))==1 && !j_get(old,"sourceFaceId")
        && cg_j_count(j_get(edge,"normals"))==2 && load64(pc_edge_vector(j_get(edge,"via"))+16)==60000000,
        "One straight edge with world-space midpoint");
    let edit=cad_project_set_extrusion_options(projected,"native-extrude-1",80000000,"newBody","blind",0,"");
    m_assert(edit,m_cat("Resize source of an edge: ",cg_error));
    let resized=cad_project_rebuild_projections(edit);m_assert(resized,cg_error);
    m_assert(projection_max_height(resized)==80000000,"Single projected edge follows the resized source");
    let next=pc_first(projection_relations(resized));
    m_assert(m_eq(j_string(old,"id"),j_string(next,"id")) && m_eq(j_string(old,"entityId"),j_string(next,"entityId"))
        && load64(pc_edge_vector(j_get(j_get(next,"sourceEdge"),"via"))+16)==80000000,"A translated edge retains its linked identity");
}

fn projection_top_sketch(project,x,y) {
    let face=cad_project_pick_face(project,cg_v(x,y,150000000),cg_v(0,0,-1000000000));
    m_assert(face,cg_error);let attached=cad_project_add_face_sketch(project,face);m_assert(attached,cg_error);
    return attached;
}

fn check_circle_projection() {
    let base="native-sketch-1";let sketch="native-sketch-2";
    let source=cad_project_new("Projected disk");
    m_assert(cad_project_add_primitive(source,base,"circle",cg_v(0,0,0),cg_v(10000000,0,0)),cg_error);
    source=cad_project_add_extrusion(source,base,1,20000000,"newBody");m_assert(source,cg_error);
    source=projection_top_sketch(source,0,0);
    let projected=cad_project_project_face_edges(source,sketch);m_assert(projected,cg_error);
    let refs=projection_relations(projected);let id=j_string(pc_first(refs),"entityId");
    let graph=pc_nodes(cad_project_part(projected));let node=pc_find(graph,id);
    m_assert(cg_j_count(refs)==1 && pc_sketch_circle(node),"The cap rim becomes one projected circle");
    m_assert(cg_abs(pc_circle_measure(node,"radius")-10000000)<=10 && j_integer(pc_curve_geometry(node),"segments")==48,
        "Preserve rim radius and tessellation");
    let report=cad_project_line_sketch(projected,sketch);
    m_assert(report && j_integer(report,"degrees_of_freedom")==0,"Projected circle has zero degrees of freedom");
    m_assert(!cad_project_move_point(projected,sketch,id,j_parse("{\"x\":4,\"y\":3}")),"Projected center cannot move independently");
    m_assert(!cad_project_set_circle_dimension(projected,sketch,id,"diameter","22"),"Projected radius cannot be driven independently");
    m_assert(!cad_project_project_face_edges(projected,sketch) && m_eq(cg_error,"No new face edges to project"),"Repeated projection skips the circle");
    let cut=cad_project_add_extrusion(projected,sketch,1,5000000,"cut");m_assert(cut,cg_error);
    let changed=cad_project_set_circle_dimension(cut,base,"native-entity-1","diameter","26");m_assert(changed,cg_error);
    let cached=j_encode(changed);let mesh=cad_project_mesh(changed);
    m_assert(mesh && cg_stl(mesh) && m_eq(cached,j_encode(changed)),"Cut evaluates against the new rim from a scratch copy");
    let rebuilt=cad_project_rebuild_projections(changed);m_assert(rebuilt,cg_error);
    let resized=pc_find(pc_nodes(cad_project_part(rebuilt)),id);
    m_assert(cg_abs(pc_circle_measure(resized,"radius")-13000000)<=10 && m_eq(j_encode(refs),j_encode(projection_relations(rebuilt))),
        "Changing the source diameter updates the linked rim with stable IDs");
    let bounds=j_get(pc_first(j_get(mesh,"parts")),"bounds");
    let top=pc_edge_vector(load64(pc_first(bounds)+24));
    m_assert(cg_abs(load64(top)-13000000)<=10 && load64(top+16)==15000000,"Machining follows the resized circle");
    let again=cad_project_rebuild_projections(rebuilt);
    m_assert(again && m_eq(j_encode(rebuilt),j_encode(again)),"Projected-circle rebuild is idempotent");
}

fn check_arc_projection() {
    let base="native-sketch-1";let sketch="native-sketch-2";
    let source=cad_project_new("Projected semicircle");let points=cg_array();
    let right=cg_v(20000000,0,0);let left=cg_v(-20000000,0,0);
    cg_push(points,right);cg_push(points,cg_v(0,20000000,0));cg_push(points,left);
    m_assert(cad_project_add_curve(source,base,"arc",points),cg_error);
    m_assert(cad_project_add_primitive(source,base,"line",left,right),cg_error);
    source=cad_project_add_extrusion(source,base,1,20000000,"newBody");m_assert(source,cg_error);
    let projected=cad_project_project_face_edges(projection_top_sketch(source,0,5000000),sketch);
    m_assert(projected,cg_error);
    let nodes=pc_nodes(cad_project_part(projected));let refs=projection_relations(projected);let arcs=0;
    let rel=pc_first(refs);while rel {
        let entity=pc_find(nodes,j_string(rel,"entityId"));
        if pc_circular_arc(entity) {
            let sampled=pc_arc_path(entity);
            m_assert(sampled && cg_count(sampled)==65 && cg_abs(pc_circle_measure(entity,"radius")-20000000)<=10,"Projected arc matches the source tessellation and radius");
            arcs=arcs+1;
        }
        rel=load64(rel+24);
    }
    m_assert(cg_j_count(refs)==2 && arcs==1,"Retain the chord and native circular arc");
    let report=cad_project_line_sketch(projected,sketch);
    m_assert(report && j_integer(report,"degrees_of_freedom")==0,"Projected arc center and shape are locked");
    let cut=cad_project_add_extrusion(projected,sketch,1,5000000,"cut");m_assert(cut,cg_error);
    m_assert(cg_stl(cad_project_mesh(cut)),cg_error);
}

fn main() {
    let project=projection_part();m_assert(project,m_cat("Create side face sketch: ",cg_error));
    check_face_projection(project);
    check_edge_projection(project);
    check_circle_projection();
    check_arc_projection();
    return 0;
}
