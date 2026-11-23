import "cad/studio-history.flex";

fn history_volume(mesh,id) {
    m_assert(j_value(j_get(mesh,"closed")),j_string(mesh,"error"));
    let part=pc_find(j_get(mesh,"parts"),id);m_assert(part,"Expected part");
    return cg_number_bounded(j_get(part,"volume_mm3"),1000000);
}

fn history_mutations(plate) {
    let source=j_encode(plate);
    let features=j_get(cad_studio_feature_history(plate),"features");
    m_assert(cg_j_count(features)==4,"Original shape order");
    let toggle=pc_find(features,"cut");
    m_assert(m_eq(j_string(toggle,"source"),"stock") && m_eq(j_string(toggle,"state"),"active"),"Cut retains stock");
    m_assert(history_volume(cad_project_mesh(plate),"plate")==1146000000,"Active cut volume");

    let suppressed=cad_studio_suppress_feature(plate,"cut",1);m_assert(suppressed,cg_error);
    let cut=pc_find(j_get(suppressed,"nodes"),"cut");
    m_assert(j_value(j_get(cut,"suppressed")) && m_eq(j_string(cut,"b"),"punch"),"Suppression retains inputs");
    let expected=j_parse(source);cg_j_set(pc_find(j_get(expected,"nodes"),"cut"),"suppressed",j_new(5,1));
    m_assert(m_eq(j_encode(suppressed),j_encode(expected)),"Only the cut suppression changes");
    m_assert(history_volume(cad_project_mesh(suppressed),"plate")==1200000000,"Suppressed cut volume");
    let restored=cad_studio_suppress_feature(suppressed,"cut",0);m_assert(restored,cg_error);
    m_assert(m_eq(j_encode(restored),source),"Restore drops only the suppression field");
    m_assert(!cad_studio_suppress_feature(plate,"stock",1),"Cannot suppress a primitive");

    let reordered=cad_studio_move_feature(plate,"punch",-1);m_assert(reordered,cg_error);
    m_assert(m_eq(j_encode(j_get(reordered,"feature_order")),"[\"punch\",\"stock\",\"cut\",\"finish\"]"),"Explicit adjacent order");
    m_assert(m_eq(j_encode(j_get(reordered,"nodes")),j_encode(j_get(plate,"nodes"))),"Node storage order remains authored");
    m_assert(m_eq(j_encode(cad_project_mesh(reordered)),j_encode(cad_project_mesh(plate))),"Independent reorder preserves the mesh");
    m_assert(!cad_studio_move_feature(plate,"cut",-1) && m_len(cg_error),"Reject moving a feature before an active dependency");
    m_assert(!cad_studio_move_feature(plate,"stock",-1),"Outside the history");
    m_assert(!cad_studio_move_feature(plate,"punch",2),"Only adjacent moves");

    let deferred=cad_studio_move_feature(suppressed,"punch",1);m_assert(deferred,cg_error);
    m_assert(history_volume(cad_project_mesh(deferred),"plate")==1200000000,"Suppressed secondary input need not precede the cut");
    let deferred_source=j_encode(deferred);
    m_assert(!cad_studio_suppress_feature(deferred,"cut",0) && m_len(cg_error),"Restore checks saved dependencies again");
    m_assert(m_eq(j_encode(deferred),deferred_source) && m_eq(j_encode(plate),source),"Rejected copies leave input documents intact");
}

fn history_earlier(plate) {
    let states=cad_studio_earlier_features(plate,"plate");m_assert(states,cg_error);
    m_assert(m_eq(j_encode(states),"[\"cut\",\"stock\"]"),"Only earlier primary shapes are selectable");
    let source=j_encode(plate);
    m_assert(history_volume(cad_studio_preview_feature(plate,"plate","cut"),"plate")==1146000000,"Preview active cut");
    m_assert(history_volume(cad_studio_preview_feature(plate,"plate","stock"),"plate")==1200000000,"Preview stock");
    m_assert(j_get(cad_studio_preview_feature(plate,"plate","punch"),"error"),"Tool geometry is not an earlier part state");
    m_assert(m_eq(j_encode(plate),source),"Preview leaves the document intact");

    let nodes=j_get(plate,"nodes");
    let stock=pc_find(nodes,"stock");let final=pc_find(nodes,"finish");
    // Both binding nodes and a second part remain available in the earlier graph.
    j_add(nodes,0,j_parse("{\"id\":\"width\",\"type\":\"box\",\"size\":[22,5,5]}"));
    j_add(nodes,0,j_parse("{\"id\":\"offset\",\"type\":\"box\",\"size\":[7,5,5]}"));
    j_add(nodes,0,j_parse("{\"id\":\"other-body\",\"type\":\"box\",\"size\":[3,4,5],\"position\":[40,0,0]}"));
    j_add(stock,"size_bindings",j_parse("{\"x\":{\"node\":\"width\",\"axis\":\"x\",\"offset_mm\":0}}"));
    let parts=j_get(plate,"parts");let part=pc_find(parts,"plate");
    j_add(part,"datums",j_parse("[{\"id\":\"seat\",\"position\":[0,0,0],\"position_bindings\":{\"x\":{\"node\":\"offset\",\"axis\":\"x\",\"offset_mm\":0}}}]"));
    j_add(parts,0,j_parse("{\"id\":\"other\",\"node\":\"other-body\"}"));
    cg_j_set(final,"position",j_parse("[501,0,0]"));
    j_add(plate,"feature_order",j_parse("[\"stock\",\"punch\",\"cut\",\"finish\",\"width\",\"offset\",\"other-body\"]"));
    m_assert(j_get(cad_project_mesh(plate),"error"),"The authored final placement is broken");
    source=j_encode(plate);
    let earlier=cad_studio_preview_feature(plate,"plate","stock");
    m_assert(history_volume(earlier,"plate")==1320000000 && history_volume(earlier,"other")==60000000,"Earlier preview keeps bindings and other parts");
    m_assert(m_eq(j_encode(plate),source),"Earlier preview cannot save over the broken final graph");
}

fn main() {
    let source="{\"format\":\"puppycorp.pcad\",\"schema_version\":1,\"units\":\"mm\",\"nodes\":[{\"id\":\"stock\",\"type\":\"box\",\"size\":[20,10,6]},{\"id\":\"punch\",\"type\":\"box\",\"size\":[3,3,10],\"position\":[5,4,-2]},{\"id\":\"cut\",\"type\":\"subtract\",\"a\":\"stock\",\"b\":\"punch\"},{\"id\":\"finish\",\"type\":\"transform\",\"source\":\"cut\",\"position\":[2,0,0]}],\"parts\":[{\"id\":\"plate\",\"name\":\"Cut plate\",\"node\":\"finish\"}]}";
    history_mutations(j_parse(source));history_earlier(j_parse(source));
    m_print(1,"Standalone PCAD history preserved suppression, order, previews and recovery.\n");
    return 0;
}
