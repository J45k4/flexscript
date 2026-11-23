import "cad/project-legacy-sketch.flex";
import "cad/project-access.flex";

fn pla_select(project,index) {
    let path=j_array();j_add(path,0,j_number(index));cg_j_set(project,"selectedPath",path);
}
fn pla_edit(project,index,volume,vertices) {
    pla_select(project,index);
    let id="body/sketch";let arc_id="ellipse-rim";
    let original=cad_project_legacy_sketch(project,id);
    let raw=pc_find(j_get(original,"entities"),arc_id);
    let wrapped=m_eq(j_string(raw,"type"),"sketchArc");let original_arc=raw;
    if wrapped {original_arc=j_get(raw,"arc");}
    cg_j_text(original_arc,"inspectionNote","Keep the original arc payload");
    cg_j_text(j_get(original_arc,"center"),"inspectionNote","Keep the original point metadata");
    let saved=j_encode(project);
    let view=cad_project_legacy_sketch_view(project,id);m_assert(view,cg_error);
    let edited=cad_project_set_curve_dimension(view,id,arc_id,"height","12 mm");m_assert(edited,cg_error);
    let nodes=pc_nodes(cad_project_part(edited));let arc=j_get(pc_find(nodes,arc_id),"arc");
    // The editor can replace a draft point record. Authored metadata remains
    // part of the saved TypeScript record even when absent from the draft.
    cg_j_set(arc,"center",j_parse("{\"x\":0,\"y\":0}"));
    let updated=cad_project_apply_legacy_sketch(project,id,edited);m_assert(updated,cg_error);
    let report=cad_project_inspect_source(j_encode(updated));
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let reopened=j_get(report,"document");
    let next=cad_project_legacy_sketch(reopened,id);let record=pc_find(j_get(next,"entities"),arc_id);
    let saved_arc=record;if wrapped {saved_arc=j_get(record,"arc");}
    let data=j_get(cad_project_part(reopened),"data");
    m_assert(!j_get(data,"cad") && m_eq(j_encode(project),saved),"Save keeps the legacy graph and leaves the original unchanged");
    m_assert(m_eq(j_string(record,"type"),j_string(raw,"type")) && m_eq(j_string(saved_arc,"id"),arc_id)
        && pc_pose_number(j_get(saved_arc,"height"))==12000000,"Retain the source record family and persistent arc ID");
    m_assert(m_eq(j_encode(j_get(saved_arc,"startAngle")),j_encode(j_get(original_arc,"startAngle")))
        && m_eq(j_encode(j_get(saved_arc,"sweep")),j_encode(j_get(original_arc,"sweep"))),"Editing the height preserves the start and signed sweep");
    m_assert(m_eq(j_string(saved_arc,"inspectionNote"),"Keep the original arc payload")
        && m_eq(j_string(j_get(saved_arc,"center"),"inspectionNote"),"Keep the original point metadata"),"Keep opaque arc and point fields");
    if wrapped {
        m_assert(m_eq(j_string(record,"wrapperNote"),"preserve wrapper") && m_eq(j_string(saved_arc,"payloadNote"),"preserve arc payload")
            && m_eq(j_string(j_get(saved_arc,"center"),"centerNote"),"preserve center metadata"),"A nested source keeps metadata on both layers");
    }
    m_assert(m_eq(j_encode(j_get(next,"target")),j_encode(j_get(original,"target")))
        && m_eq(j_encode(j_get(next,"profiles")),j_encode(j_get(original,"profiles")))
        && m_eq(j_encode(j_get(next,"loops")),j_encode(j_get(original,"loops")))
        && cg_j_count(j_get(next,"vertices"))==vertices,"Regenerate the same TypeScript loop and profile ordinals");
    let mesh=cad_project_mesh(reopened);
    m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let part=pc_first(j_get(mesh,"parts"));let actual=pc_serial_number(j_get(part,"volume_mm3"),6,1000000,1000000);
    m_assert(cg_abs(actual-volume)<1000000,"Edited legacy arc produces the TypeScript manufacturing volume");
    let feature=pc_find(j_get(data,"features"),"body");
    m_assert(m_eq(j_string(j_get(feature,"target"),"profileId"),"body/sketch-profile-1"),"Extrusion retains the original sketch profile");
    let boss=pc_find(j_get(data,"features"),"boss/sketch");
    if boss {
        m_assert(m_eq(j_string(j_get(j_get(boss,"target"),"face"),"faceId"),"body-solid-face-39"),"Attached sketch stays on the saved top cap");
        let wider=cad_project_set_curve_dimension(view,id,arc_id,"width","24 mm");m_assert(wider,cg_error);
        let chord=pc_find(pc_nodes(cad_project_part(wider)),"chord");
        cg_j_set(j_get(chord,"p0"),"x",j_number(12));cg_j_set(j_get(chord,"p1"),"x",j_number(-12));
        m_assert(!cad_project_apply_legacy_sketch(project,id,wider)
            && m_eq(cg_error,"Sketch edit changes a face used by boss/sketch") && m_eq(j_encode(project),saved),
            "A new chord count cannot turn the saved cap into a sampled wall");
    }
    return reopened;
}

fn pla_sweep(project) {
    pla_select(project,3);let id="body/sketch";let arc_id="ellipse-rim";
    let data=j_get(cad_project_part(project),"data");let sketch=j_parse(j_encode(cad_project_legacy_sketch(project,id)));
    let features=j_array();j_add(features,0,sketch);cg_j_set(data,"features",features);cg_j_set(data,"solidSteps",j_array());
    let original=pc_find(j_get(sketch,"entities"),arc_id);let start=j_encode(j_get(j_get(original,"arc"),"startAngle"));
    let view=cad_project_legacy_sketch_view(project,id);m_assert(view,cg_error);
    let edited=cad_project_set_curve_dimension(view,id,arc_id,"arcSweep","-135 deg");m_assert(edited,cg_error);
    let saved=cad_project_apply_legacy_sketch(project,id,edited);m_assert(saved,cg_error);
    let arc=pc_find(j_get(cad_project_legacy_sketch(saved,id),"entities"),arc_id);
    m_assert(m_eq(j_string(arc,"type"),"sketchArc") && m_eq(j_encode(j_get(j_get(arc,"arc"),"startAngle")),start)
        && pc_circle_measure(arc,"arcSweep")==-135000000,"A signed sweep edit round-trips through the nested source");
}

fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/legacy-typescript-elliptic-sketch.pcad");
    let report=cad_project_inspect_source(source);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    pla_edit(project,0,753025617,37);
    pla_edit(project,1,777025617,37);
    pla_edit(project,2,2007645014,68);
    pla_edit(project,3,777025617,37);
    pla_sweep(project);
    return 0;
}
