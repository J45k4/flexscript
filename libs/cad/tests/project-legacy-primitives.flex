import "cad/project-legacy-sketch.flex";
import "cad/project-access.flex";

fn plt_select(project,index) {
    cg_begin();let path=j_array();j_add(path,0,j_number(index));cg_j_set(project,"selectedPath",path);
}
fn plt_shape(project,sk,id) {return pc_find(j_get(cad_project_legacy_sketch(project,sk),"entities"),id);}
fn plt_draft_shape(draft,id) {return j_get(pc_find(pc_nodes(cad_project_part(draft)),id),"primitive");}
fn plt_volume(project,sk,vertices,volume) {
    let report=cad_project_inspect_source(j_encode(project));
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let reopened=j_get(report,"document");let sketch=cad_project_legacy_sketch(reopened,sk);
    m_assert(!pc_nodes(cad_project_part(reopened)) && !j_get(project,"legacySketchView")
        && cg_j_count(j_get(sketch,"vertices"))==vertices,"Reopen raw TypeScript features with a rebuilt cache");
    let mesh=cad_project_mesh(reopened);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let value=pc_serial_number(j_get(pc_first(j_get(mesh,"parts")),"volume_mm3"),6,1000000,1000000);
    m_assert(cg_abs(value-volume)<1000000,"TypeScript and PuppyCAD agree on the solid volume");
    return reopened;
}
fn plt_ellipse(project) {
    plt_select(project,0);let sk="body/sketch";let id="body/sketch/0";
    let shape=plt_shape(project,sk,id);cg_j_text(shape,"runNote","Preserve ellipse provenance");
    cg_j_text(j_get(shape,"center"),"inspection","Preserve point provenance");
    let before=j_encode(project);
    let draft=cad_project_legacy_sketch_view(project,sk);m_assert(draft,cg_error);
    draft=cad_project_set_curve_dimension(draft,sk,id,"height","16.125 mm");m_assert(draft,cg_error);
    pc_remove_field(j_get(plt_draft_shape(draft,id),"center"),"inspection");
    let result=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(result,cg_error);
    let reopened=plt_volume(result,sk,31,2483290394);let saved=plt_shape(reopened,sk,id);
    m_assert(m_eq(j_string(saved,"type"),"ellipse") && m_eq(j_string(saved,"id"),id) && !j_get(saved,"legacyPrimitiveSampling")
        && pc_pose_number(j_get(saved,"height"))==16125000 && j_integer(saved,"segments")==31
        && m_eq(j_encode(j_get(saved,"width")),j_encode(j_get(shape,"width")))
        && m_eq(j_encode(j_get(saved,"rotation")),j_encode(j_get(shape,"rotation")))
        && m_eq(j_string(saved,"runNote"),"Preserve ellipse provenance")
        && m_eq(j_string(j_get(saved,"center"),"inspection"),"Preserve point provenance") && m_eq(j_encode(project),before),
        "Preserve the ellipse record, non-edited fields and unknown data");
    let data=j_get(cad_project_part(reopened),"data");let features=j_get(data,"features");
    let boss=pc_find(features,"boss/sketch");let face=j_get(j_get(boss,"target"),"face");
    let relation=pc_find(j_get(cad_project_legacy_sketch(reopened,sk),"relations"),"body/sketch/0-height");
    m_assert(m_eq(j_string(face,"faceId"),"body-solid-face-33") && pc_pose_number(j_get(relation,"value"))==16125000,
        "Preserve top-face and driving-dimension identity");
}
fn plt_capsule(project) {
    plt_select(project,1);let sk="body/sketch";let id="body/sketch/0";
    let old=plt_shape(project,sk,id);cg_j_text(j_get(old,"from"),"inspection","Preserve endpoint provenance");
    let before=j_encode(project);let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let draft=cad_project_set_profile_parameter(view,sk,id,"8.125");m_assert(draft,cg_error);
    pc_remove_field(j_get(plt_draft_shape(draft,id),"from"),"inspection");
    let result=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(result,cg_error);
    let reopened=plt_volume(result,sk,16,1676913089);let shape=plt_shape(reopened,sk,id);
    m_assert(m_eq(j_string(shape,"type"),"capsule") && m_eq(j_string(shape,"id"),id) && pc_pose_number(j_get(shape,"width"))==8125000
        && j_integer(shape,"arcSegments")==7 && m_eq(j_encode(j_get(shape,"from")),j_encode(j_get(old,"from")))
        && m_eq(j_encode(j_get(shape,"to")),j_encode(j_get(old,"to"))),"Keep the authored endpoint sequence and cap counts");
    let primitive=plt_draft_shape(draft,id);let from=j_parse(j_encode(j_get(primitive,"from")));
    cg_j_set(primitive,"to",from);
    m_assert(!cad_project_apply_legacy_sketch(project,sk,draft) && m_eq(cg_error,"Invalid legacy capsule width, endpoints or arc segment count")
        && m_eq(j_encode(project),before),"Coincident capsule endpoints cannot replace the saved slot");
}
fn plt_polygon(project) {
    plt_select(project,2);let sk="body/sketch";let id="body/sketch/0";
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let fields=j_get(cad_project_line_sketch(view,sk),"radial");
    let radius=pc_first(fields);
    m_assert(cg_j_count(fields)==2 && m_eq(j_string(radius,"field"),"radius")
        && m_eq(j_string(load64(radius+24),"field"),"rotation"),"The sketch reports both editable polygon dimensions");
    let draft=cad_project_set_profile_parameter(view,sk,id,"9");m_assert(draft,cg_error);
    draft=cad_project_set_curve_dimension(draft,sk,id,"radius","8.5 mm");m_assert(draft,cg_error);
    draft=cad_project_set_curve_dimension(draft,sk,id,"rotation","-23.125 deg");m_assert(draft,cg_error);
    let result=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(result,cg_error);
    let reopened=plt_volume(result,sk,9,1671890573);let shape=plt_shape(reopened,sk,id);
    m_assert(m_eq(j_string(shape,"type"),"polygon") && m_eq(j_string(shape,"id"),id) && j_integer(shape,"sides")==9
        && pc_pose_number(j_get(shape,"radius"))==8500000 && pc_pose_number(j_get(shape,"rotation"))==-23125000,
        "The editable polygon retains its type and updates all three typed parameters");
}
fn plt_pattern(project) {
    plt_select(project,3);let sk="plate/sketch";let id="polygon-hole";
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    m_assert(!cad_project_set_profile_parameter(view,sk,"pattern-copy-1","9")
        && m_eq(cg_error,"Edit the source of this linked profile"),"A generated polygon follows its source");
    let draft=cad_project_set_profile_parameter(view,sk,id,"9");m_assert(draft,cg_error);
    draft=cad_project_set_curve_dimension(draft,sk,id,"radius","5.5 mm");m_assert(draft,cg_error);
    let result=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(result,cg_error);
    let reopened=plt_volume(result,sk,22,36040008586);let source=plt_shape(reopened,sk,id);let copy=plt_shape(reopened,sk,"pattern-copy-1");
    let rel=pp_first(cad_project_legacy_sketch(reopened,sk));
    m_assert(j_integer(source,"sides")==9 && j_integer(copy,"sides")==9 && pc_pose_number(j_get(copy,"radius"))==5500000
        && m_eq(j_string(rel,"id"),"linear-pattern-1") && m_eq(j_encode(j_get(rel,"instances")),"[[\"pattern-copy-1\"]]"),
        "A source polygon edit rebuilds the same patterned hole and relation");
}
fn plt_protected(project,index,message) {
    plt_select(project,index);let sk="body/sketch";let id="body/sketch/0";let before=j_encode(project);
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let draft=cad_project_set_profile_parameter(view,sk,id,"9");m_assert(draft,cg_error);
    m_assert(!cad_project_apply_legacy_sketch(project,sk,draft) && m_eq(cg_error,message) && m_eq(j_encode(project),before),
        "Changing the vertex count may not retarget an attached face or indexed corner");
}
fn plt_polygon_side(project) {
    plt_select(project,6);let sk="body/sketch";let id="body/sketch/0";
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let draft=cad_project_set_curve_dimension(view,sk,id,"radius","8.485281 mm");m_assert(draft,cg_error);
    let result=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(result,cg_error);
    let reopened=plt_volume(result,sk,4,1156000000);let features=j_get(j_get(cad_project_part(reopened),"data"),"features");
    let face=j_get(j_get(pc_find(features,"side/sketch"),"target"),"face");
    m_assert(m_eq(j_string(face,"faceId"),"body-solid-face-1"),"The same local polygon side follows a radius edit");
}
fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/legacy-typescript-direct-primitives.pcad");
    let report=cad_project_inspect_source(source);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    plt_ellipse(project);plt_capsule(project);plt_polygon(project);plt_pattern(project);
    plt_protected(project,4,"Sketch edit changes a face used by boss/sketch");
    plt_protected(project,5,"Sketch edit changes a corner used by body");
    plt_polygon_side(project);
    return 0;
}
