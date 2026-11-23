import "cad/studio-edit.flex";

fn main() {
    let source="{\"format\":\"puppycorp.pcad\",\"schema_version\":1,\"units\":\"mm\",\"parameters\":[{\"id\":\"width\",\"name\":\"Width\",\"mm\":10}],\"nodes\":[{\"id\":\"block\",\"type\":\"box\",\"size\":[1,5,2],\"size_bindings\":{\"x\":{\"parameter\":\"width\"}}}],\"parts\":[{\"id\":\"block\",\"node\":\"block\"}],\"tag\":\"preserved\"}";
    let project=cad_project_open(source);
    let fields=cad_studio_properties(project);
    m_assert(cg_count(fields)==3,"Only the parameter and unbound box axes are editable");
    let copy=cad_studio_set_property(project,0,12000000);
    m_assert(copy,cg_error);
    let mesh=cad_project_mesh(copy);let part=pc_first(j_get(mesh,"parts"));
    let maximum=load64(pc_first(j_get(part,"bounds"))+24);
    m_assert(cg_number(pc_first(maximum))==12000000,"The parameter drives the solid");
    let node=pc_first(j_get(copy,"nodes"));
    m_assert(j_value(pc_first(j_get(node,"size")))==1 && j_get(node,"size_bindings"),"Save authored sizes and bindings");
    m_assert(m_eq(j_string(copy,"tag"),"preserved") && m_eq(j_encode(project),source),"Preserve source and extension fields");
    m_assert(!cad_studio_set_property(copy,0,-1000000) && cg_error,"Reject invalid solved geometry");
    m_assert(!cad_studio_set_property(copy,3,1000000),"Reject missing property");
    m_assert(!cad_studio_toggle_fixed(copy,"missing"),"Reject missing occurrence");
    return 0;
}
