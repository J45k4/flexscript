import "cad/project-access.flex";
import "cad/project-spline-edit.flex";

fn sde_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}
fn sde_rows(project) {return j_get(sde_node(project,"native-sketch-1"),"relations");}
fn sde_target(project,id,original,curve) {
    let old=pc_find(sde_rows(original),id);let next=pc_find(sde_rows(project),id);
    m_assert(old && next,"Original contact ID must survive");
    let copy=j_parse(j_encode(old));cg_j_text(copy,"b",curve);
    return m_assert(m_eq(j_encode(next),j_encode(copy)),m_cat("Unexpected retargeted relation: ",j_encode(next)));
}
fn sde_mesh(project) {
    let mesh=cad_project_mesh(project);
    m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));return mesh;
}
fn sde_edit(original,split) {
    let sk="native-sketch-1";let source="spline-guide";let target="native-entity-1";
    let saved=j_encode(original);let changed=0;
    if split {changed=cad_project_split_spline(original,sk,source,cg_v(15000000,15000000,0),1000000);}
    else {changed=cad_project_trim_spline(original,sk,source,cg_v(12000000,14400000,0),1000000);}
    m_assert(changed,cg_error);
    let inspect=cad_project_inspect_source(j_encode(changed));m_assert(!j_get(inspect,"readOnly"),j_string(inspect,"readOnly"));
    changed=j_get(inspect,"document");m_assert(changed,"Reopen the edited PCAD document");
    sde_target(changed,"normal-from-web",original,target);sde_target(changed,"contact-right",original,target);
    m_assert(m_eq(j_encode(sde_node(changed,"normal-line")),j_encode(sde_node(original,"normal-line"))),"Remap the relation while preserving the original follower geometry");
    let rows=sde_rows(changed);let join=pc_find(rows,"native-spline-coincident-1");
    if split {
        sde_target(changed,"contact-between",original,source);sde_target(changed,"contact-at-split",original,source);
        m_assert(join && m_eq(j_string(j_get(join,"a"),"entityId"),source) && m_eq(j_string(j_get(join,"b"),"entityId"),target),"Join the two cut endpoints while keeping a contact at that tie on the first piece");
    }else {
        m_assert(!join && !pc_find(rows,"contact-between") && !pc_find(rows,"contact-at-split"),"Drop only relations on the discarded interval");
        m_assert(sde_node(changed,"follower-between") && sde_node(changed,"follower-at-split"),"Keep followers whose contacts were removed");
    }
    let piece=sde_node(changed,target);let points=j_get(j_get(piece,"spline"),"points");let first=15000000;if !split {first=18000000;}
    m_assert(cg_j_count(points)==4 && load64(pc_uv(pc_first(points)))==first,"Select the precise retained cubic interval");
    let mesh=sde_mesh(original);m_assert(m_eq(j_encode(mesh),j_encode(sde_mesh(changed))),"A construction spline edit preserves the independent closed solid");
    let lengthened=cad_project_set_line_length(changed,sk,"normal-line",8000000);m_assert(lengthened,cg_error);
    sde_target(lengthened,"normal-from-web",original,target);
    m_assert(m_eq(j_encode(mesh),j_encode(sde_mesh(lengthened))) && m_eq(saved,j_encode(original)),"Later edits solve the original Normal on the new piece without mutating the source graph");
    return 1;
}
fn sde_wrapped() {
    let sk="native-sketch-1";let id="native-entity-1";let project=cad_project_new("Wrapped contact");
    let points=cg_array();cg_push(points,cg_v(-20000000,-20000000,0));cg_push(points,cg_v(20000000,-20000000,0));
    cg_push(points,cg_v(20000000,20000000,0));cg_push(points,cg_v(-20000000,20000000,0));
    m_assert(cad_project_add_curve(project,sk,"periodic",points),cg_error);
    m_assert(cad_project_add_primitive(project,sk,"line",cg_v(0,-30000000,0),cg_v(0,30000000,0)),cg_error);
    let at=cg_v(-27500000,0,0);m_assert(cad_project_add_primitive(project,sk,"point",at,at),cg_error);
    let rows=sde_rows(project);j_add(rows,0,j_parse("{\"id\":\"wrapped-contact\",\"type\":\"pointOnCurve\",\"a\":{\"entityId\":\"native-entity-3\",\"point\":\"center\"},\"b\":\"native-entity-1\"}"));
    let trimmed=cad_project_trim_spline(project,sk,id,cg_v(27500000,0,0),1000000);m_assert(trimmed,cg_error);
    sde_target(trimmed,"wrapped-contact",project,id);
    let first=pc_first(j_get(j_get(sde_node(trimmed,id),"spline"),"points"));
    m_assert(cg_distance2(pc_uv(first),cg_v(0,27500000,0))==0,"Cut opens the retained side at the upper intersection");
    let split=cad_project_split_spline(project,sk,id,cg_v(27500000,0,0),1000000);m_assert(split,cg_error);
    sde_target(split,"wrapped-contact",project,id);
    return 1;
}
fn main() {
    let input=cad_project_open(m_read_file("libs/cad/tests/fixtures/spline-dependent-edit.pcad"));m_assert(input,cg_error);
    return !(sde_edit(input,1) && sde_edit(input,0) && sde_wrapped());
}
