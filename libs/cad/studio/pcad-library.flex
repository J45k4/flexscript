// Validate pinned local component definitions and their materialized interfaces.
// Used by the shared resolver before projecting modules or computing artifacts.
import "../electrical/model.flex";
fn pl_text(value,limit,required) {
    if !value {return !required;}
    if j_kind(value)!=2 {return 0;}
    let text=j_value(value);let size=m_len(text);
    if size>limit || (required && !size) {return 0;}
    let i=0;let visible=0;
    while i<size {
        let c=load8(text+i);if c<32 {return 0;}
        if c!=32 {visible=1;}
        i=i+1;
    }
    return !required || visible;
}

fn pl_role(role) {
    return m_eq(role,"passive") || m_eq(role,"input") || m_eq(role,"output")
        || m_eq(role,"bidirectional") || m_eq(role,"power_in") || m_eq(role,"power_out");
}

fn pl_representation(def,pins,count) {
    let symbol=j_get(def,"symbol");
    if symbol {
        let kind=j_string(def,"symbol");
        if !m_eq(kind,"generic") && (count!=2 || (!m_eq(kind,"resistor") && !m_eq(kind,"capacitor") && !m_eq(kind,"voltage"))) {
            return cg_fail("Unsupported library symbol or pin count");
        }
    }
    let footprint=j_get(def,"footprint");
    if footprint {
        let kind=j_string(footprint,"kind");
        let pads=j_get(footprint,"pad_pins");
        let count=pc_pad_count(pc_package_footprint(kind));
        if cg_error || j_kind(pads)!=3 || cg_j_count(pads)!=count {return cg_fail("Invalid library footprint or pad map");}
        let pad=load64(pads+16);
        while pad {
            if j_kind(pad)!=0 && (j_kind(pad)!=2 || !ph_get(pins,j_value(pad))) {
                return cg_fail("Library pad mappings need existing pins or explicit null");
            }
            pad=load64(pad+24);
        }
    }
    let simulation=j_get(def,"simulation");
    if simulation {
        let kind=j_string(simulation,"kind");
        let value=j_get(simulation,"value");let map=j_get(simulation,"pin_ids");
        if count!=2 || (!m_eq(kind,"resistor") && !m_eq(kind,"capacitor") && !m_eq(kind,"voltage"))
            || (j_kind(value)!=1 && j_kind(value)!=6) || j_kind(map)!=3 || cg_j_count(map)!=2 {
            return cg_fail("Invalid library simulation model");
        }
        let first=load64(map+16);let second=load64(first+24);
        if j_kind(first)!=2 || j_kind(second)!=2 || !m_eq(j_string(ph_get(pins,j_value(first)),"number"),"1")
            || !m_eq(j_string(ph_get(pins,j_value(second)),"number"),"2") {
            return cg_fail("Map the library simulation model to pins 1 and 2 in order");
        }
    }
    let mechanical=j_get(def,"mechanical");
    if mechanical {
        let footprint_kind=j_string(footprint,"kind");
        let asset=j_get(mechanical,"asset");
        let nodes=j_get(asset,"nodes");let parts=j_get(asset,"parts");
        if j_kind(mechanical)!=4 || !m_len(footprint_kind)
            || !m_eq(j_string(mechanical,"footprint_kind"),footprint_kind)
            || !m_eq(j_string(asset,"units"),"mm") || j_kind(parts)!=3 || cg_j_count(parts)!=1
            || j_kind(nodes)!=3 || !cg_j_count(nodes) || cg_j_count(nodes)>24
            || j_get(asset,"assembly") || j_get(asset,"electrical") || m_len(j_encode(asset))>12000 {
            return cg_fail("A library 3D model needs a bounded CAD body and its compatible footprint");
        }
        let p=load64(nodes+16);
        while p {
            if m_eq(j_string(p,"type"),"pcb-board") {return cg_fail("A package body must be independent of PCB geometry");}
            p=load64(p+24);
        }
        if !cg_vector(j_get(mechanical,"position"),0) || !cg_vector(j_get(mechanical,"rotation"),0) || cg_error {
            return cg_fail("A PCB package needs a valid mounting frame");
        }
    }
    return 1;
}

fn pl_pinned(e,component) {
    let pin=j_get(component,"definition");if !pin {return 0;}
    let rows=j_get(e,"component_definitions");if j_kind(rows)!=3 {return 0;}
    let p=load64(rows+16);
    while p {
        if m_eq(j_string(pin,"definition_id"),j_string(p,"id")) && j_integer(pin,"revision")==j_integer(p,"revision") {return p;}
        p=load64(p+24);
    }
    return 0;
}

fn pl_catalog(source) {
    let definitions=j_get(source,"component_definitions");let catalog=j_object();
    if !definitions {return catalog;}
    if j_kind(definitions)!=3 || cg_j_count(definitions)>32 {return cg_fail("Invalid local library revision list");}
    let row=load64(definitions+16);
    while row && !cg_error {
        let id=j_string(row,"id");let revision=ph_revision(row);
        if !ph_id(id,48,1) || !revision || !pl_text(j_get(row,"name"),80,1) || !pl_text(j_get(row,"family"),80,1)
            || !pl_text(j_get(row,"description"),400,0) || !pl_text(j_get(row,"value"),120,0)
            || !pl_text(j_get(row,"manufacturer"),120,0) || !pl_text(j_get(row,"part_number"),120,0)
            || !ph_index(catalog,ph_key(id,revision),row) {return cg_fail("Invalid or duplicate local library revision");}
        let pins=j_object();let numbers=j_object();let count=0;let pin=ph_rows(row,"pins",64);
        while pin && !cg_error {
            let key=j_string(pin,"id");let number=j_string(pin,"number");
            if !ph_id(key,64,1) || !pl_text(j_get(pin,"number"),16,1)
                || !pl_role(j_string(pin,"role")) || j_kind(j_get(pin,"name"))!=2 || !pl_text(j_get(pin,"name"),80,0)
                || !ph_index(pins,key,pin) || !ph_index(numbers,number,pin) {return cg_fail("Invalid library pin");}
            count=count+1;pin=load64(pin+24);
        }
        let terminals=j_object();let terminal=ph_rows(row,"terminals",64);
        while terminal && !cg_error {
            let key=j_string(terminal,"id");
            if !ph_id(key,64,1) || !pl_text(j_get(terminal,"name"),80,1) || !ph_get(pins,j_string(terminal,"pin_id"))
                || !ph_index(terminals,key,terminal) {return cg_fail("Invalid library terminal");}
            terminal=load64(terminal+24);
        }
        if !count || cg_error || !pl_representation(row,pins,count) {return cg_fail("Invalid library definition interface");}
        row=load64(row+24);
    }
    if cg_error {return 0;}
    return catalog;
}

fn pl_mapping(rows,instances,targets,identity,origin) {
    let count=0;if j_kind(rows)==3 {count=cg_j_count(rows);}
    if j_kind(rows)!=3 || j_kind(instances)!=3 || j_kind(targets)!=3 || count>64
        || count!=cg_j_count(instances) || count!=cg_j_count(targets) {
        return cg_fail("Every library interface item needs a matching binding");
    }
    let ids=j_object();let target_ids=j_object();let entry=load64(targets+16);
    while entry {ph_index(target_ids,j_string(entry,"id"),entry);entry=load64(entry+24);}
    entry=load64(instances+16);
    while entry {ph_index(ids,j_string(entry,"id"),entry);entry=load64(entry+24);}
    let used=j_object();let out=j_object();entry=load64(rows+16);
    while entry && !cg_error {
        let key=j_string(entry,identity);let target=j_string(entry,origin);
        let bound=ph_get(target_ids,target);
        if !ph_get(ids,key) || !bound || !ph_index(out,key,bound) || !ph_index(used,target,bound) {
            return cg_fail("Library bindings need distinct existing identities");
        }
        entry=load64(entry+24);
    }
    if cg_error {return 0;}
    return out;
}

fn pl_bindings(rows,catalog) {
    if j_kind(rows)!=3 {return 1;}
    let component=load64(rows+16);
    while component && !cg_error {
        let binding=j_get(component,"definition");
        if binding {
            let revision=ph_revision(binding);let id=j_string(binding,"definition_id");
            let definition=ph_get(catalog,ph_key(id,revision));
            if !definition || j_get(component,"connector") {return cg_fail("Missing or conflicting pinned library revision");}
            let pins=pl_mapping(j_get(binding,"pins"),j_get(component,"pins"),j_get(definition,"pins"),
                "pin_id","definition_pin_id");
            let terminals=pl_mapping(j_get(binding,"terminals"),j_get(component,"terminals"),j_get(definition,"terminals"),
                "terminal_id","definition_terminal_id");
            if !pins || !terminals {return 0;}
            let pin=load64(j_get(component,"pins")+16);
            while pin {
                let target=ph_get(pins,j_string(pin,"id"));
                if !m_eq(j_string(pin,"number"),j_string(target,"number")) {
                    return cg_fail("A component pin number differs from its pinned library revision");
                }
                pin=load64(pin+24);
            }
            let terminal=load64(j_get(component,"terminals")+16);
            while terminal {
                let target=ph_get(terminals,j_string(terminal,"id"));let pin=ph_get(pins,j_string(terminal,"pin_id"));
                if !pin || !m_eq(j_string(target,"pin_id"),j_string(pin,"id"))
                    || !m_eq(j_string(target,"name"),j_string(terminal,"name")) {
                    return cg_fail("A component terminal differs from its pinned library pin");
                }
                terminal=load64(terminal+24);
            }
        }
        component=load64(component+24);
    }
    return !cg_error;
}
