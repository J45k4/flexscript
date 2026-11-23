import "cad/linked-boards.flex";

fn board_named(rows,id) {
    let row=pc_first(rows);
    while row && !m_eq(j_string(row,"board_id"),id) {row=load64(row+24);}
    return row;
}

fn check_sensor_links(document,fixture) {
    let snapshot=j_encode(document);
    m_assert(cad_pcad_board_count(document)==2,"Two authored boards");
    let release=cad_pcad_linked_boards(document,0);m_assert(release,cg_error);
    let manifest=j_get(release,"manifest");let maps=j_get(manifest,"boards");
    m_assert(m_eq(j_string(manifest,"format"),"biscuit-pcad-pcb-assembly-1") && m_eq(j_string(manifest,"units"),"mm")
        && m_len(j_string(manifest,"placement_frame")) && m_len(j_string(manifest,"occurrence_frame")),"Manifest frames and units");
    let controller=pc_first(maps);let sensor=load64(controller+24);
    m_assert(m_eq(j_string(controller,"board_id"),"controller-board") && m_eq(j_string(sensor,"board_id"),"sensor-board")
        && !load64(sensor+24),"Ordered board map");
    let mounted=pc_first(j_get(sensor,"occurrences"));
    m_assert(m_eq(j_string(mounted,"id"),"sensor") && m_eq(j_string(mounted,"part"),"sensor-pcb")
        && m_eq(j_string(mounted,"node"),"sensor-shape") && !load64(mounted+24),"Sensor links to its solved occurrence");
    let transform="[[1.000000,0.000000,0.000000,54.000000],[0.000000,1.000000,0.000000,8.000000],[0.000000,0.000000,1.000000,7.000000]]";
    if !fixture {
        transform="[[1.000000,0.000000,0.000000,54.000000],[0.000000,1.000000,0.000000,7.000000],[0.000000,0.000000,1.000000,5.000000]]";
    }
    m_assert(m_eq(j_encode(j_get(mounted,"transform")),transform),"Exact world transform");
    let placement=pc_first(j_get(sensor,"placements"));let pad=pc_first(j_get(placement,"pad_pins"));
    m_assert(m_eq(j_string(placement,"component_id"),"socket_b") && j_integer(placement,"rotation")==90
        && m_eq(j_string(placement,"side"),"front"),"PCB placement remains board-local");
    m_assert(j_integer(pad,"pad")==1 && m_eq(j_string(pad,"pin_id"),"power") && m_eq(j_string(pad,"pin_number"),"1")
        && m_eq(j_string(pad,"net_id"),"supply"),"Pin and net IDs survive copper projection");
    pad=load64(pad+24);
    m_assert(j_integer(pad,"pad")==2 && m_eq(j_string(pad,"pin_id"),"spare") && j_kind(j_get(pad,"net_id"))==0,
        "Explicit no-connect keeps the logical pin identity");

    let row=board_named(j_get(release,"boards"),"sensor-board");let source=j_get(row,"source");
    m_assert(source && !j_get(row,"error"),j_string(row,"error"));
    m_assert(m_eq(j_encode(j_get(source,"nets")),"[\"VCC\"]"),"Use board-local KiCad net names");
    let pads=j_get(pc_first(j_get(source,"components")),"pins");
    m_assert(m_eq(j_string(pads,"1"),"VCC") && j_kind(j_get(pads,"2"))==0,"Export connected and no-connect pads");
    let via=pc_first(j_get(source,"vias"));
    m_assert(m_eq(j_string(via,"net"),"VCC") && m_eq(j_encode(j_get(via,"at")),"[17,10]"),"Preserve a board-local via");
    m_assert(m_eq(j_encode(j_get(j_get(source,"board"),"size")),"[40,25]"),"Preserve board dimensions");

    let mesh=pcad_mechanical(j_parse(snapshot));m_assert(!j_get(mesh,"error"),j_string(mesh,"error"));
    let same=cad_pcad_linked_boards(document,mesh);m_assert(same,cg_error);
    m_assert(m_eq(j_encode(release),j_encode(same)) && m_eq(j_encode(document),snapshot),
        "Reusing the solved pose preserves the deterministic output and authored document");
}

fn check_board_errors(document) {
    let electrical=j_get(document,"electrical");let boards=j_get(electrical,"boards");
    let controller=pc_first(boards);let sensor=load64(controller+24);
    let track=pc_first(j_get(sensor,"tracks"));cg_j_text(track,"net_id","missing");
    let error=cad_pcad_linked_boards(document,0);m_assert(error,cg_error);
    let rows=j_get(error,"boards");let first=pc_first(rows);let second=load64(first+24);
    m_assert(j_get(first,"source") && !j_get(first,"error") && !j_get(second,"source")
        && m_len(j_string(second,"error")) && !cg_error,"Report invalid source copper on the selected board only");
    cg_j_text(track,"net_id","supply");
    let placement=pc_first(j_get(sensor,"placements"));cg_j_text(placement,"component_id","socket_a");
    error=cad_pcad_linked_boards(document,0);m_assert(error,cg_error);
    second=load64(pc_first(j_get(error,"boards"))+24);
    m_assert(m_eq(j_string(second,"error"),"A logical component is placed on multiple footprints or boards"),
        "Reject a shared logical instance being placed twice");
    cg_j_text(sensor,"id","controller-board");
    m_assert(!cad_pcad_linked_boards(document,0) && m_eq(cg_error,"Boards, components and nets need stable unique IDs"),
        "Reject ambiguous board IDs before reporting board positions");
    j_add(electrical,"pcb",j_object());
    m_assert(!cad_pcad_board_count(document),"Do not accept both legacy and multi-board records");
}

fn check_repeated_occurrence(document) {
    let assembly=j_get(document,"assembly");
    j_add(j_get(assembly,"instances"),0,j_parse("{\"id\":\"sensor-copy\",\"part\":\"sensor-pcb\"}"));
    j_add(j_get(assembly,"mates"),0,j_parse("{\"id\":\"mount-copy\",\"type\":\"fixed\",\"parent\":\"world\",\"child\":\"sensor-copy\",\"parent_frame\":{\"position\":[94,50,20],\"rotation\":[0,0,90]}}"));
    let result=cad_pcad_linked_boards(document,0);m_assert(result,cg_error);
    let sensor=board_named(j_get(j_get(result,"manifest"),"boards"),"sensor-board");
    let first=pc_first(j_get(sensor,"occurrences"));let second=load64(first+24);
    m_assert(m_eq(j_string(first,"id"),"sensor") && m_eq(j_string(second,"id"),"sensor-copy") && !load64(second+24),
        "One board contains each physical occurrence of the same part");
    m_assert(m_eq(j_encode(j_get(second,"transform")),"[[0.000000,-1.000000,0.000000,94.000000],[1.000000,0.000000,0.000000,50.000000],[0.000000,0.000000,1.000000,20.000000]]"),
        "A rotated occurrence keeps its own world frame");
}

fn check_routing_rules(document) {
    let electrical=j_get(document,"electrical");let net=pc_find(j_get(electrical,"nets"),"supply");
    j_add(electrical,"net_classes",j_parse("[{\"id\":\"power\",\"name\":\"Power\",\"minimum_width\":0.4,\"clearance\":0.2}]"));
    cg_j_text(net,"class_id","power");let snapshot=j_encode(document);
    let linked=cad_pcad_linked_boards(document,0);m_assert(linked,cg_error);
    let board=board_named(j_get(j_get(linked,"manifest"),"boards"),"sensor-board");
    let rule=pc_first(j_get(board,"routing_rules"));
    m_assert(rule && !load64(rule+24) && m_eq(j_string(rule,"net"),"VCC")
        && m_eq(j_string(rule,"net_id"),"supply") && m_eq(j_string(rule,"class_id"),"power")
        && m_eq(j_string(rule,"class_name"),"Power"),"The route names retain canonical net and class IDs");
    m_assert(cg_number(j_get(rule,"minimum_width"))==400000 && cg_number(j_get(rule,"clearance"))==200000
        && cg_number(j_get(rule,"effective_clearance"))==250000,"The board clearance takes precedence over a smaller class clearance");
    let source=board_named(j_get(linked,"boards"),"sensor-board");
    let projected=pc_first(j_get(j_get(source,"source"),"net_rules"));
    m_assert(m_eq(j_string(projected,"net"),"VCC") && !j_get(projected,"net_id")
        && m_eq(j_encode(document),snapshot),"Release metadata leaves checker inputs and authored board untouched");
}

fn check_fitted_package(document) {
    let snapshot=j_encode(document);let mesh=pcad_mechanical(j_parse(snapshot));
    m_assert(j_value(j_get(mesh,"closed")) && !j_get(mesh,"error"),j_string(mesh,"error"));
    let assembly=j_get(mesh,"assembly");let instances=j_get(assembly,"instances");
    let fitted=pc_find(instances,"pkg-3289940991");
    m_assert(cg_j_count(instances)==7 && fitted,"Reopen the historical fitted package occurrence");
    m_assert(m_eq(j_encode(j_get(fitted,"transform")),
        "[[0.000000,-1.000000,0.000000,14.000000],[1.000000,0.000000,0.000000,18.000000],[0.000000,0.000000,1.000000,7.100000]]"),
        "The package carries the original pinned front-side pose");
    let projected=cad_pcad_linked_boards(document,mesh);m_assert(projected,cg_error);
    let same=cad_pcad_linked_boards(document,0);m_assert(same,cg_error);
    m_assert(m_eq(j_encode(projected),j_encode(same)) && m_eq(j_encode(document),snapshot),
        "Evaluating or reusing the pose preserves the source and board projections");
    let boards=j_get(j_get(projected,"manifest"),"boards");let controller=pc_first(boards);
    let mount=pc_first(j_get(controller,"occurrences"));
    m_assert(cg_j_count(boards)==2 && m_eq(j_string(mount,"id"),"controller") && !load64(mount+24),
        "Fitted mechanical bodies do not become extra board occurrences");
    let first=pc_first(j_get(projected,"boards"));let second=load64(first+24);
    m_assert(j_get(first,"source") && j_get(second,"source"),"Both source boards still export");

    let before=j_encode(mesh);let corrupt=j_parse(before);
    let bad_assembly=j_get(corrupt,"assembly");
    cg_j_text(pc_find(j_get(bad_assembly,"instances"),"lid"),"part","pkg-part-missing");
    m_assert(!cad_pcad_linked_boards(document,corrupt)
        && m_eq(cg_error,"A solved assembly occurrence has no part definition"),
        "A package prefix does not authorize an unknown authored part");
    corrupt=j_parse(before);bad_assembly=j_get(corrupt,"assembly");
    cg_j_text(pc_find(j_get(bad_assembly,"mates"),"pkg-3289940991"),"parent","sensor");
    m_assert(!cad_pcad_linked_boards(document,corrupt)
        && m_eq(cg_error,"A solved assembly occurrence has no part definition"),
        "A genuine fitted ID still needs its authored board's fixed mate");
    let collision=j_parse(snapshot);
    j_add(j_get(j_get(collision,"assembly"),"instances"),0,
        j_parse("{\"id\":\"pkg-3289940991\",\"part\":\"missing\"}"));
    m_assert(!cad_pcad_linked_boards(collision,mesh)
        && m_eq(cg_error,"A solved assembly occurrence has no part definition"),
        "An authored missing part cannot masquerade as a fitted package");
}

fn main(argc,argv) {
    let text=m_read_file("libs/cad/tests/fixtures/linked-boards.pcad");
    let document=j_parse(text);m_assert(document,"Load the two-board fixture");
    check_sensor_links(document,1);
    check_board_errors(j_parse(text));
    check_repeated_occurrence(j_parse(text));
    check_routing_rules(j_parse(text));
    check_fitted_package(j_parse(m_read_file("libs/cad/tests/fixtures/studio-fitted-package.pcad")));
    if argc==2 {
        let sensor=j_parse(m_read_file(load64(argv+8)));m_assert(sensor,"Load the standalone sensor unit");
        check_sensor_links(sensor,0);
    }
    return 0;
}
