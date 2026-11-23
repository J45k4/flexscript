// Derive electrical occurrences from the frozen source before any physical evaluation.
import "../math.flex";
import "pcad-library.flex";
import "pcad-net-rules.flex";

fn ph_id(s,limit,hyphen) {
    let n=m_len(s);
    if !n || n>limit {return 0;}
    let i=0;
    while i<n {
        let c=load8(s+i);
        if !(c>=48 && c<=57) && !(c>=65 && c<=90) && !(c>=97 && c<=122) && c!=95 && !(hyphen && c==45) {return 0;}
        i=i+1;
    }
    return 1;
}

fn ph_rows(row,key,max) {
    let a=j_get(row,key);
    if j_kind(a)!=3 || cg_j_count(a)>max {cg_fail(m_cat("Invalid module list: ",key));return 0;}
    return load64(a+16);
}

fn ph_revision(row) {
    let revision=j_get(row,"revision");
    if j_kind(revision)!=1 || j_value(revision)<1 || j_value(revision)>1000000 {return 0;}
    return j_value(revision);
}

fn ph_key(id,revision) {return m_cat(id,m_cat(":",m_int(revision)));}
fn ph_get(index,key) {return j_value(j_get(index,key));}

fn ph_index(index,key,row) {
    if !m_len(key) || j_get(index,key) {return cg_fail("Duplicate or missing module identity");}
    j_add(index,key,j_number(row));return 1;
}

fn ph_validate(def) {
    let members=j_object();let refs=j_object();let end_slots=j_object();
    let c=ph_rows(def,"components",32);
    while c && !cg_error {
        let id=j_string(c,"id");let ref=j_string(c,"reference");
        if !ph_id(id,16,0) || !ph_id(ref,80,1) || !ph_index(members,id,c) || !ph_index(refs,ref,c) {return cg_fail("Invalid module component identity");}
        let pins=j_object();let numbers=j_object();let p=ph_rows(c,"pins",64);
        while p && !cg_error {
            let pin_id=j_string(p,"id");let number=j_string(p,"number");
            if !ph_id(pin_id,64,1) || !ph_index(pins,pin_id,p) || !ph_index(numbers,number,p) {return cg_fail("Invalid module pin identity");}
            if !j_value(j_get(p,"no_connect")) {ph_index(end_slots,ph_key_pin(id,pin_id),p);}
            p=load64(p+24);
        }
        let contacts=j_object();let t=ph_rows(c,"terminals",64);
        while t && !cg_error {
            if !ph_id(j_string(t,"id"),64,1) || !ph_index(contacts,j_string(t,"id"),t) || !ph_get(pins,j_string(t,"pin_id")) {
                return cg_fail("Invalid module terminal or pin reference");
            }
            t=load64(t+24);
        }
        c=load64(c+24);
    }
    let nets=j_object();let names=j_object();let assigned=j_object();
    let n=ph_rows(def,"nets",32);
    while n && !cg_error {
        let id=j_string(n,"id");let name=j_string(n,"name");
        if !ph_id(id,16,0) || !ph_id(name,80,1) || !ph_index(nets,id,n) || !ph_index(names,name,n) {return cg_fail("Invalid module net identity");}
        let end=ph_rows(n,"endpoints",2048);
        while end && !cg_error {
            let key=ph_key_pin(j_string(end,"component_id"),j_string(end,"pin_id"));
            if !ph_get(end_slots,key) || !ph_index(assigned,key,end) {return cg_fail("A module pin must exist and belong to at most one net");}
            end=load64(end+24);
        }
        n=load64(n+24);
    }
    let port=ph_rows(def,"ports",32);let port_ids=j_object();let exposed=j_object();
    while port && !cg_error {
        let id=j_string(port,"id");let net=j_string(port,"net_id");
        if !ph_id(id,16,0) || !m_len(j_string(port,"name")) || !ph_get(nets,net)
            || !ph_index(port_ids,id,port) || !ph_index(exposed,net,port) {return cg_fail("Each module port must expose a distinct local net");}
        port=load64(port+24);
    }
    return !cg_error;
}

fn ph_key_pin(component,pin) {return m_cat(component,m_cat(":",pin));}

fn ph_child(parent,key,item) {
    let out=j_new(j_kind(item),j_value(item));
    store64(out+16,load64(item+16));
    return j_add(parent,key,out);
}

fn ph_expand(state,instances,parent_nets,path,labels,ancestors,depth) {
    let defs=load64(state);let e=load64(state+8);
    let components=j_get(e,"components");let nets=j_get(e,"nets");
    let siblings=j_object();let names=j_object();let instance=instances;
    while instance && !cg_error {
        let id=j_string(instance,"id");let name=j_string(instance,"name");
        let def_id=j_string(instance,"definition_id");let revision=ph_revision(instance);
        let def=ph_get(defs,ph_key(def_id,revision));
        if !ph_id(id,16,0) || !ph_id(name,80,1) || !ph_id(def_id,16,0) || !def
            || !ph_index(siblings,id,instance) || !ph_index(names,name,instance) {
            return cg_fail("Invalid module occurrence or missing definition revision");
        }
        if j_get(ancestors,def_id) {return cg_fail("Recursive module instantiation");}
        if depth>=4 || load64(state+16)>=32 {return cg_fail("Use at most 32 module occurrences and four levels");}
        store64(state+16,load64(state+16)+1);
        let path_ids=j_parse(j_encode(path));j_add(path_ids,0,j_text(id));
        let prefix=m_cat("m_",id);
        let part=load64(path+16);
        if part {
            prefix="m_";
            while part {prefix=m_cat(prefix,m_cat(j_value(part),"-"));part=load64(part+24);}
            prefix=m_cat(prefix,id);
        }
        prefix=m_cat(prefix,"-");
        let label=m_cat(m_cat(labels,name),"_");

        let ports=j_object();let port=load64(j_get(def,"ports")+16);
        while port {ph_index(ports,j_string(port,"id"),port);port=load64(port+24);}
        let bindings=j_object();let binding=ph_rows(instance,"bindings",32);
        while binding && !cg_error {
            let port=ph_get(ports,j_string(binding,"port_id"));
            let target=ph_get(parent_nets,j_string(binding,"net_id"));
            if !port || !target || !ph_index(bindings,j_string(port,"net_id"),target) {return cg_fail("Invalid or duplicate module port binding");}
            binding=load64(binding+24);
        }

        let component=load64(j_get(def,"components")+16);
        while component && !cg_error {
            let row=j_parse(j_encode(component));let member=j_string(component,"id");
            let full=m_cat(prefix,member);let reference=m_cat(label,j_string(component,"reference"));
            if m_len(reference)>80 || !ph_id(full,64,1) || cg_j_count(components)>=96
                || !ph_index(load64(state+24),full,row) || !ph_index(load64(state+32),reference,row) {return cg_fail("Module component identity or bound exceeded");}
            cg_j_text(row,"id",full);cg_j_text(row,"reference",reference);
            let provenance=j_object();
            ph_child(provenance,"path",path_ids);cg_j_text(provenance,"definition_id",def_id);
            cg_j_int(provenance,"revision",revision);cg_j_text(provenance,"member_id",member);
            cg_j_set(row,"module_occurrence",provenance);j_add(components,0,row);
            component=load64(component+24);
        }
        let local_nets=j_object();let net=load64(j_get(def,"nets")+16);
        while net && !cg_error {
            let net_id=j_string(net,"id");let target=ph_get(bindings,net_id);
            if !target {
                target=j_parse(j_encode(net));
                let full=m_cat(prefix,net_id);let name=m_cat(label,j_string(net,"name"));
                if m_len(name)>80 || !ph_id(full,64,1) || cg_j_count(nets)>=128
                    || !ph_index(load64(state+40),full,target) || !ph_index(load64(state+48),name,target) {return cg_fail("Module net identity or bound exceeded");}
                cg_j_text(target,"id",full);cg_j_text(target,"name",name);
                cg_j_set(target,"endpoints",j_array());j_add(nets,0,target);
            }
            ph_index(local_nets,net_id,target);
            let endpoints=j_get(target,"endpoints");
            let pin=load64(j_get(net,"endpoints")+16);
            while pin && !cg_error {
                if cg_j_count(endpoints)>=6144 {return cg_fail("Module net endpoint bound exceeded");}
                let end=j_parse(j_encode(pin));
                cg_j_text(end,"component_id",m_cat(prefix,j_string(pin,"component_id")));
                j_add(endpoints,0,end);pin=load64(pin+24);
            }
            net=load64(net+24);
        }
        if j_get(def,"instances") {
            let children=ph_rows(def,"instances",32);
            let next=j_parse(j_encode(ancestors));cg_j_int(next,def_id,1);
            if !ph_expand(state,children,local_nets,path_ids,label,next,depth+1) {return 0;}
        }
        instance=load64(instance+24);
    }
    return !cg_error;
}

fn pcad_resolve(document) {
    let source=j_get(document,"electrical");let modules=j_get(source,"modules");
    let library=pl_catalog(source);let classes=pnr_classes(source);
    if !library || !pnr_validate(j_get(source,"nets"),classes) || !pl_bindings(j_get(source,"components"),library) {return 0;}
    if !modules {return document;}
    if j_kind(modules)!=4 {return cg_fail("Invalid module hierarchy");}
    let defs=j_object();
    let def=ph_rows(modules,"definitions",32);
    while def && !cg_error {
        let id=j_string(def,"id");let revision=ph_revision(def);
        if !ph_id(id,16,0) || !revision || !m_len(j_string(def,"name")) || !ph_index(defs,ph_key(id,revision),def) || !ph_validate(def)
            || !pnr_validate(j_get(def,"nets"),classes) || !pl_bindings(j_get(def,"components"),library) {
            return cg_fail("Invalid module definition revision");
        }
        def=load64(def+24);
    }
    let out=j_parse(j_encode(document));let e=j_object();
    let field=load64(j_get(out,"electrical")+16);
    while field {
        let key=load64(field+32);
        if !m_eq(key,"modules") {ph_child(e,key,field);}
        field=load64(field+24);
    }
    cg_j_set(out,"electrical",e);
    let state=m_take(56);store64(state,defs);store64(state+8,e);store64(state+16,0);
    let components=j_object();let refs=j_object();let net_ids=j_object();let net_names=j_object();
    store64(state+24,components);store64(state+32,refs);store64(state+40,net_ids);store64(state+48,net_names);
    let component=ph_rows(e,"components",96);
    while component && !cg_error {
        ph_index(components,j_string(component,"id"),component);
        ph_index(refs,j_string(component,"reference"),component);
        component=load64(component+24);
    }
    let parent_nets=j_object();let net=ph_rows(e,"nets",128);
    while net && !cg_error {
        let id=j_string(net,"id");
        ph_index(net_ids,id,net);ph_index(net_names,j_string(net,"name"),net);ph_index(parent_nets,id,net);
        let pin=ph_rows(net,"endpoints",6144);
        while pin && !cg_error {
            if !ph_get(components,j_string(pin,"component_id")) {return cg_fail("Bind module pins through their declared ports");}
            pin=load64(pin+24);
        }
        net=load64(net+24);
    }
    let roots=ph_rows(modules,"instances",32);
    if cg_error || !ph_expand(state,roots,parent_nets,j_array(),"",j_object(),0) {return 0;}
    return out;
}
