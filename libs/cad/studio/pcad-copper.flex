// Shared physical copper topology and spacing. Net labels do not join copper.
import "../electrical/check.flex";
import "../linked-boards.flex";

fn pcc_board(source) {return pcc_board_review(source,0);}
fn pcc_board_review(source,spacing) {return pcc_board_classed(source,spacing,0,0);}
fn pcc_board_classed(source,spacing,electrical,legacy) {
    let zones=pc_list(source,"zones",8);
    if cg_error {return pc_error();}
    if cg_j_count(zones) {
        let source_board=pcb_linked_board_model(electrical,source,legacy,j_array(),0);
        if !source_board || cg_error {return pc_error();}
        return pcc_compiled(pc_compile(source_board),spacing);
    }
    if j_kind(source)!=4 {cg_fail("Invalid PCAD board");return pc_error();}
    let out=j_parse("{\"units\":\"mm\",\"nets\":[\"copper\"]}");
    let outline=j_object();
    pcc_copy(source,"size",outline);
    pcc_copy(source,"outline",outline);
    pcc_copy(source,"thickness",outline);
    pcc_copy(source,"clearance",outline);
    let holes=pc_list(source,"holes",4);
    let mounts=cg_json_array();
    let hole=load64(holes+16);
    while hole && !cg_error {
        let mount=j_object();
        pcc_copy(hole,"at",mount);
        pcc_copy(hole,"diameter",mount);
        cg_json_push(mounts,mount);
        hole=load64(hole+24);
    }
    j_add(outline,"holes",mounts);
    j_add(out,"board",outline);

    let components=cg_json_array();
    let placements=pc_list(source,"placements",6);
    let placement=load64(placements+16);
    let i=0;
    while placement && !cg_error {
        let part=j_object();cg_j_text(part,"value","");
        let pins=j_object();j_add(part,"pins",pins);
        let count=pc_pad_count(pc_footprint(j_string(placement,"footprint")));let pad=1;
        while pad<=count {cg_j_text(pins,m_int(pad),"copper");pad=pad+1;}
        cg_j_text(part,"ref",m_cat("P",m_int(i)));
        pcc_copy(placement,"footprint",part);
        pcc_copy(placement,"at",part);
        pcc_copy(placement,"rotation",part);
        pcc_copy(placement,"side",part);
        cg_json_push(components,part);
        i=i+1;
        placement=load64(placement+24);
    }
    j_add(out,"components",components);

    let tracks=cg_json_array();
    let track=load64(pc_list(source,"tracks",32)+16);
    while track && !cg_error {
        let item=j_parse("{\"net\":\"copper\"}");
        pcc_copy(track,"layer",item);
        pcc_copy(track,"start",item);
        pcc_copy(track,"end",item);
        pcc_copy(track,"width",item);
        cg_json_push(tracks,item);
        track=load64(track+24);
    }
    j_add(out,"tracks",tracks);

    let vias=cg_json_array();
    let via=load64(pc_list(source,"vias",4)+16);
    while via && !cg_error {
        let item=j_parse("{\"net\":\"copper\"}");
        pcc_copy(via,"at",item);
        pcc_copy(via,"diameter",item);
        pcc_copy(via,"drill",item);
        cg_json_push(vias,item);
        via=load64(via+24);
    }
    j_add(out,"vias",vias);
    if cg_error {return pc_error();}
    if !i {
        if cg_j_count(tracks) || cg_j_count(vias) {cg_fail("Place a footprint before tracing board copper");return pc_error();}
        if j_get(source,"outline") {
            let size=pc_xy(j_get(source,"size"));
            let ring=cb_outline(j_get(source,"outline"),load64(size)*1000,load64(size+8)*1000);
            let hole=load64(mounts+16);let index=0;
            while hole && !cg_error {
                let at=pc_xy(j_get(hole,"at"));
                let radius=pc_um(j_get(hole,"diameter"))*500;
                if !cg_error && !cb_ring_clear(ring,cg_v(load64(at)*1000,load64(at+8)*1000,0),radius) {
                    cg_fail(m_cat("A drill exceeds this board's outline: mount-",m_int(index)));
                }
                hole=load64(hole+24);index=index+1;
            }
            if cg_error {return pc_error();}
        }
        return j_parse("{\"count\":0,\"links\":[]}");
    }
    let board=pc_compile(out);
    if spacing && electrical && !cg_error {pnr_board(electrical,source,board,legacy);}
    return pcc_compiled(board,spacing);
}

fn pcc_compiled(board,spacing) {
    let result=pc_copper_links(board);
    if spacing && !cg_error {j_add(result,"spacing",pc_copper_spacing(board));}
    if cg_error {return pc_error();}
    return result;
}

fn pcc_review_boards(electrical,inspect,rules) {
    let boards=pc_list(electrical,"boards",8);
    if cg_error {return pc_error();}
    let legacy=j_get(electrical,"pcb");
    if legacy && j_get(electrical,"boards") {
        cg_fail("Use one PCAD board representation");return pc_error();
    }
    let out=j_object();let results=cg_json_array();
    cg_j_text(out,"format","pcad-copper-1");j_add(out,"boards",results);
    if legacy {
        cg_json_push(results,pcc_board_classed(legacy,inspect==0,rules,1));
        return out;
    }
    let board=load64(boards+16);
    let index=0;
    while board {
        cg_begin();
        cg_json_push(results,pcc_board_classed(board,inspect==index,rules,0));
        board=load64(board+24);
        index=index+1;
    }
    return out;
}

fn pcc_trace_board(source,electrical,legacy) {
    return pcc_board_classed(source,0,electrical,legacy);
}

fn pcc_trace_copper(electrical) {
    cg_begin();
    return pcc_review_boards(electrical,-1,electrical);
}
