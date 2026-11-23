import "../continuity.flex";

fn ct_first(document) {
    return pc_first(j_get(j_get(document,"electrical"),"required_traces"));
}

fn ct_path_mentions(path,key,value) {
    let row=pc_first(path);
    while row {
        if m_eq(j_string(row,key),value) {return 1;}
        row=load64(row+24);
    }
    return 0;
}

fn ct_connected(document,count) {
    let checked=pcad_required_traces(document);
    m_assert(m_eq(j_string(checked,"status"),"checks_passed"),j_encode(checked));
    let traces=j_get(checked,"traces");
    m_assert(cg_j_count(traces)==count,"Each authored system path is checked in order");
    let trace=pc_first(traces);
    while trace {
        let path=j_get(trace,"path");let end=j_string(trace,"from");
        let row=pc_first(path);
        while row {
            m_assert(m_eq(j_string(row,"from"),end),"The reported physical path is contiguous");
            end=j_string(row,"to");row=load64(row+24);
        }
        m_assert(m_eq(end,j_string(trace,"to")) && m_eq(j_string(trace,"state"),"connected"),j_encode(trace));
        m_assert(ct_path_mentions(path,"record_id","controller-board") && ct_path_mentions(path,"record_id","sensor-board")
            && ct_path_mentions(path,"record_id","controller-mating") && ct_path_mentions(path,"record_id","sensor-mating")
            && ct_path_mentions(path,"kind","Wire"),"Both mounted boards, mating maps, and harness copper are traversed");
        trace=load64(trace+24);
    }
    let supply=pc_first(traces);
    m_assert(m_eq(j_string(supply,"id"),"sensor-supply")
        && ct_path_mentions(j_get(supply,"path"),"to","b:sensor-board:v:sensor-via"),"The supply path crosses the plated via");
}

fn ct_missing_conductors(text) {
    let document=j_parse(text);let e=j_get(document,"electrical");
    let sensor=pcm_find(j_get(e,"boards"),"sensor-board");
    cg_j_set(sensor,"vias",j_array());
    let report=pcad_required_traces(document);
    m_assert(m_eq(j_string(report,"status"),"checks_failed")
        && m_eq(j_string(pc_first(j_get(report,"traces")),"state"),"open"),"Board-side labels cannot connect across a missing via");

    document=j_parse(text);e=j_get(document,"electrical");
    let harness=j_get(e,"harness");
    let plugged=pcm_find(j_get(harness,"matings"),"sensor-mating");
    cg_j_set(plugged,"connected",j_new(5,0));
    report=pcad_required_traces(document);
    m_assert(m_eq(j_string(report,"status"),"checks_failed")
        && m_eq(j_string(pc_first(j_get(report,"traces")),"state"),"open"),"An unplugged connector opens the declared system path");

    document=j_parse(text);e=j_get(document,"electrical");sensor=pcm_find(j_get(e,"boards"),"sensor-board");
    cg_j_set(pc_first(j_get(sensor,"tracks")),"start",j_parse("[-1,10]"));
    report=pcad_required_traces(document);
    let trace=pc_first(j_get(report,"traces"));
    m_assert(m_eq(j_string(report,"status"),"unknown") && m_eq(j_string(trace,"state"),"unresolved")
        && m_eq(j_string(pc_first(j_get(trace,"unchecked")),"board_id"),"sensor-board"),j_encode(report));

    document=j_parse(text);e=j_get(document,"electrical");
    cg_j_set(e,"required_traces",j_array());
    m_assert(m_eq(j_string(pcad_required_traces(document),"status"),"unknown"),"Omitted paths cannot pass by default");
}

fn ct_branch_evidence(text) {
    let document=j_parse(text);let e=j_get(document,"electrical");
    let plug=pcm_find(j_get(e,"components"),"plug_a");let spare=pcm_find(j_get(plug,"pins"),"spare");
    cg_j_set(spare,"no_connect",j_new(5,0));
    j_add(j_get(e,"nets"),0,j_parse("{\"id\":\"foreign\",\"name\":\"WRONG\",\"endpoints\":[{\"component_id\":\"plug_a\",\"pin_id\":\"spare\"}]}"));
    let branch=j_parse("{\"id\":\"wrong-branch\",\"net_id\":\"foreign\",\"ends\":[{\"kind\":\"terminal\",\"component_id\":\"plug_a\",\"terminal_id\":\"t1\"},{\"kind\":\"terminal\",\"component_id\":\"plug_a\",\"terminal_id\":\"t2\"}]}");
    j_add(j_get(j_get(e,"harness"),"wires"),0,branch);
    let result=pcad_required_traces(document);let trace=pc_first(j_get(result,"traces"));
    m_assert(m_eq(j_string(result,"status"),"checks_failed") && m_eq(j_string(trace,"state"),"connected")
        && m_eq(j_encode(j_get(trace,"conflict_net_ids")),"[\"foreign\"]")
        && !ct_path_mentions(j_get(trace,"path"),"record_id","wrong-branch"),j_encode(trace));

    document=j_parse(text);e=j_get(document,"electrical");
    branch=j_parse(j_encode(branch));cg_j_set(branch,"net_id",j_text(""));
    j_add(j_get(j_get(e,"harness"),"wires"),0,branch);
    result=pcad_required_traces(document);trace=pc_first(j_get(result,"traces"));
    m_assert(m_eq(j_string(result,"status"),"checks_failed") && m_eq(j_string(trace,"state"),"connected")
        && ct_path_mentions(j_get(trace,"no_connects"),"id","t:plug_a:t2"),j_encode(trace));
}

fn ct_splice_and_zone(text) {
    let document=j_parse(text);let e=j_get(document,"electrical");let harness=j_get(e,"harness");
    cg_j_set(harness,"splices",j_parse("[{\"id\":\"junction\",\"name\":\"Supply junction\"}]"));
    let wire=pc_first(j_get(harness,"wires"));let first=pc_first(j_get(wire,"ends"));let last=load64(first+24);
    let junction=j_parse("{\"kind\":\"splice\",\"splice_id\":\"junction\"}");
    let wires=j_array();let left=j_parse("{\"id\":\"wire-a\",\"net_id\":\"supply\"}");
    let right=j_parse("{\"id\":\"wire-b\",\"net_id\":\"supply\"}");
    let ends=j_array();j_add(ends,0,j_parse(j_encode(first)));j_add(ends,0,j_parse(j_encode(junction)));j_add(left,"ends",ends);
    ends=j_array();j_add(ends,0,junction);j_add(ends,0,j_parse(j_encode(last)));j_add(right,"ends",ends);
    j_add(wires,0,left);j_add(wires,0,right);cg_j_set(harness,"wires",wires);
    let trace=pcad_trace(document,ct_first(document));
    m_assert(m_eq(j_string(trace,"state"),"connected") && ct_path_mentions(j_get(trace,"path"),"to","s:junction"),j_encode(trace));

    let controller=pcm_find(j_get(e,"boards"),"controller-board");
    cg_j_set(controller,"tracks",j_array());
    cg_j_set(controller,"zones",j_parse("[{\"id\":\"supply-fill\",\"net_id\":\"supply\",\"layer\":\"F.Cu\",\"outline\":[[8,8],[26,8],[26,11],[8,11]]}]"));
    trace=pcad_trace(document,ct_first(document));
    m_assert(m_eq(j_string(trace,"state"),"connected") && ct_path_mentions(j_get(trace,"path"),"kind","Zone copper"),j_encode(trace));
}

fn main(argc,argv) {
    let reference=m_read_file("libs/cad/tests/fixtures/sensor-continuity.pcad");
    m_assert(m_len(reference)>0,"Load the original sensor-unit continuity fixture");
    ct_connected(j_parse(reference),1);
    ct_missing_conductors(reference);
    ct_branch_evidence(reference);
    ct_splice_and_zone(reference);
    if argc==2 {
        let three_wire=j_parse(m_read_file(load64(argv+8)));
        m_assert(three_wire,"Load the original three-wire sensor fixture");
        ct_connected(three_wire,3);
    }
    return 0;
}
