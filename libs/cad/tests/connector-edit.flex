import "cad/author.flex";
import "cad/project-access.flex";

fn ce_data(project) {return j_get(cad_project_item(project),"data");}
fn ce_axis(row,group,axis) {return pc_pose_number(j_get(j_get(row,group),axis));}
fn ce_pose(project,id,group,axis) {
    let pose=cad_project_instance_transform(project,id);m_assert(pose,cg_error);
    return ce_axis(pose,group,axis);
}

fn ce_project() {
    let project=cad_project_new("Connector plate");
    m_assert(cad_project_add_primitive(project,"native-sketch-1","rectangle",cg_v(0,0,0),cg_v(12000000,8000000,0)),cg_error);
    project=cad_project_add_extrusion(project,"native-sketch-1",1,4000000,"newBody");m_assert(project,cg_error);
    project=cad_project_add_item(project,"assembly");m_assert(project,cg_error);
    let i=0;
    while i<3 {project=cad_project_insert_instance(project,"native-part-1");m_assert(project,cg_error);i=i+1;}
    let data=ce_data(project);
    cg_j_set(data,"connectors",j_parse("[{\"id\":\"loc\",\"instanceId\":null,\"label\":\"Ground\",\"position\":{\"x\":0,\"y\":0,\"z\":0}},{\"id\":\"loc\",\"instanceId\":\"instance-1\"},{\"id\":\"tip\",\"instanceId\":\"instance-1\",\"label\":\"Top frame\",\"position\":{\"x\":0,\"y\":0,\"z\":10,\"label\":\"Measured\"}},{\"id\":\"loc\",\"instanceId\":\"instance-2\"},{\"id\":\"tip\",\"instanceId\":\"instance-2\",\"position\":{\"x\":0,\"y\":20,\"z\":5}},{\"id\":\"loc\",\"instanceId\":\"instance-3\"}]"));
    cg_j_set(data,"mates",j_parse("[{\"id\":\"ground\",\"type\":\"fasten\",\"a\":{\"instanceId\":null,\"connectorId\":\"loc\"},\"b\":{\"instanceId\":\"instance-1\",\"connectorId\":\"loc\"}},{\"id\":\"mount\",\"type\":\"fasten\",\"a\":{\"instanceId\":\"instance-1\",\"connectorId\":\"tip\"},\"b\":{\"instanceId\":\"instance-2\",\"connectorId\":\"loc\"}},{\"id\":\"hinge\",\"type\":\"revolute\",\"a\":{\"instanceId\":\"instance-2\",\"connectorId\":\"tip\"},\"b\":{\"instanceId\":\"instance-3\",\"connectorId\":\"loc\"}}]"));
    cg_j_set(data,"actuators",j_parse("[{\"id\":\"servo\",\"type\":\"servo\",\"mateId\":\"hinge\",\"homeDeg\":30}]"));
    return project;
}

fn ce_attached_and_world(project) {
    let before=j_encode(project);let data=ce_data(project);
    let frame=cad_project_connector_frame(project,"instance-1","tip");m_assert(frame,cg_error);
    m_assert(ce_axis(frame,"position","z")==10000000 && !ce_axis(frame,"rotation","z"),"Read local axes with default zero rotation");
    let unchanged=cad_project_set_connector_component(project,"instance-1","tip","rotation","z",0);
    m_assert(unchanged && unchanged!=project && m_eq(j_encode(unchanged),before),"No-op keeps the omitted rotation and stored poses");
    let updated=cad_project_set_connector_component(project,"instance-1","tip","position","z",25000000);m_assert(updated,cg_error);
    m_assert(!ce_pose(updated,"instance-1","translation","z") && ce_pose(updated,"instance-2","translation","z")==25000000
        && ce_pose(updated,"instance-3","translation","z")==30000000,"Connector position moves both downstream occurrences");
    let result=ce_data(updated);let top=pc_editable_connector(result,"instance-1","tip");
    m_assert(m_eq(j_string(top,"label"),"Top frame") && m_eq(j_string(j_get(top,"position"),"label"),"Measured") && !j_get(top,"rotation"),"Preserve frame metadata and omitted fields");
    frame=cad_project_connector_frame(updated,"instance-2","tip");m_assert(frame && ce_axis(frame,"position","z")==5000000,"Same connector ID on another instance stays intact");
    m_assert(m_eq(j_encode(j_get(result,"mates")),j_encode(j_get(data,"mates")))
        && m_eq(j_encode(j_get(result,"actuators")),j_encode(j_get(data,"actuators"))),"Preserve exact mate and servo references");

    updated=cad_project_set_connector_component(updated,"instance-1","tip","rotation","z",90000000);m_assert(updated,cg_error);
    m_assert(ce_pose(updated,"instance-2","rotation","z")==90000000
        && ce_pose(updated,"instance-3","translation","x")== -20000000,"Connector rotation carries the fixed group and the hinge frame");
    updated=cad_project_set_connector_component(updated,"","loc","position","x",3000000);m_assert(updated,cg_error);
    m_assert(ce_pose(updated,"instance-1","translation","x")==3000000
        && ce_pose(updated,"instance-3","translation","x")== -17000000,"Moving a world connector carries the grounded group");
    let world=pc_editable_connector(ce_data(updated),"","loc");
    m_assert(j_kind(j_get(world,"instanceId"))==0 && m_eq(j_string(world,"label"),"Ground"),"Preserve explicit world ownership");
    let inspected=cad_project_inspect_source(j_encode(updated));
    m_assert(inspected && !j_get(inspected,"readOnly"),j_string(inspected,"readOnly"));
    m_assert(m_eq(j_encode(project),before),"Successful edits leave the source document unchanged");
}

fn ce_conflicts(project) {
    let data=ce_data(project);
    j_add(j_get(data,"connectors"),0,j_parse("{\"id\":\"second\",\"instanceId\":\"instance-1\",\"position\":{\"x\":0,\"y\":0,\"z\":10}}"));
    j_add(j_get(data,"mates"),0,j_parse("{\"id\":\"parallel\",\"type\":\"fasten\",\"a\":{\"instanceId\":\"instance-1\",\"connectorId\":\"second\"},\"b\":{\"instanceId\":\"instance-2\",\"connectorId\":\"loc\"}}"));
    let before=j_encode(project);
    m_assert(!cad_project_set_connector_component(project,"instance-1","tip","position","z",25000000)
        && m_eq(cg_error,"Conflicting assembly mates") && m_eq(j_encode(project),before),"Conflicting fastens reject the complete edit");
    m_assert(!cad_project_connector_frame(project,"instance-3","tip"),"A connector cannot be selected on the wrong owner");
    m_assert(!cad_project_set_connector_component(project,"instance-1","tip","scale","z",1),"Reject unsupported frame fields");
    m_assert(!cad_project_set_connector_component(project,"instance-1","tip","position","w",1),"Reject unsupported frame axes");
    m_assert(!cad_project_set_connector_component(project,"instance-1","tip","position","z",500000001),"Reject out-of-range components");
    j_add(j_get(data,"connectors"),0,j_parse("{\"id\":\"tip\",\"instanceId\":\"instance-1\"}"));
    m_assert(!cad_project_connector_frame(project,"instance-1","tip") && m_eq(cg_error,"Duplicate connector on an assembly instance"),"Reject ambiguous IDs on the same owner");
}

fn ce_empty() {
    let project=cad_project_add_item(cad_project_new("Empty"),"assembly");m_assert(project,cg_error);
    cg_j_set(ce_data(project),"connectors",j_parse("[{\"id\":\"world-only\",\"instanceId\":null}]"));
    let updated=cad_project_set_connector_component(project,"","world-only","rotation","y",-45000000);m_assert(updated,cg_error);
    let frame=cad_project_connector_frame(updated,"","world-only");m_assert(frame,cg_error);
    m_assert(ce_axis(frame,"rotation","y")== -45000000 && !pc_first(j_get(ce_data(updated),"instances")),"An empty assembly retains an editable world frame");
}

fn main() {
    let project=ce_project();
    ce_attached_and_world(project);
    ce_conflicts(project);
    ce_empty();
    return 0;
}
