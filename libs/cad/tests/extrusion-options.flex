import "cad/author.flex";

fn option_sketch(project,id,xmin,ymin,xmax,ymax) {
    let result=cad_project_add_plane_sketch(project,"XY");m_assert(result,cg_error);
    m_assert(cad_project_add_primitive(result,id,"rectangle",cg_v(xmin,ymin,0),cg_v(xmax,ymax,0)),cg_error);
    return result;
}
fn feature(project,id) {
    return pc_find(pc_nodes(cad_project_part(project)),id);
}
fn assert_body(project,id,low,high,wanted_volume) {
    let mesh=cad_project_mesh(project);m_assert(j_value(j_get(mesh,"closed")),cg_error);
    let body=pc_find(j_get(mesh,"parts"),id);
    let bounds=pc_first(j_get(body,"bounds"));
    let min=pc_first(bounds);let max=pc_first(load64(bounds+24));
    m_assert(pc_pose_number(load64(load64(min+24)+24))==low &&
        pc_pose_number(load64(load64(max+24)+24))==high,"Body has the expected Z bounds");
    // Volume uses a larger range than an individual coordinate.
    let volume=pc_serial_number(j_get(body,"volume_mm3"),6,1000000,100000000);
    m_assert(cg_abs(volume-wanted_volume*1000000)<100000,"Body has the expected volume");
}
fn assert_targets(project,stop,first,second) {
    let targets=cad_project_extrusion_targets(project,stop);m_assert(targets,cg_error);
    let row=pc_first(targets);
    if first {
        m_assert(m_eq(j_string(row,"id"),first) && m_len(j_string(row,"name")),"First evaluated target");
        row=load64(row+24);
    }
    if second {
        m_assert(m_eq(j_string(row,"id"),second) && m_len(j_string(row,"name")),"Second evaluated target");
        row=load64(row+24);
    }
    m_assert(!row,"No unexpected extrusion targets");
}

fn check_target_stage() {
    let base="native-sketch-1";let side="native-sketch-2";let cap="native-sketch-3";
    let base_id="native-extrude-1";let edit_id="native-extrude-2";let cap_id="native-extrude-3";
    let project=cad_project_new("Earlier target stage");
    m_assert(cad_project_add_primitive(project,base,"rectangle",cg_v(0,0,0),cg_v(10000000,10000000,0)),cg_error);
    project=cad_project_add_extrusion(project,base,1,4000000,"newBody");m_assert(project,cg_error);
    project=option_sketch(project,side,20000000,0,30000000,10000000);
    project=cad_project_add_extrusion(project,side,1,6000000,"newBody");m_assert(project,cg_error);
    let eye=cg_v(5000000,5000000,20000000);let down=cg_v(0,0,-1000000000);
    let face=cad_project_pick_face(project,eye,down);m_assert(face,cg_error);
    project=cad_project_add_face_sketch(project,face);m_assert(project,cg_error);
    m_assert(cad_project_add_primitive(project,cap,"rectangle",cg_v(2000000,2000000,0),cg_v(8000000,8000000,0)),cg_error);
    project=cad_project_add_extrusion(project,cap,1,5000000,"newBody");m_assert(project,cg_error);
    let snapshot=j_encode(project);
    let hit=cad_project_surface_hit(project,eye,down);
    m_assert(hit && m_eq(load64(load64(hit+16)),cap_id),"A later body obstructs the earlier cap");

    let stage=cad_project_extrusion_target_stage(project,edit_id);m_assert(stage,cg_error);
    hit=cad_project_surface_hit(stage,eye,down);
    m_assert(hit && m_eq(load64(load64(hit+16)),base_id) && load64(load64(hit)+16)==4000000,
        "Picking before the edited feature reaches the earlier body");
    m_assert(m_eq(j_encode(project),snapshot),"Staging a pick preserves the original graph");

    let rolled=cad_project_roll_to(project,1);m_assert(rolled,cg_error);
    let rolled_snapshot=j_encode(rolled);
    let before_cap=cad_project_extrusion_target_stage(rolled,cap_id);
    m_assert(before_cap && m_eq(j_encode(before_cap),rolled_snapshot),"Retain earlier rollback for an existing feature");
    let append=cad_project_extrusion_target_stage(rolled,"");m_assert(append,cg_error);
    hit=cad_project_surface_hit(append,eye,down);
    m_assert(hit && m_eq(load64(load64(hit+16)),cap_id),"Appending picks at the end of the timeline");
    m_assert(m_eq(j_encode(rolled),rolled_snapshot),"Append staging preserves the saved rollback");
    m_assert(!cad_project_extrusion_target_stage(project,"missing") && m_eq(cg_error,"Select an extrusion"),
        "Reject an invalid earlier stage");
}

fn main() {
    check_target_stage();
    let sketch="native-sketch-1";let second="native-sketch-2";let cutter="native-sketch-3";
    let first_body="native-extrude-1";let second_body="native-extrude-2";let cut="native-extrude-3";
    let project=cad_project_new("Extrusion options");
    m_assert(cad_project_add_primitive(project,sketch,"rectangle",cg_v(0,0,0),cg_v(10000000,10000000,0)),cg_error);
    assert_targets(project,"",0,0);
    let legacy=cad_project_add_extrusion(project,sketch,1,4000000,"newBody");m_assert(legacy,cg_error);
    let blind=cad_project_add_extrusion_options(project,sketch,1,4000000,"newBody","blind",0,"");
    m_assert(blind && m_eq(j_encode(blind),j_encode(legacy)),"Default serialization matches the legacy API");
    let equivalent=cad_project_open(j_encode(blind));let imported=feature(equivalent,first_body);
    cg_j_set(imported,"depth",j_number(4));cg_j_text(imported,"endCondition","blind");
    cg_j_set(imported,"flip",j_new(5,0));cg_j_text(imported,"unknownField","extra metadata");
    let explicit_defaults=j_encode(equivalent);
    let unchanged=cad_project_set_extrusion_options(equivalent,first_body,4000000,"newBody","blind",0,"");
    m_assert(unchanged && unchanged!=equivalent && m_eq(j_encode(unchanged),explicit_defaults) &&
        m_eq(j_encode(equivalent),explicit_defaults),"Equivalent options preserve explicit defaults, depth spelling and field order");
    let flipped=cad_project_set_extrusion_options(blind,first_body,4000000,"newBody","blind",1,"");m_assert(flipped,cg_error);
    assert_body(flipped,first_body,-4000000,0,400);
    m_assert(j_value(j_get(feature(flipped,first_body),"flip")) && !j_get(feature(flipped,first_body),"endCondition"),
        "Blind flip uses the v4 flag without an explicit default end");
    assert_targets(blind,first_body,0,0);

    project=option_sketch(blind,second,20000000,0,40000000,20000000);
    let block=cad_project_add_extrusion_options(project,second,1,20000000,"newBody","symmetric",1,"");m_assert(block,cg_error);
    assert_body(block,second_body,-10000000,10000000,8000);
    m_assert(m_eq(j_string(feature(block,second_body),"endCondition"),"symmetric"),"Save symmetric extent");
    assert_targets(block,second_body,first_body,0);assert_targets(block,"",first_body,second_body);
    m_assert(!cad_project_extrusion_targets(block,"unknown") && m_eq(cg_error,"Select an extrusion"),"Reject an unknown feature");
    m_assert(!cad_project_set_extrusion_options(block,second_body,20000000,"cut","up-to-body",0,second_body)
        && m_eq(cg_error,"Extrusion target body is missing"),"Reject a body targeting itself");

    project=option_sketch(block,cutter,24000000,4000000,30000000,10000000);
    let through=cad_project_add_extrusion_options(project,cutter,1,1000000,"cut","through-all",0,"");m_assert(through,cg_error);
    assert_body(through,first_body,0,4000000,400);
    assert_body(through,second_body,-10000000,10000000,7280);
    assert_targets(through,cut,first_body,second_body);
    let snapshot=j_encode(through);
    m_assert(!cad_project_set_extrusion_options(through,second_body,20000000,"join","symmetric",0,"")
        && m_eq(cg_error,"Feature would apply to a different body"),"Reject a downstream cut silently switching bodies");
    m_assert(!cad_project_set_extrusion_options(through,cut,1000000,"newBody","through-all",0,"")
        && m_eq(cg_error,"Extent needs a cut or join"),"An adaptive extent needs an existing body");
    m_assert(!cad_project_set_extrusion_options(through,cut,1000000,"cut","up-to-body",0,"later")
        && m_eq(cg_error,"Extrusion target body is missing"),"Reject an unavailable target");
    m_assert(!cad_project_set_extrusion_options(through,cut,1000000,"cut","up-to-body",1,first_body)
        && m_eq(cg_error,"Target is unreachable in the extrusion direction"),"Reject a target beyond the opposite direction");
    m_assert(m_eq(j_encode(through),snapshot),"Rejected edits leave the source graph unchanged");

    let stop=cad_project_set_extrusion_options(through,cut,2000000,"cut","up-to-body",0,first_body);m_assert(stop,cg_error);
    assert_body(stop,first_body,0,4000000,400);
    assert_body(stop,second_body,-10000000,10000000,7856);
    let saved=feature(stop,cut);cg_j_text(saved,"annotation","preserve me");
    stop=cad_project_open(j_encode(stop));m_assert(stop,cg_error);
    m_assert(m_eq(j_string(feature(stop,cut),"targetId"),first_body),"Save distinct measuring body");
    m_assert(!cad_project_set_extrusion_options(stop,first_body,4000000,"newBody","blind",1,"")
        && m_eq(cg_error,"Target is unreachable in the extrusion direction"),"Validate downstream extents after a change");
    let back=cad_project_set_extrusion_options(stop,cut,2000000,"cut","blind",0,first_body);m_assert(back,cg_error);
    saved=feature(back,cut);
    m_assert(!j_get(saved,"endCondition") && !j_get(saved,"targetId") && !j_get(saved,"flip")
        && m_eq(j_string(saved,"annotation"),"preserve me"),"Remove stale option fields only");
    assert_body(back,second_body,-10000000,10000000,7928);
    let joined=cad_project_set_extrusion_options(back,cut,12000000,"join","blind",0,"");m_assert(joined,cg_error);
    assert_body(joined,second_body,-10000000,12000000,8072);

    let rolled=cad_project_roll_to(stop,1);m_assert(rolled,cg_error);
    assert_targets(rolled,cut,first_body,0);assert_targets(rolled,"",first_body,second_body);
    let rolled_edit=cad_project_set_extrusion_options(rolled,cut,3000000,"cut","blind",0,"");m_assert(rolled_edit,cg_error);
    let data=j_get(cad_project_part(rolled_edit),"data");
    m_assert(j_integer(j_get(data,"tree"),"rollbackIndex")==1,"Keep rollback while validating saved edits");
    let suppressed=cad_project_suppress_feature(block,second_body,1);m_assert(suppressed,cg_error);
    assert_targets(suppressed,"",first_body,0);
    return 0;
}
