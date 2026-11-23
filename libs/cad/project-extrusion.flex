import "project-history.flex";

fn pc_extrusion_options_valid(operation,end,flip,target_id) {
    if !m_eq(operation,"newBody") && !m_eq(operation,"cut") && !m_eq(operation,"join") {
        return cg_fail("Unknown solid operation");
    }
    if flip!=0 && flip!=1 {return cg_fail("Extrusion flip must be boolean");}
    let to_body=m_eq(end,"up-to-body");
    if !m_eq(end,"blind") && !m_eq(end,"symmetric") && !m_eq(end,"through-all") && !to_body {
        return cg_fail("Unknown extrusion end condition");
    }
    if (m_eq(end,"through-all") || to_body) && m_eq(operation,"newBody") {
        return cg_fail("Extent needs a cut or join");
    }
    if to_body && !m_len(target_id) {return cg_fail("Select an extrusion target body");}
    return 1;
}
fn pc_write_extrusion_options(node,end,flip,target_id) {
    pc_remove_field(node,"endCondition");pc_remove_field(node,"flip");pc_remove_field(node,"targetId");
    if !m_eq(end,"blind") {cg_j_text(node,"endCondition",end);}
    if m_eq(end,"up-to-body") {cg_j_text(node,"targetId",target_id);}
    if flip {cg_j_set(node,"flip",j_new(5,1));}
}
fn pc_same_extrusion_options(node,depth,operation,end,flip,target_id) {
    if !m_eq(j_string(node,"operation"),operation) {return 0;}
    let previous_end=j_get(node,"endCondition");
    if !previous_end {
        if !m_eq(end,"blind") {return 0;}
    }else if !m_eq(j_string(node,"endCondition"),end) {return 0;}
    let previous_flip=j_get(node,"flip");
    if (previous_flip && j_kind(previous_flip)!=5) || j_value(previous_flip)!=flip {return 0;}
    if m_eq(end,"up-to-body") && !m_eq(j_string(node,"targetId"),target_id) {return 0;}
    let previous_depth=cg_number(j_get(node,"depth"));
    if cg_error {cg_begin();return 0;}
    return previous_depth==depth;
}

fn pc_extrusion_target_feature(part,id) {
    if !m_len(id) {return 0;}
    let node=pc_find(pc_nodes(part),id);
    if !m_eq(j_string(node,"type"),"extrude") {return cg_fail("Select an extrusion");}
    return node;
}

// Appending restores the end of the timeline, while editing an existing row
// exposes only bodies currently evaluated before that row.
fn cad_project_extrusion_targets(project,feature_id) {
    cg_begin();let part=cad_project_part(project);
    if j_integer(project,"version")!=4 || !part {return cg_fail("Select a v4 part");}
    let stop=pc_extrusion_target_feature(part,feature_id);
    if cg_error {return 0;}
    let bodies=pc_walk_features_before(part,cg_array(),j_array(),stop,!stop);
    if cg_error {return 0;}
    let result=j_array();let i=0;
    while i<cg_count(bodies) {
        let body=cg_at(bodies,i);let row=j_object();
        cg_j_text(row,"id",load64(body));cg_j_text(row,"name",load64(body+8));
        j_add(result,0,row);i=i+1;
    }
    return result;
}

// Surface picking needs the same history boundary as the target list. Use a
// disposable rollback copy so the caller can keep the saved timeline intact.
fn cad_project_extrusion_target_stage(project,feature_id) {
    cg_begin();let part=cad_project_part(project);
    if j_integer(project,"version")!=4 || !part {return cg_fail("Select a v4 part");}
    let stop=pc_extrusion_target_feature(part,feature_id);
    if cg_error {return 0;}
    return pc_project_stage_before(project,stop,stop!=0);
}
fn pc_project_stage_before(project,stop,keep_rollback) {
    let part=cad_project_part(project);
    let bar=j_get(j_get(j_get(part,"data"),"tree"),"rollbackIndex");
    if bar && (j_kind(bar)!=1 || j_value(bar)<0) {return cg_fail("Invalid feature rollback index");}
    let count=0;let row=pc_first(pc_nodes(part));
    while row && row!=stop {
        if !cg_step() {return 0;}
        if pc_model_feature(row) {count=count+1;}
        row=load64(row+24);
    }
    if keep_rollback && bar && count>j_value(bar) {count=j_value(bar);}
    return cad_project_roll_to(project,count);
}

// Validate saved options through the end of the tree, including when the
// edited feature is suppressed or the rollback bar is above it.
fn pc_extrusion_validation_tree(project,id) {
    let part=cad_project_part(project);let node=pc_find(pc_nodes(part),id);
    let tree=j_get(j_get(part,"data"),"tree");
    if !j_get(tree,"rollbackIndex") && !j_value(j_get(node,"suppressed")) {return project;}
    let copy=j_parse(j_encode(project));part=cad_project_part(copy);
    tree=j_get(j_get(part,"data"),"tree");node=pc_find(pc_nodes(part),id);
    if j_kind(tree)==4 {pc_remove_field(tree,"rollbackIndex");}
    pc_remove_field(node,"suppressed");return copy;
}
fn cad_project_set_extrusion_options(project,feature_id,depth,operation,end,flip,target_id) {
    cg_begin();
    if depth<=0 || depth>500000000 {return cg_fail("Extrusion depth must be positive and at most 500 mm");}
    if !pc_extrusion_options_valid(operation,end,flip,target_id) {return 0;}
    let nodes=pc_nodes(cad_project_part(project));let before=pc_find(nodes,feature_id);
    if !m_eq(j_string(before,"type"),"extrude") {return cg_fail("Select an extrusion");}
    let result=j_parse(j_encode(project));let edited=pc_nodes(cad_project_part(result));let node=pc_find(edited,feature_id);
    if !pc_same_extrusion_options(before,depth,operation,end,flip,target_id) {
        cg_j_text(node,"operation",operation);cg_j_set(node,"depth",cg_json_number(depth));
        pc_write_extrusion_options(node,end,flip,target_id);
    }
    if !m_eq(j_string(before,"operation"),operation)
        && !pc_same_boolean_targets(pc_history_targets(nodes),pc_history_targets(edited),feature_id) {return 0;}
    let valid_before=pc_extrusion_validation_tree(project,feature_id);
    let valid_after=pc_extrusion_validation_tree(result,feature_id);
    if !pc_checked_feature_edit_requiring(valid_before,valid_after,feature_id) {return 0;}
    return result;
}
