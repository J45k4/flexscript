import "cad/studio/pcad-copper-review.flex";

fn main() {
    let document=j_parse(m_read_file("libs/cad/tests/fixtures/linked-boards.pcad"));
    let original=j_encode(document);
    let electrical=j_get(document,"electrical");
    let board=pc_first(j_get(electrical,"boards"));

    let topology=pcad_copper(document);
    m_assert(m_eq(j_string(topology,"format"),"pcad-copper-1"),"Review both board rows");
    let rows=j_get(topology,"boards");
    m_assert(cg_j_count(rows)==2 && j_integer(pc_first(rows),"count")==5,"First board has two physical footprints and a track");
    m_assert(m_eq(j_encode(topology),j_encode(pcc_trace_copper(electrical))),"Review and continuity share copper topology");

    let spacing=pcad_copper_review(document,1);
    rows=j_get(spacing,"boards");
    let first=pc_first(rows);let second=load64(first+24);
    m_assert(!j_get(first,"spacing") && j_get(second,"spacing"),"Only the requested board carries spacing");

    cg_begin();
    let projected=pcb_linked_board_source(electrical,board,0,j_array());
    m_assert(projected,cg_error);
    let rules=pcad_board_rule_report(projected,0);
    m_assert(m_eq(j_string(rules,"status"),"checks_passed"),"The original controller route is intact");
    m_assert(m_eq(j_encode(rules),j_encode(pcad_board_rules(document,0))),"Checked rules use the shared strict PCB projection");
    m_assert(m_eq(j_encode(document),original),"The review does not modify its input");

    cg_j_set(board,"tracks",j_array());
    rules=pcad_board_rules(document,0);
    m_assert(j_integer(rules,"connections_needed")==1,"A missing route remains open despite matching net names");
    j_add(board,"zones",j_parse("[{\"id\":\"supply-fill\",\"net_id\":\"supply\",\"layer\":\"F.Cu\",\"outline\":[[8,8],[27,8],[27,16],[8,16]]}]"));
    rules=pcad_board_rules(document,0);
    m_assert(m_eq(j_string(rules,"status"),"checks_passed"),"The poured zone restores physical connectivity");
    let fill=pcc_zone_view(document,0,"supply-fill");
    m_assert(m_eq(j_string(fill,"format"),"pcad-zone-fill-1") && j_integer(fill,"cells")==432
        && j_integer(fill,"islands")==1 && m_len(j_string(fill,"runs"))>0,"Zone preview reports the actual filled island");
    m_assert(m_eq(j_string(pcc_zone_view(document,1,"supply-fill"),"error"),"Copper zone is missing from this board"),
        "A zone belongs only to the requested board");
    m_print(1,"PCAD copper review shares bounded topology, strict rules and zone fill\n");
    return 0;
}
