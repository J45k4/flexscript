// Author or inspect the ordered shape history of a standalone PCAD document.
import "studio-edit.flex";

fn psh_rows(project) {
    cg_begin();
    if !cad_project_is_studio(project) || j_kind(j_get(project,"schema_version"))!=1
        || j_integer(project,"schema_version")!=1 || !m_eq(j_string(project,"units"),"mm") {
        return cg_fail("Select a standalone schema-1 PCAD design in millimetres");
    }
    let nodes=j_get(project,"nodes");
    if j_kind(nodes)!=3 || !cg_j_count(nodes) || cg_j_count(nodes)>48 {
        return cg_fail("Feature history requires one to 48 shape nodes");
    }
    return cg_feature_rows(nodes,j_get(project,"feature_order"));
}

fn psh_primary(node) {
    let type=j_string(node,"type");
    if cg_modifier(type) {return j_string(node,"source");}
    if cg_combines(type) {return j_string(node,"a");}
    return "";
}

fn cad_studio_feature_history(project) {
    let rows=psh_rows(project);if cg_error {return ca_error();}
    let features=j_array();let i=0;
    while i<cg_count(rows) {
        let node=cg_at(rows,i);let feature=j_object();
        let id=j_string(node,"id");let name=j_string(node,"name");
        if !m_len(name) {name=id;}
        cg_j_text(feature,"id",id);cg_j_text(feature,"name",name);
        cg_j_text(feature,"type",j_string(node,"type"));
        let state="active";if j_value(j_get(node,"suppressed")) {state="suppressed";}
        cg_j_text(feature,"state",state);
        let source=psh_primary(node);if m_len(source) {cg_j_text(feature,"source",source);}
        j_add(features,0,feature);i=i+1;
    }
    let out=j_object();j_add(out,"features",features);return out;
}

fn psh_validate(project) {
    let mesh=cad_project_mesh(project);
    if cg_error || j_get(mesh,"error") {return 0;}
    if !j_value(j_get(mesh,"closed")) {return cg_fail("The feature change needs closed solids");}
    return project;
}

fn cad_studio_suppress_feature(project,id,suppressed) {
    psh_rows(project);
    if cg_error {return 0;}
    if suppressed!=0 && suppressed!=1 {return cg_fail("Suppression must be true or false");}
    let copy=j_parse(j_encode(project));let node=pc_find(j_get(copy,"nodes"),id);
    if !m_len(psh_primary(node)) {return cg_fail("Suppress a modifier with an earlier body");}
    if suppressed {cg_j_set(node,"suppressed",j_new(5,1));}
    else {pcs_remove(node,"suppressed");}
    return psh_validate(copy);
}

fn cad_studio_move_feature(project,id,delta) {
    let rows=psh_rows(project);if cg_error {return 0;}
    if delta!=1 && delta!= -1 {return cg_fail("Move a feature by one history position");}
    let index=0;let count=cg_count(rows);
    while index<count && !m_eq(j_string(cg_at(rows,index),"id"),id) {index=index+1;}
    let target=index+delta;
    if index==count || target<0 || target>=count {
        return cg_fail("The feature cannot move beyond the history");
    }
    let order=j_array();let i=0;
    while i<count {
        let selected=i;
        if i==index {selected=target;}
        else if i==target {selected=index;}
        j_add(order,0,j_text(j_string(cg_at(rows,selected),"id")));
        i=i+1;
    }
    let copy=j_parse(j_encode(project));cg_j_set(copy,"feature_order",order);
    return psh_validate(copy);
}

fn psh_earlier(project,part_id) {
    let parts=j_get(project,"parts");let nodes=j_get(project,"nodes");
    let part=pcm_find(parts,part_id);
    if !part {return cg_fail("Select a standalone PCAD part");}
    let seen=j_object();let states=j_array();let id=j_string(part,"node");
    cg_j_int(seen,id,1);
    let next=psh_primary(pc_find(nodes,id));
    while m_len(next) && !j_get(seen,next) {
        let node=pc_find(nodes,next);if !node {return states;}
        j_add(states,0,j_text(next));cg_j_int(seen,next,1);
        next=psh_primary(node);
    }
    return states;
}

fn cad_studio_earlier_features(project,part_id) {
    psh_rows(project);if cg_error {return 0;}
    return psh_earlier(project,part_id);
}

fn psh_root(roots,queued,id) {
    if m_len(id) && !j_get(queued,id) {
        cg_push(roots,id);cg_j_int(queued,id,1);
    }
    return 1;
}

fn psh_binding_roots(bindings,roots,queued) {
    if j_kind(bindings)!=4 {return 0;}
    let field=load64(bindings+16);
    while field {
        psh_root(roots,queued,j_string(field,"node"));field=load64(field+24);
    }
    return 1;
}

fn psh_preview_nodes(project,rows,sketches) {
    let roots=cg_array();let queued=j_object();let needed=j_object();
    let part=pc_first(j_get(project,"parts"));
    while part {
        psh_root(roots,queued,j_string(part,"node"));
        let datum=pc_first(j_get(part,"datums"));
        while datum {
            psh_binding_roots(j_get(datum,"position_bindings"),roots,queued);
            datum=load64(datum+24);
        }
        part=load64(part+24);
    }
    let nodes=j_get(project,"nodes");let index=0;
    while index<cg_count(roots) {
        let id=cg_at(roots,index);
        if !j_get(needed,id) {
            let picked=cg_pick_inputs(project,rows,id,sketches);
            if cg_error {return 0;}
            let field=load64(picked+16);
            while field {
                let node_id=load64(field+32);
                if !j_get(needed,node_id) {
                    cg_j_int(needed,node_id,1);
                    let node=pc_find(nodes,node_id);
                    psh_binding_roots(j_get(node,"size_bindings"),roots,queued);
                }
                field=load64(field+24);
            }
        }
        index=index+1;
    }
    return needed;
}

fn psh_filter(rows,kept,key) {
    let filtered=j_array();let row=pc_first(rows);
    while row {
        let id=j_value(row);if key {id=j_string(row,key);}
        if j_get(kept,id) {j_add(filtered,0,j_parse(j_encode(row)));}
        row=load64(row+24);
    }
    return filtered;
}

// Evaluate a temporary earlier body graph with the rest of the design still present.
fn cad_studio_preview_feature(project,part_id,feature_id) {
    let rows=psh_rows(project);if cg_error {return ca_error();}
    let step=pc_first(psh_earlier(project,part_id));
    while step && !m_eq(j_value(step),feature_id) {step=load64(step+24);}
    if !step {cg_fail("The earlier part state is missing");return ca_error();}
    let copy=j_parse(j_encode(project));let part=pc_find(j_get(copy,"parts"),part_id);
    cg_j_text(part,"node",feature_id);
    let sketches=j_object();let kept=psh_preview_nodes(copy,rows,sketches);
    if cg_error {return ca_error();}
    let nodes=psh_filter(j_get(copy,"nodes"),kept,"id");cg_j_set(copy,"nodes",nodes);
    let order=j_get(copy,"feature_order");
    if order {cg_j_set(copy,"feature_order",psh_filter(order,kept,0));}
    let defined=j_get(copy,"sketches");
    if defined {cg_j_set(copy,"sketches",psh_filter(defined,sketches,"id"));}
    return cad_project_mesh(copy);
}
