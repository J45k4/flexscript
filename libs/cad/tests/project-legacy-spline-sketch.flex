import "cad/project-legacy-sketch.flex";
import "cad/project-smooth-author.flex";
import "cad/project-access.flex";

fn pls_test_edit(project,index,key,position,volume,count) {
    cg_begin();
    let path=j_array();j_add(path,0,j_number(index));cg_j_set(project,"selectedPath",path);
    let sketch_id="body/sketch";let spline_id="spline-rim";
    let sketch=cad_project_legacy_sketch(project,sketch_id);let spline=pc_find(j_get(sketch,"entities"),spline_id);
    let point_index=m_number(key+5);let point=pls_array_entry(j_get(spline,"points"),point_index);
    cg_j_text(spline,"sourceNote","Retain authored spline metadata");
    cg_j_text(point,"sourceNote","Retain authored handle metadata");
    let before=j_encode(project);
    let view=cad_project_legacy_sketch_view(project,sketch_id);m_assert(view,cg_error);
    if index==3 {
        let node=pc_find(pc_nodes(cad_project_part(view)),spline_id);
        m_assert(cg_count(pc_spline_path(node))==2 && cg_count(pc_curve_path(node))==3,
            "A raw TypeScript handle just over 0.01 mm must subdivide before whole-nanometre rounding");
    }
    let anchor=ps_anchor(spline_id,key);
    let draft=cad_project_move_smooth_point(view,sketch_id,anchor,j_parse(position));m_assert(draft,cg_error);
    let node=pc_find(pc_nodes(cad_project_part(draft)),spline_id);
    let draft_point=pls_array_entry(j_get(j_get(node,"spline"),"points"),point_index);
    pc_remove_field(draft_point,"sourceNote");
    let saved=cad_project_apply_legacy_sketch(project,sketch_id,draft);m_assert(saved,cg_error);
    let report=cad_project_inspect_source(j_encode(saved));
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let reopened=j_get(report,"document");
    let next=cad_project_legacy_sketch(reopened,sketch_id);let edited=pc_find(j_get(next,"entities"),spline_id);
    let edited_point=pls_array_entry(j_get(edited,"points"),point_index);
    m_assert(!j_get(j_get(cad_project_part(reopened),"data"),"cad") && !j_get(edited,"legacySplineSampling")
        && m_eq(j_encode(project),before),"Persist the original grammar without changing the input");
    m_assert(m_eq(j_string(edited,"type"),"spline") && m_eq(j_string(edited,"id"),spline_id)
        && m_eq(j_string(edited,"mode"),j_string(spline,"mode")) && m_eq(j_encode(j_get(edited,"closed")),j_encode(j_get(spline,"closed")))
        && m_eq(j_encode(j_get(edited,"construction")),j_encode(j_get(spline,"construction"))),"Preserve the spline record flags and ID");
    m_assert(pc_profile_same_point(pc_uv(edited_point),pc_uv(j_parse(position)))
        && m_eq(j_string(edited,"sourceNote"),"Retain authored spline metadata")
        && m_eq(j_string(edited_point,"sourceNote"),"Retain authored handle metadata"),"The edited handle keeps its opaque metadata");
    let i=0;let original_point=pc_first(j_get(spline,"points"));let saved_point=pc_first(j_get(edited,"points"));
    while original_point {
        m_assert(saved_point && (i==point_index || m_eq(j_encode(original_point),j_encode(saved_point))),"Every untouched control point keeps its original spelling");
        i=i+1;original_point=load64(original_point+24);saved_point=load64(saved_point+24);
    }
    m_assert(!saved_point && m_eq(j_encode(j_get(next,"profiles")),j_encode(j_get(sketch,"profiles")))
        && m_eq(j_encode(j_get(next,"relations")),j_encode(j_get(sketch,"relations")))
        && cg_j_count(j_get(next,"vertices"))==count,"Retain the TypeScript profile and constraints");
    let mesh=cad_project_mesh(reopened);
    m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let part=pc_first(j_get(mesh,"parts"));let actual=pc_serial_number(j_get(part,"volume_mm3"),6,1000000,1000000);
    m_assert(cg_abs(actual-volume)<1000000,"Saved geometry matches the TypeScript volume");

    if index==0 {
        let features=j_get(j_get(cad_project_part(reopened),"data"),"features");
        let target=j_get(pc_find(features,"boss/sketch"),"target");
        m_assert(m_eq(j_string(j_get(target,"face"),"faceId"),"body-solid-face-53"),"Keep the saved cap reference");
        let changed=cad_project_move_smooth_point(view,sketch_id,anchor,j_parse("{\"x\":-8,\"y\":9.1}"));m_assert(changed,cg_error);
        m_assert(!cad_project_apply_legacy_sketch(project,sketch_id,changed)
            && m_eq(cg_error,"Sketch edit changes a face used by boss/sketch") && m_eq(j_encode(project),before),
            "Refuse to retarget a dependent cap when the adaptive chord count changes");
    }
    if index==1 {
        m_assert(!cad_project_move_smooth_point(view,sketch_id,ps_anchor(spline_id,"point0"),j_parse("{\"x\":13,\"y\":0}"))
            && m_eq(cg_error,"Saved spline coincidence anchors do not meet") && m_eq(j_encode(project),before),
            "A constrained spline endpoint cannot be detached by a control drag");
    }
}

fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/legacy-typescript-splines.pcad");
    let report=cad_project_inspect_source(source);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    pls_test_edit(project,0,"point1","{\"x\":-8,\"y\":8.8}",957171939,51);
    pls_test_edit(project,1,"point2","{\"x\":-5,\"y\":8.2}",1037885492,36);
    pls_test_edit(project,2,"point2","{\"x\":8,\"y\":6.2}",2062496387,108);
    pls_test_edit(project,3,"point1","{\"x\":4,\"y\":0.011}",384378007,5);
    return 0;
}
