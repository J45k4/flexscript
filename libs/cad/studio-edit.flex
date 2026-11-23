// Expose direct driving values in the authored v1 document. Bindings and derived
// dimensions stay in the tree. Each edit rebuilds a copy before it is returned.
import "project.flex";

fn pcs_property(list,owner,key,slot,label,unit) {
    let entry=m_take(40);store64(entry,owner);store64(entry+8,key);store64(entry+16,slot);
    store64(entry+24,label);store64(entry+32,unit);cg_push(list,entry);return entry;
}
fn cad_studio_properties(project) {
    let list=cg_array();let row=pc_first(j_get(j_get(project,"assembly"),"mates"));
    while row {
        let kind=j_string(row,"type");let unit="mm";if m_eq(kind,"revolute") {unit="deg";}
        if !j_get(row,"drive") && !j_get(row,"held_transform") && (m_eq(kind,"revolute") || m_eq(kind,"slider") || m_eq(kind,"screw")) {
            pcs_property(list,row,"value",j_get(row,"value"),j_string(row,"id"),unit);
        }
        row=load64(row+24);
    }
    row=pc_first(j_get(project,"parameters"));while row {
        if j_get(row,"mm") && !j_get(row,"expression") {pcs_property(list,row,"mm",j_get(row,"mm"),j_string(row,"name"),"mm");}
        row=load64(row+24);
    }
    row=pc_first(j_get(project,"nodes"));while row {
        let id=j_string(row,"id");let kind=j_string(row,"type");
        if m_eq(kind,"box") || m_eq(kind,"drilled-board") {
            let slot=pc_first(j_get(row,"size"));let axis=0;
            while slot && axis<3 {
                let key=pcd_axis_key(axis);
                if !j_get(j_get(row,"size_bindings"),key) {pcs_property(list,row,0,slot,m_cat(id,m_cat(" / ",key)),"mm");}
                slot=load64(slot+24);axis=axis+1;
            }
        }else {
            if m_eq(kind,"cylinder") || m_eq(kind,"sphere") {pcs_property(list,row,"radius",j_get(row,"radius"),m_cat(id," / radius"),"mm");}
            if m_eq(kind,"cylinder") || (m_eq(kind,"extrude") && !j_get(row,"height_parameter")) {
                pcs_property(list,row,"height",j_get(row,"height"),m_cat(id," / height"),"mm");
            }
            if m_eq(kind,"revolve") {pcs_property(list,row,"sweep_deg",j_get(row,"sweep_deg"),m_cat(id," / sweep"),"deg");}
        }
        row=load64(row+24);
    }
    return list;
}
fn cad_studio_set_property(project,index,value) {
    cg_begin();let copy=j_parse(j_encode(project));let entry=cg_at(cad_studio_properties(copy),index);
    if !entry || value< -500000000 || value>500000000 {return cg_fail("Invalid PCAD property or value");}
    let number=cg_json_number(value);let key=load64(entry+8);let slot=load64(entry+16);
    if key {cg_j_set(load64(entry),key,number);}
    else {store64(slot,j_kind(number));store64(slot+8,j_value(number));}
    let mesh=cad_project_mesh(copy);if j_get(mesh,"error") || cg_error {return 0;}return copy;
}

fn pcs_shell_copy(project,side,thickness) {
    cg_begin();
    if !cad_project_is_studio(project) {return cg_fail("Shell requires a standalone PCAD design");}
    if !m_eq(side,"x") && !m_eq(side,"-x") && !m_eq(side,"y") && !m_eq(side,"-y") && !m_eq(side,"z") && !m_eq(side,"-z") {
        return cg_fail("Choose the signed local X, Y or Z opening face");
    }
    if thickness<10000 || thickness>500000000 {return cg_fail("Wall thickness must be from 0.01 to 500 mm");}
    return cad_project_open(j_encode(project));
}

fn pcs_shell_validate(copy,feature) {
    let suppressed=j_get(feature,"suppressed");
    if j_kind(suppressed)==5 && j_value(suppressed) {
        // A dormant feature still needs valid parameters for the next unsuppression.
        store64(suppressed+8,0);
        let checked=pcad_feature_mesh(j_parse(j_encode(copy)),j_string(feature,"id"));
        store64(suppressed+8,1);
        if cg_error || j_get(checked,"error") {return 0;}
        if !j_value(j_get(checked,"closed")) {return cg_fail("Shell did not produce a closed solid");}
    }
    let mesh=cad_project_mesh(copy);
    if cg_error || j_get(mesh,"error") {return 0;}
    if !j_value(j_get(mesh,"closed")) {return cg_fail("Shell did not produce a closed solid");}
    return copy;
}

// Append a modifier while preserving the identity of the output part and its assemblies.
fn cad_studio_add_shell(project,part_id,side,thickness) {
    let copy=pcs_shell_copy(project,side,thickness);if !copy {return 0;}
    let parts=j_get(copy,"parts");let part=pc_find(parts,part_id);let nodes=j_get(copy,"nodes");
    if !m_len(part_id) || !part {return cg_fail("Select a standalone PCAD output part");}
    if j_kind(nodes)!=3 || cg_j_count(nodes)>=48 {return cg_fail("PCAD supports at most 48 shape nodes");}
    let source=j_string(part,"node");
    if !cg_id(source) || !pc_find(nodes,source) {return cg_fail("Shell needs an earlier body in this part");}
    let order=j_get(copy,"feature_order");
    if order && j_kind(order)!=3 {return cg_fail("Feature order must list every shape ID exactly once");}
    let i=1;let id="shell-1";
    while pc_find(nodes,id) {i=i+1;id=m_cat("shell-",m_int(i));}
    let feature=j_object();cg_j_text(feature,"id",id);cg_j_text(feature,"type","shell");
    cg_j_text(feature,"source",source);cg_j_text(feature,"open_side",side);cg_j_set(feature,"thickness",cg_json_number(thickness));
    j_add(nodes,0,feature);
    if order {j_add(order,0,j_text(id));}
    cg_j_text(part,"node",id);
    return pcs_shell_validate(copy,feature);
}

// Update only the authored settings on the original feature.
fn cad_studio_set_shell(project,feature_id,side,thickness) {
    let copy=pcs_shell_copy(project,side,thickness);if !copy {return 0;}
    let feature=pc_find(j_get(copy,"nodes"),feature_id);
    if !m_len(feature_id) || !m_eq(j_string(feature,"type"),"shell") {return cg_fail("Select a standalone PCAD shell feature");}
    if !m_eq(side,j_string(feature,"open_side")) {cg_j_text(feature,"open_side",side);}
    if cg_number(j_get(feature,"thickness"))!=thickness || cg_error {
        cg_error=0;cg_j_set(feature,"thickness",cg_json_number(thickness));
    }
    return pcs_shell_validate(copy,feature);
}

fn pcs_remove(row,key) {
    let link=row+16;while load64(link) {
        let field=load64(link);if m_eq(load64(field+32),key) {store64(link,load64(field+24));return 1;}link=field+24;
    }
    return 0;
}
fn cad_studio_toggle_fixed(project,id) {
    cg_begin();let copy=j_parse(j_encode(project));let mesh=cad_project_mesh(copy);if cg_error {return 0;}
    let instance=pc_find(j_get(j_get(mesh,"assembly"),"instances"),id);
    if !instance {return cg_fail("Select an assembly occurrence");}
    let assembly=j_get(copy,"assembly");let pins=j_get(assembly,"fixed_instances");
    if pins && pcs_remove(pins,id) {
        if !cg_j_count(pins) {pcs_remove(assembly,"fixed_instances");}
    }else {
        if !pins {pins=j_object();j_add(assembly,"fixed_instances",pins);}
        cg_j_set(pins,id,j_parse(j_encode(j_get(instance,"transform"))));
    }
    mesh=cad_project_mesh(copy);if j_get(mesh,"error") || cg_error {return 0;}return copy;
}

// A selection may belong to a fastened child of the hinge. Look through those
// links, respecting solved occurrence pins and the scoped identity of each mate.
fn cad_studio_hinge(project,mesh,id) {
    let assembly=j_get(mesh,"assembly");let instances=j_get(assembly,"instances");let mates=j_get(assembly,"mates");
    let count=cg_j_count(instances);let step=0;
    while step<count {
        let occurrence=pc_find(instances,id);
        if !occurrence || j_value(j_get(occurrence,"fixed")) {return 0;}
        let row=pc_first(mates);while row && !m_eq(j_string(row,"child"),id) {row=load64(row+24);}
        if !row || j_value(j_get(row,"suppressed")) {return 0;}
        if m_eq(j_string(row,"type"),"revolute") {
            if j_value(j_get(row,"locked")) || j_get(row,"driven_by") {return 0;}
            let source=pc_find(j_get(j_get(project,"assembly"),"mates"),j_string(row,"id"));
            if !source {return 0;}
            let frame=ca_held(j_get(row,"hinge_frame"));if !frame {return 0;}return cg_v(frame,source,row);
        }
        if !m_eq(j_string(row,"type"),"fixed") {return 0;}id=j_string(row,"parent");step=step+1;
    }
    return 0;
}

fn cad_studio_hinge_followers(mesh,joint) {
    let assembly=j_get(mesh,"assembly");let mates=j_get(assembly,"mates");
    let instances=j_get(assembly,"instances");let moving=cg_array();
    cg_push(moving,cg_v(j_string(joint,"child"),0,0));
    let row=pc_first(mates);
    while row {
        if j_get(row,"driven_by") {return 0;}
        row=load64(row+24);
    }
    let i=0;while i<cg_count(moving) {
        let id=load64(cg_at(moving,i));row=pc_first(mates);
        while row {
            let child=j_string(row,"child");let parent=j_string(row,"parent");
            if j_value(j_get(row,"suppressed")) {parent=cah_parent(child);}
            if m_eq(id,parent) && !ca_find(moving,child) && !j_value(j_get(pc_find(instances,child),"fixed")) {
                cg_push(moving,cg_v(child,0,0));
            }
            row=load64(row+24);
        }
        i=i+1;
    }
    return moving;
}
