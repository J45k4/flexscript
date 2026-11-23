import "cad/electrical/check.flex";
import "cad/linked-boards.flex";

fn pcb_test_source() {
    let document=j_parse(m_read_file("libs/cad/tests/fixtures/linked-boards.pcad"));
    let release=cad_pcad_linked_boards(document,0);m_assert(release,cg_error);
    let source=j_get(pc_first(j_get(release,"boards")),"source");m_assert(source,"Project the legacy controller board");
    return source;
}

fn pcb_test_has_issue(report,kind) {
    let issue=pc_first(j_get(report,"issues"));
    while issue {
        if m_eq(j_string(issue,"kind"),kind) {return 1;}
        issue=load64(issue+24);
    }
    return 0;
}

fn check_legacy_report(source) {
    let report=pcb_check(source);
    let expected=j_parse("{\"issues\":[],\"unrouted\":[],\"scope\":\"Two copper layers; circular through-hole pads/vias, straight constant-width tracks, rectangular outline and round holes. No zones, silkscreen, solder-mask, thermal, signal-integrity or electrical-driver ERC checks.\",\"connections_needed\":0,\"status\":\"checks_passed\"}");
    m_assert(m_eq(j_encode(report),j_encode(expected)),"Preserve the original two-pad board report");
    let netlist=pcb_netlist(source);let nets=pc_first(j_get(netlist,"nets"));
    m_assert(m_eq(j_encode(j_get(nets,"nodes")),"[{\"ref\":\"U1\",\"pin\":\"1\"},{\"ref\":\"J1\",\"pin\":\"1\"}]"),
        "Preserve stable legacy netlist order");
    cg_j_set(source,"tracks",j_array());
    report=pcb_check(source);
    m_assert(j_integer(report,"connections_needed")==1 && m_eq(j_string(report,"status"),"violations"),
        "A matching net label does not bridge physically open copper");
}

fn check_through_and_surface_pads(source) {
    let first=pc_first(j_get(source,"components"));let second=load64(first+24);
    cg_j_text(first,"footprint","HEADER_1X03_P2_54");j_add(j_get(first,"pins"),"3",j_new(0,0));
    cg_j_text(second,"footprint","SMD_1206_OVAL");
    let compiled=pc_compile(source);m_assert(!cg_error,cg_error);
    let parts=pc_first(j_get(compiled,"components"));let header=j_get(parts,"pads");
    let third=load64(load64(pc_first(header)+24)+24);
    m_assert(cg_j_count(header)==3 && m_eq(j_string(third,"pin"),"3") && j_integer(third,"drill")==1000
        && j_integer(third,"layers")==3 && j_integer(third,"ay")==15080,"Three-pad headers keep the through-hole drill and rotated pitch");
    let oval=pc_first(j_get(load64(parts+24),"pads"));
    m_assert(j_integer(oval,"layers")==1 && !j_integer(oval,"drill") && j_integer(oval,"radius")==700
        && cg_abs(j_integer(oval,"ax")-j_integer(oval,"bx"))==200 && cg_j_count(j_get(compiled,"holes"))==4,
        "The oval surface pad is front copper with no drill");
    m_assert(m_eq(j_string(pcb_check(source),"status"),"checks_passed"),"Front routing connects the front surface pad");

    cg_j_text(second,"side","back");
    compiled=pc_compile(source);m_assert(!cg_error,cg_error);
    parts=load64(pc_first(j_get(compiled,"components"))+24);
    oval=pc_first(j_get(parts,"pads"));
    m_assert(j_integer(oval,"layers")==2 && j_integer(load64(oval+24),"ay")==7000,"Back-side placement reflects pad 2 before rotation");
    let report=pcb_check(source);
    m_assert(j_integer(report,"connections_needed")==1,"A front track cannot reach an unplated back pad");
    cg_j_text(pc_first(j_get(source,"tracks")),"layer","B.Cu");
    m_assert(m_eq(j_string(pcb_check(source),"status"),"checks_passed"),"Switching the actual route to back copper closes the net");
    let connectivity=pcb_copper_links(source);
    m_assert(!j_get(connectivity,"error") && j_integer(connectivity,"count")==6 && cg_j_count(j_get(connectivity,"links"))==2,
        "Copper link indices include the added header pad and real tracks");
}

fn check_zone_and_edge_clearance(source) {
    cg_j_set(source,"tracks",j_array());
    let zones=j_parse("[{\"id\":\"supply-fill\",\"net\":\"VCC\",\"layer\":\"F.Cu\",\"outline\":[[8,8],[27,8],[27,16],[8,16]]}]");
    j_add(source,"zones",zones);
    let report=pcb_check(source);
    let zone=pc_first(j_get(report,"zones"));let island=pc_first(j_get(zone,"islands"));
    m_assert(m_eq(j_string(report,"status"),"checks_passed") && j_integer(island,"cells")==432
        && m_eq(j_encode(j_get(island,"contacts")),"[0,2]"),"Solid zone joins the board through these physical pads");
    let rules=j_parse("[{\"net\":\"VCC\",\"minimum_width\":0.5,\"clearance\":0.5}]");
    j_add(source,"net_rules",rules);
    report=pcb_check(source);
    zone=pc_first(j_get(report,"zones"));island=pc_first(j_get(zone,"islands"));
    m_assert(m_eq(j_string(report,"status"),"checks_passed") && j_integer(island,"cells")<432,
        "The net class narrows the usable fill without breaking those contacts");

    let substrate=j_get(source,"board");
    j_add(substrate,"outline",j_parse("[[0,0],[40,0],[40,25],[26,25],[26,9],[23,9],[23,25],[0,25]]"));
    let snapshot=j_encode(source);
    report=pcb_check(source);
    m_assert(pcb_test_has_issue(report,"copper_edge_clearance"),"Copper cannot cross the physical straight-edged outline");
    m_assert(m_eq(j_encode(source),snapshot),"Compiling the outline keeps the authored JSON independent");
}

fn check_three_wire_fixture(path) {
    let input=j_parse(m_read_file(path));m_assert(input,"Read the original three-wire PCAD fixture");
    let release=cad_pcad_linked_boards(input,0);m_assert(release,cg_error);
    let row=pc_first(j_get(release,"boards"));let count=0;
    while row {
        let check=pcb_check(j_get(row,"source"));
        m_assert(m_eq(j_string(check,"status"),"checks_passed"),j_encode(check));
        count=count+1;row=load64(row+24);
    }
    m_assert(count==2,"Both standalone three-wire PCB projections pass the expanded checker");
}

fn main(argc,argv) {
    check_legacy_report(pcb_test_source());
    check_through_and_surface_pads(pcb_test_source());
    check_zone_and_edge_clearance(pcb_test_source());
    if argc==2 {check_three_wire_fixture(load64(argv+8));}
    return 0;
}
