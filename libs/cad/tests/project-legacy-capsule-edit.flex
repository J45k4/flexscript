import "cad/project-legacy-sketch.flex";
import "cad/project-access.flex";

fn ple_select(project,index) {
    cg_begin();let path=j_array();j_add(path,0,j_number(index));cg_j_set(project,"selectedPath",path);
}
fn ple_sketch(project) {return cad_project_legacy_sketch(project,"slot/sketch");}
fn ple_shape(project,id) {return pc_find(j_get(ple_sketch(project),"entities"),id);}
fn ple_relation(project,id) {return pc_find(j_get(ple_sketch(project),"relations"),id);}
fn ple_position(shape,end,x,y) {
    let uv=pc_uv(j_get(shape,end));return load64(uv)==x && load64(uv+8)==y;
}
fn ple_save(project,draft,count,volume) {
    let edited=cad_project_apply_legacy_sketch(project,"slot/sketch",draft);m_assert(edited,cg_error);
    let report=cad_project_inspect_source(j_encode(edited));
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let result=j_get(report,"document");let sketch=ple_sketch(result);
    m_assert(!pc_nodes(cad_project_part(result)) && cg_j_count(j_get(sketch,"vertices"))==count,"Reopen the original PartBuilder sketch format");
    let mesh=cad_project_mesh(result);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let actual=pc_serial_number(j_get(pc_first(j_get(mesh,"parts")),"volume_mm3"),6,1000000,1000000);
    m_assert(cg_abs(actual-volume)<1000000,"Edited capsule volume matches the original TypeScript solver");
    return result;
}
fn ple_driving(project) {
    ple_select(project,0);let sk="slot/sketch";let id="slot/sketch/0";let shape=ple_shape(project,id);
    cg_j_text(ple_relation(project,"slot-width"),"sourceNote","Keep width dimension provenance");
    cg_j_text(j_get(shape,"from"),"sourceNote","Keep the dragged endpoint metadata");
    let before=j_encode(project);
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    m_assert(!cad_project_move_capsule_endpoint(view,sk,id,"to",j_parse("{\"x\":-4,\"y\":-8}"))
        && m_eq(cg_error,"Capsule endpoint is fixed"),"A locked cap center cannot be dragged");
    let inconsistent=j_parse(j_encode(view));let target=pc_find(pc_nodes(cad_project_part(inconsistent)),id);
    cg_j_set(j_get(target,"primitive"),"width",j_number(7));
    m_assert(!cad_project_apply_legacy_sketch(project,sk,inconsistent)
        && m_eq(cg_error,"Capsule dimension disagrees with saved geometry: slot-width"),
        "A raw capsule cannot bypass its driving width expression");
    let draft=cad_project_set_profile_parameter(view,sk,id,"#stock + 1.625 mm");m_assert(draft,cg_error);
    draft=cad_project_move_capsule_endpoint(draft,sk,id,"from",j_parse("{\"x\":10.5,\"y\":2.125}"));m_assert(draft,cg_error);
    let primitive=j_get(pc_find(pc_nodes(cad_project_part(draft)),id),"primitive");
    pc_remove_field(j_get(primitive,"from"),"sourceNote");
    let saved=ple_save(project,draft,16,1685042433);let updated=ple_shape(saved,id);
    let relation=ple_relation(saved,"slot-width");let span=ple_relation(saved,"slot-span");
    m_assert(pc_pose_number(j_get(updated,"width"))==8125000 && j_integer(updated,"arcSegments")==7
        && ple_position(updated,"from",10500000,2125000) && m_eq(j_encode(j_get(updated,"to")),j_encode(j_get(shape,"to")))
        && m_eq(j_string(j_get(updated,"from"),"sourceNote"),"Keep the dragged endpoint metadata"),"Keep the opposite cap center, sampler and authored metadata");
    m_assert(pc_pose_number(j_get(relation,"value"))==8125000 && m_eq(j_string(relation,"expression"),"#stock + 1.625 mm")
        && m_eq(j_string(relation,"sourceNote"),"Keep width dimension provenance")
        && m_eq(j_encode(j_get(relation,"labelPosition")),j_encode(j_get(ple_relation(project,"slot-width"),"labelPosition"))),
        "Modify the existing driving relation and preserve its metadata");
    m_assert(j_value(j_get(span,"reference")) && pc_pose_number(j_get(span,"value"))==19631368
        && m_eq(j_encode(ple_relation(saved,"fixed-cap")),j_encode(ple_relation(project,"fixed-cap"))),
        "Remeasure the center distance and keep the original fixed constraint");
    let features=j_get(j_get(cad_project_part(saved),"data"),"features");
    let face=j_get(j_get(pc_find(features,"boss/sketch"),"target"),"face");
    m_assert(m_eq(j_string(face,"faceId"),"slot-solid-face-18"),"Retain the attached cap ID");
    cg_j_int(primitive,"arcSegments",8);
    m_assert(!cad_project_apply_legacy_sketch(project,sk,draft) && m_eq(cg_error,"Sketch edit changes a face used by boss/sketch")
        && m_eq(j_encode(project),before),"An edited capsule cannot turn its saved cap into a side");
}
fn ple_reference(project) {
    ple_select(project,1);let sk="slot/sketch";let id="slot/sketch/0";
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let draft=cad_project_set_profile_parameter(view,sk,id,"8.125");m_assert(draft,cg_error);
    draft=cad_project_move_capsule_endpoint(draft,sk,id,"to",j_parse("{\"x\":-7.25,\"y\":-7.125}"));m_assert(draft,cg_error);
    let saved=ple_save(project,draft,16,1677042433);let shape=ple_shape(saved,id);let width=ple_relation(saved,"slot-width");
    m_assert(j_value(j_get(width,"reference")) && pc_pose_number(j_get(width,"value"))==8125000
        && ple_position(shape,"from",8750000,4250000) && ple_position(shape,"to",-7250000,-7125000),
        "Reference width follows a free width edit and both named cap centers survive");
}
fn ple_distance(project) {
    ple_select(project,2);let sk="slot/sketch";let id="slot/sketch/0";let before=j_encode(project);
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let draft=cad_project_set_profile_parameter(view,sk,id,"8.125");m_assert(draft,cg_error);
    let saved=ple_save(project,draft,16,1676913089);
    m_assert(m_eq(j_encode(ple_relation(saved,"slot-span")),j_encode(ple_relation(project,"slot-span")))
        && m_eq(j_encode(project),before),"Width edits preserve independent driving center distance");
}
fn ple_pattern(project) {
    ple_select(project,3);let sk="slot/sketch";let id="slot-hole";
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    m_assert(!cad_project_move_capsule_endpoint(view,sk,"pattern-copy-1","from",j_parse("{\"x\":10,\"y\":0}"))
        && m_eq(cg_error,"Edit the source of this linked profile"),"Pattern copies are driven from the source");
    let draft=cad_project_set_profile_parameter(view,sk,id,"#stock + 1.625 mm");m_assert(draft,cg_error);
    draft=cad_project_move_capsule_endpoint(draft,sk,id,"from",j_parse("{\"x\":-12.25,\"y\":3.125}"));m_assert(draft,cg_error);
    let saved=ple_save(project,draft,36,24279085245);let copy=ple_shape(saved,"pattern-copy-1");
    m_assert(ple_position(copy,"from",19750000,3125000) && pc_pose_number(j_get(copy,"width"))==8125000
        && m_eq(j_encode(ple_relation(saved,"linear-pattern-1")),j_encode(ple_relation(project,"linear-pattern-1"))),
        "Both primitive edits propagate through the original pattern relation");
}
fn ple_dimensions(project) {
    ple_select(project,0);let sk="slot/sketch";let id="slot/sketch/0";
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let report=cad_project_line_sketch(view,sk);m_assert(report,cg_error);
    let width=pc_find(j_get(report,"radial"),id);let before=j_encode(view);
    m_assert(m_eq(j_string(width,"field"),"width") && m_eq(j_string(width,"relationId"),"slot-width")
        && m_eq(j_string(width,"expression"),"#stock") && pc_pose_number(j_get(width,"measured"))==6500000
        && j_integer(report,"degrees_of_freedom")==2,"The original slot width and expression appear in Dimensions");
    m_assert(!cad_project_edit_line_variable(view,sk,"stock","stock","") && m_eq(j_encode(view),before),
        "A variable used by the width cannot be deleted");
    let draft=cad_project_edit_line_variable(view,sk,"stock","stockThickness","8.125 mm");m_assert(draft,cg_error);
    let saved=ple_save(project,draft,16,1684913089);let original=ple_shape(project,id);let shape=ple_shape(saved,id);
    let rel=ple_relation(saved,"slot-width");
    m_assert(pc_pose_number(j_get(shape,"width"))==8125000 && pc_pose_number(j_get(rel,"value"))==8125000
        && m_eq(j_string(rel,"expression"),"#stockThickness") && m_eq(j_encode(j_get(shape,"from")),j_encode(j_get(original,"from")))
        && m_eq(j_encode(j_get(shape,"to")),j_encode(j_get(original,"to"))),"A variable update resizes just the original slot width");
    let typed=cad_project_set_curve_dimension(view,sk,id,"width","#stock + 1.625 mm");m_assert(typed,cg_error);
    let edited=ple_save(project,typed,16,1684913089);
    m_assert(m_eq(j_string(ple_relation(edited,"slot-width"),"expression"),"#stock + 1.625 mm")
        && m_eq(j_encode(j_get(ple_sketch(edited),"variables")),j_encode(j_get(ple_sketch(project),"variables"))),
        "The ordinary dimension editor keeps the source width relation and variables");
    ple_select(project,1);view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    report=cad_project_line_sketch(view,sk);m_assert(report,cg_error);
    width=pc_find(j_get(report,"radial"),id);
    m_assert(j_value(j_get(width,"reference")) && m_eq(j_string(width,"relationId"),"slot-width")
        && j_integer(report,"degrees_of_freedom")==5,"A reference dimension consumes no freedom");
    m_assert(!cad_project_set_curve_dimension(view,sk,id,"width","7 mm") && m_eq(cg_error,"Reference curve dimension is measured"),
        "A measured capsule width cannot be directly edited");
    let driven=cad_project_toggle_curve_reference(view,sk,id,"width");m_assert(driven,cg_error);
    report=cad_project_line_sketch(driven,sk);m_assert(report,cg_error);width=pc_find(j_get(report,"radial"),id);
    m_assert(!j_value(j_get(width,"reference")) && m_eq(j_string(width,"relationId"),"slot-width")
        && j_integer(report,"degrees_of_freedom")==4 && pc_pose_number(j_get(width,"measured"))==6500000,
        "Toggling a reference width creates a driver at the existing value and retains its identity");
    driven=cad_project_set_curve_dimension(driven,sk,id,"width","7 mm");m_assert(driven,cg_error);
    let measured=cad_project_toggle_curve_reference(driven,sk,id,"width");m_assert(measured,cg_error);
    report=cad_project_line_sketch(measured,sk);m_assert(report,cg_error);width=pc_find(j_get(report,"radial"),id);
    m_assert(j_value(j_get(width,"reference")) && !j_get(width,"expression") && m_eq(j_string(width,"relationId"),"slot-width")
        && pc_pose_number(j_get(width,"measured"))==7000000,"A toggled reference width reads the edited geometry");
    let unbound=cad_project_remove_curve_dimension(measured,sk,id,"width");m_assert(unbound,cg_error);
    report=cad_project_line_sketch(unbound,sk);m_assert(report,cg_error);width=pc_find(j_get(report,"radial"),id);
    m_assert(!j_get(width,"relationId") && !j_get(width,"reference") && pc_pose_number(j_get(width,"measured"))==7000000,
        "Removing a width relation leaves the primitive at its current size");
    let removed=cad_project_apply_legacy_sketch(project,sk,unbound);m_assert(removed,cg_error);
    m_assert(!ple_relation(removed,"slot-width") && pc_pose_number(j_get(ple_shape(removed,id),"width"))==7000000,
        "Removed width relations remain removed when the original format is saved");
    ple_select(project,3);view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    draft=cad_project_edit_line_variable(view,sk,"stock","stock","8.125 mm");m_assert(draft,cg_error);
    let linked=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(linked,cg_error);
    m_assert(pc_pose_number(j_get(ple_shape(linked,"pattern-copy-1"),"width"))==8125000
        && m_eq(j_encode(ple_relation(linked,"linear-pattern-1")),j_encode(ple_relation(project,"linear-pattern-1"))),
        "Variable reevaluation rebuilds the same linked copy");
}
fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/legacy-typescript-capsule-edit.pcad");
    let report=cad_project_inspect_source(source);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");ple_driving(project);ple_reference(project);ple_distance(project);ple_pattern(project);ple_dimensions(project);
    return 0;
}
