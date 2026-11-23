import "cad/mate-author.flex";

fn sample(project,x,y,visible,kind) {
    let pick=cad_project_pick_mate_element(project,cg_v(x,y,30000000),cg_v(0,0,-1000000000),visible,300000,0);
    m_assert(pick,cg_error);m_assert(m_eq(j_string(pick,"pickKind"),kind),m_cat("Expected ",kind));return pick;
}
fn half_disc() {
    let p=cad_project_new("Half disc");let sketch="native-sketch-1";
    let a=cg_v(4000000,0,0);let b=cg_v(-4000000,0,0);let top=cg_v(0,4000000,0);
    let coords=cg_array();cg_push(coords,a);cg_push(coords,top);cg_push(coords,b);
    m_assert(cad_project_add_curve(p,sketch,"arc",coords),cg_error);
    m_assert(cad_project_add_primitive(p,sketch,"line",b,a),cg_error);
    p=cad_project_add_extrusion(p,sketch,1,3000000,"newBody");m_assert(p,cg_error);
    p=cad_project_add_item(p,"assembly");p=cad_project_insert_instance(p,"native-part-1");m_assert(p,cg_error);
    let down=cg_v(0,0,-1000000000);
    let curved=cad_project_pick_mate_element(p,cg_v(0,4070000,20000000),down,0,200000,0);m_assert(curved,cg_error);
    let corner=cad_project_pick_mate_element(p,cg_v(4050000,-50000,20000000),down,0,200000,0);m_assert(corner,cg_error);
    let chord=cad_project_pick_mate_element(p,cg_v(0,-90000,20000000),down,0,200000,0);m_assert(chord,cg_error);
    m_assert(m_eq(j_string(curved,"pickKind"),"Curved edge") && m_eq(j_string(corner,"pickKind"),"Vertex") && m_eq(j_string(chord,"pickKind"),"Edge"),"An open arc has two end vertices and a separate straight chord");
    let center=pc_pose_vector(j_get(curved,"position"),0);
    m_assert(cg_abs(load64(center))<100 && load64(center+8)>2400000 && load64(center+8)<2600000,"Open curve uses only the arc samples");
    m_assert(load64(pm_axis(corner)+16)>999990000,"Prefer the planar cap normal at the end of a curved rim");return 1;
}
fn main() {
    half_disc();
    let p=cad_project_new("Plate");let sketch="native-sketch-1";
    m_assert(cad_project_add_primitive(p,sketch,"rectangle",cg_v(-5000000,-3000000,0),cg_v(5000000,3000000,0)),cg_error);
    p=cad_project_add_extrusion(p,sketch,1,4000000,"newBody");p=cad_project_add_item(p,"assembly");
    p=cad_project_insert_instance(p,"native-part-1");p=cad_project_insert_instance(p,"native-part-1");m_assert(p,cg_error);
    let corner=sample(p,5200000,3200000,0,"Vertex");
    m_assert(m_eq(j_encode(j_get(corner,"position")),j_encode(pc_pose_json(5000000,3000000,4000000))),"Snap a corner outside the silhouette");
    let edge=sample(p,20300000,3160000,0,"Edge");
    m_assert(m_eq(j_encode(j_get(edge,"position")),j_encode(pc_pose_json(0,3000000,4000000))),"Snap to the local midpoint of the front edge");
    m_assert(cg_abs(load64(pm_axis(edge)))>=999990000,"Straight edge axis is tangent");
    sample(p,22000000,1800000,0,"Face");
    let stacked=cad_project_set_instance_component(p,"instance-2","translation","x",0);
    stacked=cad_project_set_instance_component(stacked,"instance-2","translation","z",10000000);
    m_assert(m_eq(j_string(sample(stacked,5000000,3000000,0,"Vertex"),"instanceId"),"instance-2"),"Front vertex wins a depth tie");
    m_assert(m_eq(j_string(sample(stacked,0,3100000,"instance-1","Edge"),"instanceId"),"instance-1"),"Isolation reveals a hidden edge");
    stacked=cad_project_set_instance_component(stacked,"instance-2","scale","x",2000000);
    stacked=cad_project_set_instance_component(stacked,"instance-2","scale","y",2000000);
    m_assert(m_eq(j_string(sample(stacked,5000000,3000000,0,"Face"),"instanceId"),"instance-2"),"A hidden corner cannot win over a nearer face");

    let round=cad_project_new("Pin");
    m_assert(cad_project_add_primitive(round,sketch,"circle",cg_v(0,0,0),cg_v(4000000,0,0)),cg_error);
    round=cad_project_add_extrusion(round,sketch,1,4000000,"newBody");round=cad_project_add_item(round,"assembly");
    round=cad_project_insert_instance(round,"native-part-1");round=cad_project_insert_instance(round,"native-part-1");
    let rim=sample(round,4120000,0,0,"Curved edge");let center=pc_pose_vector(j_get(rim,"position"),0);
    m_assert(cg_abs(load64(center))<100 && cg_abs(load64(center+8))<100 && load64(center+16)==4000000,"Circle rim uses centre of complete loop");
    m_assert(cg_abs(load64(pm_axis(rim)+16))>999990000,"Rim axis is perpendicular to the loop");
    // A flipped copy presents its bottom rim to the same eye. Its local
    // axis may oppose the first rim, but the new world axes must agree.
    round=cad_project_set_instance_component(round,"instance-2","rotation","y",180000000);
    let other=sample(round,22120000,0,0,"Curved edge");let drawn=j_encode(round);
    let joined=cad_project_add_mate(round,"fasten",rim,other);m_assert(joined,cg_error);
    let data=j_get(cad_project_item(joined),"data");let frames=pc_first(j_get(data,"connectors"));
    let rows=pc_assembly_poses(j_get(cad_project_item(round),"data"));let next=load64(frames+24);
    m_assert(cg_dot(pm_world_axis(rows,frames,pm_axis(frames)),pm_world_axis(rows,next,pm_axis(next)))>999990000,"Picked edge axes agree before solving");
    m_assert(!j_get(frames,"pickKind") && m_eq(drawn,j_encode(round)),"Transient topology stays out of the saved connectors");
    return 0;
}
