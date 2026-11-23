// Preserve the standalone board projection entry points with the shared model.
import "../linked-boards.flex";

fn pce_pin_net(electrical,component,pin) {
    let selected=pnr_assigned_net(electrical,component,pin);
    let no_connect=j_get(pin,"no_connect");
    let nc=j_kind(no_connect)==5 && j_value(no_connect);
    if (!selected && !nc) || (selected && nc) {
        cg_fail("PCB pins need either one assigned net or an explicit no-connect");
    }
    return selected;
}

fn pce_net_use(net,used) {
    return pcb_linked_net_use(net,used);
}

fn pce_tracks(electrical,board,used,key,fields) {
    let limit=32;
    if m_eq(key,"vias") {limit=4;}
    else if m_eq(key,"zones") {limit=8;}
    return pcb_linked_copper(electrical,board,used,key,fields,limit);
}

fn pce_board(electrical,board,legacy,placement_refs) {
    return pce_board_model(electrical,board,legacy,placement_refs,1);
}

fn pce_board_model(electrical,board,legacy,placement_refs,strict) {
    cg_begin();
    if j_kind(j_get(electrical,"nets"))!=3 || cg_j_count(j_get(electrical,"nets"))>128
        || j_kind(j_get(electrical,"components"))!=3 || cg_j_count(j_get(electrical,"components"))>96 {
        return cg_fail("PCB export exceeded the electrical model limits");
    }
    return pcb_linked_board_model(electrical,board,legacy,placement_refs,strict);
}
