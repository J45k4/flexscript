import "cad/project-access.flex";
import "cad/project-legacy-edit.flex";

fn plr_select(project,index) {
    let path=j_array();j_add(path,0,j_number(index));cg_j_set(project,"selectedPath",path);
}
fn plr_mesh(project,expected,bounds) {
    let mesh=cad_project_mesh(project);m_assert(!j_get(mesh,"error") && j_value(j_get(mesh,"closed")),j_string(mesh,"error"));
    let parts=j_get(mesh,"parts");m_assert(cg_j_count(parts)==1,"Regions keep one accumulated PartBuilder body");
    let part=pc_first(parts);let volume=pc_legacy_number(part,"volume_mm3",0);
    m_assert(cg_abs(volume-expected)<1000000,"Closed mesh volume agrees with TypeScript");
    let actual=pc_first(j_get(part,"bounds"));let target=pc_first(j_parse(bounds));
    while target {
        let a=pc_first(actual);let b=pc_first(target);
        while b {
            m_assert(cg_abs(pc_pose_number(a)-pc_pose_number(b))<=1000,"Region tool bounds match the authored frame and extent");
            a=load64(a+24);b=load64(b+24);
        }
        actual=load64(actual+24);target=load64(target+24);
    }
    return mesh;
}
fn plr_attached_edit(project) {
    plr_select(project,4);let before=j_encode(project);
    plr_mesh(project,1912016800,"[[-8,-2,4],[33,8,15]]");
    let fields=cad_project_legacy_step_fields(project,"base");let x=pc_find(fields,"region-1-center-x");
    m_assert(pc_legacy_number(x,"value",0)==28000000,"History reads the existing extra region coordinate");
    let edited=cad_project_edit_legacy_step(project,"base","region-1-center-x",j_number(32));m_assert(edited,cg_error);
    edited=cad_project_edit_legacy_step(edited,"base","depth",j_number(10));m_assert(edited,cg_error);
    let report=cad_project_inspect_source(j_encode(edited));m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let reopened=j_get(report,"document");
    plr_mesh(reopened,2384021800,"[[-8,-2,4],[37,8,17]]");
    let data=j_get(cad_project_part(reopened),"data");
    let base=pc_find(j_get(data,"solidSteps"),"base");let region=pc_first(j_get(base,"regions"));
    let sketch=pc_find(j_get(data,"features"),"boss/sketch");let face=j_get(j_get(sketch,"target"),"face");
    m_assert(!j_get(data,"cad") && m_eq(j_string(region,"id"),"second-base")
        && m_eq(j_string(face,"faceId"),"base-solid-face-6") && m_eq(j_string(face,"extrudeId"),"base"),
        "Region edit keeps the saved sketch topology, nominal face and region identity");
    m_assert(m_eq(j_encode(project),before),"Region edits use a copy of the original records");
}
fn plr_capsule_edit(project) {
    plr_select(project,5);let before=j_encode(project);
    plr_mesh(project,4784185394,"[[-10,-10,0],[10,40,5]]");
    let fields=cad_project_legacy_step_fields(project,"plate");let y=pc_find(fields,"region-1-to-y");
    m_assert(pc_legacy_number(y,"value",0)==30000000,"Region capsule endpoint is a History field");
    let edited=cad_project_edit_legacy_step(project,"plate","region-1-to-y",j_number(40));m_assert(edited,cg_error);
    plr_mesh(edited,5784075152,"[[-10,-10,0],[10,50,5]]");
    let data=j_get(cad_project_part(edited),"data");
    let region=pc_first(j_get(pc_first(j_get(data,"solidSteps")),"regions"));
    m_assert(m_eq(j_string(region,"id"),"region-2") && pc_legacy_number(j_get(region,"to"),"y",0)==40000000,
        "Updated endpoint is saved on the original region");
    m_assert(!cad_project_edit_legacy_step(project,"plate","region-1-arcSegments",j_parse("32.5"))
        && m_eq(cg_error,"Invalid legacy region segment count"),"Reject non-integer segment edits");
    m_assert(!cad_project_edit_legacy_step(project,"plate","region-1-width",j_number(0))
        && cg_error && m_eq(j_encode(project),before),"Reject an invalid region edit atomically");
}
fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/legacy-typescript-filled-regions.pcad");
    let report=cad_project_inspect_source(source);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");let saved=j_encode(project);
    plr_mesh(project,2400006400,"[[-10,-10,0],[10,10,8]]");
    m_assert(m_eq(j_encode(project),saved),"Evaluation preserves the legacy source records");
    plr_select(project,1);plr_mesh(project,2336003840,"[[-10,-10,0],[10,10,8]]");

    // Both distant windows enter one through-all intersection tool.
    plr_select(project,2);let mesh=plr_mesh(project,160000000,"[[-6,-10,4],[6,10,6]]");
    let vertex=pc_first(j_get(mesh,"vertices"));
    while vertex {
        let x=cg_abs(pc_pose_number(pc_first(vertex)));
        m_assert(x>=4000000 && x<=6000000,"The two window solids stay disconnected");
        vertex=load64(vertex+24);
    }
    m_assert(!cad_project_edit_legacy_step(project,"windows","endCondition",j_text("blind"))
        && m_eq(cg_error,"Legacy solid operations produced an empty part"),"A blind edit cannot reach the translated section");

    // The second filled shape becomes an island inside the primary hole.
    // Every cross-section shares the same taper.
    plr_select(project,3);plr_mesh(project,2786724933,"[[-15,-15,0],[15,15,5]]");
    plr_attached_edit(project);
    plr_capsule_edit(project);
    return 0;
}
