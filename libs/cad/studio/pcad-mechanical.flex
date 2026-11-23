// Expand the board-owned outline and mounting datums for this CAD evaluation.
// Only the evaluated document contains the derived geometry.
import "../assembly.flex";
import "pcad-routing.flex";
import "pcad-hierarchy.flex";
import "pcad-dimensions.flex";
import "pcad-packages.flex";

fn pcm_find(rows,id) {
    if j_kind(rows)!=3 {return 0;}
    let p=load64(rows+16);
    let match=0;
    while p {
        if m_eq(j_string(p,"id"),id) {
            if match {cg_fail("Duplicate PCAD reference");return 0;}
            match=p;
        }
        p=load64(p+24);
    }
    return match;
}

fn pcm_board(document,id) {
    let electrical=j_get(document,"electrical");
    let boards=j_get(electrical,"boards");
    let legacy=j_get(electrical,"pcb");
    if !m_len(id) || m_len(id)>64 || (legacy && boards) {return 0;}
    if !boards && m_eq(id,"legacy-board") {return legacy;}
    if j_kind(boards)!=3 || cg_j_count(boards)>8 {return 0;}
    return pcm_find(boards,id);
}

fn pcm_expand_board(node,board) {
    let size=j_get(board,"size");
    if j_kind(size)!=3 || cg_j_count(size)!=2 || j_get(node,"position") || j_get(node,"rotation") {
        return cg_fail("A linked PCB needs its own outline and an assembly placement");
    }
    let xy=load64(size+16);
    let width=cg_number(xy);
    let height=cg_number(load64(xy+24));
    let thickness=cg_number(j_get(board,"thickness"));
    if width<5000000 || height<5000000 || width>100000000 || height>100000000
        || thickness<400000 || thickness>3200000 {
        return cg_fail("A linked PCB needs valid board dimensions and thickness");
    }
    let board_size=j_array();
    j_add(board_size,0,cg_json_number(width));
    j_add(board_size,0,cg_json_number(height));
    j_add(board_size,0,cg_json_number(thickness));
    let mounts=j_get(board,"holes");
    if j_kind(mounts)!=3 || cg_j_count(mounts)>4 {return cg_fail("A linked PCB supports at most four mounting holes");}
    let cutouts=j_array();
    let seen=j_object();
    let mount=load64(mounts+16);
    while mount && !cg_error {
        let id=j_string(mount,"id");
        if !m_len(id) || m_len(id)>64 || j_get(seen,id) {return cg_fail("PCB mounting holes need unique IDs");}
        j_add(seen,id,j_number(1));
        let at=j_get(mount,"at");
        if j_kind(at)!=3 || cg_j_count(at)!=2 {return cg_fail("PCB mounting holes need an XY location");}
        let xy=load64(at+16);
        let center=j_array();
        j_add(center,0,cg_json_number(cg_number(xy)));
        j_add(center,0,cg_json_number(cg_number(load64(xy+24))));
        j_add(center,0,j_number(0));
        let diameter=cg_number(j_get(mount,"diameter"));
        if diameter<1000000 || diameter>5000000 {return cg_fail("PCB mounting hole diameter must be 1–5 mm");}
        let hole=j_object();
        j_add(hole,"position",center);
        j_add(hole,"radius",cg_json_number(diameter/2));
        j_add(cutouts,0,hole);
        mount=load64(mount+24);
    }
    cg_j_text(node,"type","drilled-board");
    cg_j_set(node,"size",board_size);
    let outline=j_get(board,"outline");if outline {cg_j_set(node,"outline",outline);}
    cg_j_set(node,"holes",cutouts);
    return !cg_error;
}

fn pcm_add_datum(datums,id,position) {
    if pcm_find(datums,id) || cg_error {return cg_fail("A linked PCB datum conflicts with a part datum");}
    let item=j_object();
    cg_j_text(item,"id",id);
    j_add(item,"position",position);
    j_add(datums,0,item);
    return 1;
}

fn pcm_add_board_datums(part,board) {
    let datums=j_get(part,"datums");
    if !datums {datums=j_array();j_add(part,"datums",datums);}
    if j_kind(datums)!=3 || cg_j_count(datums)>16 {return cg_fail("Use at most 16 authored datums on a linked PCB part");}
    if !pcm_add_datum(datums,"pcb-origin",j_parse("[0,0,0]")) {return 0;}
    let holes=j_get(board,"holes");
    let hole=load64(holes+16);
    while hole && !cg_error {
        let position=j_parse(j_encode(j_get(hole,"at")));
        j_add(position,0,j_number(0));
        pcm_add_datum(datums,m_cat("mount:",j_string(hole,"id")),position);
        hole=load64(hole+24);
    }
    return !cg_error;
}

fn pcm_prepare(document,report) {
    cg_begin();
    if j_get(document,"assembly_definitions") && !j_get(document,"assembly") {
        return cg_fail("Reusable assembly definitions require a root assembly");
    }
    let linked_boards=j_object();
    let nodes=j_get(document,"nodes");
    let parts=j_get(document,"parts");
    if j_kind(nodes)!=3 || cg_j_count(nodes)>48 || j_kind(parts)!=3 || cg_j_count(parts)>16 {
        cg_fail("Invalid PCAD mechanical definitions");
        return 0;
    }
    if !pcd_prepare(document,report) {return 0;}
    let node=load64(nodes+16);
    while node && !cg_error {
        if m_eq(j_string(node,"type"),"pcb-board") {
            let board_id=j_string(node,"board_id");
            let board=pcm_board(document,board_id);
            if !board {cg_fail(m_cat("Linked board is missing: ",board_id));return 0;}
            if !pcm_expand_board(node,board) {return 0;}
            cg_j_text(linked_boards,j_string(node,"id"),board_id);
            let part=load64(parts+16);
            while part && !cg_error {
                if m_eq(j_string(part,"node"),j_string(node,"id")) {
                    pcm_add_board_datums(part,board);
                }
                part=load64(part+24);
            }
        }
        node=load64(node+24);
    }
    if cg_error {return 0;}
    return linked_boards;
}

fn pcad_mechanical(document) {return pcm_evaluate(document,0);}
fn pcm_evaluate(document,bodies_only) {
    cg_begin();
    document=pcad_resolve(document);
    if !document {return ca_error();}
    let report=j_array();
    let linked_boards=pcm_prepare(document,report);
    if cg_error {return ca_error();}
    let sketch_report=0;
    if j_get(document,"sketches") {sketch_report=j_array();}

    let parameter_report=0;
    if j_get(document,"parameters") {parameter_report=j_array();}
    let prototypes=pmb_compile_dimensions(document,linked_boards,sketch_report,parameter_report);
    if cg_error {return ca_error();}
    let mesh=0;
    if !j_get(document,"assembly") {
        if bodies_only {return prototypes;}
        mesh=cg_tessellate(prototypes);
        if !cg_error {pcr_routes(document,linked_boards,0,0,mesh);}
    }else {
        let assembly=ca_compile_prototypes(document,prototypes);
        let solids=ca_evaluate(assembly,0);
        if bodies_only {return solids;}
        mesh=ca_mesh(assembly,solids,0);
        if !cg_error {pcr_routes(document,linked_boards,assembly,solids,mesh);}
    }
    if !cg_error && cg_j_count(report) {j_add(mesh,"bound_dimensions",report);}
    if !cg_error && cg_j_count(sketch_report) {j_add(mesh,"sketches",sketch_report);}
    if !cg_error && cg_j_count(parameter_report) {j_add(mesh,"parameters",parameter_report);}
    return mesh;
}

// A face picker uses the original prototype and checked polygon normals. It
// can inspect the attachment source of an unresolved assembly or sketch.
fn pcad_feature_mesh(document,id) {
    cg_begin();
    if !cg_id(id) {cg_fail("Select a feature to pick");return ca_error();}
    document=pcad_resolve(document);
    if !document {return ca_error();}
    pcm_prepare(document,0);
    if cg_error {return ca_error();}
    return cg_tessellate_faces(cg_compile_selection(document,0,0,id),1);
}
