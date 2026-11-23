import "cad/projection-author.flex";
import "cad/project-access.flex";

fn projection_test_rectangle(project,id,x0,y0,x1,y1) {
    return cad_project_add_primitive(project,id,"rectangle",cg_v(x0,y0,0),cg_v(x1,y1,0));
}
fn projection_test_height(part,id) {
    let nodes=pc_nodes(part);let sketch=pc_find(nodes,id);let relation=pc_first(j_get(sketch,"relations"));
    let high=0;
    while relation {
        if m_eq(j_string(relation,"type"),"projected") {
            let line=pc_find(nodes,j_string(relation,"entityId"));
            let a=pc_pose_number(j_get(j_get(line,"p0"),"y"));let b=pc_pose_number(j_get(j_get(line,"p1"),"y"));
            if a>high {high=a;}if b>high {high=b;}
        }
        relation=load64(relation+24);
    }
    return high;
}
fn projection_test_volume(project,id,volume) {
    let mesh=cad_project_mesh(project);m_assert(mesh && j_value(j_get(mesh,"closed")),cg_error);
    let body=pc_find(j_get(mesh,"parts"),id);
    let got=pc_serial_number(j_get(body,"volume_mm3"),6,1000000,100000000);
    m_assert(cg_abs(got-volume*1000000)<100000,"Loft volume reflects current projected section");
}

fn main() {
    let base="native-extrude-1";let front="native-sketch-3";
    let model=cad_project_new("Projected loft");
    m_assert(cad_project_rebuild_projections(model)==model,"Unlinked documents need no geometry rebuild");
    let first="native-sketch-1";let second="native-sketch-2";
    m_assert(projection_test_rectangle(model,first,-10000000,-5000000,10000000,5000000),cg_error);
    model=cad_project_add_extrusion(model,first,1,10000000,"newBody");m_assert(model,cg_error);
    model=cad_project_add_plane_sketch(model,"XY");m_assert(model,cg_error);
    m_assert(projection_test_rectangle(model,second,-10000000,-25000000,10000000,-15000000),cg_error);
    model=cad_project_add_extrusion(model,second,1,10000000,"newBody");m_assert(model,cg_error);
    let inward=cg_v(0,1000000000,0);
    let face=cad_project_pick_face(model,cg_v(0,-10000000,5000000),inward);m_assert(face,cg_error);
    model=cad_project_add_face_sketch(model,face);m_assert(model,cg_error);
    model=cad_project_project_face_edges(model,front);m_assert(model,cg_error);
    m_assert(projection_test_height(cad_project_part(model),front)==10000000,"Initial linked side height");
    face=cad_project_pick_face(model,cg_v(0,-40000000,5000000),inward);m_assert(face,cg_error);
    model=cad_project_add_face_sketch(model,face);m_assert(model,cg_error);
    m_assert(projection_test_rectangle(model,"native-sketch-4",0,0,20000000,10000000),cg_error);
    model=cad_project_add_loft(model,front,1,"native-sketch-4",1,"newBody");m_assert(model,cg_error);
    projection_test_volume(model,"native-loft-1",4000);

    // An upstream edit leaves the loaded projection coordinates stale until
    // its preview is rebuilt. Manufacturing computes on its own scratch copy.
    let edited=cad_project_set_extrusion_options(model,base,15000000,"newBody","blind",0,"");m_assert(edited,cg_error);
    let original=j_encode(edited);
    m_assert(projection_test_height(cad_project_part(edited),front)==10000000,"Unnormalized record retains its old cached endpoints");
    projection_test_volume(edited,"native-loft-1",5000);
    m_assert(m_eq(j_encode(edited),original),"Manufacturing does not edit the saved graph");
    let access=cad_project_inspect_source(original);
    m_assert(access && !j_get(access,"readOnly"),"Rust projected relations open as editable v4 records");
    let refreshed=cad_project_rebuild_projections(edited);m_assert(refreshed,cg_error);
    m_assert(projection_test_height(cad_project_part(refreshed),front)==15000000,"Normalize a named loft section at its first consumer");

    let rolled=cad_project_roll_to(edited,2);m_assert(rolled,cg_error);
    let pending=cad_project_rebuild_projections(rolled);m_assert(pending,cg_error);
    m_assert(m_eq(j_encode(rolled),j_encode(pending)),"Rollback preserves linked geometry below the bar");
    let assembly=cad_project_add_item(edited,"assembly");m_assert(assembly,cg_error);
    let normalized=cad_project_rebuild_projections(assembly);m_assert(normalized,cg_error);
    let prototype=pc_find(j_get(normalized,"items"),"native-part-1");
    m_assert(!cad_project_part(normalized) && projection_test_height(prototype,front)==15000000,
        "An active assembly still normalizes its linked part");
    return 0;
}
