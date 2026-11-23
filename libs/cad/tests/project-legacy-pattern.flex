import "cad/project-legacy-sketch.flex";
import "cad/project-pattern-author.flex";
import "cad/project-access.flex";

fn plpt_select(project,index) {
    cg_begin();let path=j_array();j_add(path,0,j_number(index));cg_j_set(project,"selectedPath",path);
}
fn plpt_source(project) {return cad_project_legacy_sketch(project,"plate/sketch");}
fn plpt_copy(sketch,id) {return pc_find(j_get(sketch,"entities"),id);}
fn plpt_read(encoded,volume,holes) {
    let report=cad_project_inspect_source(encoded);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");let part=cad_project_part(project);let source=plpt_source(project);
    m_assert(!pc_nodes(part) && !j_get(project,"legacySketchView") && cg_j_count(j_get(source,"profiles"))==1
        && cg_j_count(j_get(pc_first(j_get(source,"profiles")),"holeLoopIds"))==holes,
        "Reopen the raw TypeScript grammar with the materialized holes");
    let mesh=cad_project_mesh(project);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let value=pc_serial_number(j_get(pc_first(j_get(mesh,"parts")),"volume_mm3"),6,1000000,1000000);
    m_assert(cg_abs(value-volume)<1000000,"Saved pattern preserves the TypeScript manufacturing volume");
    return project;
}
fn plpt_xy(entity,key,x,y) {
    let point=pc_uv(j_get(entity,key));return load64(point)==x*1000000 && load64(point+8)==y*1000000;
}
fn plpt_grid(project) {
    plpt_select(project,0);let sk="plate/sketch";let id="linear-pattern-1";
    let source=plpt_source(project);let rel=pp_first(source);cg_j_text(rel,"processNote","Keep original grid metadata");
    cg_j_text(plpt_copy(source,"pattern-copy-3"),"processNote","Keep surviving cell metadata");
    let prior=j_encode(project);let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let settings=j_parse("{\"columns\":2,\"rows\":3,\"step\":{\"x\":15,\"y\":0},\"rowStep\":{\"x\":5,\"y\":12}}");
    let draft=cad_project_set_pattern(view,sk,id,settings);m_assert(draft,cg_error);
    let result=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(result,cg_error);
    let reopened=plpt_read(j_encode(result),36720000000,6);let sketch=plpt_source(reopened);let updated=pp_first(sketch);
    let groups="[[\"pattern-copy-1\"],[\"pattern-copy-3\"],[\"pattern-copy-4\"],[\"pattern-copy-6\"],[\"pattern-copy-7\"]]";
    m_assert(m_eq(j_string(updated,"id"),id) && m_eq(j_encode(j_get(updated,"sources")),"[\"grid-hole\"]")
        && m_eq(j_encode(j_get(updated,"instances")),groups) && m_eq(j_encode(plpt_copy(sketch,"grid-hole")),j_encode(plpt_copy(source,"grid-hole"))),
        "Resizing the TypeScript grid retains its source and row-column cell identities");
    m_assert(m_eq(j_string(updated,"processNote"),"Keep original grid metadata")
        && m_eq(j_string(plpt_copy(sketch,"pattern-copy-3"),"processNote"),"Keep surviving cell metadata"),"Preserve relation and retained copy metadata");
    m_assert(plpt_xy(plpt_copy(sketch,"pattern-copy-1"),"p0",-5,-12) && plpt_xy(plpt_copy(sketch,"pattern-copy-3"),"p0",-15,0)
        && plpt_xy(plpt_copy(sketch,"pattern-copy-4"),"p0",0,0) && plpt_xy(plpt_copy(sketch,"pattern-copy-6"),"p0",-10,12)
        && plpt_xy(plpt_copy(sketch,"pattern-copy-7"),"p0",5,12),"Every surviving or new cut has the expected location");
    let data=j_get(cad_project_part(reopened),"data");let features=j_get(data,"features");let original=j_get(cad_project_part(project),"data");
    let boss=pc_find(features,"boss/sketch");
    m_assert(m_eq(j_string(j_get(j_get(boss,"target"),"face"),"faceId"),"plate-solid-face-30")
        && m_eq(j_encode(boss),j_encode(pc_find(j_get(original,"features"),"boss/sketch")))
        && m_eq(j_encode(j_get(data,"solidSteps")),j_encode(j_get(original,"solidSteps"))),"Keep the cap and operation chain references");
    let shorter=cad_project_set_pattern(view,sk,id,j_parse("{\"columns\":2,\"rows\":2}"));m_assert(shorter,cg_error);
    m_assert(!cad_project_apply_legacy_sketch(project,sk,shorter) && m_eq(cg_error,"Sketch edit changes a face used by boss/sketch")
        && m_eq(j_encode(project),prior),"Do not retarget a cap when shrinking the hole array");
    let changed=pc_find(pc_nodes(cad_project_part(draft)),"pattern-copy-3");
    cg_j_set(j_get(changed,"p0"),"x",j_number(-99));
    m_assert(!cad_project_apply_legacy_sketch(project,sk,draft) && m_eq(cg_error,"Pattern geometry disagrees with relation: linear-pattern-1")
        && m_eq(j_encode(project),prior),"Reject an inconsistent saved pattern copy atomically");
}
fn plpt_ring(project) {
    plpt_select(project,1);let sk="plate/sketch";let id="circular-pattern-1";
    let before=j_encode(project);let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let shifted=cad_project_move_pattern_center(view,sk,id,j_parse("{\"x\":1,\"y\":2}"));m_assert(shifted,cg_error);
    let draft=cad_project_set_pattern(shifted,sk,id,j_parse("{\"count\":3,\"angle\":-180}"));m_assert(draft,cg_error);
    let result=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(result,cg_error);
    let sketch=plpt_source(plpt_read(j_encode(result),37824000000,3));let rel=pp_first(sketch);let anchor=j_get(rel,"centerAnchor");
    m_assert(m_eq(j_string(rel,"id"),id) && m_eq(j_encode(j_get(rel,"sources")),"[\"ring-hole\"]")
        && m_eq(j_encode(j_get(rel,"instances")),"[[\"circular-copy-1\"],[\"circular-copy-2\"]]")
        && plpt_xy(rel,"center",1,2) && m_eq(j_string(anchor,"entityId"),"ring-center") && m_eq(j_string(anchor,"point"),"center")
        && plpt_xy(plpt_copy(sketch,"ring-center"),"center",1,2) && m_eq(j_encode(project),before),
        "Circular editing retains the center anchor, source and surviving positions");
    let first=plpt_copy(sketch,"circular-copy-1");let second=plpt_copy(sketch,"circular-copy-2");
    m_assert(m_eq(j_string(plpt_copy(sketch,"ring-hole"),"type"),"cornerRectangle")
        && m_eq(j_string(first,"type"),"rectangle") && pc_pose_number(j_get(first,"rotation"))==-90000000
        && pc_pose_number(j_get(second,"rotation"))==-180000000 && plpt_xy(first,"center",-1,-12)
        && plpt_xy(second,"center",-13,4) && !plpt_copy(sketch,"circular-copy-3"),"A negative open sweep retains oriented rectangular cuts");
}
fn plpt_author(project) {
    plpt_select(project,2);let sk="plate/sketch";let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let sources=j_parse("[\"grid-hole\"]");
    let settings=j_parse("{\"type\":\"linearPattern\",\"columns\":2,\"rows\":2,\"step\":{\"x\":15,\"y\":0},\"rowStep\":{\"x\":5,\"y\":12}}");
    let draft=cad_project_add_pattern(view,sk,sources,settings);m_assert(draft,cg_error);
    let result=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(result,cg_error);
    let rel=pp_first(plpt_source(plpt_read(j_encode(result),37248000000,4)));
    m_assert(m_eq(j_string(rel,"id"),"linear-pattern-1")
        && m_eq(j_encode(j_get(rel,"instances")),"[[\"pattern-copy-1\"],[\"pattern-copy-2\"],[\"pattern-copy-3\"]]"),"Author a raw TypeScript grid");
    draft=cad_project_add_pattern(view,sk,sources,j_parse("{\"type\":\"circularPattern\",\"count\":4}"));m_assert(draft,cg_error);
    result=cad_project_apply_legacy_sketch(project,sk,draft);m_assert(result,cg_error);
    rel=pp_first(plpt_source(plpt_read(j_encode(result),37248000000,4)));
    m_assert(m_eq(j_string(rel,"id"),"circular-pattern-1")
        && m_eq(j_encode(j_get(rel,"instances")),"[[\"circular-copy-1\"],[\"circular-copy-2\"],[\"circular-copy-3\"]]"),"Author a raw TypeScript ring");
}
fn plpt_retained_profile(project) {
    plpt_select(project,3);let sk="plate/sketch";let before=j_encode(project);
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let edit=cad_project_set_pattern(view,sk,"linear-pattern-1",j_parse("{\"columns\":2,\"rows\":2}"));m_assert(edit,cg_error);
    m_assert(!cad_project_apply_legacy_sketch(project,sk,edit)
        && m_eq(cg_error,"Sketch edit changes a profile used by plate") && m_eq(j_encode(project),before),
        "Do not retarget an extrusion whose patterned source cell disappeared");
}
fn plpt_retained_edge(project) {
    plpt_select(project,4);let sk="plate/sketch";let before=j_encode(project);
    let view=cad_project_legacy_sketch_view(project,sk);m_assert(view,cg_error);
    let settings=j_parse("{\"columns\":2,\"rows\":3,\"step\":{\"x\":15,\"y\":0},\"rowStep\":{\"x\":5,\"y\":12}}");
    let edit=cad_project_set_pattern(view,sk,"linear-pattern-1",settings);m_assert(edit,cg_error);
    m_assert(!cad_project_apply_legacy_sketch(project,sk,edit)
        && m_eq(cg_error,"Sketch pattern changes a saved edge finish: plate-solid-edge-98") && m_eq(j_encode(project),before),
        "An existing edge number cannot move to a different patterned hole");
}
fn main() {
    let report=cad_project_inspect_source(m_read_file("libs/cad/tests/fixtures/legacy-typescript-patterns.pcad"));
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));let project=j_get(report,"document");
    plpt_grid(project);plpt_ring(project);plpt_author(project);plpt_retained_profile(project);plpt_retained_edge(project);
    return 0;
}
