// Shared class validation and native PCB shape-to-net mapping.
import "../electrical/model.flex";

fn pcc_copy(source,key,out) {
    let value=j_get(source,key);
    if value {j_add(out,key,j_parse(j_encode(value)));}
    return 0;
}

fn pnr_classes(electrical) {
    let index=j_object();let names=j_object();
    let row=load64(pc_list(electrical,"net_classes",16)+16);
    while row && !cg_error {
        let id=j_string(row,"id");let name=j_string(row,"name");
        if !pc_fields(row,"[\"id\",\"name\",\"minimum_width\",\"clearance\"]")
            || !cg_id(id) || j_get(index,id) || j_kind(j_get(row,"name"))!=2 || !m_len(name) || !pc_text(name)
            || j_get(names,name) {
            return cg_fail("PCB net classes need distinct IDs and names up to 64 bytes");
        }
        pc_width_rule(row);pc_clearance_rule(row);
        cg_j_int(index,id,row);cg_j_int(names,name,1);row=load64(row+24);
    }
    return index;
}
fn pnr_validate(nets,classes) {
    if !nets {return !cg_error;}
    if j_kind(nets)!=3 || cg_j_count(nets)>128 {return cg_fail("Invalid PCB net list");}
    let row=load64(nets+16);
    while row && !cg_error {
        let value=j_get(row,"class_id");
        if value && (j_kind(value)!=2 || !j_get(classes,j_value(value))) {
            return cg_fail("A net references a missing PCB class");
        }
        row=load64(row+24);
    }
    return !cg_error;
}
fn pnr_rule(classes,net) {return j_integer(classes,j_string(net,"class_id"));}
fn pnr_find(rows,id) {
    let row=load64(rows+16);let found=0;
    while row {
        if m_eq(j_string(row,"id"),id) {
            if found {return cg_fail("PCB mapping refers to duplicate IDs");}
            found=row;
        }
        row=load64(row+24);
    }
    return found;
}
fn pnr_assigned_net(electrical,component,pin) {
    if !pin {return cg_fail("The PCB pad needs an existing pin mapping");}
    let selected=0;
    let net=load64(j_get(electrical,"nets")+16);
    while net && !cg_error {
        let ends=j_get(net,"endpoints");
        if j_kind(ends)!=3 || cg_j_count(ends)>6144 {return cg_fail("Invalid board net membership");}
        let end=load64(ends+16);
        while end && !cg_error {
            if m_eq(j_string(end,"component_id"),j_string(component,"id")) && m_eq(j_string(end,"pin_id"),j_string(pin,"id")) {
                if selected {cg_fail("A PCB pin belongs to multiple intended nets");}
                selected=net;
            }
            end=load64(end+24);
        }
        net=load64(net+24);
    }
    return selected;
}

fn pce_pad_pin(component,placement,index,count,legacy) {
    let pins=j_get(component,"pins");let mapping=j_get(placement,"pad_pins");
    if j_kind(pins)!=3 || cg_j_count(pins)>64 {return cg_fail("Invalid component pins");}
    if !mapping && legacy && count==2 {
        let pin=load64(pins+16);let selected=0;
        while pin {
            if m_eq(j_string(pin,"number"),m_int(index+1)) {
                if selected {return cg_fail("Legacy numbered pins are ambiguous");}
                selected=pin;
            }
            pin=load64(pin+24);
        }
        if !selected {return cg_fail("Legacy pad requires its numbered pin");}
        return selected;
    }
    if j_kind(mapping)!=3 || cg_j_count(mapping)!=count {return cg_fail("Map every physical footprint pad");}
    let entry=load64(mapping+16);
    while index {entry=load64(entry+24);index=index-1;}
    if j_kind(entry)==0 {return 0;}
    if j_kind(entry)!=2 {return cg_fail("A pad mapping needs a pin ID or explicit null");}
    let pin=pnr_find(pins,j_value(entry));
    if !pin {return cg_fail("Pad mapping references a missing pin");}
    return pin;
}


// Resolve one physical pad per contact. Sharing a pin does not connect its pads.
fn pce_contact_pads(component,placement,count,legacy) {
    let pads=m_take(count*8);let first=j_object();let i=0;
    while i<count && !cg_error {
        let pin=pce_pad_pin(component,placement,i,count,legacy);
        let id=j_string(pin,"id");store64(pads+i*8,id);
        if pin && !j_get(first,id) {cg_j_int(first,id,i+1);}
        i=i+1;
    }
    let terminals=pc_list(component,"terminals",64);
    let mapping=j_object();let row=load64(terminals+16);
    while row && !cg_error {
        let pad=j_integer(first,j_string(row,"pin_id"));
        if pad {cg_j_int(mapping,j_string(row,"id"),pad);}
        row=load64(row+24);
    }
    let overrides=load64(pc_list(placement,"contact_pads",64)+16);
    let seen=j_object();
    while overrides && !cg_error {
        if !pc_fields(overrides,"[\"terminal_id\",\"pad\"]") {return 0;}
        let id=j_string(overrides,"terminal_id");let pad=j_integer(overrides,"pad");
        let contact=pnr_find(terminals,id);
        if !m_len(id) || !contact || j_get(seen,id) || j_kind(j_get(overrides,"pad"))!=1
            || pad<1 || pad>count {
            return cg_fail("Each contact override needs an existing contact, a unique mapping and a numbered pad");
        }
        let pin=load64(pads+(pad-1)*8);
        if !m_len(pin) || !m_eq(pin,j_string(contact,"pin_id")) {
            return cg_fail("The selected contact pad must map to that contact's logical pin");
        }
        cg_j_int(seen,id,1);cg_j_set(mapping,id,j_number(pad));
        overrides=load64(overrides+24);
    }
    return mapping;
}

fn pnr_routes(shape,rows,nets,classes) {
    let row=load64(rows+16);
    while row && !cg_error {
        let net=pnr_find(nets,j_string(row,"net_id"));
        if !net {cg_fail("Copper references a missing net");return shape;}
        pc_set_rule(shape,pnr_rule(classes,net));
        shape=load64(shape+24);row=load64(row+24);
    }
    return shape;
}
fn pnr_board(electrical,source,board,legacy) {
    let classes=pnr_classes(electrical);let nets=j_get(electrical,"nets");
    if cg_error || !cg_j_count(classes) {return !cg_error;}
    let components=j_get(electrical,"components");
    let shape=load64(j_get(board,"copper")+16);
    let placement=load64(j_get(source,"placements")+16);
    while placement && !cg_error {
        let component=pnr_find(components,j_string(placement,"component_id"));
        if !component {return cg_fail("PCB placement references a missing component");}
        let count=pc_pad_count(pc_package_footprint(j_string(placement,"footprint")));let i=0;
        while i<count && !cg_error {
            let pin=pce_pad_pin(component,placement,i,count,legacy);
            let net=0;if pin {net=pnr_assigned_net(electrical,component,pin);}
            pc_set_rule(shape,pnr_rule(classes,net));shape=load64(shape+24);i=i+1;
        }
        placement=load64(placement+24);
    }
    shape=pnr_routes(shape,j_get(source,"tracks"),nets,classes);
    pnr_routes(shape,j_get(source,"vias"),nets,classes);
    return !cg_error;
}
