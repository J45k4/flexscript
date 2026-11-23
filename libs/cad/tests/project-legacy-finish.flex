import "cad/project-legacy-edit.flex";

fn legacy_finish_fixture(name) {
    let path=m_cat("libs/cad/tests/fixtures/legacy-typescript-",m_cat(name,".pcad"));
    let raw=m_read_file(path);m_assert(raw,name);
    let project=cad_project_open(raw);m_assert(project,cg_error);return project;
}
fn legacy_finish_mesh(project,volume) {
    let text=j_encode(project);let mesh=cad_project_mesh(project);
    m_assert(!j_get(mesh,"error") && j_value(j_get(mesh,"closed")),cg_error);
    m_assert(m_eq(j_encode(project),text),"Finish evaluation retains the saved project");
    let part=pc_first(j_get(mesh,"parts"));
    let measured=pc_serial_number(j_get(part,"volume_mm3"),6,1000000,10000);
    m_assert(cg_abs(measured-volume)<1000000,"Legacy finish has the original TypeScript volume");
    m_assert(cg_stl(mesh),"Legacy finish exports a closed STL");
    return mesh;
}
fn legacy_finish_point(mesh,x,y,z) {
    let point=pc_first(j_get(mesh,"vertices"));
    while point {
        let row=pc_first(point);
        let px=pc_pose_number(row);row=load64(row+24);
        let py=pc_pose_number(row);row=load64(row+24);
        let pz=pc_pose_number(row);
        if cg_abs(px-x)<=6 && cg_abs(py-y)<=6 && cg_abs(pz-z)<=6 {return 1;}
        point=load64(point+24);
    }
    return 0;
}
fn legacy_finish_expect_error(project,message) {
    let saved=j_encode(project);let mesh=cad_project_mesh(project);
    m_assert(j_get(mesh,"error") && m_eq(cg_error,message),cg_error);
    m_assert(m_eq(j_encode(project),saved),"Rejected finish preserves the saved project");
}
fn legacy_finish_step(project) {
    return pc_first(j_get(j_get(cad_project_part(project),"data"),"solidSteps"));
}
fn legacy_finish_clear_cache(project) {
    let data=j_get(cad_project_part(project),"data");let sketch=pc_first(j_get(data,"features"));
    cg_j_set(sketch,"vertices",j_array());cg_j_set(sketch,"loops",j_array());cg_j_set(sketch,"profiles",j_array());
}
fn legacy_finish_check_cached_order() {
    cg_begin();
    let sketch=j_parse("{\"vertices\":[{\"x\":0,\"y\":0},{\"x\":10,\"y\":0},{\"x\":0,\"y\":10}],\"loops\":[{\"id\":\"ring\",\"vertexIndices\":[0,1,2]}],\"profiles\":[{\"id\":\"profile\",\"outerLoopId\":\"ring\"}]}");
    let target=j_parse("{\"profileId\":\"profile\"}");let points=cg_array();
    cg_push(points,cg_v(0,0,0));cg_push(points,cg_v(10000000,0,0));cg_push(points,cg_v(0,10000000,0));
    m_assert(plf_match_saved_order(points,sketch,target)==points,cg_error);
    cg_j_set(pc_first(j_get(sketch,"loops")),"vertexIndices",j_parse("[1,2,0]"));
    m_assert(!plf_match_saved_order(points,sketch,target),"A shifted loop cache cannot reinterpret finish indices");
}
fn main() {
    let project=legacy_finish_fixture("selected-corner-chamfer");
    let bevel=legacy_finish_mesh(project,1884000000);
    m_assert(!legacy_finish_point(bevel,10000000,6000000,8000000)
        && legacy_finish_point(bevel,-10000000,6000000,8000000)
        && legacy_finish_point(bevel,7000000,6000000,8000000)
        && legacy_finish_point(bevel,10000000,3000000,8000000),"Clockwise authored outline bevels the selected northeast corner");

    let holed_part=legacy_finish_fixture("sampled-fillet-hole");
    let hole=legacy_finish_mesh(holed_part,1792918480);
    m_assert(!legacy_finish_point(hole,10000000,6000000,8000000)
        && legacy_finish_point(hole,-10000000,-6000000,8000000)
        && legacy_finish_point(hole,9804226,3236068,8000000)
        && legacy_finish_point(hole,9236068,4351141,8000000)
        && legacy_finish_point(hole,8351141,5236068,8000000)
        && legacy_finish_point(hole,7236068,5804226,8000000),"Primitive rectangle preserves the selected corner and each fillet sample");
    m_assert(legacy_finish_point(hole,-1000000,-1000000,8000000)
        && legacy_finish_point(hole,-5000000,-1000000,8000000)
        && legacy_finish_point(hole,-3000000,1000000,8000000)
        && legacy_finish_point(hole,-3000000,-3000000,8000000),"Filleting the exterior keeps the original aperture");
    legacy_finish_clear_cache(holed_part);
    m_assert(m_eq(j_encode(cad_project_mesh(holed_part)),j_encode(hole)),"Primitive corner order does not use a stale sketch cache");
    let subdivided=cad_project_edit_legacy_step(holed_part,"holed-plate","finish-1-segments",j_number(7));
    m_assert(subdivided,cg_error);
    let fillet=pc_first(j_get(legacy_finish_step(subdivided),"finishes"));
    m_assert(j_integer(fillet,"segments")==7 && j_value(pc_first(j_get(fillet,"vertices")))==0,
        "The fillet edit preserves the saved selector");
    m_assert(!cad_project_edit_legacy_step(holed_part,"holed-plate","finish-1-segments",j_number(129))
        && m_eq(cg_error,"Finish segments must be between 1 and 128"),"Reject a segment count outside the TypeScript bounds");

    let sequential=legacy_finish_mesh(legacy_finish_fixture("sequential-corner-finishes"),1876721360);
    m_assert(!legacy_finish_point(sequential,10000000,6000000,8000000)
        && !legacy_finish_point(sequential,-10000000,6000000,8000000)
        && legacy_finish_point(sequential,-7000000,6000000,8000000)
        && legacy_finish_point(sequential,9618034,5175571,8000000),"Later finish indices read the previous pass outline");

    let revolve=legacy_finish_mesh(legacy_finish_fixture("revolve-oblique-fillet"),2326923207);
    m_assert(legacy_finish_point(revolve,14807496,-7000000,3038997)
        && legacy_finish_point(revolve,15703241,-7000000,4155647)
        && !legacy_finish_point(revolve,16000000,-7000000,3000000),"Partial revolve samples the oblique authored fillet before sweeping");

    legacy_finish_expect_error(legacy_finish_fixture("overlapping-chamfer-rejected"),"Finish radius is too large for adjacent profile edges");
    legacy_finish_clear_cache(project);
    m_assert(m_eq(j_encode(cad_project_mesh(project)),j_encode(bevel)),"Line corner order does not use a stale sketch cache");
    let fields=cad_project_legacy_step_fields(project,"plate");
    m_assert(m_eq(j_string(pc_find(fields,"finish-1-radius"),"label"),"Chamfer 1 distance  mm")
        && !pc_find(fields,"finish-1-segments"),"A chamfer exposes its saved setback only");
    let snapshot=j_encode(project);
    m_assert(!cad_project_edit_legacy_step(project,"plate","finish-1-radius",j_number(22))
        && m_eq(cg_error,"Finish radius is too large for adjacent profile edges")
        && m_eq(j_encode(project),snapshot),"Reject an overlapping numeric history edit atomically");
    let edited=cad_project_edit_legacy_step(project,"plate","finish-1-radius",j_number(4));m_assert(edited,cg_error);
    let expected=j_parse(snapshot);let finish=pc_first(j_get(legacy_finish_step(expected),"finishes"));
    cg_j_set(finish,"radius",cg_json_number(4000000));
    m_assert(m_eq(j_encode(edited),j_encode(expected)),"Radius edits retain the rest of the saved feature history");
    let moved=legacy_finish_mesh(edited,1856000000);
    m_assert(legacy_finish_point(moved,6000000,6000000,8000000)
        && legacy_finish_point(moved,10000000,2000000,8000000),"Edited setback moves both ends of the selected bevel");
    legacy_finish_check_cached_order();
    return 0;
}
