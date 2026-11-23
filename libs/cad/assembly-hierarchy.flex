// Expand authored assembly scopes without changing the source. Scope paths
// belong to physical occurrences and mate IDs, never to part definitions.
import "assembly-coordinates.flex";

fn cah_path(scope,id) {
    if !m_len(scope) {return id;}
    return m_cat(scope,m_cat("/",id));
}

fn cah_parent(path) {
    let i=m_len(path)-1;
    while i>=0 && load8(path+i)!=47 {i=i-1;}
    if i<0 {return "";}
    return m_slice(path,i);
}

fn cah_contains(target,path) {
    let length=m_len(target);
    return m_eq(target,path) || (length && m_len(path)>length && load8(path+length)==47 && m_eq(m_slice(path,length),target));
}

fn cah_path_id(id) {
    let length=m_len(id);let start=0;let i=0;let segments=0;
    if !length || length>120 {return 0;}
    while i<=length {
        if i==length || load8(id+i)==47 {
            segments=segments+1;
            if segments>4 || !cg_id(m_slice(id+start,i-start)) {return 0;}
            start=i+1;
        }
        i=i+1;
    }
    return 1;
}

fn cah_validate_config(definition,pose) {
    let mates=j_get(definition,"mates");
    if j_kind(mates)!=3 || cg_j_count(mates)>16 {return cg_fail("A configuration needs a bounded local mate list");}
    let value=load64(pose+16);
    while value && !cg_error {
        let id=load64(value+32);let mate=load64(mates+16);
        while mate && !m_eq(j_string(mate,"id"),id) {
            if !cg_step() {return 0;}
            mate=load64(mate+24);
        }
        if !mate {return cg_fail("Configuration references a missing local mate");}
        if m_eq(j_string(mate,"type"),"fixed") || j_get(mate,"drive") {
            return cg_fail("A configuration may set only independently moving mates");
        }
        let limits=j_get(mate,"limits");let axes=cam_axes(j_string(mate,"type"));
        if axes {
            if !cam_coordinates(axes,limits,value) {return 0;}
        }else {
            if j_kind(limits)!=3 || cg_j_count(limits)!=2 {return cg_fail("A configured mate needs ordered travel limits");}
            let pair=load64(limits+16);
            let low=cg_number(pair);let high=cg_number(load64(pair+24));let at=cg_number(value);
            if cg_error {return 0;}
            if at<low || at>high {return cg_fail("Configuration value is outside its mate travel limits");}
        }
        value=load64(value+24);
    }
    return !cg_error;
}

fn cah_configs(definition) {
    let configs=j_object();
    let rows=j_get(definition,"configurations");
    if !rows {return configs;}
    if j_kind(rows)!=3 || cg_j_count(rows)>8 {return cg_fail("Use up to eight subassembly configurations");}
    let p=load64(rows+16);
    while p && !cg_error {
        let key=j_string(p,"id");let pose=j_get(p,"pose");
        if !cg_id(key) || j_get(configs,key) || j_kind(pose)!=4 || cg_j_count(pose)>16 {
            return cg_fail("Subassembly configurations need unique IDs and a bounded mate pose");
        }
        if !cah_validate_config(definition,pose) {return 0;}
        cg_j_int(configs,key,pose);p=load64(p+24);
    }
    return configs;
}

fn cah_instances(layout,scope,definition,locked,depth) {
    let targets=j_get(layout,"assembly_definitions");let instances=j_get(definition,"instances");let p=load64(instances+16);
    let ids=j_object();
    while p && !cg_error {
        cg_step();
        let id=j_string(p,"id");let path=cah_path(scope,id);
        let part=j_string(p,"part");let sub=j_string(p,"assembly");
        if !cah_path_id(path) || !cg_id(id) || m_eq(id,"world") || j_get(ids,id)
            || (m_len(part)>0)==(m_len(sub)>0) {
            return cg_fail("Assembly occurrences need unique local IDs and one part or assembly definition");
        }
        cg_j_int(ids,id,1);
        let copy=j_parse(j_encode(p));cg_j_text(copy,"id",path);
        cg_json_push(j_get(layout,"instances"),copy);
        if m_len(sub) {
            let child=j_integer(targets,sub);
            let flexible=j_get(p,"flexible");let config=j_get(p,"configuration");
            if !child || (flexible && j_kind(flexible)!=5) || (config && (j_kind(config)!=2 || !cg_id(j_value(config)))) {
                return cg_fail("Subassemblies need an existing definition, optional configuration ID and boolean flexibility");
            }
            let active=j_get(layout,"active");
            if j_integer(active,sub) || depth>=3 {return cg_fail("Subassembly cycle or depth limit exceeded");}
            if j_integer(layout,"containers")>=16 {return cg_fail("Expanded assembly exceeds 16 subassembly occurrences");}
            cg_j_int(layout,"containers",j_integer(layout,"containers")+1);
            let options=j_integer(j_get(layout,"configurations"),sub);
            let pose=j_integer(options,j_string(p,"configuration"));
            if config && !pose {return cg_fail("Subassembly configuration is missing");}
            cg_j_int(active,sub,1);
            cah_scope(layout,path,child,pose,locked || !j_value(flexible),depth+1);
            cg_j_int(active,sub,0);
        }else {
            if j_get(p,"flexible") || j_get(p,"configuration") {return cg_fail("Only subassemblies have configurations and flexibility");}
            if j_integer(layout,"leaves")>=16 {return cg_fail("Expanded assembly exceeds 16 placed parts");}
            cg_j_int(layout,"leaves",j_integer(layout,"leaves")+1);
        }
        p=load64(p+24);
    }
    return !cg_error;
}

fn cah_mates(layout,scope,rows,pose,locked) {
    let used=j_object();let p=load64(rows+16);
    while p && !cg_error {
        cg_step();
        let id=j_string(p,"id");let parent=j_string(p,"parent");let child=j_string(p,"child");
        if !cg_id(id) || !cah_path_id(cah_path(scope,id)) || j_get(used,id) || !cg_id(child) || !cah_path_id(parent) {
            return cg_fail("A scoped mate needs a unique local ID, local child and valid parent occurrence path");
        }
        cg_j_int(used,id,1);
        let key=cah_path(scope,id);let copy=j_parse(j_encode(p));
        let full_parent=cah_path(scope,parent);
        if m_eq(parent,"world") && m_len(scope) {full_parent=scope;}
        cg_j_text(copy,"id",key);cg_j_text(copy,"parent",full_parent);cg_j_text(copy,"child",cah_path(scope,child));
        let drive=j_get(copy,"drive");
        if drive {
            let driver=j_string(drive,"mate");
            if !cg_id(driver) {return cg_fail("A subassembly drive must reference a local mate");}
            cg_j_text(drive,"mate",cah_path(scope,driver));
        }
        let value=j_get(pose,id);
        if value {cg_j_set(copy,"value",j_parse(j_encode(value)));}
        if locked {cg_j_int(j_get(layout,"locked"),key,1);}
        cg_json_push(j_get(layout,"mates"),copy);
        p=load64(p+24);
    }
    return !cg_error;
}

fn cah_patterns(layout,scope,rows) {
    if !rows {return 1;}
    if j_kind(rows)!=3 || cg_j_count(rows)>15 {return cg_fail("Use up to 15 patterns per assembly scope");}
    let p=load64(rows+16);
    while p && !cg_error {
        let id=j_string(p,"id");let seed=j_string(p,"seed");let members=j_get(p,"members");
        if !cg_id(id) || !cg_id(seed) || j_kind(members)!=3 || cg_j_count(members)>15 {
            return cg_fail("A scoped pattern needs local IDs for its seed and members");
        }
        let copy=j_parse(j_encode(p));let full=j_array();let member=load64(members+16);
        while member && !cg_error {
            let id="";if j_kind(member)==2 {id=j_value(member);}
            if !cg_id(id) {return cg_fail("A scoped pattern member needs a local occurrence ID");}
            j_add(full,0,j_text(cah_path(scope,id)));member=load64(member+24);
        }
        cg_j_text(copy,"id",cah_path(scope,id));cg_j_text(copy,"seed",cah_path(scope,seed));
        cg_j_set(copy,"members",full);cg_json_push(j_get(layout,"patterns"),copy);
        p=load64(p+24);
    }
    return !cg_error;
}

fn cah_scope(layout,scope,definition,pose,locked,depth) {
    let instances=j_get(definition,"instances");let mates=j_get(definition,"mates");
    if j_kind(instances)!=3 || j_kind(mates)!=3 || cg_j_count(instances)<1 || cg_j_count(instances)>16
        || cg_j_count(mates)!=cg_j_count(instances) {
        return cg_fail("Assembly scopes need 1-16 occurrences with one incoming mate per occurrence");
    }
    if !cah_instances(layout,scope,definition,locked,depth) || !cah_mates(layout,scope,mates,pose,locked) {return 0;}
    return cah_patterns(layout,scope,j_get(definition,"patterns"));
}

fn cah_expand(source) {
    let rows=j_get(source,"assembly_definitions");
    if !rows {return 0;}
    if j_kind(rows)!=3 || cg_j_count(rows)>16 || j_kind(j_get(source,"assembly"))!=4 {
        return cg_fail("Use up to 16 reusable definitions with an authored root assembly");
    }
    let layout=j_object();let defs=j_object();let configs=j_object();
    j_add(layout,"assembly_definitions",defs);j_add(layout,"configurations",configs);
    j_add(layout,"active",j_object());j_add(layout,"locked",j_object());
    j_add(layout,"instances",cg_json_array());j_add(layout,"mates",cg_json_array());j_add(layout,"patterns",cg_json_array());
    let p=load64(rows+16);
    while p && !cg_error {
        let id=j_string(p,"id");let datums=j_get(p,"datums");
        if !cg_id(id) || j_get(defs,id) || m_len(j_string(p,"name"))>96
            || (datums && (j_kind(datums)!=3 || cg_j_count(datums)>16)) {
            return cg_fail("Subassembly definitions need unique IDs and up to 16 named datums");
        }
        let options=cah_configs(p);
        if cg_error {return 0;}
        cg_j_int(defs,id,p);cg_j_int(configs,id,options);p=load64(p+24);
    }
    if !cah_scope(layout,"",j_get(source,"assembly"),0,0,0) {return 0;}
    return layout;
}
