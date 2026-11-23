import "cad/project-access.flex";
import "cad/project-legacy-edit.flex";

fn legacy_fixture(name) {
    let path=m_cat("libs/cad/tests/fixtures/legacy-typescript-",m_cat(name,".pcad"));
    let bytes=m_read_file(path);m_assert(bytes,"Read actual PartBuilder fixture");return bytes;
}
fn legacy_geometry(name,expected) {
    let bytes=legacy_fixture(name);let project=cad_project_open(bytes);m_assert(project,cg_error);
    let saved=j_encode(project);let mesh=cad_project_mesh(project);
    m_assert(!j_get(mesh,"error") && j_value(j_get(mesh,"closed")),j_string(mesh,"error"));
    let parts=j_get(mesh,"parts");m_assert(cg_j_count(parts)==1,"PartBuilder has one accumulated body");
    let volume=pc_serial_number(j_get(pc_first(parts),"volume_mm3"),6,1000000,1000000);
    // The report rounds each tetrahedron to 0.001 mm³. Compare exported mesh
    // volume separately when validating against the TypeScript STL.
    m_assert(cg_abs(volume-expected)<1000000,m_cat("TypeScript volume for ",m_cat(name,m_cat(": ",m_int(volume)))));
    m_assert(m_eq(j_encode(project),saved),"Evaluating legacy features preserves their serialized source");
    let report=cad_project_inspect_source(bytes);
    m_assert(report && !j_get(report,"readOnly"),"A supported legacy drawing opens for editing");
    return project;
}

fn legacy_edit(project) {
    let id="Intersect window";let saved=j_encode(project);
    let rows=j_get(cad_project_feature_history(project),"features");
    m_assert(cg_j_count(rows)==2 && m_eq(j_string(pc_find(rows,id),"operation"),"intersect"),"Read the authored solid order");
    let fields=cad_project_legacy_step_fields(project,id);
    m_assert(pc_legacy_number(pc_find(fields,"depth"),"value",0)==8000000
        && pc_legacy_number(pc_find(fields,"x"),"value",0)==8000000,"Field defaults and translation");
    let edited=cad_project_edit_legacy_step(project,id,"depth",j_number(6));m_assert(edited,cg_error);
    let shorter=cad_project_edit_legacy_step(edited,id,"x",j_number(6));m_assert(shorter,cg_error);
    let mesh=cad_project_mesh(shorter);let volume=pc_first(j_get(mesh,"parts"));
    m_assert(pc_legacy_number(volume,"volume_mm3",0)==720000000,"Edited solid is 10 x 12 x 6 mm");
    let data=j_get(cad_project_part(shorter),"data");
    m_assert(!j_get(data,"cad") && m_eq(j_string(j_get(pc_find(j_get(data,"features"),id),"target"),"profileId"),"Intersect window/sketch-profile-1"),
        "Keep the legacy graph and profile ID while editing the feature");
    m_assert(!cad_project_edit_legacy_step(shorter,id,"x",j_number(240)) && m_eq(cg_error,"Legacy solid operations produced an empty part"),
        "Reject a disjoint intersection before committing the edit");
    m_assert(!cad_project_move_legacy_step(shorter,id,-1),"The intersection cannot precede its stock");
    let joined=cad_project_edit_legacy_step(shorter,id,"operation",j_text("join"));m_assert(joined,cg_error);
    let step=pc_find(j_get(j_get(cad_project_part(joined),"data"),"solidSteps"),id);
    m_assert(m_eq(j_string(step,"operation"),"join") && j_integer(j_get(step,"translation"),"z")==2,"Operation edit preserves the other fields");
    m_assert(m_eq(j_encode(project),saved),"Source stays unchanged on both accepted and rejected edits");
}
fn main() {
    let project=legacy_geometry("translated-intersection",768000000);
    legacy_edit(project);
    legacy_geometry("selected-corner-blank",1920000000);
    legacy_geometry("face-socket",7087627976);
    legacy_geometry("translated-face-socket",7087627977);
    legacy_geometry("transverse-through-all",6525767872);
    let tapered=legacy_geometry("tapered-revolve",5254859580);
    let moved=cad_project_move_legacy_step(tapered,"Boss",-1);m_assert(moved,cg_error);
    m_assert(m_eq(j_string(pc_first(j_get(cad_project_feature_history(moved),"features")),"id"),"Boss"),"Independent tools can move one slot");
    legacy_geometry("partial-revolve",50184776);
    let data=j_get(cad_project_part(project),"data");let steps=j_get(data,"solidSteps");
    let intersection=pc_find(steps,"Intersect window");let translation=j_get(intersection,"translation");
    cg_j_set(translation,"x",j_number(240));let broken=j_encode(project);
    let mesh=cad_project_mesh(project);
    m_assert(j_get(mesh,"error") && m_eq(cg_error,"Legacy solid operations produced an empty part"),"Reject a disjoint intersection");
    m_assert(m_eq(j_encode(project),broken),"A failed Boolean preserves the original geometry records");
    cg_j_text(pc_first(steps),"type","unsupported-model");
    let report=cad_project_inspect_source(j_encode(project));
    m_assert(j_get(report,"readOnly"),"An unknown legacy tool remains available through the source reader");
    return 0;
}
