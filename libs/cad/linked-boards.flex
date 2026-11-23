// Project a standalone PCAD's authored boards into bounded PCB checker inputs.
// Artifact paths and electrical check results belong to the caller.
import "studio/pcad-mechanical.flex";
import "project-nodes.flex";

fn cad_pcad_board_count(document) {
    let electrical=j_get(document,"electrical");
    let legacy=j_get(electrical,"pcb");
    let boards=j_get(electrical,"boards");
    if legacy {return !boards && j_kind(legacy)==4;}
    if j_kind(boards)!=3 {return 0;}
    let count=cg_j_count(boards);
    if count>8 {return 0;}
    return count;
}

fn pcb_linked_unique_ids(rows,limit) {
    if j_kind(rows)!=3 || cg_j_count(rows)>limit {return 0;}
    let seen=j_object();let row=pc_first(rows);
    while row {
        let id=j_string(row,"id");
        if !m_len(id) || m_len(id)>64 || j_get(seen,id) {return 0;}
        cg_j_int(seen,id,1);row=load64(row+24);
    }
    return 1;
}

fn pcb_linked_net_use(net,used) {
    let name=j_string(net,"name");
    if !net || !cg_id(name) {return cg_fail("PCB exports need stable net references and simple net names");}
    cg_j_text(used,j_string(net,"id"),name);
    return name;
}

fn pcb_linked_copper(electrical,board,used,key,fields,limit) {
    let rows=j_array();let item=pc_first(pc_list(board,key,limit));
    while item && !cg_error {
        let net=pnr_find(j_get(electrical,"nets"),j_string(item,"net_id"));
        let name=pcb_linked_net_use(net,used);if !name {return 0;}
        let row=j_object();cg_j_text(row,"net",name);
        let field=pc_first(fields);
        while field {pcc_copy(item,j_value(field),row);field=load64(field+24);}
        j_add(rows,0,row);item=load64(item+24);
    }
    return rows;
}

fn pcb_linked_placement(electrical,item,legacy,used,placements,strict) {
    let component=pnr_find(j_get(electrical,"components"),j_string(item,"component_id"));
    let ref=j_string(component,"reference");
    if !component || !cg_id(ref) || m_len(ref)>16 {
        return cg_fail("PCB placements need a known component ID and a reference up to 16 bytes");
    }
    let footprint=pc_package_footprint(j_string(item,"footprint"));
    let side=pc_side(item);
    if cg_error {return 0;}
    let row=j_object();let placement=j_object();
    cg_j_text(row,"ref",ref);cg_j_text(row,"value",j_string(component,"value"));
    cg_j_text(placement,"component_id",j_string(component,"id"));cg_j_text(placement,"ref",ref);
    let fields=j_parse("[\"footprint\",\"at\",\"rotation\",\"reference_offset\"]");
    let field=pc_first(fields);
    while field {
        pcc_copy(item,j_value(field),row);pcc_copy(item,j_value(field),placement);field=load64(field+24);
    }
    let side_name="front";
    if side<0 {side_name="back";}
    pcc_copy(item,"side",row);
    cg_j_text(placement,"side",side_name);
    if !j_integer(footprint,"drill") {
        let layer="F.Cu";if side<0 {layer="B.Cu";}
        cg_j_text(placement,"pad_type","surface_mount");cg_j_text(placement,"copper_layer",layer);
    }
    let pins=j_object();let identities=j_array();let count=pc_pad_count(footprint);let index=0;
    if j_get(item,"contact_pads") {
        if !pce_contact_pads(component,item,count,legacy) {return 0;}
        pcc_copy(item,"contact_pads",placement);
    }
    while index<count {
        let pin=pce_pad_pin(component,item,index,count,legacy);
        if cg_error {return 0;}
        let net=0;
        if pin {
            net=pnr_assigned_net(electrical,component,pin);
            if cg_error {return 0;}
            let no_connect=j_get(pin,"no_connect");
            let nc=j_kind(no_connect)==5 && j_value(no_connect);
            if strict && ((!net && !nc) || (net && nc)) {
                return cg_fail("PCB pins need one assigned net or an explicit no-connect");
            }
        }
        let number=index+1;let identity=j_object();cg_j_int(identity,"pad",number);
        if pin {
            cg_j_text(identity,"pin_id",j_string(pin,"id"));
            cg_j_text(identity,"pin_number",j_string(pin,"number"));
        }else {
            j_add(identity,"pin_id",j_new(0,0));j_add(identity,"pin_number",j_new(0,0));
        }
        if net {
            let name=pcb_linked_net_use(net,used);if !name {return 0;}
            cg_j_text(pins,m_int(number),name);cg_j_text(identity,"net_id",j_string(net,"id"));
        }else {
            j_add(pins,m_int(number),j_new(0,0));j_add(identity,"net_id",j_new(0,0));
        }
        j_add(identities,0,identity);index=index+1;
    }
    j_add(row,"pins",pins);j_add(placement,"pad_pins",identities);
    j_add(placements,0,placement);return row;
}

fn pcb_linked_board_source(electrical,board,legacy,placements) {
    return pcb_linked_board_model(electrical,board,legacy,placements,1);
}

fn pcb_linked_board_model(electrical,board,legacy,placements,strict) {
    return pcb_linked_board_model_rules(electrical,board,legacy,placements,strict,0);
}

// Collect release identities from the same net and class records used by the checker.
fn pcb_linked_routing_rule(source,net,class,board) {
    let row=j_parse(j_encode(source));
    cg_j_text(row,"net_id",j_string(net,"id"));
    cg_j_text(row,"class_id",j_string(class,"id"));
    cg_j_text(row,"class_name",j_string(class,"name"));
    let margin=pc_field(board,"clearance",250,100,2000);let clearance=pc_clearance_rule(class);
    if clearance>margin {margin=clearance;}
    j_add(row,"effective_clearance",cg_json_number(margin*1000));
    return row;
}

fn pcb_linked_board_model_rules(electrical,board,legacy,placements,strict,routing_rules) {
    let output=j_object();cg_j_text(output,"units","mm");
    let used=j_object();let substrate=j_object();let holes=j_array();let parts=j_array();
    pcc_copy(board,"size",substrate);pcc_copy(board,"thickness",substrate);
    pcc_copy(board,"clearance",substrate);pcc_copy(board,"outline",substrate);
    let hole=pc_first(pc_list(board,"holes",4));
    while hole && !cg_error {
        let row=j_object();pcc_copy(hole,"at",row);pcc_copy(hole,"diameter",row);
        j_add(holes,0,row);hole=load64(hole+24);
    }
    j_add(substrate,"holes",holes);j_add(output,"board",substrate);
    let item=pc_first(pc_list(board,"placements",6));
    if !item {return cg_fail("Place at least one mapped component on each exported PCB");}
    while item && !cg_error {
        let row=pcb_linked_placement(electrical,item,legacy,used,placements,strict);if !row {return 0;}
        j_add(parts,0,row);item=load64(item+24);
    }
    j_add(output,"components",parts);
    j_add(output,"tracks",pcb_linked_copper(electrical,board,used,"tracks",j_parse("[\"layer\",\"start\",\"end\",\"width\"]"),32));
    j_add(output,"vias",pcb_linked_copper(electrical,board,used,"vias",j_parse("[\"at\",\"diameter\",\"drill\"]"),4));
    if j_get(board,"zones") {
        j_add(output,"zones",pcb_linked_copper(electrical,board,used,"zones",j_parse("[\"id\",\"layer\",\"outline\",\"priority\",\"thermal\"]"),8));
    }
    if cg_error {return 0;}
    let nets=j_array();let rules=j_array();let classes=pnr_classes(electrical);
    let net=pc_first(j_get(electrical,"nets"));
    while net && !cg_error {
        let name=j_get(used,j_string(net,"id"));
        if name {
            j_add(nets,0,j_text(j_value(name)));
            let rule=pnr_rule(classes,net);
            if rule {
                let row=j_object();cg_j_text(row,"net",j_value(name));
                pcc_copy(rule,"minimum_width",row);pcc_copy(rule,"clearance",row);
                if routing_rules {j_add(routing_rules,0,pcb_linked_routing_rule(row,net,rule,substrate));}
                j_add(rules,0,row);
            }
        }
        net=load64(net+24);
    }
    if cg_error {return 0;}
    j_add(output,"nets",nets);
    if pc_first(rules) {j_add(output,"net_rules",rules);}
    return output;
}

// Fitted packages are derived occurrences. Resolve the fixed mate back to the
// matching authored board in its own scope before accepting their part IDs.
fn pcb_linked_fitted_package(document,assembly,occurrence) {
    let id=j_string(occurrence,"id");let part=j_string(occurrence,"part");
    let mate=pcm_find(j_get(assembly,"mates"),id);let path=j_string(mate,"parent");
    if !m_eq(j_string(mate,"type"),"fixed") || !m_eq(j_string(mate,"child"),id)
        || j_value(j_get(mate,"suppressed")) || !cah_path_id(path) {return 0;}
    let scope=j_get(document,"assembly");let local=path;let cursor=path;
    while load8(cursor) {
        if load8(cursor)==47 {
            let container=pcm_find(j_get(scope,"instances"),m_slice(local,cursor-local));
            scope=pcm_find(j_get(document,"assembly_definitions"),j_string(container,"assembly"));
            if !scope {return 0;}
            local=cursor+1;
        }
        cursor=cursor+1;
    }
    let authored=j_get(scope,"instances");let source=pcm_find(authored,local);
    let parent=pcm_find(j_get(assembly,"instances"),path);
    let board_part=j_string(source,"part");
    if !m_len(board_part) || !m_eq(j_string(parent,"part"),board_part) {return 0;}
    let prototype=pcm_find(j_get(document,"parts"),board_part);
    let node=pcm_find(j_get(document,"nodes"),j_string(prototype,"node"));
    if !m_eq(j_string(node,"type"),"pcb-board") {return 0;}
    let board=pcm_board(document,j_string(node,"board_id"));let electrical=j_get(document,"electrical");
    let placement=pc_first(pc_list(board,"placements",6));
    while placement && !cg_error {
        let component=pcm_find(j_get(electrical,"components"),j_string(placement,"component_id"));
        let definition=pl_pinned(electrical,component);
        if j_get(definition,"mechanical") {
            let generated=pmb_key("pkg-",local,j_string(component,"id"));
            let wanted=pmb_key("pkg-part-",j_string(definition,"id"),m_int(j_integer(definition,"revision")));
            if m_eq(id,m_cat(m_slice(path,local-path),generated)) && m_eq(part,wanted)
                && !pcm_find(authored,generated) && !cg_error {
                return pmb_compatible(component,placement,definition);
            }
        }
        placement=load64(placement+24);
    }
    return 0;
}

fn pcb_linked_occurrences(document,mesh,by_board) {
    let assembly=j_get(mesh,"assembly");let instances=j_get(assembly,"instances");
    if j_kind(instances)!=3 {return cg_fail("Linked PCB positions need a solved assembly");}
    let parts=j_get(document,"parts");let nodes=j_get(document,"nodes");
    let occurrence=pc_first(instances);
    while occurrence {
        if j_get(occurrence,"part") {
            let part=pcm_find(parts,j_string(occurrence,"part"));
            if cg_error {return 0;}
            if !part {
                if !pcb_linked_fitted_package(document,assembly,occurrence) {
                    return cg_fail("A solved assembly occurrence has no part definition");
                }
            }else {
                let node=pcm_find(nodes,j_string(part,"node"));
                if cg_error {return 0;}
                if m_eq(j_string(node,"type"),"pcb-board") {
                    let rows=j_get(by_board,j_string(node,"board_id"));
                    if !rows || j_kind(j_get(occurrence,"transform"))!=3 {
                        return cg_fail("A solved PCB occurrence needs its linked board and transform");
                    }
                    let row=j_object();pcc_copy(occurrence,"id",row);pcc_copy(occurrence,"part",row);
                    cg_j_text(row,"node",j_string(node,"id"));pcc_copy(occurrence,"transform",row);
                    pcc_copy(occurrence,"local_transform",row);pcc_copy(occurrence,"fixed",row);
                    j_add(rows,0,row);
                }
            }
        }
        occurrence=load64(occurrence+24);
    }
    return 1;
}

fn pcb_linked_register_components(placements,occupied) {
    let seen=j_object();let placement=pc_first(placements);
    while placement {
        let id=j_string(placement,"component_id");
        if j_get(seen,id) || j_get(occupied,id) {
            return cg_fail("A logical component is placed on multiple footprints or boards");
        }
        cg_j_int(seen,id,1);placement=load64(placement+24);
    }
    let row=load64(seen+16);
    while row {cg_j_int(occupied,load64(row+32),1);row=load64(row+24);}
    return 1;
}

// Board rows preserve authored order and contain a PCB source or a scoped error.
// Pass the mesh evaluated from this same document to reuse its occurrence poses.
fn cad_pcad_linked_boards(document,mesh) {
    cg_begin();
    if !m_eq(j_string(document,"format"),"puppycorp.pcad") || j_integer(document,"schema_version")!=1
        || !m_eq(j_string(document,"units"),"mm") || j_kind(j_get(document,"assembly"))!=4 {
        return cg_fail("Select a PCAD schema 1 assembly in millimetres");
    }
    if !cad_pcad_board_count(document) {return cg_fail("Select a PCAD assembly with 1–8 boards");}
    document=pcad_resolve(document);
    if !document {return 0;}
    let electrical=j_get(document,"electrical");let legacy=j_get(electrical,"pcb");
    let boards=j_get(electrical,"boards");
    if (!legacy && !pcb_linked_unique_ids(boards,8)) || !pcb_linked_unique_ids(j_get(electrical,"components"),96)
        || !pcb_linked_unique_ids(j_get(electrical,"nets"),128) {
        return cg_fail("Boards, components and nets need stable unique IDs");
    }
    if !mesh {mesh=pcad_mechanical(j_parse(j_encode(document)));}
    if j_get(mesh,"error") {return cg_fail(j_string(mesh,"error"));}
    let occurrences=j_object();let board=pc_first(boards);
    if legacy {j_add(occurrences,"legacy-board",j_array());}
    while board {
        j_add(occurrences,j_string(board,"id"),j_array());board=load64(board+24);
    }
    if !pcb_linked_occurrences(document,mesh,occurrences) {return 0;}

    let result=j_object();let manifest=j_object();let assembly_rows=j_array();let projected=j_array();
    j_add(result,"manifest",manifest);j_add(result,"boards",projected);
    cg_j_text(manifest,"format","biscuit-pcad-pcb-assembly-1");cg_j_text(manifest,"units","mm");
    cg_j_text(manifest,"placement_frame","Board local lower-left origin, Y up, positive rotation counterclockwise. Back reflects footprint X at pad 1 before rotation. KiCad export reflects board Y and embeds pad offsets.");
    cg_j_text(manifest,"occurrence_frame","Row-major 3 by 4 rigid transform from board-local coordinates to assembly coordinates in millimetres.");
    j_add(manifest,"boards",assembly_rows);
    let occupied=j_object();board=legacy;
    if !legacy {board=pc_first(boards);}
    while board {
        cg_begin();let id="legacy-board";
        if !legacy {id=j_string(board,"id");}
        let row=j_object();let entry=j_object();let placements=j_array();let routing_rules=j_array();
        cg_j_text(row,"board_id",id);cg_j_text(entry,"board_id",id);cg_j_text(entry,"name",j_string(board,"name"));
        j_add(entry,"placements",placements);
        j_add(entry,"occurrences",j_parse(j_encode(j_get(occurrences,id))));
        let source=pcb_linked_board_model_rules(electrical,board,legacy,placements,1,routing_rules);
        if source && pcb_linked_register_components(placements,occupied) {
            j_add(row,"source",source);
            if j_get(board,"outline") {j_add(entry,"substrate",j_parse(j_encode(j_get(source,"board"))));}
            pcc_copy(board,"zones",entry);
            if pc_first(routing_rules) {j_add(entry,"routing_rules",routing_rules);}
        }else {
            cg_j_text(row,"error",cg_error);
        }
        j_add(projected,0,row);j_add(assembly_rows,0,entry);
        board=load64(board+24);
    }
    cg_error=0;
    return result;
}
