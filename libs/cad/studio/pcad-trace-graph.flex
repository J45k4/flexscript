// Physical graph from the same copper kernel used by the board checker.
// Graph keys identify logical terminals, authored conductors or board shapes.
import "pcad-copper.flex";
import "pcad-mechanical.flex";

fn pgt_id(id) {
    let length=m_len(id);
    if !length || length>64 {return 0;}
    let i=0;
    while i<length {
        let c=load8(id+i);
        if !((c>=48 && c<=57) || (c>=65 && c<=90) || (c>=97 && c<=122) || c==45 || c==95) {return 0;}
        i=i+1;
    }
    return 1;
}

fn pgt_rows(row,key,limit) {
    let values=pc_list(row,key,limit);
    return load64(values+16);
}

fn pgt_pair(a,b) {
    if !pgt_id(a) || !pgt_id(b) {return cg_fail("A terminal or pin reference has an invalid ID");}
    return m_cat(a,m_cat(":",b));
}
fn pgt_contact(component,terminal) {
    let pair=pgt_pair(component,terminal);
    if !pair {return 0;}
    return m_cat("t:",pair);
}
fn pgt_end(end) {
    let kind=j_string(end,"kind");
    if m_eq(kind,"terminal") {return pgt_contact(j_string(end,"component_id"),j_string(end,"terminal_id"));}
    let splice=j_string(end,"splice_id");
    if m_eq(kind,"splice") && pgt_id(splice) {return m_cat("s:",splice);}
    return cg_fail("A wire endpoint needs a terminal or splice");
}

// Graph: node map, node array, pin intent, net records, unchecked boards.
fn pgt_new() {
    let out=m_take(40);
    store64(out,j_object());store64(out+8,cg_array());store64(out+16,j_object());
    store64(out+24,j_object());store64(out+32,j_array());
    return out;
}
// Node: index, stable key, label, net ID, outgoing edges, no-connect flag.
fn pgt_node(g,key,label,net,no_connect) {
    let lookup=load64(g);
    if !key || j_get(lookup,key) || cg_count(load64(g+8))>=8192 {
        return cg_fail("Duplicate or oversized physical graph");
    }
    let row=m_take(48);
    store64(row,cg_count(load64(g+8)));store64(row+8,key);store64(row+16,label);
    store64(row+24,net);store64(row+32,0);store64(row+40,no_connect);
    if !cg_push(load64(g+8),row) {return 0;}
    j_add(lookup,key,j_new(8,row));return row;
}
fn pgt_find(g,key) {return j_value(j_get(load64(g),key));}
fn pgt_link_one(from,to,kind,id,label) {
    let row=m_take(48);
    store64(row,from);store64(row+8,to);store64(row+16,kind);
    store64(row+24,id);store64(row+32,label);
    store64(row+40,load64(from+32));store64(from+32,row);return 1;
}
fn pgt_link(from,to,kind,id,label) {
    if !from || !to || from==to || !cg_step() {return cg_fail("A physical edge refers to a missing or repeated endpoint");}
    pgt_link_one(from,to,kind,id,label);return pgt_link_one(to,from,kind,id,label);
}

fn pgt_label(row,key,fallback) {
    let label=j_string(row,key);
    if !m_len(label) {return fallback;}
    return label;
}
fn pgt_definition(definition) {
    let direction=j_string(definition,"viewing_direction");
    let id=j_string(definition,"id");
    let pins=j_get(definition,"pins");let contacts=j_get(definition,"contacts");
    if !pgt_id(id) || j_integer(definition,"revision")!=1 || !m_len(j_string(definition,"name"))
        || (!m_eq(direction,"mating-face") && !m_eq(direction,"wire-side"))
        || j_kind(pins)!=3 || !cg_j_count(pins) || cg_j_count(pins)>64
        || j_kind(contacts)!=3 || !cg_j_count(contacts) || cg_j_count(contacts)>64 {
        return cg_fail("A local connector definition needs its identity, pins, contacts and viewing direction");
    }
    let pin_ids=j_object();let numbers=j_object();let p=load64(pins+16);
    while p {
        let key=j_string(p,"id");let number=j_string(p,"number");
        if !pgt_id(key) || !m_len(number) || m_len(number)>32 || j_get(pin_ids,key) || j_get(numbers,number) {
            return cg_fail("Connector definition pin IDs and numbers must be unique");
        }
        cg_j_int(pin_ids,key,1);cg_j_int(numbers,number,1);p=load64(p+24);
    }
    let contact_ids=j_object();let labels=j_object();p=load64(contacts+16);
    while p {
        let key=j_string(p,"id");let label=j_string(p,"name");
        if !pgt_id(key) || !m_len(label) || m_len(label)>64 || !j_get(pin_ids,j_string(p,"pin_id"))
            || j_get(contact_ids,key) || j_get(labels,label) {
            return cg_fail("Connector definition contacts need unique identities and existing logical pins");
        }
        cg_j_int(contact_ids,key,1);cg_j_int(labels,label,1);p=load64(p+24);
    }
    return 1;
}

fn pgt_connector_binding(component,binding,definition) {
    let pins=j_get(component,"pins");let terminals=j_get(component,"terminals");
    let pin_maps=j_get(binding,"pins");let contact_maps=j_get(binding,"contacts");
    let definition_pins=j_get(definition,"pins");let definition_contacts=j_get(definition,"contacts");
    if !definition || j_integer(binding,"revision")!=j_integer(definition,"revision")
        || j_kind(pins)!=3 || j_kind(terminals)!=3 || j_kind(pin_maps)!=3 || j_kind(contact_maps)!=3
        || cg_j_count(pin_maps)!=cg_j_count(pins) || cg_j_count(pin_maps)!=cg_j_count(definition_pins)
        || cg_j_count(contact_maps)!=cg_j_count(terminals) || cg_j_count(contact_maps)!=cg_j_count(definition_contacts) {
        return cg_fail("Each connector pin and contact needs an exact local revision binding");
    }
    let logical=j_object();let claimed=j_object();let p=load64(pin_maps+16);
    while p && !cg_error {
        let id=j_string(p,"pin_id");let target=j_string(p,"definition_pin_id");
        let old=pcm_find(pins,id);let next=pcm_find(definition_pins,target);
        if !pgt_id(id) || !old || !next || j_get(logical,id) || j_get(claimed,target)
            || !m_eq(j_string(old,"number"),j_string(next,"number")) {
            return cg_fail("A pin number disagrees with its reviewed connector definition");
        }
        cg_j_text(logical,id,target);cg_j_int(claimed,target,1);p=load64(p+24);
    }
    let used=j_object();claimed=j_object();p=load64(contact_maps+16);
    while p && !cg_error {
        let id=j_string(p,"terminal_id");let target=j_string(p,"definition_contact_id");
        let contact=pcm_find(terminals,id);let next=pcm_find(definition_contacts,target);
        if !pgt_id(id) || !contact || !next || j_get(used,id) || j_get(claimed,target)
            || !m_eq(j_string(next,"pin_id"),j_string(logical,j_string(contact,"pin_id")))
            || !m_eq(j_string(contact,"name"),j_string(next,"name")) {
            return cg_fail("A contact disagrees with its reviewed connector definition or logical pin");
        }
        cg_j_int(used,id,1);cg_j_int(claimed,target,1);p=load64(p+24);
    }
    return !cg_error;
}
fn pgt_connector_definitions(e) {
    let by_id=j_object();
    let p=pgt_rows(e,"connector_definitions",32);
    while p && !cg_error {
        let id=j_string(p,"id");
        if !pgt_definition(p) || j_get(by_id,id) {return cg_fail("Connector definitions need unique revision identities");}
        j_add(by_id,id,j_new(8,p));p=load64(p+24);
    }
    p=pgt_rows(e,"components",96);
    while p && !cg_error {
        let binding=j_get(p,"connector");
        if binding {
            let definition=j_value(j_get(by_id,j_string(binding,"definition_id")));
            if !pgt_connector_binding(p,binding,definition) {return 0;}
        }
        p=load64(p+24);
    }
    return !cg_error;
}
fn pgt_no_connect(pin) {
    let marker=j_get(pin,"no_connect");
    return j_kind(marker)==5 && j_value(marker);
}
fn pgt_intent(g,e) {
    let nets=load64(g+24);let intent=load64(g+16);
    let net=pgt_rows(e,"nets",128);
    while net && !cg_error {
        let id=j_string(net,"id");
        if !pgt_id(id) || j_get(nets,id) {return cg_fail("Intended nets need unique stable IDs");}
        cg_j_text(nets,id,pgt_label(net,"name",id));
        let end=pgt_rows(net,"endpoints",6144);
        while end && !cg_error {
            let component=j_string(end,"component_id");let pin=j_string(end,"pin_id");
            let key=pgt_pair(component,pin);
            let row=pcm_find(j_get(e,"components"),component);
            let exists=pcm_find(j_get(row,"pins"),pin);
            if !exists || pgt_no_connect(exists) || j_get(intent,key) {
                return cg_fail("Intended nets refer to missing, no-connect or multiply assigned pins");
            }
            cg_j_text(intent,key,id);end=load64(end+24);
        }
        net=load64(net+24);
    }
    return !cg_error;
}
fn pgt_contacts(g,e) {
    let components=j_object();
    let row=pgt_rows(e,"components",96);
    while row && !cg_error {
        let id=j_string(row,"id");
        if !pgt_id(id) || j_get(components,id) {return cg_fail("Components need unique stable IDs");}
        cg_j_int(components,id,1);
        let pins=j_get(row,"pins");
        if j_kind(pins)!=3 || cg_j_count(pins)>64 {return cg_fail("Invalid component pins");}
        let terminal=pgt_rows(row,"terminals",64);
        while terminal && !cg_error {
            let t=j_string(terminal,"id");let pin=j_string(terminal,"pin_id");
            let key=pgt_contact(id,t);let assignment=pgt_pair(id,pin);
            let definition=pcm_find(pins,pin);
            if !definition || cg_error {return cg_fail("A terminal refers to a missing pin");}
            let label=m_cat(pgt_label(row,"reference",id),m_cat(" · ",pgt_label(terminal,"name",t)));
            pgt_node(g,key,label,j_string(load64(g+16),assignment),pgt_no_connect(definition));
            terminal=load64(terminal+24);
        }
        row=load64(row+24);
    }
    return !cg_error;
}
fn pgt_harness(g,harness) {
    let splice=pgt_rows(harness,"splices",128);
    while splice && !cg_error {
        let id=j_string(splice,"id");
        if !pgt_id(id) {return cg_fail("A splice needs a stable ID");}
        pgt_node(g,m_cat("s:",id),m_cat("Splice · ",pgt_label(splice,"name",id)),"",0);
        splice=load64(splice+24);
    }
    let wire=pgt_rows(harness,"wires",256);
    while wire && !cg_error {
        let id=j_string(wire,"id");let net=j_string(wire,"net_id");
        let ends=j_get(wire,"ends");
        if !pgt_id(id) || (m_len(net) && !j_get(load64(g+24),net))
            || j_kind(ends)!=3 || cg_j_count(ends)!=2 {return cg_fail("A wire needs a stable ID, valid net and two endpoints");}
        let a=load64(ends+16);
        let left=pgt_find(g,pgt_end(a));let right=pgt_find(g,pgt_end(load64(a+24)));
        if !left || !right || left==right {return cg_fail("Wire endpoints are missing or identical");}
        let label=pgt_label(wire,"name",id);
        let node=pgt_node(g,m_cat("w:",id),label,net,0);
        pgt_link(left,node,"Wire",id,label);
        pgt_link(node,right,"Termination",id,label);
        wire=load64(wire+24);
    }
    let active=j_object();let seen=j_object();
    let map=pgt_rows(harness,"matings",32);
    while map && !cg_error {
        let id=j_string(map,"id");let a=j_string(map,"a_component_id");let b=j_string(map,"b_component_id");
        let state=j_get(map,"connected");
        if !pgt_id(id) || j_get(seen,id) || !pgt_id(a) || !pgt_id(b) || m_eq(a,b) || j_kind(state)!=5 {
            return cg_fail("Invalid connector mating or connected state");
        }
        cg_j_int(seen,id,1);
        let contacts=j_object();
        let pair=pgt_rows(map,"pairs",64);
        while pair && !cg_error {
            let left=pgt_contact(a,j_string(pair,"a_terminal_id"));
            let right=pgt_contact(b,j_string(pair,"b_terminal_id"));
            let from=pgt_find(g,left);let to=pgt_find(g,right);
            if !from || !to || j_get(contacts,left) || j_get(contacts,right) {return cg_fail("Invalid or ambiguous mating contact map");}
            cg_j_int(contacts,left,1);cg_j_int(contacts,right,1);
            if j_value(state) {
                if j_get(active,left) || j_get(active,right) {return cg_fail("A contact has multiple connected mates");}
                cg_j_int(active,left,1);cg_j_int(active,right,1);
                pgt_link(from,to,"Mating map",id,pgt_label(map,"name",id));
            }
            pair=load64(pair+24);
        }
        map=load64(map+24);
    }
    return !cg_error;
}
fn pgt_millimetres(value) {
    // Coordinates have already been validated by the copper kernel.
    let text=j_encode(value);let n=m_len(text);let i=0;let dot=0;
    while i<n {if load8(text+i)==46 {dot=1;}i=i+1;}
    if !dot {return text;}
    while n && load8(text+n-1)==48 {n=n-1;}
    if n && load8(text+n-1)==46 {n=n-1;}
    return m_slice(text,n);
}
fn pgt_xy(value) {
    let x=load64(value+16);
    return m_cat("(",m_cat(pgt_millimetres(x),m_cat(", ",m_cat(pgt_millimetres(load64(x+24)),")"))));
}
fn pgt_pads(g,e,board,prefix,legacy,shapes,title,board_id,placed) {
    let placement=pgt_rows(board,"placements",6);
    while placement && !cg_error {
        let id=j_string(placement,"component_id");
        let component=pcm_find(j_get(e,"components"),id);
        if !component || j_get(placed,id) {return cg_fail("A footprint needs a unique source component");}
        cg_j_int(placed,id,1);
        let count=pc_pad_count(pc_footprint(j_string(placement,"footprint")));
        let contacts=pce_contact_pads(component,placement,count,legacy);let index=0;
        while index<count && !cg_error {
            let pin=pce_pad_pin(component,placement,index,count,legacy);
            if cg_error {return 0;}
            let pin_id="";let net="";let no_connect=1;
            if pin {
                pin_id=j_string(pin,"id");
                let assignment=pgt_pair(id,pin_id);if !assignment {return 0;}
                net=j_string(load64(g+16),assignment);no_connect=pgt_no_connect(pin);
            }
            let number=m_int(index+1);
            let key=m_cat(prefix,m_cat("p:",m_cat(id,m_cat(":",number))));
            let label=m_cat(pgt_label(component,"reference",id),m_cat(" pad ",number));
            let node=pgt_node(g,key,label,net,no_connect);
            cg_push(shapes,node);
            if pin {
                let terminal=pgt_rows(component,"terminals",64);
                while terminal && !cg_error {
                    let terminal_id=j_string(terminal,"id");
                    if j_integer(contacts,terminal_id)==index+1 {
                        pgt_link(pgt_find(g,pgt_contact(id,terminal_id)),node,"Pin to pad",board_id,title);
                    }
                    terminal=load64(terminal+24);
                }
            }
            index=index+1;
        }
        placement=load64(placement+24);
    }
    return !cg_error;
}
fn pgt_copper_shapes(g,board,prefix,kind,shapes) {
    let limit=32;let key="tracks";if m_eq(kind,"v:") {key="vias";limit=4;}
    let row=pgt_rows(board,key,limit);
    while row && !cg_error {
        let id=j_string(row,"id");let net=j_string(row,"net_id");
        if !pgt_id(id) || !j_get(load64(g+24),net) {return cg_fail("Copper needs stable shape and net IDs");}
        let label="";
        if m_eq(kind,"v:") {label=m_cat("Via ",pgt_xy(j_get(row,"at")));}
        else {label=m_cat("Track ",m_cat(j_string(row,"layer"),m_cat(" ",m_cat(pgt_xy(j_get(row,"start")),m_cat(" to ",pgt_xy(j_get(row,"end")))))));}
        cg_push(shapes,pgt_node(g,m_cat(prefix,m_cat(kind,id)),label,net,0));
        row=load64(row+24);
    }
    return !cg_error;
}
fn pgt_zones(g,board,geometry,shapes,prefix,board_id,title) {
    if cg_j_count(j_get(board,"zones"))!=cg_j_count(j_get(geometry,"zones")) {
        return cg_fail("Copper zone count does not match the authored board");
    }
    let zone=pgt_rows(geometry,"zones",8);let nodes=cg_array();
    while zone && !cg_error {
        let id=j_string(zone,"id");let record=pnr_find(j_get(board,"zones"),id);
        let net=j_string(record,"net_id");let layer=j_string(record,"layer");
        if !pgt_id(id) || !j_get(load64(g+24),net) || !m_eq(layer,j_string(zone,"layer")) {
            return cg_fail("Copper zone does not match its authored identity");
        }
        let thermals=pgt_rows(zone,"thermals",24);let thermal_mask=0;
        while thermals && !cg_error {
            let index=j_integer(thermals,"pad_index");
            if index<0 || index>=24 || index>=cg_count(shapes) {return cg_fail("Invalid thermal pad index");}
            thermal_mask=thermal_mask|(1<<index);thermals=load64(thermals+24);
        }
        let island=pgt_rows(zone,"islands",24);let i=1;
        while island && !cg_error {
            let key=m_cat(prefix,m_cat("z:",m_cat(id,m_cat(":",m_int(i)))));
            let name=m_cat("Zone ",m_cat(id,m_cat(" ",m_cat(layer,m_cat(" island ",m_int(i))))));
            let node=pgt_node(g,key,name,net,0);cg_push(nodes,node);
            let index=pgt_rows(island,"contacts",48);
            while index && !cg_error {
                let edge="Zone copper";let pad=j_value(index);
                if thermal_mask&(1<<pad) {edge="Thermal pad contact";}
                pgt_link(cg_at(shapes,pad),node,edge,board_id,title);
                index=load64(index+24);
            }
            i=i+1;island=load64(island+24);
        }
        zone=load64(zone+24);
    }
    let pair=pgt_rows(geometry,"zone_links",47);
    while pair && !cg_error {
        let a=load64(pair+16);let b=load64(a+24);
        let first=cg_at(nodes,j_value(a));let second=cg_at(nodes,j_value(b));
        pgt_link(first,second,"Zone contact",board_id,title);pair=load64(pair+24);
    }
    return !cg_error;
}
fn pgt_board(g,e,board,geometry,legacy,id,title,placed) {
    let shapes=cg_array();let prefix=m_cat("b:",m_cat(id,":"));
    if !pgt_pads(g,e,board,prefix,legacy,shapes,title,id,placed)
        || !pgt_copper_shapes(g,board,prefix,"t:",shapes)
        || !pgt_copper_shapes(g,board,prefix,"v:",shapes) {return 0;}
    if cg_count(shapes)!=j_integer(geometry,"count") {return cg_fail("Copper geometry does not match the authored board");}
    let pair=pgt_rows(geometry,"links",47);
    while pair && !cg_error {
        let a=load64(pair+16);
        let from=cg_at(shapes,j_value(a));let to=cg_at(shapes,j_value(load64(a+24)));
        pgt_link(from,to,"Copper",id,title);pair=load64(pair+24);
    }
    return pgt_zones(g,board,geometry,shapes,prefix,id,title);
}
fn pgt_build(document) {
    cg_begin();
    document=pcad_resolve(document);
    if !document {return 0;}
    let e=j_get(document,"electrical");
    let copper=pcc_trace_copper(e);
    if m_len(j_string(copper,"error")) {return 0;}
    cg_begin();
    let g=pgt_new();
    if j_kind(e)!=4 || !pgt_connector_definitions(e) || !pgt_intent(g,e) || !pgt_contacts(g,e) || !pgt_harness(g,j_get(e,"harness")) {
        return cg_fail("Invalid PCAD electrical graph");
    }
    let legacy=j_get(e,"pcb");
    let board=legacy;if !board {board=pgt_rows(e,"boards",8);}
    let result=pgt_rows(copper,"boards",8);
    let placements=j_object();let board_ids=j_object();
    while result && board && !cg_error {
        let id=j_string(board,"id");if legacy {id="legacy-board";}
        if !pgt_id(id) || j_get(board_ids,id) {return cg_fail("Boards need unique stable IDs");}
        cg_j_int(board_ids,id,1);
        let title=pgt_label(board,"name",id);
        let error=j_string(result,"error");
        if m_len(error) {
            let row=j_object();cg_j_text(row,"board_id",id);cg_j_text(row,"board",title);cg_j_text(row,"error",error);
            j_add(load64(g+32),0,row);
        }else {pgt_board(g,e,board,result,legacy,id,title,placements);}
        result=load64(result+24);board=load64(board+24);
    }
    if cg_error {return 0;}
    return g;
}
