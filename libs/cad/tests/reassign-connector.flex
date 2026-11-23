import "cad/author.flex";
import "cad/project-access.flex";

fn rc_data(project) {return j_get(cad_project_item(project),"data");}
fn rc_pose(project,id) {
    let pose=cad_project_instance_transform(project,id);m_assert(pose,cg_error);
    return j_get(pose,"translation");
}

fn main() {
    let project=cad_project_new("Plate");let sk="native-sketch-1";
    m_assert(cad_project_add_primitive(project,sk,"rectangle",cg_v(0,0,0),cg_v(8000000,6000000,0)),cg_error);
    project=cad_project_add_extrusion(project,sk,1,4000000,"newBody");m_assert(project,cg_error);
    project=cad_project_add_item(project,"assembly");m_assert(project,cg_error);
    let i=0;
    while i<3 {project=cad_project_insert_instance(project,"native-part-1");m_assert(project,cg_error);i=i+1;}
    let data=rc_data(project);let instances=j_get(data,"instances");
    cg_j_set(pc_find(instances,"instance-3"),"transform",j_parse("{\"translation\":{\"x\":50,\"y\":0,\"z\":0}}"));
    cg_j_set(data,"connectors",j_parse("[{\"id\":\"anchor\",\"instanceId\":null,\"position\":{\"x\":0,\"y\":0,\"z\":5},\"memo\":\"World reference\"},{\"id\":\"anchor\",\"instanceId\":\"instance-1\"},{\"id\":\"root\",\"instanceId\":\"instance-2\"},{\"id\":\"existing\",\"instanceId\":\"instance-3\"}]"));
    cg_j_set(data,"mates",j_parse("[{\"id\":\"mount\",\"type\":\"fasten\",\"a\":{\"instanceId\":null,\"connectorId\":\"anchor\",\"memo\":\"Datum side\"},\"b\":{\"instanceId\":\"instance-2\",\"connectorId\":\"root\"}}]"));
    let original=j_encode(project);let before=rc_pose(project,"instance-2");
    m_assert(!pc_pose_number(j_get(before,"x")) && pc_pose_number(j_get(before,"z"))==5000000,"World connector sets the initial pose");
    let edited=cad_project_reassign_connector(project,"","anchor","instance-3","tab");m_assert(edited,cg_error);
    let changed=rc_data(edited);let side=j_get(pc_find(j_get(changed,"mates"),"mount"),"a");
    m_assert(m_eq(j_string(side,"instanceId"),"instance-3") && m_eq(j_string(side,"connectorId"),"tab")
        && m_eq(j_string(side,"memo"),"Datum side"),"Replace the owner's identity in each referencing mate endpoint only");
    let connector=pc_editable_connector(changed,"instance-3","tab");
    m_assert(connector && m_eq(j_string(connector,"memo"),"World reference")
        && pc_editable_connector(changed,"instance-1","anchor"),"Keep local frame fields and same IDs owned elsewhere");
    let report=cad_project_inspect_source(j_encode(edited));m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let reopened=rc_pose(j_get(report,"document"),"instance-2");
    m_assert(pc_pose_number(j_get(reopened,"x"))==50000000 && pc_pose_number(j_get(reopened,"z"))==5000000,
        "Solve the reattached connector on reopen");
    let renamed=cad_project_reassign_connector(edited,"instance-3","tab","instance-3","renamed");m_assert(renamed,cg_error);
    m_assert(m_eq(j_encode(rc_pose(renamed,"instance-2")),j_encode(reopened)),"Renaming keeps the solved pose");
    let unmounted=cad_project_reassign_connector(renamed,"instance-3","renamed","","renamed");m_assert(unmounted,cg_error);
    m_assert(m_eq(j_encode(rc_pose(unmounted,"instance-2")),j_encode(before)),"Reassign back to world");
    m_assert(!cad_project_reassign_connector(project,"","anchor","instance-3","existing")
        && m_eq(cg_error,"Connector ID already exists on the destination"),"Reject a duplicate on the destination owner");
    m_assert(!cad_project_reassign_connector(project,"","anchor","instance-2","other")
        && m_eq(cg_error,"Mate needs distinct instances"),"Reject attaching to the other end of the same mate");
    m_assert(!cad_project_reassign_connector(project,"","anchor","missing","other") && cg_error
        && m_eq(j_encode(project),original),"Failed edits leave every original node intact");

    let empty=cad_project_add_item(cad_project_new("Empty"),"assembly");m_assert(empty,cg_error);
    cg_j_set(rc_data(empty),"connectors",j_parse("[{\"id\":\"world\",\"memo\":\"Implicit world owner\"}]"));
    let renamed_world=cad_project_reassign_connector(empty,"","world","","origin");m_assert(renamed_world,cg_error);
    let world=pc_editable_connector(rc_data(renamed_world),"","origin");
    m_assert(world && !j_get(world,"instanceId") && m_eq(j_string(world,"memo"),"Implicit world owner"),
        "Rename an unmounted connector in an empty assembly without materializing an omitted owner");
    return 0;
}
