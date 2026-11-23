// Apply a normalized STEP body to a copy. Replacement retains the node ID
// and all existing part, assembly and feature references to it.
import "step-import.flex";
import "project.flex";

fn si_free_id(rows,prefix) {
    let i=1;let id=m_cat(prefix,"1");while pc_find(rows,id) {i=i+1;id=m_cat(prefix,m_int(i));}return id;
}
fn cad_step_apply(project,shape,replacement) {
    cg_begin();
    if project && !cad_project_is_studio(project) {return cg_fail("Choose a standalone PCAD design");}
    let result=0;if project {result=j_parse(j_encode(project));}
    else {result=j_parse("{\"format\":\"puppycorp.pcad\",\"schema_version\":1,\"units\":\"mm\",\"project_scope\":\"mechanical\",\"nodes\":[],\"parts\":[]}");}
    if !m_eq(j_string(shape,"type"),"faceted") {return cg_fail("Choose a faceted STEP shape");}
    let nodes=j_get(result,"nodes");let parts=j_get(result,"parts");let name=j_string(j_get(shape,"import"),"name");
    if j_kind(nodes)!=3 || j_kind(parts)!=3 {return cg_fail("Expected PCAD nodes and parts");}
    if m_len(replacement) {
        let node=pc_find(nodes,replacement);if !m_eq(j_string(node,"type"),"faceted") {return cg_fail("Select an existing imported shape");}
        let keys=j_parse("[\"vertices\",\"triangles\",\"import\"]");let key=pc_first(keys);while key {
            let field=j_value(key);cg_j_set(node,field,j_parse(j_encode(j_get(shape,field))));key=load64(key+24);
        }
    }else {
        let id=si_free_id(nodes,"step-geometry-");let node=j_parse(j_encode(shape));cg_j_text(node,"id",id);j_add(nodes,0,node);
        let part=j_object();let part_id=si_free_id(parts,"step-part-");cg_j_text(part,"id",part_id);cg_j_text(part,"node",id);
        cg_j_text(part,"name",name);cg_j_text(part,"color","#82b38e");j_add(parts,0,part);
        let assembly=j_get(result,"assembly");if assembly {
            let instances=j_get(assembly,"instances");let mates=j_get(assembly,"mates");
            if j_kind(instances)!=3 || j_kind(mates)!=3 {return cg_fail("Expected assembly instances and mates");}
            let occurrence=part_id;if pc_find(instances,occurrence) {occurrence=si_free_id(instances,"step-occurrence-");}
            let instance=j_object();cg_j_text(instance,"id",occurrence);cg_j_text(instance,"part",part_id);cg_j_text(instance,"name",name);j_add(instances,0,instance);
            let mate=j_object();cg_j_text(mate,"id",si_free_id(mates,"step-mate-"));cg_j_text(mate,"type","fixed");cg_j_text(mate,"parent","world");cg_j_text(mate,"child",occurrence);j_add(mates,0,mate);
        }
    }
    let mesh=cad_project_mesh(result);if j_get(mesh,"error") || !j_value(j_get(mesh,"closed")) {return cg_fail("STEP import needs closed solids");}
    return result;
}
