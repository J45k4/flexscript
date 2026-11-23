import "cad/step-assembly.flex";
fn main() {
    let file=cad_step_read(m_read_file("libs/cad/tests/fixtures/step-mounts.step"));m_assert(file,cg_error);
    let tree=cad_step_hierarchy(file);m_assert(tree,cg_error);
    m_assert(j_integer(tree,"placedParts")==2 && j_integer(tree,"placedAssemblies")==2,"Count both paths through the shared mount");
    let wanted=j_parse(m_read_file("libs/cad/tests/fixtures/step-mounts.pcad"));
    let hash=j_string(j_get(j_get(wanted,"assembly"),"import"),"sha256");
    let starter=sa_starter();let result=cad_step_adopt(starter,file,"step-mounts.step",hash);m_assert(result,cg_error);
    m_assert(sa_matches(result,wanted),"Repeated nested parts and reversed frame match Biscuit");
    m_assert(!j_get(starter,"assembly") && m_eq(j_string(pc_first(j_get(starter,"nodes")),"id"),"body"),"Original document is unchanged");
    cg_j_int(starter,"segments",32);m_assert(!cad_step_adopt(starter,file,"step-mounts.step",hash),"Customized starter must survive");
    m_assert(!cad_step_can_adopt(result),"Protect existing hierarchy");
    return 0;
}
