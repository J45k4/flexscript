// Edit the feature history on a document copy so failed changes are atomic.
import "project.flex";
fn pc_remove_field(object,key) {
    let link=object+16;
    while load64(link) {
        let field=load64(link);
        if m_eq(load64(field+32),key) {store64(link,load64(field+24));return 1;}
        link=field+24;
    }
    return 0;
}
fn cad_project_suppress_feature(project,id,suppressed) {
    cg_begin();let result=j_parse(j_encode(project));
    let row=pc_find(pc_nodes(cad_project_part(result)),id);
    if !row || !pc_model_feature(row) {return cg_fail("Feature is missing");}
    if suppressed {cg_j_set(row,"suppressed",j_new(5,1));}
    else {pc_remove_field(row,"suppressed");}
    return result;
}
// The web v4 chamfer stores optional d2. Zero selects the saved d1 default.
fn cad_project_set_chamfer_distances(project,id,d1,d2) {
    cg_begin();
    if d1<=0 || d1>500000000 || d2<0 || d2>500000000 {return cg_fail("Chamfer distances must be positive and at most 500 mm");}
    let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let row=pc_find(nodes,id);
    if !m_eq(j_string(row,"type"),"chamfer") {return cg_fail("Select a saved chamfer");}
    if !pc_chamfer_reference(nodes,row) {return 0;}
    let previous=pc_chamfer_dimensions(row);cg_error=0;
    let other=j_get(row,"d2");
    if !previous || load64(previous)!=d1 {cg_j_set(row,"d1",cg_json_number(d1));}
    if d2 && (!other || !previous || load64(previous+8)!=d2) {cg_j_set(row,"d2",cg_json_number(d2));}
    if !d2 && other {pc_remove_field(row,"d2");}
    return pc_checked_feature_edit_at(project,result,id,1);
}
// Evaluate count features. Passing the feature count moves the bar to the end.
fn cad_project_roll_to(project,count) {
    cg_begin();let result=j_parse(j_encode(project));let part=cad_project_part(result);
    let tree=j_get(j_get(part,"data"),"tree");
    if j_kind(tree)!=4 {return cg_fail("Part has no feature tree");}
    let row=pc_first(pc_nodes(part));let total=0;
    while row {if pc_model_feature(row) {total=total+1;}row=load64(row+24);}
    if count<0 || count>total {return cg_fail("Rollback index outside the feature tree");}
    if count==total {pc_remove_field(tree,"rollbackIndex");}
    else {cg_j_int(tree,"rollbackIndex",count);}
    return result;
}
fn pc_history_face_dep(nodes,ref,id) {
    let sketch=pc_find(nodes,j_string(ref,"sketchId"));
    let face=pc_find(nodes,j_string(sketch,"targetId"));
    return m_eq(j_string(face,"sourceId"),id);
}
fn pc_history_depends(nodes,node,id) {
    if m_eq(j_string(node,"sourceId"),id) || m_eq(j_string(node,"targetId"),id) || pc_history_face_dep(nodes,node,id) {return 1;}
    if m_eq(j_string(node,"type"),"chamfer") {
        let edge=pc_find(nodes,j_string(node,"edgeId"));
        if m_eq(j_string(edge,"type"),"edge") && m_eq(j_string(edge,"sourceId"),id) {return 1;}
    }
    let ref=pc_first(j_get(node,"profiles"));
    while ref {if pc_history_face_dep(nodes,ref,id) {return 1;}ref=load64(ref+24);}
    return 0;
}
fn pc_history_swap_payload(a,b) {
    // Keep the list links in their slots, moving only the JSON value.
    let i=0;while i<=16 {
        let value=load64(a+i);store64(a+i,load64(b+i));store64(b+i,value);i=i+8;
    }
    return 1;
}
fn pc_history_swap_ids(list,a,b) {
    let first=0;let second=0;let row=pc_first(list);
    while row {
        if j_kind(row)==2 && m_eq(j_value(row),a) {first=row;}
        if j_kind(row)==2 && m_eq(j_value(row),b) {second=row;}
        row=load64(row+24);
    }
    if first && second {pc_history_swap_payload(first,second);}
    return 1;
}
fn pc_history_targets(nodes) {
    let targets=j_object();let target="";let row=pc_first(nodes);
    while row {
        let op=j_string(row,"operation");
        if pc_model_feature(row) {
            if m_eq(op,"newBody") {target=j_string(row,"id");}
            else if m_eq(op,"cut") || m_eq(op,"join") {cg_j_text(targets,j_string(row,"id"),target);}
        }
        row=load64(row+24);
    }
    return targets;
}
fn pc_same_boolean_targets(before,after,edited_id) {
    let row=load64(after+16);
    while row {
        let id=load64(row+32);
        if !m_eq(id,edited_id) && !m_eq(j_value(row),j_string(before,id)) {
            return cg_fail("Feature would apply to a different body");
        }
        row=load64(row+24);
    }
    return 1;
}
fn pc_history_without_id(list,id) {
    let link=list+16;
    while load64(link) {
        let row=load64(link);let key=j_string(row,"id");
        if j_kind(row)==2 {key=j_value(row);}
        if m_eq(key,id) {store64(link,load64(row+24));}
        else {link=row+24;}
    }
    return 1;
}
fn pc_history_delete_dependencies(nodes,feature) {
    let id=j_string(feature,"id");let face=j_object();cg_j_text(face,"sourceId",id);
    let between_bodies=0;let row=pc_first(nodes);
    while row {
        if !cg_step() {return 0;}
        if row==feature {between_bodies=m_eq(j_string(feature,"type"),"extrude");}
        else {
            if m_eq(j_string(row,"sourceId"),id) || m_eq(j_string(row,"targetId"),id) {
                return cg_fail("Other features depend on this feature");
            }
            let op=j_string(row,"operation");
            if pc_model_feature(row) && m_eq(op,"newBody") {between_bodies=0;}
            if between_bodies && pc_model_feature(row) && (m_eq(op,"cut") || m_eq(op,"join")) {
                return cg_fail("Later cut or join features depend on this extrusion");
            }
            let relation=pc_first(j_get(row,"relations"));
            while relation {
                if !cg_step() {return 0;}
                if m_eq(j_string(relation,"type"),"projected") && j_get(relation,"sourceFaceId") {
                    cg_j_text(face,"faceId",j_string(relation,"sourceFaceId"));
                    if pc_face_number(face) {return cg_fail("A sketch projects a face from this feature");}
                }
                relation=load64(relation+24);
            }
        }
        row=load64(row+24);
    }
    return 1;
}
fn pc_history_missing_edge_projection(original,preview) {
    let nodes=pc_nodes(preview);let row=pc_first(pc_nodes(original));
    while row {
        let relation=pc_first(j_get(row,"relations"));
        while relation {
            if m_eq(j_string(relation,"type"),"projected") && j_get(relation,"sourceEdge") {
                let sketch=pc_find(nodes,j_string(row,"id"));
                if !pc_find(j_get(sketch,"relations"),j_string(relation,"id")) {return 1;}
            }
            relation=load64(relation+24);
        }
        row=load64(row+24);
    }
    return 0;
}
fn pc_history_projection_preview(part) {
    let scratch=j_parse(j_encode(part));let seen=j_object();let sources=cg_array();
    let bodies=pc_walk_part_features(scratch,sources,j_array(),0,1,seen,0);
    if cg_error || !pc_refresh_unused_projections(scratch,bodies,sources,seen) {return 0;}
    return scratch;
}
fn pc_history_check_edge_projections(original,updated) {
    // A geometric edge has no source feature ID. Compare the resolved links
    // on scratch graphs, leaving already-stale saved links repairable.
    if !pc_history_missing_edge_projection(original,0) {return 1;}
    let after=pc_history_projection_preview(updated);if !after {return 0;}
    if !pc_history_missing_edge_projection(original,after) {return 1;}
    let before=pc_history_projection_preview(original);if !before {return 0;}
    if pc_history_missing_edge_projection(before,after) {return cg_fail("A sketch projects an edge from this feature");}
    return 1;
}
fn cad_project_delete_feature(project,id) {
    cg_begin();
    let result=j_parse(j_encode(project));let part=cad_project_part(result);let nodes=pc_nodes(part);
    if !m_len(id) {return cg_fail("Feature is missing");}
    let feature=pc_find(nodes,id);
    if !feature || !pc_model_feature(feature) {return cg_fail("Feature is missing");}
    let data=j_get(part,"data");let tree=j_get(data,"tree");
    let roots=j_get(j_get(data,"cad"),"rootNodeIds");let ordered=j_get(tree,"orderedNodeIds");
    if (roots && j_kind(roots)!=3) || (ordered && j_kind(ordered)!=3) {return cg_fail("Invalid feature order");}
    if !pc_history_delete_dependencies(nodes,feature) {return 0;}
    let position=0;let total=0;let row=pc_first(nodes);
    while row {
        if row==feature {position=total;}
        if pc_model_feature(row) {total=total+1;}
        row=load64(row+24);
    }
    let rollback=j_get(tree,"rollbackIndex");
    if rollback && (j_kind(rollback)!=1 || j_value(rollback)<0) {return cg_fail("Invalid feature rollback index");}
    let old_targets=pc_history_targets(nodes);
    pc_history_without_id(nodes,id);
    if roots {pc_history_without_id(roots,id);}
    if ordered {pc_history_without_id(ordered,id);}
    if !pc_same_boolean_targets(old_targets,pc_history_targets(nodes),0) {return 0;}
    if rollback {
        let bar=j_value(rollback);if position<bar {bar=bar-1;}
        if bar>=total-1 {pc_remove_field(tree,"rollbackIndex");}
        else if bar!=j_value(rollback) {cg_j_int(tree,"rollbackIndex",bar);}
    }
    if !pc_checked_feature_edit_at(project,result,0,1) {return 0;}
    if !pc_history_check_edge_projections(cad_project_part(project),part) {return 0;}
    return result;
}
fn cad_project_move_feature(project,id,step) {
    cg_begin();
    if step!=1 && step!=-1 {return cg_fail("Choose an adjacent feature");}
    let result=j_parse(j_encode(project));let part=cad_project_part(result);let nodes=pc_nodes(part);
    let left=0;let right=0;let row=pc_first(nodes);let previous=0;
    while row && !right {
        if pc_model_feature(row) {
            if step==-1 && m_eq(j_string(row,"id"),id) {left=previous;right=row;}
            if step==1 && previous && m_eq(j_string(previous,"id"),id) {left=previous;right=row;}
            previous=row;
        }
        row=load64(row+24);
    }
    if !left || !right {return cg_fail("Feature cannot move further");}
    let a=j_string(left,"id");let b=j_string(right,"id");
    if pc_history_depends(nodes,right,a) {return cg_fail(m_cat("Feature depends on ",a));}
    let old_targets=pc_history_targets(nodes);pc_history_swap_payload(left,right);
    if !pc_same_boolean_targets(old_targets,pc_history_targets(nodes),0) {return 0;}
    let data=j_get(part,"data");pc_history_swap_ids(j_get(j_get(data,"cad"),"rootNodeIds"),a,b);
    pc_history_swap_ids(j_get(j_get(data,"tree"),"orderedNodeIds"),a,b);
    return pc_checked_feature_edit(project,result);
}
// Keep earlier feature diagnostics editable while rejecting a newly broken dependency.
fn pc_checked_feature_edit(project,result) {
    return pc_checked_feature_edit_requiring(project,result,0);
}
fn pc_checked_feature_edit_requiring(project,result,id) {
    return pc_checked_feature_edit_at(project,result,id,0);
}
fn pc_checked_feature_edit_at(project,result,id,full_timeline) {
    let part=cad_project_part(result);
    let after=j_array();let bodies=pc_walk_features_before(part,cg_array(),after,0,full_timeline);if cg_error {return 0;}
    let before=0;let row=pc_first(after);
    while row {
        if m_eq(j_string(row,"state"),"error") {
            if m_eq(j_string(row,"id"),id) {return cg_fail(j_string(row,"message"));}
            if !before {
                before=j_array();pc_walk_features_before(cad_project_part(project),cg_array(),before,0,full_timeline);
                if cg_error {return 0;}
            }
            let old=pc_find(before,j_string(row,"id"));
            if !m_eq(j_string(old,"state"),"error") {return cg_fail(j_string(row,"message"));}
        }
        row=load64(row+24);
    }
    if id && cg_count(bodies) && j_get(cg_tessellate(bodies),"error") {return 0;}
    return result;
}
