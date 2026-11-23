// A splice shares one assembly point across every incident conductor.
// Its wire endpoints still come from the explicitly authored harness graph.
fn pcr_splice_position(document,assembly,splice,placement) {
    if !placement {return cg_fail(m_cat("Place splice in Design: ",j_string(splice,"id")));}
    if !assembly {return cg_fail("Resolve the assembly before positioning splices");}
    if !pc_fields(placement,"[\"position\",\"instance_id\",\"datum_id\"]") {return 0;}
    let instance=j_get(placement,"instance_id");let datum=j_get(placement,"datum_id");
    if (instance && j_kind(instance)!=2) || (datum && j_kind(datum)!=2) {
        return cg_fail("Splice support and datum need stable reference IDs");
    }
    if !j_get(placement,"position") {return cg_fail("A splice needs a three-axis position");}
    return pcr_guide(document,assembly,placement);
}

fn pcr_splice_end(document,assembly,end,attachment) {
    let id=j_string(end,"splice_id");
    let harness=j_get(j_get(document,"electrical"),"harness");
    let all=pc_list(harness,"splices",128);
    if cg_error {return 0;}
    let splice=pcm_find(all,id);
    if !splice || !ph_id(id,64,1) {return cg_fail(m_cat("Route splice is missing: ",id));}
    let placement=j_get(splice,"placement");
    let point=pcr_splice_position(document,assembly,splice,placement);
    if !point || cg_error {return 0;}
    cg_j_text(attachment,"splice_id",id);
    let name=j_string(splice,"name");if !m_len(name) {name=id;}
    cg_j_text(attachment,"reference",name);j_add(attachment,"at",pcr_json_point(point));
    pcc_copy(placement,"instance_id",attachment);pcc_copy(placement,"datum_id",attachment);
    return point;
}

fn pcr_splice_members(wires,id) {
    let members=j_array();let wire=load64(wires+16);
    while wire {
        let ends=j_get(wire,"ends");
        if j_kind(ends)==3 && cg_j_count(ends)==2 {
            let end=load64(ends+16);let i=0;
            while end {
                if m_eq(j_string(end,"kind"),"splice") && m_eq(j_string(end,"splice_id"),id) {
                    let row=j_object();cg_j_text(row,"wire_id",j_string(wire,"id"));
                    cg_j_text(row,"side","from");if i {cg_j_text(row,"side","to");}
                    j_add(members,0,row);
                }
                end=load64(end+24);i=i+1;
            }
        }
        wire=load64(wire+24);
    }
    return members;
}

fn pcr_splices(document,assembly,harness,mesh) {
    let splices=pc_list(harness,"splices",128);let wires=pc_list(harness,"wires",256);
    if cg_error {cg_j_text(mesh,"splice_error",cg_error);cg_error=0;return 0;}
    let row=load64(splices+16);let results=j_array();let seen=j_object();
    while row {
        let placement=j_get(row,"placement");
        if placement {
            let id=j_string(row,"id");
            if !ph_id(id,64,1) || j_get(seen,id) {
                cg_j_text(mesh,"splice_error","Placed splices need distinct stable IDs");return 0;
            }
            cg_j_int(seen,id,1);
            let result=j_object();cg_j_text(result,"splice_id",id);pcc_copy(row,"name",result);
            let point=pcr_splice_position(document,assembly,row,placement);
            if point && !cg_error {j_add(result,"at",pcr_json_point(point));}
            if cg_error {
                cg_j_text(result,"status","unresolved");cg_j_text(result,"error",cg_error);cg_error=0;
            }else {cg_j_text(result,"status","positioned");}
            pcc_copy(placement,"instance_id",result);pcc_copy(placement,"datum_id",result);
            j_add(result,"members",pcr_splice_members(wires,id));j_add(results,0,result);
        }
        row=load64(row+24);
    }
    if cg_j_count(results) {j_add(mesh,"splices",results);}
    return !cg_error;
}
