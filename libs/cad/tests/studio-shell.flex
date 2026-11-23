import "cad/studio-edit.flex";

fn shell_part(mesh,id,volume,bounds) {
    m_assert(!cg_error && j_value(j_get(mesh,"closed")),"The shell builds a closed solid");
    let part=pc_find(j_get(mesh,"parts"),id);
    let measured=j_encode(j_get(part,"volume_mm3"));
    m_assert(part && m_eq(measured,m_cat(volume,".000000")),m_cat("Expected shell volume ",m_cat(volume,m_cat("; measured ",measured))));
    let actual=pc_first(j_get(part,"bounds"));let expected=pc_first(j_parse(bounds));
    while expected {
        let a=pc_first(actual);let b=pc_first(expected);
        while b {
            m_assert(cg_number(a)==cg_number(b) && !cg_error,"Shell retains the source bounds");
            a=load64(a+24);b=load64(b+24);
        }
        actual=load64(actual+24);expected=load64(expected+24);
    }
}

fn main() {
    let source="{\"format\":\"puppycorp.pcad\",\"schema_version\":1,\"units\":\"mm\",\"nodes\":[{\"id\":\"stock\",\"type\":\"box\",\"size\":[24,16,9]}],\"parts\":[{\"id\":\"enclosure\",\"name\":\"Enclosure\",\"node\":\"stock\"}],\"feature_order\":[\"stock\"],\"tag\":\"preserve\"}";
    let project=cad_project_open(source);
    let top=cad_studio_add_shell(project,"enclosure","z",2000000);
    m_assert(top,cg_error);
    m_assert(m_eq(j_encode(project),source),"Shell addition leaves the original untouched");
    let part=pc_first(j_get(top,"parts"));let id=j_string(part,"node");
    let shell=pc_find(j_get(top,"nodes"),id);
    m_assert(m_eq(id,"shell-1") && m_eq(j_string(part,"id"),"enclosure") && m_eq(j_string(shell,"source"),"stock"),"Keep part identity and add one modifier for its stock");
    m_assert(m_eq(j_encode(j_get(top,"feature_order")),"[\"stock\",\"shell-1\"]") && m_eq(j_string(top,"tag"),"preserve"),"Append the authored feature order and preserve unknown fields");
    shell_part(cad_project_mesh(top),"enclosure","1776","[[0,0,0],[24,16,9]]");

    let wider=cad_studio_set_property(top,0,30000000);m_assert(wider,cg_error);
    shell_part(cad_project_mesh(wider),"enclosure","2136","[[0,0,0],[30,16,9]]");
    let old_shell=pc_find(j_get(wider,"nodes"),id);cg_j_text(old_shell,"description","preserve");
    let old=j_encode(wider);
    let side=cad_studio_set_shell(wider,id,"-x",1500000);m_assert(side,cg_error);
    shell_part(cad_project_mesh(side),"enclosure","2097","[[0,0,0],[30,16,9]]");
    let edited=pc_find(j_get(side,"nodes"),id);
    m_assert(m_eq(j_string(edited,"source"),"stock") && m_eq(j_string(edited,"description"),"preserve"),"Shell edit keeps source and extension data");
    m_assert(m_eq(j_encode(wider),old),"Shell editing leaves the original untouched");
    let equivalent=cad_studio_set_shell(side,id,"-x",1500000);m_assert(equivalent,cg_error);
    m_assert(m_eq(j_encode(equivalent),j_encode(side)),"Equivalent settings preserve the encoded feature");

    m_assert(!cad_studio_add_shell(project,"missing","z",2000000) && cg_error,"Reject an unknown output part");
    m_assert(!cad_studio_add_shell(project,"enclosure","top",2000000) && cg_error,"Reject an invalid local direction token");
    m_assert(!cad_studio_add_shell(project,"enclosure","z",9999) && cg_error,"Reject an out-of-range wall thickness");
    m_assert(!cad_studio_set_shell(wider,id,"z",32000000) && !m_eq(cg_error,""),"Reject thickness that exhausts the body");
    m_assert(m_eq(j_encode(wider),old),"A failed edit leaves the shell and its source byte-identical");
    m_assert(!cad_studio_set_property(top,0,3000000) && cg_error,"Validate downstream shell when shrinking the source");
    m_assert(!cad_studio_set_shell(wider,"stock","z",2000000) && cg_error,"Selecting a non-shell shape does not edit it");

    cg_j_set(edited,"suppressed",j_new(5,1));
    shell_part(cad_project_mesh(side),"enclosure","4320","[[0,0,0],[30,16,9]]");
    m_assert(!cad_studio_set_shell(side,id,"z",32000000) && cg_error,"Reject invalid walls even when suppressed");
    let suppressed=cad_studio_set_shell(side,id,"z",2000000);m_assert(suppressed,cg_error);
    m_assert(j_value(j_get(pc_find(j_get(suppressed,"nodes"),id),"suppressed")),"Editing a dormant feature preserves suppression");

    let assembly=j_parse("{\"instances\":[{\"id\":\"unit\",\"part\":\"enclosure\"}],\"mates\":[{\"id\":\"ground\",\"type\":\"fixed\",\"parent\":\"world\",\"child\":\"unit\"}]}");
    j_add(project,"assembly",assembly);
    let placed=cad_studio_add_shell(project,"enclosure","z",2000000);m_assert(placed,cg_error);
    m_assert(m_eq(j_encode(j_get(placed,"assembly")),j_encode(assembly)),"Preserve references to the part from every occurrence");
    shell_part(cad_project_mesh(placed),"unit","1776","[[0,0,0],[24,16,9]]");
    return 0;
}
