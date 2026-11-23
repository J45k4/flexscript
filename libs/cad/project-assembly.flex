// PuppyCAD v4 uses three.js intrinsic XYZ Euler frames and named connectors.
// The pose matrices and polygon placement are shared with the Biscuit evaluator.
import "assembly.flex";
import "free-mates.flex";

import "project-number.flex";

fn pc_pose_vector(value,default_value) {
    if !value {return cg_v(default_value,default_value,default_value);}
    return cg_v(pc_pose_number(j_get(value,"x")),pc_pose_number(j_get(value,"y")),pc_pose_number(j_get(value,"z")));
}
fn pc_radians(degrees) {
    return f64_mul(f64_div(f64_from_i64(degrees),f64_from_i64(180000000)),0x400921fb54442d18);
}
fn pc_sincos_component(value) {
    return f64_to_i64_round(f64_mul(value,f64_from_i64(1000000)));
}
fn pc_pose_frame(row,position) {
    let p=pc_pose_vector(j_get(row,position),0);let r=pc_pose_vector(j_get(row,"rotation"),0);
    let x=pc_radians(load64(r));let y=pc_radians(load64(r+8));let z=pc_radians(load64(r+16));
    let rx=ca_identity();let ry=ca_identity();let rz=ca_identity();
    let c=pc_sincos_component(f64_cos(x));let s=pc_sincos_component(f64_sin(x));store64(rx+32,c);store64(rx+40,-s);store64(rx+56,s);store64(rx+64,c);
    c=pc_sincos_component(f64_cos(y));s=pc_sincos_component(f64_sin(y));store64(ry,c);store64(ry+16,s);store64(ry+48,-s);store64(ry+64,c);
    c=pc_sincos_component(f64_cos(z));s=pc_sincos_component(f64_sin(z));store64(rz,c);store64(rz+8,-s);store64(rz+24,s);store64(rz+32,c);
    let pose=ca_product(rx,ca_product(ry,rz));m_copy(pose+72,p,24);return pose;
}
fn pc_mate_servo(data,id) {
    let servo=pc_first(j_get(data,"actuators"));
    while servo {
        if m_eq(j_string(servo,"type"),"servo") && m_eq(j_string(servo,"mateId"),id) {return servo;}
        servo=load64(servo+24);
    }
    return 0;
}
fn pc_connector(data,ref) {
    let row=pc_first(j_get(data,"connectors"));let owner=j_string(ref,"instanceId");
    while row {
        if m_eq(j_string(row,"id"),j_string(ref,"connectorId")) && m_eq(j_string(row,"instanceId"),owner) {return row;}
        row=load64(row+24);
    }
    return cg_fail("Unknown assembly connector");
}
// Instance fields: ID, source, initial/solved poses, incoming fasten, scale,
// mated flag, rigid-group parent and group record.
fn pc_instance(instances,world,ref) {
    if j_kind(j_get(ref,"instanceId"))==0 {return world;}
    let instance=ca_find(instances,j_string(ref,"instanceId"));
    if !instance {return cg_fail("Unknown mate instance");}return instance;
}
fn pc_unscaled(row) {
    let scale=load64(row+40);let k=0;
    while k<24 {if cg_abs(load64(scale+k)-1000000)>1 {return 0;}k=k+8;}
    return 1;
}
fn pc_assembly_links(data,instances,world) {
    let links=cg_array();let seen=cg_array();let mate=pc_first(j_get(data,"mates"));
    while mate && !cg_error {
        let id=j_string(mate,"id");if !m_len(id) || ca_find(seen,id) {return cg_fail("Duplicate or empty assembly mate ID");}
        cg_push(seen,cg_v(id,mate,0));
        let a=j_get(mate,"a");let b=j_get(mate,"b");let left=pc_instance(instances,world,a);let right=pc_instance(instances,world,b);
        if !left || !right || left==right {return cg_fail("Mate needs distinct instances");}
        let ca=pc_connector(data,a);let cb=pc_connector(data,b);
        let fa=pc_pose_frame(ca,"position");let fb=pc_pose_frame(cb,"position");
        let kind=j_string(mate,"type");let mode=PC_FASTEN;let rotation=0;
        if m_eq(kind,"fasten") {store64(right+32,1);}
        else if m_eq(kind,"revolute") && pc_mate_servo(data,j_string(mate,"id")) {
            let servo=pc_mate_servo(data,j_string(mate,"id"));
            let angle=pc_radians(pc_pose_number(j_get(servo,"homeDeg")));
            rotation=ca_identity();let c=pc_sincos_component(f64_cos(angle));let s=pc_sincos_component(f64_sin(angle));
            store64(rotation,c);store64(rotation+8,-s);store64(rotation+24,s);store64(rotation+32,c);
            fa=ca_product(fa,rotation);mode=PC_SERVO;
        }else if m_eq(kind,"revolute") {mode=PC_REVOLUTE;}
        else if m_eq(kind,"prismatic") {mode=PC_PRISMATIC;}
        else if m_eq(kind,"planar") {mode=PC_PLANAR;}
        else if m_eq(kind,"ball") {mode=PC_BALL;}
        else {return cg_fail("Unknown assembly mate type");}
        store64(left+48,1);store64(right+48,1);
        if mode==PC_FASTEN && (!pc_unscaled(left) || !pc_unscaled(right)) {return cg_fail("Fixed mates require unscaled instances");}
        let link=m_take(64);store64(link+40,ca);store64(link+48,cb);store64(link+56,rotation);store64(link,left);store64(link+8,right);
        let delta=ca_product(fa,ca_inverse(fb));store64(link+16,delta);store64(link+24,ca_inverse(delta));store64(link+32,mode);
        cg_push(links,link);mate=load64(mate+24);
    }
    return links;
}
fn pc_propagate(links,fixed_only) {
    let changed=1;
    while changed && !cg_error {
        changed=0;let i=0;
        while i<cg_count(links) && !cg_error {
            if !cg_step() {return 0;}
            let link=cg_at(links,i);let a=load64(link);let b=load64(link+8);
            if !fixed_only || !load64(link+32) {
                if load64(a+24) && !load64(b+24) {store64(b+24,ca_product(load64(a+24),load64(link+16)));changed=1;}
                else if load64(b+24) && !load64(a+24) {store64(a+24,ca_product(load64(b+24),load64(link+24)));changed=1;}
            }
            i=i+1;
        }
    }
    return !cg_error;
}
fn pc_solve_instances(data,instances,world) {
    let links=pc_assembly_links(data,instances,world);if cg_error {return 0;}
    // Resolve ground fastens first. Then seed other rigid groups from their
    // non-child instance, matching the v4 fixed-connection placement rule.
    pc_propagate(links,1);let pass=0;
    while pass<2 && !cg_error {
        let i=0;while i<cg_count(instances) {
            let row=cg_at(instances,i);
            if !load64(row+24) && (pass || !load64(row+32)) {store64(row+24,load64(row+16));pc_propagate(links,1);}
            i=i+1;
        }
        pass=pass+1;
    }
    if !pc_check_links(links,1) {return 0;}
    let link_index=0;
    while link_index<cg_count(links) {
        let link=cg_at(links,link_index);
        if load64(link+32)>=PC_REVOLUTE || !pc_unscaled(load64(link)) || !pc_unscaled(load64(link+8)) {
            return pf_solve(instances,world,links);
        }
        link_index=link_index+1;
    }

    let i=0;while i<cg_count(instances) {
        let row=cg_at(instances,i);store64(row+16,load64(row+24));store64(row+24,0);i=i+1;
    }
    pc_propagate(links,1);
    let first=cg_at(instances,0);if !load64(first+24) {store64(first+24,load64(first+16));}
    pc_propagate(links,0);i=0;
    while i<cg_count(instances) && !cg_error {
        let row=cg_at(instances,i);
        if !load64(row+24) && load64(row+48) {
            // A disconnected driven joint has no grounded parent. Let both
            // groups move, starting from their fasten-only placements.
            let j=0;while j<cg_count(instances) {
                let member=cg_at(instances,j);store64(member+24,load64(member+16));j=j+1;
            }
            return pf_solve(instances,world,links);
        }
        if !load64(row+24) {store64(row+24,load64(row+16));}
        i=i+1;
    }
    return pc_check_links(links,0);
}
fn pc_check_links(links,fixed_only) {
    let i=0;while i<cg_count(links) && !cg_error {
        let link=cg_at(links,i);
        if !fixed_only || !load64(link+32) {
            let expected=ca_product(load64(load64(link)+24),load64(link+16));let actual=load64(load64(link+8)+24);
            let k=0;while k<96 {
                let tol=8;if k>=72 {tol=1000;}
                if cg_abs(load64(expected+k)-load64(actual+k))>tol {return cg_fail("Conflicting assembly mates");}
                k=k+8;
            }
        }
        i=i+1;
    }
    return !cg_error;
}
fn pc_instance_row(instance) {
    let row=m_take(80);store64(row+56,row);store64(row+64,0);store64(row+48,0);let transform=j_get(instance,"transform");
    if transform && j_kind(transform)!=4 {cg_fail("Invalid assembly instance transform");}
    store64(row,j_string(instance,"id"));store64(row+8,instance);store64(row+16,pc_pose_frame(transform,"translation"));
    store64(row+72,load64(row+16));store64(row+24,0);store64(row+32,0);store64(row+40,pc_pose_vector(j_get(transform,"scale"),1000000));return row;
}
fn pc_assembly_poses(data) {
    if j_get(data,"mates") && j_kind(j_get(data,"mates"))!=3 {return cg_fail("Expected an array of assembly mates");}
    if j_get(data,"connectors") && j_kind(j_get(data,"connectors"))!=3 {return cg_fail("Expected an array of assembly connectors");}
    if j_get(data,"actuators") && j_kind(j_get(data,"actuators"))!=3 {return cg_fail("Expected an array of assembly actuators");}
    let instance=pc_first(j_get(data,"instances"));let rows=cg_array();
    if !instance {return cg_fail("Assembly has no instances");}
    while instance && !cg_error {
        let id=j_string(instance,"id");if !m_len(id) || ca_find(rows,id) {return cg_fail("Duplicate or empty assembly instance ID");}
        cg_push(rows,pc_instance_row(instance));instance=load64(instance+24);
    }
    let world=pc_instance_row(0);store64(world+24,load64(world+16));
    if !pc_solve_instances(data,rows,world) {return 0;}
    return rows;
}
fn pc_place_scaled_bodies(parts,frame,scale) {
    let pose=ca_product(ca_identity(),frame);
    let k=0;let mirror=0;
    while k<3 {
        let factor=load64(scale+k*8);if !factor {return cg_fail("Assembly scale must be nonzero");}if factor<0 {mirror=!mirror;}
        let j=k;while j<9 {store64(pose+j*8,load64(pose+j*8)*factor/1000000);j=j+3;}k=k+1;
    }
    let polygons=cg_array();let j=0;
    while j<cg_count(parts) && !cg_error {
        cg_join(polygons,ca_place(load64(cg_at(parts,j)+24),pose));j=j+1;
    }
    if mirror {j=0;while j<cg_count(polygons) {cg_flip(cg_at(polygons,j));j=j+1;}}
    return polygons;
}
fn pc_assembly_bodies(project,item) {
    let rows=pc_assembly_poses(j_get(item,"data"));let bodies=cg_array();let cache=cg_array();let i=0;
    while i<cg_count(rows) && !cg_error {
        let row=cg_at(rows,i);let instance=load64(row+8);let id=j_string(instance,"partId");
        let prototype=ca_find(cache,id);
        if !prototype {
            let part=pc_find(j_get(project,"items"),id);
            if !m_eq(j_string(part,"type"),"part") {return cg_fail("Assembly instance references a missing part");}
            prototype=cg_v(id,pc_part_bodies(part),0);cg_push(cache,prototype);
        }
        let polygons=pc_place_scaled_bodies(load64(prototype+8),load64(row+24),load64(row+40));
        if cg_error {return 0;}
        let name=j_string(instance,"name");if !m_len(name) {name=load64(row);}
        cad_part(bodies,polygons,load64(row),name,"#82b38e");i=i+1;
    }
    return bodies;
}

fn pc_pose_json(x,y,z) {
    let point=j_object();j_add(point,"x",cg_json_number(x));j_add(point,"y",cg_json_number(y));j_add(point,"z",cg_json_number(z));return point;
}
fn pc_angle_degrees(y,x) {
    let radians=f64_atan2(f64_from_i64(y),f64_from_i64(x));
    return f64_to_i64_round(f64_div(f64_mul(radians,f64_from_i64(180000000)),0x400921fb54442d18));
}
fn pc_pose_rotation(pose) {
    let cy=cg_sqrt(load64(pose)*load64(pose)+load64(pose+8)*load64(pose+8));
    let y=pc_angle_degrees(load64(pose+16),cy);let x=0;let z=0;
    if cy<2 {x=pc_angle_degrees(load64(pose+56),load64(pose+32));}
    else {x=pc_angle_degrees(-load64(pose+40),load64(pose+64));z=pc_angle_degrees(-load64(pose+8),load64(pose));}
    return pc_pose_json(x,y,z);
}
fn pc_save_pose(instance,pose) {
    let transform=j_get(instance,"transform");
    if !transform {transform=j_object();j_add(instance,"transform",transform);}
    cg_j_set(transform,"translation",pc_pose_json(load64(pose+72),load64(pose+80),load64(pose+88)));
    cg_j_set(transform,"rotation",pc_pose_rotation(pose));return !cg_error;
}
// Expose the placement shown by the assembly solver, including default axes.
fn cad_project_instance_transform(project,id) {
    cg_begin();let item=cad_project_item(project);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let rows=pc_assembly_poses(j_get(item,"data"));if cg_error {return 0;}
    let row=ca_find(rows,id);if !row {return cg_fail("Select an existing instance");}
    let transform=j_get(load64(row+8),"transform");let rotation=j_get(transform,"rotation");
    let pose=load64(row+24);let scale=load64(row+40);let result=j_object();
    j_add(result,"translation",pc_pose_json(load64(pose+72),load64(pose+80),load64(pose+88)));
    if load64(row+48) {rotation=pc_pose_rotation(pose);}
    else if rotation {rotation=j_parse(j_encode(rotation));}
    else {rotation=pc_pose_json(0,0,0);}
    j_add(result,"rotation",rotation);j_add(result,"scale",pc_pose_json(load64(scale),load64(scale+8),load64(scale+16)));
    return result;
}
fn cad_project_replace_instance_part(project,id,part_id) {
    cg_begin();
    let updated=j_parse(j_encode(project));let item=cad_project_item(updated);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let instance=pc_find(j_get(j_get(item,"data"),"instances"),id);
    if !m_len(id) || !instance {return cg_fail("Select an existing instance");}
    let part=pc_find(j_get(updated,"items"),part_id);
    if !m_len(part_id) || !m_eq(j_string(part,"type"),"part") {return cg_fail("Select an existing part definition");}
    cg_j_text(instance,"partId",part_id);
    // The connector graph solves independently of the selected part geometry.
    // Evaluate the rebuilt assembly while preserving the authored pose records.
    let mesh=cad_project_mesh(updated);
    if j_get(mesh,"error") {return 0;}
    return updated;
}
fn cad_project_set_instance_component(project,id,group,axis,value) {
    cg_begin();
    if !m_eq(group,"translation") && !m_eq(group,"rotation") && !m_eq(group,"scale") {return cg_fail("Unknown transform field");}
    if !m_eq(axis,"x") && !m_eq(axis,"y") && !m_eq(axis,"z") {return cg_fail("Unknown transform axis");}
    if value< -500000000 || value>500000000 {return cg_fail("Transform component exceeds supported range");}
    let scaling=m_eq(group,"scale");if scaling && !value {return cg_fail("Assembly scale must be nonzero");}
    let updated=j_parse(j_encode(project));let item=cad_project_item(updated);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let data=j_get(item,"data");let instance=pc_find(j_get(data,"instances"),id);
    if !instance {return cg_fail("Select an existing instance");}
    if !pc_record_poses(data) {return 0;}
    let transform=j_get(instance,"transform");if !transform {transform=j_object();j_add(instance,"transform",transform);}
    let vector=j_get(transform,group);if !vector {
        let initial=0;if scaling {initial=1000000;}
        vector=pc_pose_json(initial,initial,initial);j_add(transform,group,vector);
    }
    cg_j_set(vector,axis,cg_json_number(value));return pc_apply_assembly(updated,data);
}

// Saved connector IDs need only be unique on their owning occurrence.
// An empty owner identifies a frame in world coordinates.
fn pc_editable_connector(data,owner,id) {
    let connectors=j_get(data,"connectors");
    if !m_len(id) || j_kind(connectors)!=3 {return cg_fail("Select an existing connector");}
    if m_len(owner) && !pc_find(j_get(data,"instances"),owner) {return cg_fail("Unknown connector instance");}
    let row=pc_first(connectors);let result=0;
    while row {
        if !cg_step() {return 0;}
        if m_eq(j_string(row,"id"),id) && m_eq(j_string(row,"instanceId"),owner) {
            let instance=j_get(row,"instanceId");let kind=j_kind(instance);
            if instance && kind!=0 && kind!=2 {return cg_fail("Invalid connector instance");}
            if result {return cg_fail("Duplicate connector on an assembly instance");}
            result=row;
        }
        row=load64(row+24);
    }
    if !result {return cg_fail("Select an existing connector");}
    return result;
}
fn pc_local_connector_frame(row) {
    let p=pc_pose_vector(j_get(row,"position"),0);
    let r=pc_pose_vector(j_get(row,"rotation"),0);
    if cg_error {return 0;}
    let frame=j_object();
    j_add(frame,"position",pc_pose_json(load64(p),load64(p+8),load64(p+16)));
    j_add(frame,"rotation",pc_pose_json(load64(r),load64(r+8),load64(r+16)));
    return frame;
}
fn cad_project_connector_frame(project,owner,id) {
    cg_begin();let item=cad_project_item(project);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let connector=pc_editable_connector(j_get(item,"data"),owner,id);
    if !connector {return 0;}
    return pc_local_connector_frame(connector);
}
fn pc_empty_connector_assembly(data) {
    let instances=j_get(data,"instances");let mates=j_get(data,"mates");let drivers=j_get(data,"actuators");
    return j_kind(instances)==3 && !pc_first(instances)
        && (!mates || j_kind(mates)==3 && !pc_first(mates))
        && (!drivers || j_kind(drivers)==3 && !pc_first(drivers));
}
fn pc_connector_owner_set(row,owner) {
    if !m_len(owner) {return cg_j_set(row,"instanceId",j_new(0,0));}
    return cg_j_text(row,"instanceId",owner);
}
fn cad_project_reassign_connector(project,owner,id,next_owner,next_id) {
    cg_begin();
    if !m_len(next_id) {return cg_fail("Enter a connector ID");}
    let updated=j_parse(j_encode(project));let item=cad_project_item(updated);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let data=j_get(item,"data");let connector=pc_editable_connector(data,owner,id);
    if !connector {return 0;}
    if m_len(next_owner) && !pc_find(j_get(data,"instances"),next_owner) {return cg_fail("Unknown connector instance");}
    let change_owner=!m_eq(owner,next_owner);let change_id=!m_eq(id,next_id);
    if change_owner || change_id {
        let row=pc_first(j_get(data,"connectors"));
        while row {
            if !cg_step() {return 0;}
            if row!=connector && m_eq(j_string(row,"instanceId"),next_owner) && m_eq(j_string(row,"id"),next_id) {
                return cg_fail("Connector ID already exists on the destination");
            }
            row=load64(row+24);
        }
        if change_id {cg_j_text(connector,"id",next_id);}
        if change_owner {pc_connector_owner_set(connector,next_owner);}
        let mate=pc_first(j_get(data,"mates"));
        while mate {
            if !cg_step() {return 0;}
            let index=0;
            while index<2 {
                let key="a";if index {key="b";}
                let side=j_get(mate,key);
                if m_eq(j_string(side,"instanceId"),owner) && m_eq(j_string(side,"connectorId"),id) {
                    if change_id {cg_j_text(side,"connectorId",next_id);}
                    if change_owner {pc_connector_owner_set(side,next_owner);}
                }
                index=index+1;
            }
            mate=load64(mate+24);
        }
    }
    if pc_empty_connector_assembly(data) {return updated;}
    let mesh=cad_project_mesh(updated);
    if j_get(mesh,"error") {return 0;}
    return updated;
}
fn cad_project_set_connector_component(project,owner,id,group,axis,value) {
    cg_begin();
    if !m_eq(group,"position") && !m_eq(group,"rotation") {return cg_fail("Unknown connector frame field");}
    if !m_eq(axis,"x") && !m_eq(axis,"y") && !m_eq(axis,"z") {return cg_fail("Unknown connector frame axis");}
    if value< -500000000 || value>500000000 {return cg_fail("Connector frame component exceeds supported range");}
    let updated=j_parse(j_encode(project));let item=cad_project_item(updated);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let data=j_get(item,"data");let connector=pc_editable_connector(data,owner,id);
    if !connector {return 0;}
    let frame=pc_local_connector_frame(connector);if !frame {return 0;}
    let previous=pc_pose_number(j_get(j_get(frame,group),axis));
    if previous!=value {
        let vector=j_get(connector,group);
        if !vector {vector=pc_pose_json(0,0,0);j_add(connector,group,vector);}
        cg_j_set(vector,axis,cg_json_number(value));
    }
    // A retained world connector is editable even when the assembly is empty.
    if pc_empty_connector_assembly(data) {return updated;}
    if previous==value {
        let mesh=cad_project_mesh(updated);if j_get(mesh,"error") {return 0;}
        return updated;
    }
    return pc_apply_assembly(updated,data);
}
// Return a separate document so a conflicting mate or failed rebuild leaves
// the original home angle, instance placements and unknown fields intact.
fn cad_project_servo_angle(project,mate_id,degrees) {
    cg_begin();
    let updated=j_parse(j_encode(project));let item=cad_project_item(updated);let data=j_get(item,"data");
    let mate=pc_find(j_get(data,"mates"),mate_id);let servo=pc_mate_servo(data,mate_id);
    if !servo || !m_eq(j_string(mate,"type"),"revolute") {return cg_fail("Select a servo-driven revolute mate");}
    return pc_set_servo_angle(updated,data,servo,degrees);
}
fn pc_set_servo_angle(updated,data,servo,degrees) {
    if cg_abs(degrees)>500000000 {return cg_fail("Servo angle exceeds supported range");}
    cg_j_set(servo,"homeDeg",cg_json_number(degrees));
    let range=j_get(servo,"commandRange");
    if !range {range=j_object();j_add(servo,"commandRange",range);}
    let low=-180000000;let high=180000000;
    if j_get(range,"minDeg") {low=pc_pose_number(j_get(range,"minDeg"));}
    if j_get(range,"maxDeg") {high=pc_pose_number(j_get(range,"maxDeg"));}
    if degrees<low {low=degrees;}if degrees>high {high=degrees;}
    cg_j_set(range,"minDeg",cg_json_number(low));cg_j_set(range,"maxDeg",cg_json_number(high));
    return pc_apply_assembly(updated,data);
}
fn cad_project_solve_assembly(project) {
    cg_begin();
    let updated=j_parse(j_encode(project));let item=cad_project_item(updated);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    return pc_apply_assembly(updated,j_get(item,"data"));
}
fn pc_record_poses(data) {
    let rows=pc_assembly_poses(data);let i=0;
    while i<cg_count(rows) && !cg_error {
        let row=cg_at(rows,i);if load64(row+48) {pc_save_pose(load64(row+8),load64(row+24));}i=i+1;
    }
    return !cg_error;
}
fn pc_apply_assembly(updated,data) {
    if !pc_record_poses(data) {return 0;}
    let mesh=cad_project_mesh(updated);if j_get(mesh,"error") {return 0;}return updated;
}

// Resolve the movable hinge above a picked occurrence through fastened children.
// Return its solved world frame, servo, and mate. Ambiguous or grounded chains
// have no independent drag coordinate.
fn cad_project_servo_frame(project,id) {
    cg_begin();let item=cad_project_item(project);if !m_eq(j_string(item,"type"),"assembly") {return 0;}
    let data=j_get(item,"data");let instances=j_get(data,"instances");let limit=cg_j_count(instances);
    let chain=0;
    while chain<limit {
        let instance=pc_find(instances,id);if !instance || j_value(j_get(instance,"fixed")) {return 0;}
        let mate=pc_first(j_get(data,"mates"));let incoming=0;
        while mate {
            if m_eq(j_string(j_get(mate,"b"),"instanceId"),id) {
                if incoming {return 0;}incoming=mate;
            }
            mate=load64(mate+24);
        }
        if !incoming || j_value(j_get(incoming,"suppressed")) || j_value(j_get(incoming,"locked")) {return 0;}
        let a=j_get(incoming,"a");id=j_string(a,"instanceId");
        let kind=j_string(incoming,"type");
        if m_eq(kind,"revolute") {
            let servo=pc_mate_servo(data,j_string(incoming,"id"));if !servo || !j_get(servo,"homeDeg") {return 0;}
            let frame=pc_pose_frame(pc_connector(data,a),"position");
            let rows=pc_assembly_poses(data);if cg_error {return 0;}
            if j_kind(j_get(a,"instanceId"))!=0 {
                let parent=ca_find(rows,id);if !parent {return 0;}
                frame=ca_product(load64(parent+24),frame);
            }
            return cg_v(frame,servo,incoming);
        }
        if !m_eq(kind,"fasten") {return 0;}chain=chain+1;
    }
    return 0;
}


// Identify the rigidly moving subtree for an independent hinge preview.
// A closed constraint loop crossing this subtree requires a full solve.
fn cad_project_hinge_followers(data,mate) {
    let moving=cg_array();let child=j_string(j_get(mate,"b"),"instanceId");
    cg_push(moving,cg_v(child,0,0));let mates=j_get(data,"mates");let i=0;
    while i<cg_count(moving) {
        let id=load64(cg_at(moving,i));let row=pc_first(mates);
        while row {
            if !cg_step() {return 0;}
            if m_eq(j_string(j_get(row,"a"),"instanceId"),id) {
                let kind=j_string(row,"type");
                if !m_eq(kind,"fasten") && !(m_eq(kind,"revolute") && pc_mate_servo(data,j_string(row,"id"))) {return 0;}
                let next=j_string(j_get(row,"b"),"instanceId");
                if !m_len(next) || ca_find(moving,next) {return 0;}
                cg_push(moving,cg_v(next,0,0));
            }
            row=load64(row+24);
        }
        i=i+1;
    }
    let row=pc_first(mates);
    while row {
        if row!=mate && ca_find(moving,j_string(j_get(row,"b"),"instanceId"))
            && !ca_find(moving,j_string(j_get(row,"a"),"instanceId")) {return 0;}
        row=load64(row+24);
    }
    return moving;
}
