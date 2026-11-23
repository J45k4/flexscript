// Catalog reusable product definitions and local occurrence frames before
// reading their geometry. Store the source entities once even for repeated
// subassemblies, and count placed objects on every path through the tree.
import "step-placement.flex";

fn sa_source_id(raw) {
    if j_kind(raw)!=2 {return "";}let text=j_value(raw);let b=m_buffer();let i=0;while load8(text+i) {
        let c=load8(text+i);if c<32 || c==127 {m_text(b," ");}else {m_append(b,text+i,1);}i=i+1;
    }
    text=m_data(b);while load8(text)==32 {text=text+1;}let size=m_len(text);
    while size && load8(text+size-1)==32 {size=size-1;}if size>96 {size=96;while (load8(text+size)&192)==128 {size=size-1;}}
    return m_slice(text,size);
}
fn sa_named(row,id) {
    let result=j_object();cg_j_int(result,"id",id);cg_j_text(result,"sourceId",sa_source_id(sr_arg(row,0)));
    cg_j_text(result,"name",sr_name(sr_arg(row,1),id));return result;
}
fn sa_product(file,id) {
    let entry=sr_find(file,id);if !entry {return cg_fail("Missing STEP product definition");}
    let product=load64(entry+8);let formation=sr_resolve(file,sr_arg(product,2),0);
    if !sr_type(formation,"PRODUCT_DEFINITION_FORMATION") && !sr_type(formation,"PRODUCT_DEFINITION_FORMATION_WITH_SPECIFIED_SOURCE") {return cg_fail("Invalid STEP product formation");}
    let row=sr_resolve(file,sr_arg(formation,2),"PRODUCT");if !row {return 0;}return sa_named(row,id);
}
fn sa_get(state,map,id) {return j_get(j_get(state,map),m_int(id));}
fn sa_list(state,map,id) {
    let key=m_int(id);let table=j_get(state,map);let list=j_get(table,key);
    if !list {list=j_array();j_add(table,key,list);}return list;
}
fn sa_entity(file,ref) {
    let entry=sr_find(file,sa_ref(ref));if entry {return load64(entry+8);}return 0;
}
fn cad_step_has_assembly(file) {
    if !file {return 0;}let entry=load64(file+8);while entry {
        if sr_type(load64(entry+8),"NEXT_ASSEMBLY_USAGE_OCCURRENCE") {return 1;}entry=load64(entry+24);
    }return 0;
}
fn sa_index(file,state) {
    let entry=load64(file+8);let links=0;
    while entry && !cg_error {
        let row=load64(entry+8);if sr_type(row,"NEXT_ASSEMBLY_USAGE_OCCURRENCE") {
            let a=sr_arg(row,3);let b=sr_arg(row,4);
            if !sr_resolve(file,a,"PRODUCT_DEFINITION") || !sr_resolve(file,b,"PRODUCT_DEFINITION") {return 0;}
            links=links+1;if links>32 {return cg_fail("STEP assembly exceeds 32 placement relationships");}
            let uses=sa_list(state,"uses",sa_ref(a));if cg_j_count(uses)>=16 {return cg_fail("STEP assembly exceeds 16 direct occurrences");}
            j_add(uses,0,j_number(load64(entry)));cg_j_int(j_get(state,"children"),m_int(sa_ref(b)),1);
            cg_j_int(j_get(state,"products"),m_int(sa_ref(a)),1);cg_j_int(j_get(state,"products"),m_int(sa_ref(b)),1);
            cg_j_int(j_get(state,"links"),m_int(load64(entry)),1);
        }entry=load64(entry+24);
    }
    if !links {return cg_fail("STEP file has no assembly occurrences");}
    entry=load64(file+8);while entry && !cg_error {
        let row=load64(entry+8);let placement=sr_type(row,"CONTEXT_DEPENDENT_SHAPE_REPRESENTATION");
        if placement || sr_type(row,"SHAPE_DEFINITION_REPRESENTATION") {
            let shape=sa_entity(file,sr_arg(row,placement));let target=sa_ref(sr_arg(shape,2));
            if sr_type(shape,"PRODUCT_DEFINITION_SHAPE") {
                if placement && sa_get(state,"links",target) {
                    if sa_get(state,"placements",target) {return cg_fail("Ambiguous STEP occurrence placement");}
                    let rel=sr_resolve(file,sr_arg(row,0),0);if !rel {return 0;}
                    cg_j_int(j_get(state,"placements"),m_int(target),rel);
                }else if !placement && sa_get(state,"products",target) {
                    let id=sa_ref(sr_arg(row,1));let previous=sa_get(state,"reps",target);
                    if !id || (previous && j_value(previous)!=id) {return cg_fail("STEP product needs one shape representation");}
                    cg_j_int(j_get(state,"reps"),m_int(target),id);
                }
            }
        }entry=load64(entry+24);
    }
    let use=sr_arg(j_get(state,"uses"),0);let root=0;while use {
        let key=load64(use+32);
        if !j_get(j_get(state,"children"),key) {if root {return cg_fail("STEP assembly has multiple roots");}root=m_number(key);}
        use=load64(use+24);
    }
    if !root {return cg_fail("STEP assembly contains a cycle");}return root;
}
fn sa_body(file,state,id,group) {
    let rep=j_value(sa_get(state,"reps",id));let entry=sr_find(file,rep);if !entry {return cg_fail("Missing STEP product representation");}
    let row=load64(entry+8);let items=sr_arg(row,1);
    if (!sr_type(row,"SHAPE_REPRESENTATION") && !sr_type(row,"FACETED_BREP_SHAPE_REPRESENTATION")) || j_kind(items)!=3 {return cg_fail("Expected a STEP shape representation");}
    let body=0;let item=sr_arg(items,0);while item {
        let node=sr_resolve(file,item,0);if !node {return 0;}
        if !sr_type(node,"AXIS2_PLACEMENT_3D") {
            if group {return cg_fail("STEP assembly representation may contain placement frames only");}
            if body || !sr_type(node,"FACETED_BREP") {return cg_fail("STEP part needs exactly one faceted solid");}body=sa_ref(item);
        }item=load64(item+24);
    }
    if group {return 1;}if !body {return cg_fail("STEP part has no solid");}return body;
}
fn sa_walk(file,state,parent,stack,depth) {
    if depth>3 {return cg_fail("STEP assembly exceeds three nested levels");}
    let i=0;while i<depth {if load64(stack+i*8)==parent {return cg_fail("Cycle in STEP assembly");}i=i+1;}
    store64(stack+depth*8,parent);
    if depth {
        let count=j_integer(state,"placedAssemblies")+1;if count>16 {return cg_fail("STEP exceeds 16 placed subassemblies");}cg_j_int(state,"placedAssemblies",count);
    }
    let key=m_int(parent);let scope=sa_get(state,"scopes",parent);let scope_row=j_value(scope);
    if !scope {
        if !sa_body(file,state,parent,1) {return 0;}scope_row=sa_product(file,parent);if !scope_row {return 0;}
        cg_j_int(j_get(state,"scopes"),key,scope_row);if depth {j_add(j_get(state,"subassemblies"),0,scope_row);}
        let list=j_array();j_add(scope_row,"occurrences",list);let use=sr_arg(sa_get(state,"uses",parent),0);
        while use && !cg_error {
            let id=j_value(use);let raw=load64(sr_find(file,id)+8);let child=sa_ref(sr_arg(raw,4));
            let pose=sa_placement(file,j_value(sa_get(state,"placements",id)),j_value(sa_get(state,"reps",parent)),j_value(sa_get(state,"reps",child)));
            if !pose {return 0;}let item=sa_named(raw,id);
            let pos=j_get(pose,"position");let rot=j_get(pose,"rotation");
            store64(pos+24,0);store64(rot+24,0);j_add(item,"position",pos);j_add(item,"rotation",rot);
            let kind="part";if sa_get(state,"uses",child) {kind="assembly";}cg_j_int(item,kind,child);
            j_add(list,0,item);use=load64(use+24);
        }
    }
    let item=sr_arg(j_get(scope_row,"occurrences"),0);while item && !cg_error {
        let child=j_integer(item,"assembly");
        if child {if !sa_walk(file,state,child,stack,depth+1) {return 0;}}
        else {
            let count=j_integer(state,"placedParts")+1;if count>16 {return cg_fail("STEP exceeds 16 placed parts");}cg_j_int(state,"placedParts",count);
            child=j_integer(item,"part");if !sa_get(state,"parts",child) {
                let body=sa_body(file,state,child,0);if !body {return 0;}let part=sa_product(file,child);if !part {return 0;}
                cg_j_int(part,"body",body);cg_j_int(j_get(state,"parts"),m_int(child),1);j_add(j_get(state,"definitions"),0,part);
            }
        }item=load64(item+24);
    }return scope_row;
}
fn cad_step_hierarchy(file) {
    cg_begin();if !file {return cg_fail("Missing STEP file");}
    let state=j_parse("{\"uses\":{},\"products\":{},\"children\":{},\"links\":{},\"reps\":{},\"placements\":{},\"scopes\":{},\"parts\":{},\"subassemblies\":[],\"definitions\":[]}");
    let root=sa_index(file,state);if !root {return 0;}let tree=sa_walk(file,state,root,m_take(32),0);
    if !tree || cg_error {return 0;}
    if cg_j_count(j_get(state,"uses"))!=cg_j_count(j_get(state,"scopes")) {return cg_fail("Disconnected STEP assembly placements");}
    let parts=j_integer(state,"placedParts");let assemblies=j_integer(state,"placedAssemblies");
    let defs=j_get(state,"definitions");let groups=j_get(state,"subassemblies");store64(defs+24,0);store64(groups+24,0);
    j_add(tree,"definitions",defs);j_add(tree,"subassemblies",groups);
    cg_j_int(tree,"placedParts",parts);cg_j_int(tree,"placedAssemblies",assemblies);
    return tree;
}
