// Import one rigid assembly into a new or empty standalone PCAD drawing.
// Keep each definition once. Occurrence IDs and fixed mates belong to a scope.
import "step-hierarchy.flex";
import "step-document.flex";

fn sa_use_id(source,prefix,entity,used) {
    let fallback=m_cat(prefix,m_int(entity));let id=source;
    if !cg_id(id) || m_eq(id,"world") || j_get(used,id) {id=fallback;}
    let suffix=1;while j_get(used,id) {id=m_cat(fallback,m_cat("-",m_int(suffix)));suffix=suffix+1;}
    cg_j_int(used,id,1);return id;
}
fn sa_group_id(source) {
    if m_len(source)<12 || !m_eq(m_slice(source,9),"assembly/") {return source;}
    let start=source+9;let p=start;while load8(p) && load8(p)!=47 {p=p+1;}
    let id=m_slice(start,p-start);if !cg_id(id) || load8(p)!=47 || load8(p+1)<49 || load8(p+1)>57 {return source;}
    p=p+2;while load8(p)>=48 && load8(p)<=57 {p=p+1;}if load8(p) {return source;}return id;
}
fn sa_instances(scope,parts,groups,limit) {
    let rows=j_object();let instances=j_array();let mates=j_array();let used=j_object();
    let item=pc_first(j_get(scope,"occurrences"));while item {
        let source=j_string(item,"sourceId");let raw=source;if m_len(raw)>limit {raw="";}
        let entity=j_integer(item,"id");let id=sa_use_id(raw,"step-occurrence-",entity,used);
        let instance=j_object();cg_j_text(instance,"id",id);cg_j_text(instance,"name",j_string(item,"name"));
        cg_j_int(instance,"step_entity",entity);cg_j_text(instance,"step_id",source);
        if j_get(item,"assembly") {cg_j_text(instance,"assembly",j_string(groups,m_int(j_integer(item,"assembly"))));}
        else {cg_j_text(instance,"part",j_string(parts,m_int(j_integer(item,"part"))));}
        j_add(instances,0,instance);
        let mate=j_object();cg_j_text(mate,"id",m_cat("step-mate-",m_int(entity)));cg_j_text(mate,"type","fixed");
        cg_j_text(mate,"parent","world");cg_j_text(mate,"child",id);
        let frame=j_object();j_add(frame,"position",j_parse(j_encode(j_get(item,"position"))));
        j_add(frame,"rotation",j_parse(j_encode(j_get(item,"rotation"))));j_add(mate,"parent_frame",frame);j_add(mates,0,mate);
        item=load64(item+24);
    }
    j_add(rows,"instances",instances);j_add(rows,"mates",mates);return rows;
}
fn sa_path_fits(scope,definitions,prefix) {
    let row=pc_first(j_get(scope,"instances"));while row {
        let length=prefix+m_len(j_string(row,"id"));if length>120 {return 0;}
        if j_get(row,"assembly") && !sa_path_fits(pc_find(definitions,j_string(row,"assembly")),definitions,length+1) {return 0;}
        row=load64(row+24);
    }return 1;
}
fn sa_layout(tree,doc,part_map,group_map,limit) {
    let defs=j_array();let group=pc_first(j_get(tree,"subassemblies"));while group {
        let rows=sa_instances(group,part_map,group_map,limit);
        let entity=j_integer(group,"id");cg_j_text(rows,"id",j_string(group_map,m_int(entity)));
        cg_j_text(rows,"name",j_string(group,"name"));cg_j_int(rows,"step_entity",entity);cg_j_text(rows,"step_id",j_string(group,"sourceId"));
        j_add(defs,0,rows);group=load64(group+24);
    }
    let root=sa_instances(tree,part_map,group_map,limit);if !sa_path_fits(root,defs,0) {return 0;}
    cg_j_text(root,"name",j_string(tree,"name"));j_add(doc,"assembly",root);if pc_first(defs) {cg_j_set(doc,"assembly_definitions",defs);}return root;
}
fn sa_starter() {
    return j_parse("{\"format\":\"puppycorp.pcad\",\"schema_version\":1,\"units\":\"mm\",\"segments\":24,\"nodes\":[{\"id\":\"body\",\"type\":\"box\",\"size\":[20,20,3]}],\"parts\":[{\"id\":\"part\",\"name\":\"Body\",\"node\":\"body\",\"color\":\"#82b38e\"}]}");
}
fn sa_matches(actual,expected) {
    if j_kind(actual)!=j_kind(expected) {return 0;}
    if j_kind(expected)!=3 && j_kind(expected)!=4 {return m_eq(j_encode(actual),j_encode(expected));}
    if cg_j_count(actual)!=cg_j_count(expected) {return 0;}
    let a=load64(actual+16);let e=load64(expected+16);while e {
        if j_kind(expected)==4 {a=j_get(actual,load64(e+32));}
        if !a || !sa_matches(a,e) {return 0;}a=load64(a+24);e=load64(e+24);
    }return 1;
}
fn cad_step_can_adopt(doc) {
    if !doc {return 1;}if !cad_project_is_studio(doc) || j_get(doc,"assembly") {return 0;}
    return (j_kind(j_get(doc,"nodes"))==3 && j_kind(j_get(doc,"parts"))==3 && !pc_first(j_get(doc,"nodes")) && !pc_first(j_get(doc,"parts"))) || sa_matches(doc,sa_starter());
}
fn cad_step_adopt(project,file,filename,digest) {
    cg_begin();if !cad_step_can_adopt(project) {return cg_fail("Choose a new design for importing a STEP assembly");}
    let tree=cad_step_hierarchy(file);if !tree {return 0;}
    let doc=sa_starter();if project {doc=j_parse(j_encode(project));}
    let nodes=j_array();let parts=j_array();cg_j_set(doc,"nodes",nodes);cg_j_set(doc,"parts",parts);
    nodes=j_get(doc,"nodes");parts=j_get(doc,"parts");
    if !j_get(doc,"electrical") {cg_j_text(doc,"project_scope","mechanical");}
    let part_map=j_object();let used=j_object();let def=pc_first(j_get(tree,"definitions"));while def {
        let entity=j_integer(def,"id");let id=sa_use_id(j_string(def,"sourceId"),"step-part-",entity,used);
        let shape=cad_step_shape(file,j_integer(def,"body"),filename,digest);if !shape {return 0;}
        let node_id=m_cat("step-geometry-",m_int(entity));cg_j_text(shape,"id",node_id);j_add(nodes,0,shape);
        let part=j_object();cg_j_text(part,"id",id);cg_j_text(part,"node",node_id);cg_j_text(part,"name",j_string(def,"name"));cg_j_text(part,"color","#82b38e");
        j_add(parts,0,part);cg_j_text(part_map,m_int(entity),id);def=load64(def+24);
    }
    let group_map=j_object();used=j_object();let group=pc_first(j_get(tree,"subassemblies"));while group {
        let entity=j_integer(group,"id");let id=sa_use_id(sa_group_id(j_string(group,"sourceId")),"step-assembly-",entity,used);
        cg_j_text(group_map,m_int(entity),id);group=load64(group+24);
    }
    let assembly=sa_layout(tree,doc,part_map,group_map,48);if !assembly {assembly=sa_layout(tree,doc,part_map,group_map,29);}
    if !assembly {return cg_fail("STEP occurrence path exceeds the PCAD limit");}
    let info=j_object();cg_j_text(info,"format","step-faceted-assembly-v1");cg_j_text(info,"file",filename);cg_j_text(info,"sha256",digest);
    cg_j_int(info,"entity",j_integer(tree,"id"));cg_j_text(info,"source_id",j_string(tree,"sourceId"));j_add(assembly,"import",info);
    let mesh=cad_project_mesh(doc);if j_get(mesh,"error") || !j_value(j_get(mesh,"closed")) {return cg_fail("STEP assembly import needs closed solids");}
    return doc;
}
fn cad_step_assembly(file,filename,digest) {return cad_step_adopt(0,file,filename,digest);}
