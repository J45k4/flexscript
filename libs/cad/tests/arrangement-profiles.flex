import "cad/projection-author.flex";

fn arrangement_box(project,sketch,x0,y0,x1,y1) {
    return cad_project_add_primitive(project,sketch,"rectangle",cg_v(x0,y0,0),cg_v(x1,y1,0));
}
fn arrangement_project_face(project,eye,ray) {
    let face=cad_project_pick_face(project,eye,ray);if !face {return 0;}
    let attached=cad_project_add_face_sketch(project,face);if !attached {return 0;}
    return cad_project_project_face_edges(attached,"native-sketch-2");
}
fn arrangement_volume(project,id,expected) {
    let mesh=cad_project_mesh(project);
    m_assert(mesh && !j_get(mesh,"error") && j_value(j_get(mesh,"closed")),m_cat("Expected a closed solid: ",cg_error));
    let part=pc_find(j_get(mesh,"parts"),id);
    let volume=pc_serial_number(j_get(part,"volume_mm3"),6,1000000,100000000);
    m_assert(cg_abs(volume-expected*1000000)<100000,m_cat("Unexpected volume: ",j_encode(j_get(part,"volume_mm3"))));
}
fn arrangement_region(project,sketch_id,ordinal) {
    cg_begin();let nodes=pc_nodes(cad_project_part(project));
    let sketch=pc_find(nodes,sketch_id);let feature=pc_profile_ref(sketch_id,ordinal);
    return cad_project_profile(nodes,sketch,feature);
}
fn asymmetric_cuts() {
    let base_id="native-extrude-1";let base="native-sketch-1";let side="native-sketch-2";
    let model=cad_project_new("Asymmetric projected cuts");
    m_assert(arrangement_box(model,base,-80000000,-50000000,80000000,50000000),cg_error);
    model=cad_project_add_extrusion(model,base,1,60000000,"newBody");m_assert(model,cg_error);
    model=arrangement_project_face(model,cg_v(240000000,0,30000000),cg_v(-1000000000,0,0));
    m_assert(model,cg_error);
    m_assert(cad_project_add_primitive(model,side,"line",cg_v(35000000,0,0),cg_v(35000000,60000000,0)),cg_error);
    let before=j_encode(model);
    let larger=cad_project_add_extrusion(model,side,1,10000000,"cut");m_assert(larger,cg_error);
    let smaller=cad_project_add_extrusion(model,side,2,10000000,"cut");m_assert(smaller,cg_error);
    // Rust saved profile 1 removes the 65 mm side, profile 2 the 35 mm side.
    arrangement_volume(larger,base_id,921000);
    arrangement_volume(smaller,base_id,939000);
    m_assert(m_eq(j_encode(model),before),"Both cuts preserve the source sketch");

    let unlinked=cad_project_open(before);let sketch=pc_find(pc_nodes(cad_project_part(unlinked)),side);
    cg_j_set(sketch,"relations",j_array());
    let first_cut=cad_project_add_extrusion(unlinked,side,1,10000000,"cut");m_assert(first_cut,cg_error);
    let second_cut=cad_project_add_extrusion(unlinked,side,2,10000000,"cut");m_assert(second_cut,cg_error);
    arrangement_volume(first_cut,base_id,921000);
    arrangement_volume(second_cut,base_id,939000);
}
fn overlapping_primitives() {
    let base="native-sketch-1";
    let model=cad_project_new("Overlapping circle and rectangle");
    m_assert(cad_project_add_primitive(model,base,"circle",cg_v(0,0,0),cg_v(20000000,0,0)),cg_error);
    m_assert(arrangement_box(model,base,5000000,-15000000,35000000,15000000),cg_error);
    let nodes=pc_nodes(cad_project_part(model));let sketch=pc_find(nodes,base);
    let regions=cad_project_profiles(nodes,sketch);
    m_assert(regions && cg_count(regions)==3,m_cat("Expected 3 split regions: ",cg_error));
    let total_vol=0;let idx=1;
    while idx<=3 {
        let extruded=cad_project_add_extrusion(model,base,idx,10000000,"newBody");
        m_assert(extruded,m_cat("Expected region extrude to succeed: ",cg_error));
        let mesh=cad_project_mesh(extruded);
        m_assert(mesh && !j_get(mesh,"error") && j_value(j_get(mesh,"closed")),m_cat("Expected closed solid: ",cg_error));
        let part=pc_first(j_get(mesh,"parts"));
        total_vol=total_vol+pc_serial_number(j_get(part,"volume_mm3"),6,1000000,100000000);
        idx=idx+1;
    }
    // Circle area (~1253 mm²) + Rectangle area (900 mm²) - lens overlap (~318 mm²) => ~1835 mm² * 10 mm
    m_assert(total_vol>17000000000 && total_vol<20000000000,"Total volume of the 3 cuts should match union");
}
fn projected_hole() {
    let base="native-sketch-1";let cap="native-sketch-2";
    let model=cad_project_new("Projected hole");
    m_assert(arrangement_box(model,base,-50000000,-30000000,50000000,30000000),cg_error);
    m_assert(arrangement_box(model,base,-35000000,-8000000,-20000000,8000000),cg_error);
    model=cad_project_add_extrusion(model,base,1,10000000,"newBody");m_assert(model,cg_error);
    model=arrangement_project_face(model,cg_v(20000000,0,100000000),cg_v(0,0,-1000000000));m_assert(model,cg_error);
    let nodes=pc_nodes(cad_project_part(model));let sketch=pc_find(nodes,cap);
    m_assert(cg_j_count(j_get(sketch,"relations"))==8,"Project outer and inner boundaries");
    m_assert(cad_project_add_primitive(model,cap,"line",cg_v(0,-30000000,0),cg_v(0,30000000,0)),cg_error);
    let first=arrangement_region(model,cap,1);m_assert(first,cg_error);
    let second=arrangement_region(model,cap,2);m_assert(second,cg_error);
    m_assert(cg_count(first)+cg_count(second)==3,"The hole belongs to exactly one subdivided profile");
    let hole_ordinal=1;if cg_count(second)==2 {hole_ordinal=2;}
    let profile=first;if hole_ordinal==2 {profile=second;}
    let center=cg_v(-27000000,0,0);
    m_assert(pc_inside(load64(cg_at(profile,0)),center) && pc_inside(load64(cg_at(profile,1)),center),
        "Attach the projected hole to the region containing it");
    let raised=cad_project_add_extrusion(model,cap,hole_ordinal,2000000,"newBody");m_assert(raised,cg_error);
    arrangement_volume(raised,"native-extrude-2",5520);

    // A separate primitive crossing the divider now subdivides cleanly into selectable cuts.
    m_assert(arrangement_box(model,cap,-2000000,-2000000,2000000,2000000),cg_error);
    let cut_regions=cad_project_profiles(pc_nodes(cad_project_part(model)),pc_find(pc_nodes(cad_project_part(model)),cap));
    m_assert(cut_regions && cg_count(cut_regions)>=4,m_cat("Crossing box should subdivide cleanly: ",cg_error));
}
fn arrangement_boundaries() {
    cg_begin();
    let a=cg_v(0,0,0);let b=cg_v(10000000,0,0);let c=cg_v(10000000,10000000,0);let d=cg_v(0,10000000,0);
    let region=cg_array();cg_push(region,a);cg_push(region,b);cg_push(region,c);cg_push(region,d);
    let crossing=cg_array();cg_push(crossing,a);cg_push(crossing,cg_v(12000000,3000000,0));cg_push(crossing,cg_v(2000000,12000000,0));
    m_assert(!pc_arrangement_boundaries(region,crossing) && m_eq(cg_error,"Sketch profile loops intersect or touch"),
        "A shared vertex does not mask other crossings");
    cg_begin();
    let overlapping=cg_array();cg_push(overlapping,cg_v(5000000,0,0));cg_push(overlapping,a);cg_push(overlapping,cg_v(0,-5000000,0));
    m_assert(!pc_arrangement_boundaries(region,overlapping) && m_eq(cg_error,"Sketch profile loops intersect or touch"),
        "A shared endpoint does not mask an unaligned partial overlap");
}

fn main() {
    asymmetric_cuts();
    overlapping_primitives();
    projected_hole();
    arrangement_boundaries();
    return 0;
}
