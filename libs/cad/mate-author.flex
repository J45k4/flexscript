// Author v4 connectors in the local frame of each instance. Frame vectors
// use native project JSON (XYZ millimetres and intrinsic XYZ Euler degrees).
import "author.flex";
import "mate-pick.flex";

fn pm_frame(owner,point,rotation) {
    let frame=j_object();
    if owner {cg_j_text(frame,"instanceId",owner);}else {j_add(frame,"instanceId",j_new(0,0));}
    j_add(frame,"position",pc_pose_json(load64(point),load64(point+8),load64(point+16)));
    j_add(frame,"rotation",rotation);return frame;
}
fn pm_from_hit(project,hit,inward) {
    let owner=load64(load64(hit+16));let data=j_get(cad_project_item(project),"data");
    let rows=pc_assembly_poses(data);if cg_error {return 0;}let instance=ca_find(rows,owner);
    if !instance {return cg_fail("Pick a face on an assembly instance");}
    let inv=ca_inverse(load64(instance+24));let point=ca_point(inv,load64(hit));
    let k=0;while k<24 {
        let scale=load64(load64(instance+40)+k);if !scale {return cg_fail("Assembly scale must be nonzero");}
        store64(point+k,load64(point+k)*1000000/scale);store64(inv+72+k,0);k=k+8;
    }
    let z=cg_normal(ca_point(inv,load64(hit+8)));if !z {return cg_fail("Mate face needs a surface normal");}
    if inward {z=cg_v(-load64(z),-load64(z+8),-load64(z+16));}
    return pm_frame(owner,point,pm_rotation(z));
}
fn pm_rotation(z) {
    let helper=cg_v(1000000000,0,0);if cg_abs(load64(z))>=900000000 {helper=cg_v(0,1000000000,0);}
    let y=cg_normal(cg_cross(z,helper));let x=cg_normal(cg_cross(y,z));let pose=ca_identity();
    let k=0;while k<3 {
        store64(pose+k*24,load64(x+k*8)/1000);store64(pose+k*24+8,load64(y+k*8)/1000);store64(pose+k*24+16,load64(z+k*8)/1000);k=k+1;
    }
    return pc_pose_rotation(pose);
}
fn cad_project_pick_mate_face(project,eye,direction,visible,inward) {
    cg_begin();if !m_eq(j_string(cad_project_item(project),"type"),"assembly") {return cg_fail("Select an assembly");}
    let hit=cad_project_surface_hit_in(project,eye,direction,visible);if !hit {
        if cg_error {return 0;}return cg_fail("Click a visible assembly face");
    }
    return pm_from_hit(project,hit,inward);
}
fn pm_edge_kind(kind) {return m_eq(kind,"Edge") || m_eq(kind,"Curved edge");}
fn pm_element_frame(project,hit,inward) {
    let kind=load64(hit+24);let frame=pm_from_hit(project,hit,inward && !pm_edge_kind(kind));
    if frame {cg_j_text(frame,"pickKind",kind);}return frame;
}
fn cad_project_pick_mate_element(project,eye,direction,visible,tolerance,inward) {
    let hit=pm_element_hit(project,eye,direction,visible,tolerance);
    if !hit {if cg_error {return 0;}return cg_fail("Click a visible vertex, edge or face");}
    return pm_element_frame(project,hit,inward);
}
fn pm_axis(frame) {
    let pose=pc_pose_frame(frame,"position");return cg_v(load64(pose+16)*1000,load64(pose+40)*1000,load64(pose+64)*1000);
}
fn pm_world_axis(rows,frame,local) {
    let instance=ca_find(rows,j_string(frame,"instanceId"));if !instance {return local;}
    let pose=load64(instance+24);return cg_sub(ca_point(pose,local),pose+72);
}
fn pm_new_ref(data,connectors,frame) {
    let owner=j_get(frame,"instanceId");if j_kind(owner)!=0 && (j_kind(owner)!=2 || !pc_find(j_get(data,"instances"),j_value(owner))) {return cg_fail("Unknown mate instance");}
    let pos=j_get(frame,"position");let rot=j_get(frame,"rotation");
    if j_kind(pos)!=4 || j_kind(rot)!=4 {return cg_fail("Mate connector needs position and rotation");}
    pc_pose_vector(pos,0);pc_pose_vector(rot,0);if cg_error {return 0;}
    let id=m_cat("connector-",m_int(pc_free_index(connectors,"connector-")));let ref=j_object();let connector=j_object();
    cg_j_text(connector,"id",id);j_add(connector,"instanceId",j_parse(j_encode(owner)));
    j_add(connector,"position",j_parse(j_encode(pos)));j_add(connector,"rotation",j_parse(j_encode(rot)));j_add(connectors,0,connector);
    cg_j_text(ref,"connectorId",id);j_add(ref,"instanceId",j_parse(j_encode(owner)));return ref;
}
fn cad_project_add_mate(project,kind,a,b) {
    cg_begin();
    if !m_eq(j_string(cad_project_item(project),"type"),"assembly") {return cg_fail("Select an assembly");}
    if !m_eq(kind,"fasten") && !m_eq(kind,"revolute") && !m_eq(kind,"prismatic") && !m_eq(kind,"planar") && !m_eq(kind,"ball") {return cg_fail("Unknown assembly mate type");}
    if m_eq(j_string(a,"instanceId"),j_string(b,"instanceId")) {return cg_fail("Mate needs distinct instances");}
    let updated=j_parse(j_encode(project));let data=j_get(cad_project_item(updated),"data");
    let connectors=j_get(data,"connectors");if !connectors {connectors=j_array();j_add(data,"connectors",connectors);}
    let mates=j_get(data,"mates");if !mates {mates=j_array();j_add(data,"mates",mates);}
    if j_kind(connectors)!=3 || j_kind(mates)!=3 {return cg_fail("Expected connector and mate arrays");}
    let edge_a=pm_edge_kind(j_string(a,"pickKind"));let edge_b=pm_edge_kind(j_string(b,"pickKind"));
    if edge_a || edge_b {
        let rows=pc_assembly_poses(data);if cg_error {return 0;}let za=pm_axis(a);let zb=pm_axis(b);
        if cg_dot(pm_world_axis(rows,a,za),pm_world_axis(rows,b,zb))<0 {
            let axis=za;let frame=0;if edge_b {b=j_parse(j_encode(b));frame=b;axis=zb;}
            else {a=j_parse(j_encode(a));frame=a;}
            cg_j_set(frame,"rotation",pm_rotation(cg_v(-load64(axis),-load64(axis+8),-load64(axis+16))));
        }
    }
    let first=pm_new_ref(data,connectors,a);if !first {return 0;}
    let second=pm_new_ref(data,connectors,b);if !second {return 0;}
    let mate=j_object();cg_j_text(mate,"id",m_cat("mate-",m_int(pc_free_index(mates,"mate-"))));cg_j_text(mate,"type",kind);
    j_add(mate,"a",first);j_add(mate,"b",second);j_add(mates,0,mate);return pc_apply_assembly(updated,data);
}
fn cad_project_fasten_to_world(project,id) {
    cg_begin();let item=cad_project_item(project);if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let rows=pc_assembly_poses(j_get(item,"data"));if cg_error {return 0;}let row=ca_find(rows,id);
    if !row {return cg_fail("Select an assembly instance");}
    let pose=load64(row+24);let zero=cg_v(0,0,0);
    return cad_project_add_mate(project,"fasten",pm_frame(0,pose+72,pc_pose_rotation(pose)),pm_frame(id,zero,pc_pose_json(0,0,0)));
}

// References are scoped by owner. Different instances may use the same
// connector ID. A null instanceId denotes the assembly's world frame.
fn pm_ref_matches(ref,owner,id) {
    return m_eq(j_string(ref,"instanceId"),owner) && m_eq(j_string(ref,"connectorId"),id);
}
fn pm_touches(mate,instance) {
    return m_eq(j_string(j_get(mate,"a"),"instanceId"),instance) || m_eq(j_string(j_get(mate,"b"),"instanceId"),instance);
}
fn pm_delete_rows(rows,key,value,owner) {
    if !rows {return 0;}let link=rows+16;
    while load64(link) {
        let row=load64(link);
        if m_eq(j_string(row,key),value) && (!owner || m_eq(j_string(row,"instanceId"),owner)) {store64(link,load64(row+24));}
        else {link=row+24;}
    }return 1;
}
fn pm_release_connector(data,ref) {
    let owner=j_string(ref,"instanceId");let id=j_string(ref,"connectorId");let mate=pc_first(j_get(data,"mates"));
    while mate {
        if pm_ref_matches(j_get(mate,"a"),owner,id) || pm_ref_matches(j_get(mate,"b"),owner,id) {return 1;}
        mate=load64(mate+24);
    }
    return pm_delete_rows(j_get(data,"connectors"),"id",id,owner);
}
fn cad_project_remove_mate(project,id) {
    cg_begin();let updated=j_parse(j_encode(project));let item=cad_project_item(updated);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let data=j_get(item,"data");let mates=j_get(data,"mates");let mate=pc_find(mates,id);
    if !mate {return cg_fail("Select an existing mate");}
    // Start at the displayed pose. A conflicting mate can itself be the one removed.
    pc_record_poses(data);cg_begin();
    pm_delete_rows(mates,"id",id,0);pm_delete_rows(j_get(data,"actuators"),"mateId",id,0);
    pm_release_connector(data,j_get(mate,"a"));pm_release_connector(data,j_get(mate,"b"));
    return pc_apply_assembly(updated,data);
}
fn cad_project_remove_instance(project,id) {
    cg_begin();let updated=j_parse(j_encode(project));let item=cad_project_item(updated);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let data=j_get(item,"data");let instances=j_get(data,"instances");
    if !m_len(id) || !pc_find(instances,id) {return cg_fail("Select an existing instance");}
    pc_record_poses(data);cg_begin();
    pm_delete_rows(instances,"id",id,0);pm_delete_rows(j_get(data,"connectors"),"instanceId",id,0);
    let mates=j_get(data,"mates");let removed=j_object();
    if mates {
        let link=mates+16;while load64(link) {
            let row=load64(link);if pm_touches(row,id) {
                cg_j_int(removed,j_string(row,"id"),1);store64(link,load64(row+24));
            }else {link=row+24;}
        }
    }
    let drivers=j_get(data,"actuators");if drivers {
        let link=drivers+16;while load64(link) {
            let row=load64(link);if j_get(removed,j_string(row,"mateId")) {store64(link,load64(row+24));}
            else {link=row+24;}
        }
    }
    if !pc_first(instances) && (!mates || j_kind(mates)==3 && !pc_first(mates)) && (!drivers || j_kind(drivers)==3 && !pc_first(drivers)) {
        let connectors=j_get(data,"connectors");if !connectors || j_kind(connectors)==3 {return updated;}
    }
    return pc_apply_assembly(updated,data);
}
fn cad_project_drive_mate(project,id,degrees) {
    cg_begin();let updated=j_parse(j_encode(project));let item=cad_project_item(updated);let data=j_get(item,"data");
    if !m_eq(j_string(item,"type"),"assembly") || !m_eq(j_string(pc_find(j_get(data,"mates"),id),"type"),"revolute") {
        return cg_fail("Select a revolute mate");
    }
    let servo=pc_mate_servo(data,id);if !servo {
        let drivers=j_get(data,"actuators");if !drivers {drivers=j_array();j_add(data,"actuators",drivers);}
        if j_kind(drivers)!=3 {return cg_fail("Expected an array of assembly actuators");}
        servo=j_object();cg_j_text(servo,"id",m_cat("servo-",m_int(pc_free_index(drivers,"servo-"))));
        cg_j_text(servo,"type","servo");cg_j_text(servo,"mateId",id);j_add(drivers,0,servo);
    }
    return pc_set_servo_angle(updated,data,servo,degrees);
}
