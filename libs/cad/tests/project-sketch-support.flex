import "cad/author.flex";
import "cad/projection-author.flex";

fn support_face(source,number) {
    let face=j_object();cg_j_text(face,"sourceId",source);
    cg_j_text(face,"faceId",m_cat(source,m_cat("-solid-face-",m_int(number))));return face;
}
fn support_sketch(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}

fn main() {
    let first="native-sketch-1";let second="native-sketch-2";
    let project=cad_project_new("Sketch support changes");
    let base=cad_project_add_primitive(project,first,"rectangle",cg_v(-20000000,-15000000,0),cg_v(20000000,15000000,0));
    m_assert(base,cg_error);
    project=cad_project_add_extrusion(project,first,1,8000000,"newBody");m_assert(project,cg_error);
    let top=support_face("native-extrude-1",6);let side=support_face("native-extrude-1",1);
    let projection=cad_project_add_face_sketch(project,side);m_assert(projection,cg_error);
    projection=cad_project_project_face_edges(projection,second);m_assert(projection,cg_error);
    let before_projection=j_encode(projection);
    m_assert(!cad_project_set_sketch_support(projection,second,"XY",0)
        && m_eq(cg_error,"Sketch support would lose a projected edge"),"Reject collapsing live projected edges");
    m_assert(m_eq(j_encode(projection),before_projection),"Projected links and geometry unchanged after rejection");

    project=cad_project_add_plane_sketch(project,"YZ");m_assert(project,cg_error);
    let shape=cad_project_add_primitive(project,second,"rectangle",cg_v(-3000000,-2000000,0),cg_v(3000000,2000000,0));
    m_assert(shape,cg_error);let shape_id=j_string(shape,"id");let shape_json=j_encode(shape);
    cg_j_text(support_sketch(project,second),"legacyAnnotation","preserved");
    project=cad_project_add_extrusion(project,second,1,4000000,"newBody");m_assert(project,cg_error);
    let source_id="native-extrude-2";
    let consumer=support_sketch(project,source_id);let consumer_json=j_encode(consumer);
    let original=j_encode(project);
    m_assert(cad_project_set_sketch_support(project,second,"YZ",0)==project,"Selecting current plane requires no edit");
    m_assert(!cad_project_set_sketch_support(project,first,"",top),"A sketch cannot depend on its own extrusion");
    m_assert(!cad_project_set_sketch_support(project,second,"",support_face(source_id,6)),"The consuming extrusion cannot support its sketch");
    m_assert(!cad_project_set_sketch_support(project,second,"",support_face("native-extrude-1",99)),"Reject a stale face selector");
    m_assert(m_eq(j_encode(project),original),"All invalid attempts are atomic");

    let attached=cad_project_set_sketch_support(project,second,"",top);m_assert(attached,cg_error);
    let changed=support_sketch(attached,second);let target=j_string(changed,"targetId");
    m_assert(m_eq(j_string(support_sketch(attached,target),"faceId"),j_string(top,"faceId")),"Persistent attachment updated");
    m_assert(m_eq(j_string(changed,"legacyAnnotation"),"preserved"),"Keep opaque sketch metadata");
    m_assert(m_eq(j_encode(support_sketch(attached,shape_id)),shape_json),"Keep all authored sketch coordinates and IDs");
    m_assert(m_eq(j_encode(support_sketch(attached,source_id)),consumer_json),"Consumer profile and feature IDs preserved");
    m_assert(cad_project_set_sketch_support(attached,second,"",top)==attached,"Selecting current face requires no edit");
    m_assert(!cad_project_set_sketch_support(attached,first,"",support_face(source_id,6)),"Reject a transitive support cycle");
    let reopened=cad_project_open(j_encode(attached));
    let preview=cad_project_sketch_support_stage(reopened,second);m_assert(preview,cg_error);
    let visible=cad_project_pick_face(preview,cg_v(0,0,100000000),cg_v(0,0,-1000000000));
    m_assert(visible && m_eq(j_string(visible,"faceId"),j_string(top,"faceId")),"Only faces before the consumer are pickable");
    let bodies=pc_part_bodies(cad_project_part(reopened));m_assert(!cg_error && cg_count(bodies)==2,cg_error);
    let bounds=ca_bounds(load64(cg_at(bodies,1)+24));
    m_assert(load64(bounds)==-3000000 && load64(bounds+8)==-2000000 && load64(bounds+16)==8000000
        && load64(bounds+24)==3000000 && load64(bounds+32)==2000000 && load64(bounds+40)==12000000,"Rebuild the same profile from the cap");

    let rolled=cad_project_roll_to(attached,0);m_assert(rolled,cg_error);
    preview=cad_project_sketch_support_stage(rolled,second);m_assert(preview,cg_error);
    m_assert(!j_get(cad_project_feature_history(preview),"mesh"),"Picker preserves an earlier rollback");
    let moved=cad_project_set_sketch_support(rolled,second,"XZ",0);m_assert(moved,cg_error);
    m_assert(m_eq(j_string(support_sketch(moved,second),"targetId"),"plane-front"),"Reuse existing plane node");
    m_assert(j_integer(j_get(j_get(cad_project_part(moved),"data"),"tree"),"rollbackIndex")==0,"Preserve rollback bar");
    moved=cad_project_roll_to(moved,2);m_assert(moved,cg_error);
    bodies=pc_part_bodies(cad_project_part(moved));m_assert(!cg_error && cg_count(bodies)==2,cg_error);
    bounds=ca_bounds(load64(cg_at(bodies,1)+24));
    m_assert(load64(bounds)==-3000000 && load64(bounds+8)==0 && load64(bounds+16)==-2000000
        && load64(bounds+24)==3000000 && load64(bounds+32)==4000000 && load64(bounds+40)==2000000,"Reference plane rotates the same profile");
    let broken=cad_project_open(original);
    cg_j_text(support_sketch(broken,second),"targetId","missing-support");
    m_assert(j_get(cad_project_mesh(broken),"error"),"Missing saved support prevents manufacture");
    let repaired=cad_project_set_sketch_support(broken,second,"XZ",0);m_assert(repaired,cg_error);
    m_assert(!j_get(cad_project_mesh(repaired),"error"),"Reattaching repairs an unresolved saved support");
    m_assert(m_eq(j_encode(project),original),"Success leaves the source graph intact");
    return 0;
}
