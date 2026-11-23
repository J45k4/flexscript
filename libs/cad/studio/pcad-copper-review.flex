// Standalone PCAD board review for compiled programs and the checked VM.
import "pcad-copper.flex";

fn pcad_copper(document) {return pcad_copper_review(document,-1);}

fn pcc_zoned(electrical) {
    if j_get(j_get(electrical,"pcb"),"zones") {return 1;}
    let board=pc_first(j_get(electrical,"boards"));
    while board {
        if j_get(board,"zones") {return 1;}
        board=load64(board+24);
    }
    return 0;
}

// Review touching copper in board order, with spacing for one selected board.
fn pcad_copper_review(document,inspect) {
    cg_begin();
    let electrical=j_get(document,"electrical");
    let rules=0;
    if (inspect>=0 && j_get(electrical,"net_classes")) || pcc_zoned(electrical) {
        let resolved=pcad_resolve(document);
        if !resolved {return pc_error();}
        electrical=j_get(resolved,"electrical");
        rules=electrical;
    }
    return pcc_review_boards(electrical,inspect,rules);
}

// One selected zone per bounded viewport response. The bytes are triples
// [first column, exclusive last column, row] on the 0.5 mm lattice.
fn pcc_zone_view(document,index,id) {
    cg_begin();
    let resolved=pcad_resolve(document);
    if !resolved {return pc_error();}
    let electrical=j_get(resolved,"electrical");
    let legacy=j_get(electrical,"pcb");
    let board=legacy;
    if legacy {
        if index || j_get(electrical,"boards") {cg_fail("Invalid board selection");return pc_error();}
    }else {
        board=load64(pc_list(electrical,"boards",8)+16);
        while board && index {board=load64(board+24);index=index-1;}
    }
    let zones=j_get(board,"zones");
    if j_kind(zones)!=3 || !pnr_find(zones,id) {
        cg_fail("Copper zone is missing from this board");
        return pc_error();
    }
    let projected=pcb_linked_board_model(electrical,board,legacy,j_array(),0);
    if !projected || cg_error {return pc_error();}
    let compiled=pc_compile(projected);
    if cg_error {return pc_error();}
    let zone=pnr_find(j_get(compiled,"zones"),id);
    if !zone || cg_error {return pc_error();}
    if !pc_zone_fill(compiled) {return pc_error();}
    let runs=j_integer(zone,"runs");
    let encoded=m_take(cg_count(runs)*4+1);
    let alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let i=0;let cells=0;
    while i<cg_count(runs) && !cg_error {
        let run=cg_at(runs,i);
        let x0=load64(run+8);let x1=load64(run+16);let y=load64(run+24);
        let bits=(x0<<16)|(x1<<8)|y;
        let j=0;
        while j<4 {
            store8(encoded+i*4+j,load8(alphabet+((bits>>(18-j*6))&63)));
            j=j+1;
        }
        cells=cells+x1-x0;i=i+1;
    }
    store8(encoded+i*4,0);
    let islands=j_integer(zone,"islands");
    if cg_error {return pc_error();}
    let out=j_object();
    cg_j_text(out,"format","pcad-zone-fill-1");
    cg_j_text(out,"id",id);
    cg_j_text(out,"layer",j_string(zone,"layer"));
    cg_j_text(out,"runs",encoded);
    cg_j_int(out,"cells",cells);
    cg_j_int(out,"islands",cg_count(islands));
    let thermals=j_get(zone,"thermals");
    if thermals {j_add(out,"thermals",thermals);}
    return out;
}

fn pcad_board_rule_report(projection,index) {
    let board=pc_compile(projection);
    let report=0;
    if cg_error {report=pc_error();}
    else {
        report=pc_check(board);
        if !cg_error && !j_get(report,"zones") && pc_legacy_report_scope(board) {
            // Standalone PCAD described the full checker even on a simple board.
            cg_j_text(report,"scope","Two copper layers; through-hole and oval surface pads, through vias, straight tracks, rectangular outline and round holes. No zones, silkscreen, solder-mask, thermal, signal-integrity or electrical-driver ERC checks.");
        }
    }
    cg_j_text(report,"format","pcad-board-checks-1");
    cg_j_int(report,"board_index",index);
    return report;
}

// Apply the same strict projection and native checker used by the release.
fn pcad_board_rules(document,index) {
    cg_begin();
    let resolved=pcad_resolve(document);
    if !resolved {return pc_error();}
    let electrical=j_get(resolved,"electrical");
    let legacy=j_get(electrical,"pcb");
    let board=legacy;let offset=index;
    let boards=j_get(electrical,"boards");
    if legacy {
        if index || boards {cg_fail("Invalid board selection");return pc_error();}
    }else {
        board=load64(pc_list(electrical,"boards",8)+16);
        while board && offset>0 {board=load64(board+24);offset=offset-1;}
    }
    if !board || cg_error {cg_fail("Select an existing PCB");return pc_error();}
    let projection=pcb_linked_board_source(electrical,board,legacy,j_array());
    if !projection || cg_error {return pc_error();}
    return pcad_board_rule_report(projection,index);
}
