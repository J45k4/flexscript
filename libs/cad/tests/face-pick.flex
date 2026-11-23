import "cad/author.flex";

fn assert_world_point(point,x,y,z) {
    m_assert(point && load64(point)==x && load64(point+8)==y && load64(point+16)==z,"World sketch coordinate");
}

fn check_world_reference_sketch_paths() {
    let top="native-sketch-1";let front="native-sketch-2";let right="native-sketch-3";
    let project=cad_project_new("Sketches without solids");
    project=cad_project_add_plane_sketch(project,"XZ");m_assert(project,cg_error);
    project=cad_project_add_plane_sketch(project,"YZ");m_assert(project,cg_error);
    let a=cg_v(3000000,5000000,0);let b=cg_v(8000000,13000000,0);
    m_assert(cad_project_add_primitive(project,top,"rectangle",a,b),cg_error);
    let line=cad_project_add_primitive(project,front,"line",a,b);m_assert(line,cg_error);
    let datum=cad_project_add_primitive(project,right,"constructionPoint",a,0);m_assert(datum,cg_error);
    let ids=cg_array();cg_push(ids,right);cg_push(ids,top);cg_push(ids,front);
    let saved=j_encode(project);let paths=cad_project_world_sketch_paths(project,ids);
    m_assert(cg_count(paths)==3,cg_error);
    let path=cg_at(paths,0);let points=load64(path);
    m_assert(cg_count(points)==1 && !load64(path+8) && load64(path+16)==datum,"Point keeps its entity");
    assert_world_point(cg_at(points,0),0,3000000,5000000);
    path=cg_at(paths,1);points=load64(path);
    m_assert(cg_count(points)==4 && load64(path+8),"Rectangle remains closed");
    assert_world_point(cg_at(points,0),3000000,5000000,0);
    path=cg_at(paths,2);points=load64(path);
    m_assert(cg_count(points)==2 && !load64(path+8) && load64(path+16)==line,"Line remains open");
    assert_world_point(cg_at(points,0),3000000,0,-5000000);
    assert_world_point(cg_at(points,1),8000000,0,-13000000);
    m_assert(m_eq(j_encode(project),saved),"View paths preserve the graph");

    cg_j_set(j_get(line,"p0"),"x",j_text("invalid"));
    m_assert(!cad_project_world_sketch_paths(project,ids) && m_eq(cg_error,"Expected a finite coordinate or angle"),
        "Report invalid sketch coordinates");
}

fn check_world_face_sketch_paths(project,face_sketch,reference_sketch) {
    let source="native-extrude-1";let ids=cg_array();cg_push(ids,face_sketch);cg_push(ids,reference_sketch);
    let saved=j_encode(project);
    let paths=cad_project_world_sketch_paths(project,ids);m_assert(cg_count(paths)==3,cg_error);
    let path=cg_at(paths,0);let points=load64(path);
    m_assert(load64(path+8) && m_eq(j_string(load64(path+16),"sketchId"),face_sketch),"Face sketch appears first");
    assert_world_point(cg_at(points,0),8000000,-2000000,8000000);
    let deep=cad_project_open(saved);
    m_assert(cad_project_set_depth(deep,source,j_number(12)),cg_error);
    paths=cad_project_world_sketch_paths(deep,ids);m_assert(cg_count(paths)==3,cg_error);
    assert_world_point(cg_at(load64(cg_at(paths,0)),0),8000000,-2000000,12000000);

    let rolled=cad_project_roll_to(project,0);m_assert(rolled,cg_error);
    paths=cad_project_world_sketch_paths(rolled,ids);
    m_assert(cg_count(paths)==2 && !cg_error,"Only independent sketches remain after rollback");
    let suppressed=cad_project_suppress_feature(project,source,1);m_assert(suppressed,cg_error);
    paths=cad_project_world_sketch_paths(suppressed,ids);
    m_assert(cg_count(paths)==2 && !cg_error,"Suppressed face does not hide reference sketches");

    let copy=cad_project_open(saved);let nodes=pc_nodes(cad_project_part(copy));
    let broken=j_parse("{\"type\":\"extrude\",\"id\":\"broken\",\"sketchId\":\"missing\",\"operation\":\"newBody\"}");
    j_add(nodes,0,broken);
    paths=cad_project_world_sketch_paths(copy,ids);
    m_assert(cg_count(paths)==3 && !cg_error,"A later failed extrusion does not invalidate the earlier face");
    let sketch=pc_find(nodes,face_sketch);let face=pc_find(nodes,j_string(sketch,"targetId"));
    cg_j_set(face,"faceId",j_text("native-extrude-1-solid-face-99"));
    paths=cad_project_world_sketch_paths(copy,ids);
    m_assert(cg_count(paths)==2 && !cg_error,"Removed face does not hide reference sketches");
    cg_j_set(sketch,"targetId",j_text("deleted-face"));
    paths=cad_project_world_sketch_paths(copy,ids);
    m_assert(cg_count(paths)==2 && !cg_error,"Missing support node does not hide reference sketches");
    m_assert(m_eq(j_encode(project),saved),"View paths do not mutate the supported sketch");
}

fn main() {
    check_world_reference_sketch_paths();
    let project=cad_project_new("Frame");let sketch="native-sketch-1";
    let low=cg_v(-20000000,-15000000,0);let high=cg_v(20000000,15000000,0);
    m_assert(cad_project_add_primitive(project,sketch,"rectangle",low,high),"Outer boundary");
    m_assert(cad_project_add_primitive(project,sketch,"rectangle",cg_v(-5000000,-5000000,0),cg_v(5000000,5000000,0)),"Hole");
    project=cad_project_add_extrusion(project,sketch,1,8000000,"newBody");
    let before=j_encode(project);let down=cg_v(0,0,-1000000000);let x=cg_v(1000000000,0,0);
    let top=cad_project_pick_face(project,cg_v(10000000,0,100000000),down);
    m_assert(top && pc_face_number(top)==10,"Top face above material");
    m_assert(!cad_project_pick_face(project,cg_v(0,0,100000000),down),"Ray through the hole");
    m_assert(!cad_project_pick_face(project,cg_v(0,0,0),cg_v(0,0,0)),"Zero direction");
    let outer=cad_project_pick_face(project,cg_v(-100000000,0,4000000),x);
    m_assert(outer && pc_face_number(outer)==4,"Foremost outer side");
    let inner=cad_project_pick_face(project,cg_v(0,0,4000000),x);
    m_assert(inner && pc_face_number(inner)==6,"Inner side");
    let bottom=cad_project_pick_face(project,cg_v(10000000,0,-100000000),cg_v(0,0,1000000000));
    m_assert(bottom && pc_face_number(bottom)==9,"Bottom face");
    let edit=cad_project_add_face_sketch(project,top);m_assert(edit,cg_error);
    let nodes=pc_nodes(cad_project_part(edit));let second=pc_find(nodes,"native-sketch-2");
    let loops=cad_project_sketch_face_loops(edit,second);m_assert(cg_count(loops)==2,"Cap support includes its hole");
    let again=cad_project_add_face_sketch(edit,top);
    m_assert(cg_j_count(pc_nodes(cad_project_part(again)))==cg_j_count(nodes)+1,"Reuse face node");
    let feature="native-sketch-2";let a=cg_v(8000000,-2000000,0);let b=cg_v(12000000,2000000,0);
    m_assert(cad_project_add_primitive(edit,feature,"rectangle",a,b),"Pocket profile");
    check_world_face_sketch_paths(edit,feature,sketch);
    let pocket=cad_project_add_extrusion(edit,feature,1,3000000,"cut");m_assert(pocket,cg_error);
    m_assert(!cad_project_pick_face(pocket,cg_v(10000000,0,100000000),down),"Pocket floor has no matching outward v4 face");
    let floor=cad_project_surface_hit(pocket,cg_v(10000000,0,100000000),down);
    m_assert(floor && load64(load64(floor)+16)==5000000 && m_eq(load64(load64(floor+16)),"native-extrude-1"),"Pick real pocket floor and body");
    let beside=cad_project_pick_face(pocket,cg_v(15000000,0,100000000),down);
    m_assert(beside && m_eq(j_string(top,"id"),j_string(beside,"id")),"Surviving parent cap");
    let boss=cad_project_add_extrusion(edit,feature,1,3000000,"join");
    let highest=cad_project_pick_face(boss,cg_v(10000000,0,100000000),down);
    m_assert(highest && m_eq(j_string(highest,"sourceId"),"native-extrude-2"),"Occluding joined cap");
    let stacked=cad_project_add_extrusion(edit,feature,1,3000000,"newBody");
    let eye=cg_v(10000000,0,100000000);
    let upper=cad_project_surface_hit(stacked,eye,down);
    m_assert(upper && load64(load64(upper)+16)==11000000,"Nearest body occludes the first");
    let lower=cad_project_surface_hit_in(stacked,eye,down,"native-extrude-1");
    m_assert(lower && load64(load64(lower)+16)==8000000,"Isolated lower body remains pickable");
    m_assert(!cad_project_surface_hit_in(stacked,eye,down,"absent"),"Missing isolated occurrence has no hit");
    let support=cad_project_pick_face_in(stacked,eye,down,"native-extrude-1");
    m_assert(support && m_eq(j_string(support,"id"),j_string(top,"id")),"Isolated face belongs to the visible body");
    let side=cad_project_add_face_sketch(project,inner);let side_sketch=pc_find(pc_nodes(cad_project_part(side)),feature);
    let boundary=cg_at(cad_project_sketch_face_loops(side,side_sketch),0);let corner=cg_at(boundary,2);
    m_assert(load64(corner)==10000000 && load64(corner+8)==8000000,"Hole side sketch dimensions");
    cg_j_text(top,"faceId","native-extrude-1-solid-face-99");
    m_assert(!cad_project_add_face_sketch(project,top),"Invalid face descriptor");
    m_assert(m_eq(before,j_encode(project)),"Source graph preserved");
    return 0;
}
