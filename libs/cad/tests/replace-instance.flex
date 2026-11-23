import "cad/author.flex";
import "cad/project-access.flex";

fn ri_box(project,x,y) {
    let part=cad_project_part(project);let sketch=pc_find(pc_nodes(part),"native-sketch-1");
    let id=j_string(sketch,"id");
    m_assert(cad_project_add_primitive(project,id,"rectangle",cg_v(0,0,0),cg_v(x,y,0)),cg_error);
    let solid=cad_project_add_extrusion(project,id,1,4000000,"newBody");m_assert(solid,cg_error);
    return solid;
}

fn main() {
    let project=ri_box(cad_project_new("Original"),12000000,8000000);
    project=cad_project_add_item(project,"part");m_assert(project,cg_error);
    project=ri_box(project,6000000,8000000);
    project=cad_project_add_item(project,"part");m_assert(project,cg_error);
    project=cad_project_add_item(project,"assembly");m_assert(project,cg_error);
    let i=0;
    while i<2 {project=cad_project_insert_instance(project,"native-part-1");m_assert(project,cg_error);i=i+1;}
    let data=j_get(cad_project_item(project),"data");
    cg_j_set(data,"connectors",j_parse("[{\"id\":\"top\",\"instanceId\":\"instance-1\",\"position\":{\"x\":0,\"y\":0,\"z\":4}},{\"id\":\"base\",\"instanceId\":\"instance-2\"}]"));
    cg_j_set(data,"mates",j_parse("[{\"id\":\"elbow\",\"type\":\"revolute\",\"a\":{\"instanceId\":\"instance-1\",\"connectorId\":\"top\"},\"b\":{\"instanceId\":\"instance-2\",\"connectorId\":\"base\"}}]"));
    cg_j_set(data,"actuators",j_parse("[{\"id\":\"servo\",\"type\":\"servo\",\"mateId\":\"elbow\",\"homeDeg\":30}]"));
    let follower=pc_find(j_get(data,"instances"),"instance-2");
    cg_j_text(j_get(follower,"transform"),"memo","Keep pose metadata");
    cg_j_text(follower,"description","Keep occurrence metadata");

    let before=j_encode(project);let pose=j_encode(cad_project_instance_transform(project,"instance-2"));
    let expected=j_parse(before);let assembly=j_get(cad_project_item(expected),"data");
    cg_j_text(pc_find(j_get(assembly,"instances"),"instance-2"),"partId","native-part-2");
    let changed=cad_project_replace_instance_part(project,"instance-2","native-part-2");m_assert(changed,cg_error);
    m_assert(m_eq(j_encode(changed),j_encode(expected)) && m_eq(j_encode(project),before),"Only the selected occurrence's part ID changes");
    m_assert(m_eq(j_encode(cad_project_instance_transform(changed,"instance-2")),pose),"The mate retains the solved pose");
    let report=cad_project_inspect_source(j_encode(changed));m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let mesh=cad_project_mesh(j_get(report,"document"));let parts=j_get(mesh,"parts");
    let first=pc_pose_number(j_get(pc_find(parts,"instance-1"),"volume_mm3"));
    let second=pc_pose_number(j_get(pc_find(parts,"instance-2"),"volume_mm3"));
    m_assert(j_value(j_get(mesh,"closed")) && cg_abs(first-384000000)<1000000 && cg_abs(second-192000000)<1000000,
        m_cat("Unexpected replaced assembly volumes: ",m_cat(m_int(first),m_cat(" and ",m_int(second)))));
    m_assert(!cad_project_replace_instance_part(project,"instance-2","native-part-3") && cg_error
        && m_eq(j_encode(project),before),"An empty replacement leaves the assembly intact");
    m_assert(!cad_project_replace_instance_part(project,"missing","native-part-2") && cg_error,"Unknown occurrence is rejected");
    m_assert(!cad_project_replace_instance_part(project,"instance-2","missing") && cg_error,"Unknown part is rejected");
    return 0;
}
