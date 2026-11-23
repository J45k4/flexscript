import "cad/mate-author.flex";

fn main() {
    let p=cad_project_new("Plate");let sketch="native-sketch-1";
    m_assert(cad_project_add_primitive(p,sketch,"rectangle",cg_v(-5000000,-3000000,0),cg_v(5000000,3000000,0)),cg_error);
    p=cad_project_add_extrusion(p,sketch,1,4000000,"newBody");p=cad_project_add_item(p,"assembly");
    p=cad_project_insert_instance(p,"native-part-1");p=cad_project_insert_instance(p,"native-part-1");m_assert(p,cg_error);
    let base=j_encode(p);let eye=cg_v(10000000,0,2000000);
    let a=cad_project_pick_mate_face(p,eye,cg_v(-1000000000,0,0),0,0);m_assert(a,cg_error);
    let b=cad_project_pick_mate_face(p,eye,cg_v(1000000000,0,0),0,1);m_assert(b,cg_error);
    m_assert(m_eq(j_string(a,"instanceId"),"instance-1") && m_eq(j_string(b,"instanceId"),"instance-2"),"Pick two distinct occurrences");
    m_assert(pc_pose_number(j_get(j_get(a,"position"),"x"))==5000000 && pc_pose_number(j_get(j_get(b,"position"),"x"))== -5000000,"Connectors are local to each instance");
    let pose=pc_pose_frame(a,"position");m_assert(load64(pose+16)>999990,"Parent connector Z points outward");
    pose=pc_pose_frame(b,"position");m_assert(load64(pose+16)>999990,"Child connector Z points inward");
    let grounded=cad_project_fasten_to_world(p,"instance-1");m_assert(grounded,cg_error);
    let initial=cad_project_instance_transform(p,"instance-1");m_assert(initial,cg_error);
    m_assert(pc_pose_number(j_get(j_get(initial,"scale"),"z"))==1000000,"Initial scale is one");
    let placed=cad_project_set_instance_component(p,"instance-1","translation","y",-12500000);m_assert(placed,cg_error);
    placed=cad_project_set_instance_component(placed,"instance-1","rotation","x",225000000);m_assert(placed,cg_error);
    placed=cad_project_set_instance_component(placed,"instance-1","scale","z",-1500000);m_assert(placed,cg_error);
    let actual=cad_project_instance_transform(placed,"instance-1");
    m_assert(pc_pose_number(j_get(j_get(actual,"rotation"),"x"))==225000000 && pc_pose_number(j_get(j_get(actual,"translation"),"y"))== -12500000,"Free instance retains authored Euler angles and displacement");
    m_assert(m_eq(j_encode(j_get(actual,"scale")),j_encode(pc_pose_json(1000000,1000000,-1500000))),"Changing one scale axis preserves the other two");
    let locked=cad_project_set_instance_component(grounded,"instance-1","translation","x",70000000);m_assert(locked,cg_error);
    m_assert(!pc_pose_number(j_get(j_get(cad_project_instance_transform(locked,"instance-1"),"translation"),"x")),"Ground mate still holds after a placement edit");
    m_assert(!cad_project_set_instance_component(grounded,"instance-1","scale","y",2000000),"Reject scaling a world fasten");
    m_assert(!cad_project_set_instance_component(p,"instance-1","scale","z",0),"Reject zero scale");
    m_assert(!cad_project_set_instance_component(p,"missing","rotation","x",0) && !cad_project_set_instance_component(p,"instance-1","scale","w",1000000),"Reject missing instance and axis");
    let kinds=j_parse("[\"fasten\",\"revolute\",\"prismatic\",\"planar\",\"ball\"]");let kind=pc_first(kinds);
    while kind {
        let result=cad_project_add_mate(grounded,j_value(kind),a,b);m_assert(result,cg_error);
        let data=j_get(cad_project_item(result),"data");let mate=pc_find(j_get(data,"mates"),"mate-2");
        m_assert(m_eq(j_string(mate,"type"),j_value(kind)) && cg_j_count(j_get(data,"connectors"))==4,"Each mate has its two named connectors");
        m_assert(m_eq(j_string(j_get(mate,"a"),"connectorId"),"connector-3") && m_eq(j_string(j_get(mate,"b"),"connectorId"),"connector-4"),"References survive solving");
        if m_eq(j_value(kind),"fasten") {
            let instances=j_get(data,"instances");let transform=j_get(pc_find(instances,"instance-2"),"transform");
            m_assert(pc_pose_number(j_get(j_get(transform,"translation"),"x"))==10000000,"Fastened faces coincide");
        }
        kind=load64(kind+24);
    }
    let hinge=cad_project_add_mate(grounded,"revolute",a,b);m_assert(hinge,cg_error);
    let driven=cad_project_drive_mate(hinge,"mate-2",0);m_assert(driven,cg_error);
    let data=j_get(cad_project_item(driven),"data");let servo=pc_mate_servo(data,"mate-2");
    m_assert(m_eq(j_string(servo,"id"),"servo-1") && pc_pose_number(j_get(j_get(servo,"commandRange"),"minDeg"))== -180000000,"A zero home angle creates a servo");
    driven=cad_project_drive_mate(driven,"mate-2",215000000);m_assert(driven,cg_error);
    data=j_get(cad_project_item(driven),"data");servo=pc_mate_servo(data,"mate-2");
    m_assert(cg_j_count(j_get(data,"actuators"))==1 && pc_pose_number(j_get(j_get(servo,"commandRange"),"maxDeg"))==215000000,"Edit existing driver and extend its range");
    let mates=j_get(data,"mates");let connectors=j_get(data,"connectors");let first=pc_find(mates,"mate-1");let second=pc_find(mates,"mate-2");
    let stale=j_parse(j_encode(driven));let stale_data=j_get(cad_project_item(stale),"data");
    let saved=j_get(pc_find(j_get(data,"instances"),"instance-2"),"transform");
    let moving=pc_find(j_get(stale_data,"instances"),"instance-2");
    cg_j_set(j_get(moving,"transform"),"translation",pc_pose_json(123000000,0,0));
    let detached=cad_project_remove_mate(stale,"mate-2");m_assert(detached,cg_error);
    let after=j_get(cad_project_item(detached),"data");
    m_assert(m_eq(j_encode(j_get(pc_find(j_get(after,"instances"),"instance-2"),"transform")),j_encode(saved)),"Detached occurrence stays in its displayed solved pose");
    // Another mate uses the very same connector. An unrelated frame also
    // reuses the removed endpoint's ID on a different owner.
    cg_j_set(second,"a",j_parse(j_encode(j_get(first,"b"))));
    let duplicate=j_parse(j_encode(pc_find(connectors,"connector-4")));cg_j_text(duplicate,"instanceId","instance-1");j_add(connectors,0,duplicate);
    let removed=cad_project_remove_mate(driven,"mate-2");m_assert(removed,cg_error);
    let rest=j_get(cad_project_item(removed),"data");
    m_assert(cg_j_count(j_get(rest,"mates"))==1 && !cg_j_count(j_get(rest,"actuators")),"Only selected mate and associated drivers removed");
    m_assert(cg_j_count(j_get(rest,"connectors"))==4 && pc_find(j_get(rest,"connectors"),"connector-2"),"Shared and unrelated connectors survived");
    m_assert(m_eq(j_string(pc_find(j_get(rest,"connectors"),"connector-4"),"instanceId"),"instance-1"),"Connector IDs are scoped to the instance");
    let single=cad_project_remove_instance(driven,"instance-2");m_assert(single,cg_error);
    rest=j_get(cad_project_item(single),"data");m_assert(cg_j_count(j_get(rest,"instances"))==1 && cg_j_count(j_get(rest,"mates"))==1 && !pc_first(j_get(rest,"actuators")),"Deleting an occurrence removes all touching mates and drivers");
    let empty=cad_project_remove_instance(single,"instance-1");m_assert(empty,cg_error);
    rest=j_get(cad_project_item(empty),"data");m_assert(!pc_first(j_get(rest,"instances")) && cg_j_count(j_get(empty,"items"))==2 && cg_j_count(j_get(rest,"connectors"))==1,"Empty assembly retains reusable part and authored world frame");
    m_assert(!cad_project_remove_mate(empty,"missing") && !cad_project_remove_instance(empty,"missing"),"Stale selections rejected");
    let fixed=cad_project_fasten_to_world(grounded,"instance-2");m_assert(fixed,cg_error);let accepted=j_encode(fixed);
    m_assert(!cad_project_add_mate(fixed,"fasten",a,b),"Reject conflicting placements");
    m_assert(!cad_project_add_mate(p,"ball",a,a),"Reject mating an instance to itself");
    m_assert(!cad_project_fasten_to_world(p,"missing"),"Reject missing occurrence");
    m_assert(m_eq(j_encode(p),base) && m_eq(j_encode(fixed),accepted),"Failed edits leave the original untouched");return 0;
}
