import "cad/project-legacy-sketch.flex";
import "cad/project-access.flex";
import "cad/project-pattern-author.flex";

fn pcs_sketch(project) {return cad_project_legacy_sketch(project,"slot/sketch");}
fn pcs_relation(project,id) {return pc_find(j_get(pcs_sketch(project),"relations"),id);}
fn pcs_move(view,end,position) {
    return cad_project_move_capsule_endpoint(view,"slot/sketch","slot/sketch/0",end,j_parse(position));
}
fn pcs_center(project,end,x,y) {
    let slot=pc_find(j_get(pcs_sketch(project),"entities"),"slot/sketch/0");
    let p=pc_uv(j_get(slot,end));return load64(p)==x && load64(p+8)==y;
}
fn pcs_save(project,draft) {
    let saved=cad_project_apply_legacy_sketch(project,"slot/sketch",draft);m_assert(saved,cg_error);
    let report=cad_project_inspect_source(j_encode(saved));
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let reopened=j_get(report,"document");let sketch=pcs_sketch(reopened);
    m_assert(cg_j_count(j_get(sketch,"vertices"))==16,"Keep the original PartBuilder cap sampler");
    let mesh=cad_project_mesh(reopened);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let original=j_get(pcs_sketch(project),"relations");let updated=j_get(sketch,"relations");
    m_assert(cg_j_count(original)==cg_j_count(updated),"Do not save the transient drag relation");
    m_assert(m_eq(j_encode(pcs_relation(project,"slot-span")),j_encode(pcs_relation(reopened,"slot-span")))
        && m_eq(j_encode(pcs_relation(project,"slot-width")),j_encode(pcs_relation(reopened,"slot-width"))),
        "Keep the driving span, width expression and label metadata");
    return reopened;
}
fn pcs_free(project,view) {
    let draft=pcs_move(view,"from","{\"x\":6,\"y\":8}");m_assert(draft,cg_error);
    let reopened=pcs_save(project,draft);
    m_assert(pcs_center(reopened,"from",6000000,8000000) && pcs_center(reopened,"to",-1808169,1752400),
        "The free cap follows the TypeScript least-squares drag");
    m_assert(pc_pose_number(j_get(pcs_relation(reopened,"slot-x-reference"),"value"))==-7808169,
        "The signed reference distance measures the edited capsule");
    draft=pcs_move(view,"to","{\"x\":4,\"y\":-8}");m_assert(draft,cg_error);
    reopened=pcs_save(project,draft);
    m_assert(pcs_center(reopened,"from",11808169,-1752400) && pcs_center(reopened,"to",4000000,-8000000),
        "Either cap can drive the coupled motion");
    draft=pcs_move(view,"from","{\"x\":0,\"y\":0}");m_assert(draft,cg_error);
    reopened=pcs_save(project,draft);
    m_assert(pcs_center(reopened,"from",0,0) && pcs_center(reopened,"to",-10000000,0),"A free cap can pass the other cap's old position");
}
fn pcs_fixed(project,view) {
    let before=j_encode(view);
    m_assert(!pcs_move(view,"from","{\"x\":6.01,\"y\":8}")
        && m_eq(cg_error,"Capsule endpoint conflicts with the driving center distance"),"An off-radius cursor conflicts with both saved constraints");
    m_assert(!pcs_move(view,"to","{\"x\":1,\"y\":0}") && m_eq(cg_error,"Capsule endpoint is fixed")
        && m_eq(j_encode(view),before),"The fixed opposite cap and original graph remain intact");
    let draft=pcs_move(view,"from","{\"x\":6,\"y\":8}");m_assert(draft,cg_error);
    let reopened=pcs_save(project,draft);
    m_assert(pcs_center(reopened,"from",6000000,8000000) && pcs_center(reopened,"to",0,0)
        && m_eq(j_encode(pcs_relation(reopened,"fixed-cap")),j_encode(pcs_relation(project,"fixed-cap"))),
        "Rotate around the fixed opposite cap without changing its lock");
    let features=j_get(j_get(cad_project_part(reopened),"data"),"features");
    let face=j_get(j_get(pc_find(features,"boss/sketch"),"target"),"face");
    m_assert(m_eq(j_string(face,"faceId"),"slot-solid-face-18"),"Keep the attached boss on its original cap");
}
fn pcs_guarded(view) {
    let altered=j_parse(j_encode(view));
    let sketch=pc_find(pc_nodes(cad_project_part(altered)),"slot/sketch");
    let relations=j_get(sketch,"relations");let span=pc_find(relations,"slot-span");
    cg_j_text(span,"axis","x");let before=j_encode(altered);
    m_assert(!pcs_move(altered,"from","{\"x\":6,\"y\":8}")
        && m_eq(cg_error,"Capsule endpoint has a driving constraint") && m_eq(j_encode(altered),before),
        "A driving axis distance requires separate support");
    pc_remove_field(span,"axis");
    let duplicate=j_parse(j_encode(span));cg_j_text(duplicate,"id","second-span");j_add(relations,0,duplicate);
    before=j_encode(altered);
    m_assert(!pcs_move(altered,"from","{\"x\":6,\"y\":8}")
        && m_eq(cg_error,"Capsule endpoint has a driving constraint") && m_eq(j_encode(altered),before),
        "Multiple driving spans require a coupled solver");
    m_assert(!cad_project_set_distance_expression(altered,"slot/sketch","slot-span","14")
        && m_eq(cg_error,"Capsule center distance needs a coupled solve") && m_eq(j_encode(altered),before),
        "A dimension edit cannot move geometry with multiple driving spans");
    let nodes=pc_nodes(cad_project_part(altered));
    j_add(nodes,0,j_parse("{\"id\":\"anchor-line\",\"type\":\"sketchLine\",\"sketchId\":\"slot/sketch\",\"p0\":{\"x\":0,\"y\":1},\"p1\":{\"x\":3,\"y\":2},\"construction\":true}"));
    cg_j_text(j_get(duplicate,"b"),"entityId","anchor-line");cg_j_text(j_get(duplicate,"b"),"point","p0");
    cg_j_set(duplicate,"value",j_number(1));before=j_encode(altered);
    m_assert(!pcs_move(altered,"from","{\"x\":6,\"y\":8}")
        && m_eq(cg_error,"Capsule endpoint has a driving constraint") && m_eq(j_encode(altered),before),
        "A distance to another entity cannot be bypassed");
    let pattern_source=j_parse(j_encode(view));let preview=pc_find(pc_nodes(cad_project_part(pattern_source)),"slot/sketch");
    let original_span=pc_find(j_get(preview,"relations"),"slot-span");pc_remove_field(preview,"relations");
    let patterned=cad_project_add_pattern(pattern_source,"slot/sketch",j_parse("[\"slot/sketch/0\"]"),
        j_parse("{\"type\":\"linearPattern\",\"columns\":2,\"rows\":1,\"step\":{\"x\":0,\"y\":24}}"));
    m_assert(patterned,cg_error);
    preview=pc_find(pc_nodes(cad_project_part(patterned)),"slot/sketch");
    j_add(j_get(preview,"relations"),0,original_span);before=j_encode(patterned);
    m_assert(!pcs_move(patterned,"from","{\"x\":6,\"y\":8}")
        && m_eq(cg_error,"Capsule endpoint has a driving constraint") && m_eq(j_encode(patterned),before),
        "A patterned driving span needs to solve together with its linked copies");
}
fn pcs_measure(view,value,reference,dof) {
    let report=cad_project_line_sketch(view,"slot/sketch");m_assert(report,cg_error);
    let row=pc_find(j_get(report,"distances"),"slot-span");
    m_assert(row && cg_j_count(j_get(report,"distances"))==1
        && pc_pose_number(j_get(row,"measured"))==value && j_value(j_get(row,"reference"))==reference
        && j_integer(report,"degrees_of_freedom")==dof,"Report the original center distance and freedom");
    return row;
}
fn pcs_dimension(project,view,fixed) {
    let sk="slot/sketch";let span="slot-span";let dof=3-2*fixed;
    let source=pcs_measure(view,10000000,0,dof);
    m_assert(pc_pose_number(j_get(j_get(source,"from"),"x"))==0 && pc_pose_number(j_get(j_get(source,"to"),"x"))==10000000,
        "The dimension report uses its original anchor order");
    let before=j_encode(view);
    let draft=cad_project_set_distance_expression(view,sk,span,"#stock * 3 + 2 mm");m_assert(draft,cg_error);
    let row=pcs_measure(draft,14000000,0,dof);
    m_assert(m_eq(j_string(row,"expression"),"#stock * 3 + 2 mm")
        && m_eq(j_encode(j_get(row,"labelPosition")),j_encode(j_get(source,"labelPosition"))),
        "Typed span retains its expression and label position");
    let literal=cad_project_set_distance_expression(draft,sk,span,"14");m_assert(literal,cg_error);
    m_assert(!j_get(pcs_measure(literal,14000000,0,dof),"expression"),"Plain replacement clears the expression");
    let saved=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(saved,cg_error);
    m_assert(pcs_center(saved,"from",12000000+2000000*fixed,0) && pcs_center(saved,"to",-2000000+2000000*fixed,0),
        "Resize about the midpoint or the existing fixed cap");
    m_assert(m_eq(j_encode(pcs_relation(saved,"slot-width")),j_encode(pcs_relation(project,"slot-width")))
        && m_eq(j_encode(j_get(pcs_sketch(saved),"profiles")),j_encode(j_get(pcs_sketch(project),"profiles"))),
        "Width and profile identity survive the dimension edit");
    if fixed {
        let data=j_get(cad_project_part(saved),"data");
        let face=j_get(j_get(pc_find(j_get(data,"features"),"boss/sketch"),"target"),"face");
        m_assert(m_eq(j_string(face,"faceId"),"slot-solid-face-18"),"Resizing keeps the attached boss on its original cap");
    }
    let variable=cad_project_edit_line_variable(draft,sk,"stock","material","5 mm");m_assert(variable,cg_error);
    row=pcs_measure(variable,17000000,0,dof);
    m_assert(m_eq(j_string(row,"expression"),"#material * 3 + 2 mm"),"A variable rename re-evaluates the span expression");
    saved=cad_project_apply_legacy_sketch(project,sk,variable);m_assert(saved,cg_error);
    let width=pcs_relation(saved,"slot-width");
    m_assert(pc_pose_number(j_get(width,"value"))==5000000 && m_eq(j_string(width,"expression"),"#material")
        && pcs_center(saved,"from",13500000+3500000*fixed,0) && pcs_center(saved,"to",-3500000+3500000*fixed,0)
        && pc_pose_number(j_get(pcs_relation(saved,"slot-x-reference"),"value"))==-17000000,
        "Variable edits update both independent drivers and measure the saved reference");
    let measured=cad_project_toggle_distance_reference(draft,sk,span);m_assert(measured,cg_error);
    m_assert(!j_get(pcs_measure(measured,14000000,1,dof+1),"expression"),"Reference toggle measures and clears the expression");
    m_assert(!cad_project_set_distance_expression(measured,sk,span,"16") && m_eq(cg_error,"Reference distance is measured"),
        "Typed values cannot override a measured span");
    let moved=pcs_move(measured,"from","{\"x\":16,\"y\":0}");m_assert(moved,cg_error);
    pcs_measure(moved,18000000-2000000*fixed,1,dof+1);
    let driving=cad_project_toggle_distance_reference(moved,sk,span);m_assert(driving,cg_error);
    pcs_measure(driving,18000000-2000000*fixed,0,dof);
    let removed=cad_project_remove_point_distance(driving,sk,span);m_assert(removed,cg_error);
    saved=cad_project_apply_legacy_sketch(project,sk,removed);m_assert(saved,cg_error);
    m_assert(!pcs_relation(saved,span) && pcs_relation(saved,"slot-x-reference") && m_eq(j_encode(view),before),
        "Removing the span preserves the separate reference and original history");
    if fixed {
        let both=j_parse(j_encode(view));let sketch=pc_find(pc_nodes(cad_project_part(both)),sk);
        j_add(j_get(sketch,"relations"),0,j_parse("{\"id\":\"locked-from\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"slot/sketch/0\",\"point\":\"from\"},\"position\":{\"x\":10,\"y\":0}}"));
        before=j_encode(both);
        m_assert(!cad_project_set_distance_expression(both,sk,span,"14") && m_eq(cg_error,"Capsule center distance conflicts with fixed endpoints")
            && m_eq(j_encode(both),before),"Two fixed caps reject a conflicting length with no mutation");
    }
}
fn pcs_oblique() {
    let report=cad_project_inspect_source(m_read_file("libs/cad/tests/fixtures/legacy-typescript-capsule-edit.pcad"));
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");let sk="slot/sketch";let path=j_array();
    j_add(path,0,j_number(2));cg_j_set(project,"selectedPath",path);
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let draft=cad_project_set_distance_expression(view,sk,"slot-span","22.25 mm");m_assert(draft,cg_error);
    let saved=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(saved,cg_error);
    m_assert(pcs_center(saved,"from",9701224,5151159) && pcs_center(saved,"to",-6451224,-10151159),
        "Resize a diagonal capsule around its original midpoint");
    let mesh=cad_project_mesh(saved);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    m_assert(m_eq(j_string(pcs_relation(saved,"slot-span"),"expression"),"22.25 mm"),
        "Keep authored units on the diagonal distance");
}
fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/legacy-typescript-capsule-span.pcad");
    let report=cad_project_inspect_source(source);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");let view=cad_project_legacy_sketch_view(project,"slot/sketch");m_assert(view,cg_error);
    let dimensions=cad_project_line_sketch(view,"slot/sketch");m_assert(dimensions,cg_error);
    m_assert(j_integer(dimensions,"degrees_of_freedom")==3 && !j_get(dimensions,"degrees_of_freedom_is_upper_bound"),
        "One driving span removes one independent degree of freedom");
    pcs_free(project,view);pcs_guarded(view);pcs_dimension(project,view,0);
    let path=j_array();j_add(path,0,j_number(1));cg_j_set(project,"selectedPath",path);
    view=cad_project_legacy_sketch_view(project,"slot/sketch");m_assert(view,cg_error);
    dimensions=cad_project_line_sketch(view,"slot/sketch");m_assert(dimensions,cg_error);
    m_assert(j_integer(dimensions,"degrees_of_freedom")==1 && !j_get(dimensions,"degrees_of_freedom_is_upper_bound"),
        "The fixed opposite cap leaves rotation as the only freedom");
    pcs_fixed(project,view);pcs_dimension(project,view,1);pcs_oblique();
    return 0;
}
