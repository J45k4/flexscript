import "cad/projection-author.flex";

fn deletion_plate() {
    let project=cad_project_new("Delete feature");
    m_assert(cad_project_add_primitive(project,"native-sketch-1","rectangle",cg_v(0,0,0),cg_v(20000000,20000000,0)),cg_error);
    project=cad_project_add_extrusion(project,"native-sketch-1",1,20000000,"newBody");m_assert(project,cg_error);
    return project;
}
fn deletion_another_profile(project,low,high) {
    project=cad_project_add_plane_sketch(project,"XY");m_assert(project,cg_error);
    m_assert(cad_project_add_primitive(project,"native-sketch-2","rectangle",low,high),cg_error);
    return project;
}
fn deletion_tree(project) {return j_get(j_get(cad_project_part(project),"data"),"tree");}

fn check_delete_and_reopen() {
    let original=deletion_plate();let encoded=j_encode(original);let body="native-extrude-1";
    let updated=cad_project_delete_feature(original,body);m_assert(updated,cg_error);
    m_assert(m_eq(j_encode(original),encoded),"Deleting a feature leaves the original snapshot unchanged");
    let reopened=cad_project_open(j_encode(updated));m_assert(reopened,cg_error);
    let graph=j_get(j_get(cad_project_part(reopened),"data"),"cad");
    m_assert(!pc_find(j_get(graph,"nodes"),body),"The deleted feature is absent from the reopened CAD graph");
    let ids=j_encode(j_get(graph,"rootNodeIds"));
    m_assert(m_eq(ids,"[\"plane-top\",\"plane-front\",\"plane-right\",\"native-sketch-1\"]")
        && m_eq(j_encode(j_get(deletion_tree(reopened),"orderedNodeIds")),"[\"native-sketch-1\"]"),
        "Both saved orders keep the remaining nodes");
    m_assert(!cad_project_delete_feature(reopened,body) && !cad_project_delete_feature(reopened,"native-sketch-1"),
        "Neither a missing feature nor a sketch can be deleted through feature history");
    let restored=cad_project_add_extrusion(reopened,"native-sketch-1",1,12000000,"newBody");m_assert(restored,cg_error);
    m_assert(!j_get(cad_project_mesh(restored),"error"),"The saved sketch can drive a new extrusion");

    let part=cad_project_part(original);let data=j_get(part,"data");
    pc_remove_field(j_get(data,"cad"),"rootNodeIds");pc_remove_field(j_get(data,"tree"),"orderedNodeIds");
    let legacy=cad_project_delete_feature(original,body);
    m_assert(legacy && !pc_find(pc_nodes(cad_project_part(legacy)),body),"Delete from a drawing with implicit graph order");
}

fn check_delete_at_rollback() {
    let project=deletion_another_profile(deletion_plate(),cg_v(30000000,0,0),cg_v(40000000,10000000,0));
    project=cad_project_add_extrusion(project,"native-sketch-2",1,15000000,"newBody");m_assert(project,cg_error);
    let rolled=cad_project_roll_to(project,1);m_assert(rolled,cg_error);
    let removed=cad_project_delete_feature(rolled,"native-extrude-1");m_assert(removed,cg_error);
    let history=cad_project_feature_history(removed);
    let row=pc_first(j_get(history,"features"));
    m_assert(j_get(deletion_tree(removed),"rollbackIndex") && j_integer(deletion_tree(removed),"rollbackIndex")==0
        && m_eq(j_string(row,"state"),"rolledBack") && !load64(row+24),"A deletion above the bar keeps the next feature inactive");
    removed=cad_project_delete_feature(rolled,"native-extrude-2");m_assert(removed,cg_error);
    m_assert(!j_get(deletion_tree(removed),"rollbackIndex") && !j_get(cad_project_mesh(removed),"error"),
        "Deleting the only rolled-back feature moves the bar to the end");
}

fn check_boolean_and_face_dependencies() {
    let body="native-extrude-1";let cut_id="native-extrude-2";
    let block=deletion_plate();
    let project=deletion_another_profile(block,cg_v(5000000,5000000,0),cg_v(15000000,15000000,0));
    project=cad_project_add_extrusion(project,"native-sketch-2",1,10000000,"cut");m_assert(project,cg_error);
    let rolled=cad_project_roll_to(project,1);m_assert(rolled,cg_error);
    let saved=j_encode(rolled);
    m_assert(!cad_project_delete_feature(rolled,body) && m_eq(cg_error,"Later cut or join features depend on this extrusion")
        && m_eq(j_encode(rolled),saved),"A rolled-back cut still needs its original body");
    let suppressed=cad_project_suppress_feature(project,cut_id,1);m_assert(suppressed,cg_error);
    m_assert(!cad_project_delete_feature(suppressed,body),"A suppressed cut still needs its original body");
    let removed=cad_project_delete_feature(project,cut_id);m_assert(removed,cg_error);
    m_assert(m_eq(j_encode(cad_project_mesh(removed)),j_encode(cad_project_mesh(block))),"Deleting the cut restores the uncut block");

    let face=cad_project_pick_face(block,cg_v(10000000,-20000000,10000000),cg_v(0,1000000000,0));m_assert(face,cg_error);
    let attached=cad_project_add_face_sketch(block,face);m_assert(attached,cg_error);
    saved=j_encode(attached);
    m_assert(!cad_project_delete_feature(attached,body) && m_eq(cg_error,"Other features depend on this feature")
        && m_eq(j_encode(attached),saved),"An unconsumed face sketch still needs its supporting extrusion");

    let separate=deletion_another_profile(block,cg_v(30000000,0,0),cg_v(50000000,20000000,0));
    separate=cad_project_add_extrusion(separate,"native-sketch-2",1,40000000,"newBody");m_assert(separate,cg_error);
    separate=cad_project_add_plane_sketch(separate,"XY");m_assert(separate,cg_error);
    m_assert(cad_project_add_primitive(separate,"native-sketch-3","rectangle",cg_v(35000000,5000000,0),cg_v(45000000,15000000,0)),cg_error);
    let measured=cad_project_add_extrusion_options(separate,"native-sketch-3",1,1000000,"cut","up-to-body",0,body);
    m_assert(measured,cg_error);
    m_assert(!cad_project_delete_feature(measured,body) && m_eq(cg_error,"Other features depend on this feature"),
        "An extent reference is protected even when the cut is applied to a different body");
}

fn deletion_chamfer(project) {
    let edges=j_parse("[{\"a\":[0,0,20],\"b\":[20,0,20],\"normals\":[[0,-1,0],[0,0,1]]}]");
    return cad_project_add_edge_finish(project,"chamfer",3000000,edges);
}
fn check_edge_finish_dependency() {
    let block=deletion_plate();let project=deletion_chamfer(block);m_assert(project,cg_error);
    let rolled=cad_project_roll_to(project,1);m_assert(rolled,cg_error);
    let saved=j_encode(rolled);
    m_assert(!cad_project_delete_feature(rolled,"native-extrude-1") && m_eq(cg_error,"Finished edge no longer exists")
        && m_eq(j_encode(rolled),saved),"A later edge finish must still evaluate when the bar returns to the end");
    let removed=cad_project_delete_feature(rolled,"native-edge-finish-1");m_assert(removed,cg_error);
    m_assert(m_eq(j_encode(cad_project_mesh(removed)),j_encode(cad_project_mesh(block))),"Deleting the independent finish restores the original solid");
}

fn check_projected_edge_dependency() {
    let body=deletion_plate();
    let face=cad_project_pick_face(body,cg_v(10000000,-20000000,10000000),cg_v(0,1000000000,0));m_assert(face,cg_error);
    let finished=deletion_chamfer(body);m_assert(finished,cg_error);
    let project=cad_project_add_face_sketch(finished,face);m_assert(project,cg_error);
    let linked=cad_project_project_edge(project,"native-sketch-2",cg_v(10000000,17000000,0),500000);m_assert(linked,cg_error);
    let saved=j_encode(linked);
    m_assert(!cad_project_delete_feature(linked,"native-edge-finish-1") && m_eq(cg_error,"A sketch projects an edge from this feature")
        && m_eq(j_encode(linked),saved),"Removing a finish cannot detach an unconsumed sketch's linked edge");
}

fn main() {
    check_delete_and_reopen();
    check_delete_at_rollback();
    check_boolean_and_face_dependencies();
    check_edge_finish_dependency();
    check_projected_edge_dependency();
    return 0;
}
