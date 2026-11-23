// Deterministic AP214 assembly exchange from the checked native CAD model.
import "project.flex";
fn cst_ref(id) {return m_cat("#",m_int(id));}

fn cst_emit(writer,entity) {
    let id=load64(writer+8)+1;store64(writer+8,id);
    let out=load64(writer);
    m_text(out,cst_ref(id));m_text(out,"=");m_text(out,entity);m_text(out,";\n");
    return id;
}

fn cst_unicode(out,code) {
    let digits=4;
    if code>65535 {digits=8;m_text(out,"\\X4\\");}
    else {m_text(out,"\\X2\\");}
    let i=digits-1;let hex="0123456789ABCDEF";
    while i>=0 {
        m_append(out,hex+((code>>(i*4))&15),1);i=i-1;
    }
    m_text(out,"\\X0\\");
    return 0;
}

fn cst_quoted(text) {
    let out=m_buffer();m_text(out,"'");
    let i=0;
    while i<m_len(text) {
        let c=load8(text+i);
        if c==39 {m_text(out,"''");}
        else if c==92 {m_text(out,"\\\\");}
        else if c>=32 && c<=126 {m_append(out,text+i,1);}
        else if c>=194 && c<=244 {
            let code=c&31;let more=1;
            if c>=224 {code=c&15;more=2;}
            if c>=240 {code=c&7;more=3;}
            let end=i+more;let good=end<m_len(text);
            if good {
                let k=i+1;
                while k<=end {
                    let next=load8(text+k);
                    if next<128 || next>191 {good=0;}
                    code=(code<<6)|(next&63);k=k+1;
                }
            }
            if good && code>=160 && code<=1114111 && !(code>=55296 && code<=57343) {
                cst_unicode(out,code);i=end;
            }else {m_text(out,"?");}
        }else {m_text(out,"?");}
        i=i+1;
    }
    m_text(out,"'");return m_data(out);
}

fn cst_vector(writer,kind,vector,nm) {
    let tuple=m_buffer();m_text(tuple,kind);m_text(tuple,"('',(");
    let i=0;
    while i<3 {
        if i {m_text(tuple,",");}
        let value=load64(vector+i*8);
        if nm {m_text(tuple,cg_decimal(value));}
        else {
            if value<0 {m_text(tuple,"-");value=-value;}
            m_text(tuple,m_int(value));m_text(tuple,".");
        }
        i=i+1;
    }
    m_text(tuple,"))");return cst_emit(writer,m_data(tuple));
}

fn cst_list(list,id) {
    if load64(list+8)>2 {m_text(list,",");}
    m_text(list,cst_ref(id));return 0;
}

fn cst_wrap(writer,kind,value) {return cst_emit(writer,m_cat(kind,m_cat("(",m_cat(value,")"))));}

fn cst_product(writer,id,name,representation) {
    let product=cst_wrap(writer,"PRODUCT",m_cat(cst_quoted(id),m_cat(",",m_cat(cst_quoted(name),",'',(#3)"))));
    cst_wrap(writer,"PRODUCT_RELATED_PRODUCT_CATEGORY",m_cat("'part',$,(",m_cat(cst_ref(product),")")));
    let formation=cst_wrap(writer,"PRODUCT_DEFINITION_FORMATION",m_cat("'','',",cst_ref(product)));
    let definition=cst_wrap(writer,"PRODUCT_DEFINITION",m_cat("'design','',",m_cat(cst_ref(formation),",#4")));
    let shape=cst_wrap(writer,"PRODUCT_DEFINITION_SHAPE",m_cat("'','',",cst_ref(definition)));
    cst_wrap(writer,"SHAPE_DEFINITION_REPRESENTATION",m_cat(cst_ref(shape),m_cat(",",cst_ref(representation))));
    return definition;
}

fn cst_find_root(parents,face) {
    let next=load64(parents+face*8);
    while next!=face {
        let grand=load64(parents+next*8);store64(parents+face*8,grand);face=next;next=grand;
    }
    return face;
}

fn cst_join(edges,parents,a,b,face) {
    if a>b {let swap=a;a=b;b=swap;}
    let slot=edges+((a*73856093+b*19349663)&4095)*8;
    let row=load64(slot);
    while row {
        if load64(row)==a && load64(row+8)==b {
            let x=cst_find_root(parents,face);let y=cst_find_root(parents,load64(row+16));
            if x!=y {store64(parents+x*8,y);}
            return 1;
        }
        row=load64(row+24);
    }
    row=m_take(32);store64(row,a);store64(row+8,b);store64(row+16,face);
    store64(row+24,load64(slot));store64(slot,row);return 1;
}

fn cst_point(writer,points,entities,index) {
    let slot=entities+index*8;let id=load64(slot);
    if !id {
        id=cst_vector(writer,"CARTESIAN_POINT",cg_at(points,index),1);
        store64(slot,id);
    }
    return id;
}

fn cst_face(writer,points,entities,a,b,c) {
    let va=cg_at(points,a);let vb=cg_at(points,b);let vc=cg_at(points,c);
    let normal=cg_cross(cg_sub(vb,va),cg_sub(vc,va));
    if !load64(normal) && !load64(normal+8) && !load64(normal+16) {return cg_fail("STEP facets need three non-collinear vertices");}
    let ca=cst_point(writer,points,entities,a);
    let cb=cst_point(writer,points,entities,b);
    let cc=cst_point(writer,points,entities,c);
    let loop=cst_wrap(writer,"POLY_LOOP",m_cat("'',(",m_cat(cst_ref(ca),m_cat(",",m_cat(cst_ref(cb),m_cat(",",m_cat(cst_ref(cc),")")))))));
    let outer=cst_wrap(writer,"FACE_OUTER_BOUND",m_cat("'',",m_cat(cst_ref(loop),",.T.")));
    let direction=cst_vector(writer,"DIRECTION",normal,0);
    let placement=cst_wrap(writer,"AXIS2_PLACEMENT_3D",m_cat("'',",m_cat(cst_ref(ca),m_cat(",",m_cat(cst_ref(direction),",$")))));
    let plane=cst_wrap(writer,"PLANE",m_cat("'',",cst_ref(placement)));
    return cst_wrap(writer,"FACE_SURFACE",m_cat("'',(",m_cat(cst_ref(outer),m_cat("),",m_cat(cst_ref(plane),",.T.")))));
}

fn cst_shells(writer,points,part,bodies) {
    let triangles=j_get(part,"triangles");let count=cg_j_count(triangles)/3;
    if !j_value(j_get(part,"closed")) || !count {return cg_fail("STEP requires closed oriented part geometry");}
    let entities=m_take(cg_count(points)*8);let parents=m_take(count*8);let edges=m_take(4096*8);
    let i=0;
    while i<cg_count(points) {store64(entities+i*8,0);i=i+1;}
    i=0;while i<4096 {store64(edges+i*8,0);i=i+1;}
    i=0;while i<count {store64(parents+i*8,i);i=i+1;}
    let faces=m_take(count*16);
    let p=load64(triangles+16);i=0;
    while i<count && !cg_error {
        let a=j_value(p);p=load64(p+24);let b=j_value(p);p=load64(p+24);let c=j_value(p);p=load64(p+24);
        cst_join(edges,parents,a,b,i);cst_join(edges,parents,b,c,i);cst_join(edges,parents,c,a,i);
        let face=cst_face(writer,points,entities,a,b,c);
        store64(faces+i*16,face);
        store64(faces+i*16+8,cg_volume(cg_at(points,a),cg_at(points,b),cg_at(points,c)));
        if load64(load64(writer)+8)>2097152 {return cg_fail("STEP assembly exceeds the 2 MiB artifact limit");}
        i=i+1;
    }
    if cg_error {return 0;}
    let shells=m_take(count*16);i=0;
    while i<count {store64(shells+i*16,0);store64(shells+i*16+8,0);i=i+1;}
    i=0;
    while i<count {
        let slot=shells+cst_find_root(parents,i)*16;
        let list=load64(slot);
        if !list {list=m_buffer();m_text(list,"(");store64(slot,list);}
        cst_list(list,load64(faces+i*16));
        store64(slot+8,load64(slot+8)+load64(faces+i*16+8));
        i=i+1;
    }
    i=0;
    while i<count {
        let list=load64(shells+i*16);
        if list {
            if load64(shells+i*16+8)<=0 {return cg_fail("STEP export does not support enclosed void shells or zero-volume shells");}
            m_text(list,")");
            let shell=cst_wrap(writer,"CLOSED_SHELL",m_cat("'',",m_data(list)));
            let solid=cst_wrap(writer,"FACETED_BREP",m_cat(cst_quoted(j_string(part,"name")),m_cat(",",cst_ref(shell))));
            cst_list(bodies,solid);
        }
        i=i+1;
    }
    return !cg_error;
}

fn cst_shape_rep(writer,bodies) {
    m_text(bodies,")");
    return cst_wrap(writer,"FACETED_BREP_SHAPE_REPRESENTATION",m_cat("'',",m_cat(m_data(bodies),",#9")));
}

fn cst_part(writer,points,part) {
    let bodies=m_buffer();m_text(bodies,"(#13");
    if !cst_shells(writer,points,part,bodies) {return 0;}
    return cst_shape_rep(writer,bodies);
}

fn cst_pose(writer,matrix) {
    if j_kind(matrix)!=3 || cg_j_count(matrix)!=3 {return cg_fail("STEP assembly placement is incomplete");}
    let x=cg_v(0,0,0);let z=cg_v(0,0,0);let translation=cg_v(0,0,0);
    let row=load64(matrix+16);let i=0;
    while row && !cg_error {
        if j_kind(row)!=3 || cg_j_count(row)!=4 {return cg_fail("STEP assembly placement is incomplete");}
        let xx=load64(row+16);let zz=load64(load64(xx+24)+24);
        store64(x+i*8,cg_number(xx));store64(z+i*8,cg_number(zz));
        store64(translation+i*8,cg_number(load64(zz+24)));
        row=load64(row+24);i=i+1;
    }
    let origin=cst_vector(writer,"CARTESIAN_POINT",translation,1);
    let normal=cst_vector(writer,"DIRECTION",z,0);let reference=cst_vector(writer,"DIRECTION",x,0);
    return cst_wrap(writer,"AXIS2_PLACEMENT_3D",m_cat("'',",m_cat(cst_ref(origin),m_cat(",",m_cat(cst_ref(normal),m_cat(",",cst_ref(reference)))))));
}

fn cst_occurrence(writer,parent,child,id,name,location) {
    let occurrence=m_buffer();m_text(occurrence,cst_quoted(id));m_text(occurrence,",");
    m_text(occurrence,cst_quoted(name));m_text(occurrence,",'',");
    m_text(occurrence,cst_ref(load64(parent)));m_text(occurrence,",");
    m_text(occurrence,cst_ref(load64(child)));m_text(occurrence,",");
    m_text(occurrence,cst_quoted(id));
    let use=cst_wrap(writer,"NEXT_ASSEMBLY_USAGE_OCCURRENCE",m_data(occurrence));
    let shape=cst_wrap(writer,"PRODUCT_DEFINITION_SHAPE",m_cat("'Placement','',",cst_ref(use)));
    let transform=cst_wrap(writer,"ITEM_DEFINED_TRANSFORMATION",m_cat("'','',#13,",cst_ref(location)));
    let relation=m_buffer();m_text(relation,"(REPRESENTATION_RELATIONSHIP('','',");
    m_text(relation,cst_ref(load64(child+8)));m_text(relation,",");m_text(relation,cst_ref(load64(parent+8)));
    m_text(relation,") REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(");m_text(relation,cst_ref(transform));
    m_text(relation,") SHAPE_REPRESENTATION_RELATIONSHIP())");
    let link=cst_emit(writer,m_data(relation));
    return cst_wrap(writer,"CONTEXT_DEPENDENT_SHAPE_REPRESENTATION",m_cat(cst_ref(link),m_cat(",",cst_ref(shape))));
}

fn cst_start(source_hash) {
    let writer=m_take(16);let text=m_buffer();store64(writer,text);store64(writer+8,13);
    m_text(text,"ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('Faceted PCAD assembly'");
    if m_len(source_hash) {
        m_text(text,",'Frozen source SHA-256 ");m_text(text,source_hash);m_text(text,"'");
    }
    m_text(text,"),'2;1');\nFILE_NAME('assembly.step','2000-01-01T00:00:00',('PCAD'),");
    if m_len(source_hash) {m_text(text,"('Biscuit'),'Biscuit PCAD','Biscuit','');");}
    else {m_text(text,"('PuppyCAD'),'Flexscript CAD','PuppyCAD','');");}
    m_text(text,"\nFILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));\nENDSEC;\nDATA;\n");
    m_text(text,"#1=APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,#2);\n#2=APPLICATION_CONTEXT('core data for automotive mechanical design processes');\n#3=PRODUCT_CONTEXT('',#2,'mechanical');\n#4=PRODUCT_DEFINITION_CONTEXT('part definition',#2,'design');\n");
    m_text(text,"#5=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));\n#6=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));\n#7=(NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT());\n#8=UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(0.000001),#5,'distance_accuracy_value','native vertex resolution');\n");
    m_text(text,"#9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#8)) GLOBAL_UNIT_ASSIGNED_CONTEXT((#5,#6,#7)) REPRESENTATION_CONTEXT('','3D millimetres'));\n#10=CARTESIAN_POINT('',(0.,0.,0.));\n#11=DIRECTION('',(0.,0.,1.));\n#12=DIRECTION('',(1.,0.,0.));\n#13=AXIS2_PLACEMENT_3D('',#10,#11,#12);\n");
    return writer;
}

// STEP writes one representation per distinct evaluated subassembly
// configuration. Children in a shared representation have local usage IDs.
fn cst_scope(state,scope,occurrence) {
    let writer=load64(state);let poses=load64(state+8);let authored=load64(state+16);
    let children=cg_array();let signature=m_buffer();
    let definition=j_string(occurrence,"assembly");
    m_text(signature,definition);m_text(signature,"/");m_text(signature,j_string(occurrence,"configuration"));
    let row=load64(poses+16);
    while row && !cg_error {
        let path=j_string(row,"id");
        if m_eq(cah_parent(path),scope) {
            let child=j_integer(load64(state+24),j_string(row,"part"));
            if m_len(j_string(row,"assembly")) {child=cst_scope(state,path,row);}
            if !child {return cg_fail("STEP child is missing its part or assembly definition");}
            let id=path;
            if m_len(scope) {id=path+m_len(scope)+1;}
            let source=j_integer(authored,path);
            let name=j_string(source,"name");if !m_len(name) {name=id;}
            let transform=j_get(row,"local_transform");
            if !transform {transform=j_get(row,"transform");}
            m_text(signature,"|");m_text(signature,id);m_text(signature,":");
            m_text(signature,m_int(load64(child)));m_text(signature,j_encode(transform));
            let slot=m_take(40);store64(slot,id);store64(slot+8,name);store64(slot+16,child);
            store64(slot+24,transform);store64(slot+32,0);cg_push(children,slot);
        }
        row=load64(row+24);
    }
    if !cg_count(children) || cg_error {return cg_fail("STEP subassembly has no evaluated children");}
    let key=m_data(signature);let variants=load64(state+32);
    let prior=j_integer(variants,key);
    if prior && m_len(scope) {return prior;}
    let axes=m_buffer();m_text(axes,"(#13");let i=0;
    while i<cg_count(children) && !cg_error {
        let slot=cg_at(children,i);let location=cst_pose(writer,load64(slot+24));
        store64(slot+32,location);cst_list(axes,location);i=i+1;
    }
    if cg_error {return 0;}
    m_text(axes,")");
    let representation=cst_wrap(writer,"SHAPE_REPRESENTATION",m_cat("'',",m_cat(m_data(axes),",#9")));
    let product_id="assembly/PCAD";let name=load64(state+48);
    if m_len(scope) {
        let sub=j_integer(load64(state+40),definition);
        name=j_string(sub,"name");if !m_len(name) {name=definition;}
        let number=load64(state+56)+1;store64(state+56,number);
        product_id=m_cat("assembly/",m_cat(definition,m_cat("/",m_int(number))));
    }
    let parent=m_take(16);
    store64(parent,cst_product(writer,product_id,name,representation));store64(parent+8,representation);
    i=0;
    while i<cg_count(children) && !cg_error {
        let slot=cg_at(children,i);
        cst_occurrence(writer,parent,load64(slot+16),load64(slot),load64(slot+8),load64(slot+32));i=i+1;
    }
    if m_len(scope) {cg_j_int(variants,key,parent);}
    return parent;
}

fn cst_hierarchical(doc,poses,parts,points,writer) {
    let layout=cah_expand(doc);if !layout || cg_error {return ca_error();}
    let authors=j_object();let definitions=j_object();let count=0;
    let row=load64(j_get(layout,"instances")+16);
    while row && !cg_error {cg_j_int(authors,j_string(row,"id"),row);row=load64(row+24);}
    row=load64(j_get(parts,"parts")+16);
    while row && !cg_error {
        let id=j_string(row,"id");let representation=cst_part(writer,points,row);
        if !representation || cg_error {return ca_error();}
        let part=m_take(16);
        store64(part,cst_product(writer,id,j_string(row,"name"),representation));store64(part+8,representation);
        cg_j_int(definitions,id,part);count=count+1;row=load64(row+24);
    }
    let name=j_string(j_get(doc,"assembly"),"name");if !m_len(name) {name="PCAD assembly";}
    let state=m_take(64);store64(state,writer);store64(state+8,poses);store64(state+16,authors);
    store64(state+24,definitions);store64(state+32,j_object());store64(state+40,j_get(layout,"assembly_definitions"));
    store64(state+48,name);store64(state+56,0);
    if !cst_scope(state,"",0) || cg_error {return ca_error();}
    return cst_finish(writer,count+load64(state+56),cg_j_count(poses));
}

fn cst_finish(writer,definitions,occurrences) {
    let out=load64(writer);m_text(out,"ENDSEC;\nEND-ISO-10303-21;\n");
    if load64(out+8)>2097152 {cg_fail("STEP assembly exceeds the 2 MiB artifact limit");return ca_error();}
    let result=j_object();cg_j_text(result,"text",m_data(out));
    cg_j_int(result,"definitions",definitions);cg_j_int(result,"occurrences",occurrences);
    return result;
}

fn cst_points(mesh) {
    let points=cg_array();let v=pc_first(j_get(mesh,"vertices"));
    while v && !cg_error {cg_push(points,cg_vector(v,0));v=load64(v+24);}
    return points;
}

fn pcad_step(doc,mesh,source_hash) {
    if m_len(source_hash) {
        let i=0;while i<64 && j_hex(load8(source_hash+i))>=0 {i=i+1;}
        if i!=64 || load8(source_hash+i) {cg_fail("Invalid frozen source SHA-256");return ca_error();}
    }
    // Triangulate prototypes in part coordinates so repeated occurrences share
    // one definition and use the exact evaluated rigid assembly placements.
    let work=j_parse(j_encode(doc));
    let linked=pcm_prepare(work,0);if cg_error {return ca_error();}
    let prototypes=pmb_compile(work,linked,0);
    if cg_error {return ca_error();}
    let poses=j_get(j_get(mesh,"assembly"),"instances");
    let authored=j_get(j_get(work,"assembly"),"instances");
    let nested=j_get(work,"assembly_definitions");let limit=16;if nested {limit=32;}
    if j_kind(poses)!=3 || !cg_j_count(poses) || cg_j_count(poses)>limit {cg_fail("STEP exchange requires an evaluated assembly");return ca_error();}
    let selected=cg_array();let loaded=j_object();
    let pose=load64(poses+16);
    while pose {
        let id=j_string(pose,"part");
        if m_len(id) && !j_get(loaded,id) {
            let part=ca_find(prototypes,id);
            if !part {cg_fail("STEP occurrence refers to a missing part");return ca_error();}
            cg_push(selected,part);cg_j_int(loaded,id,1);
        }
        pose=load64(pose+24);
    }
    let parts=cg_tessellate(selected);
    if cg_error {return ca_error();}
    cg_begin();
    let writer=cst_start(source_hash);
    let points=cst_points(parts);
    if nested {return cst_hierarchical(work,poses,parts,points,writer);}
    return cst_flat(writer,poses,authored,parts,points,j_string(j_get(doc,"assembly"),"name"));
}

fn cst_flat(writer,poses,authored,parts,points,name) {
    let definitions=j_object();let locations=j_object();let def_count=0;
    let axes=m_buffer();m_text(axes,"(#13");
    let row=load64(poses+16);
    while row && !cg_error {
        let id=j_string(row,"id");let part_id=j_string(row,"part");
        if !j_get(definitions,part_id) {
            let part=pcm_find(j_get(parts,"parts"),part_id);
            if !part {cg_fail("STEP occurrence refers to a missing part");return ca_error();}
            let representation=cst_part(writer,points,part);
            if !representation || cg_error {return ca_error();}
            let definition=m_take(16);
            store64(definition,cst_product(writer,part_id,j_string(part,"name"),representation));
            store64(definition+8,representation);
            cg_j_int(definitions,part_id,definition);def_count=def_count+1;
        }
        let location=cst_pose(writer,j_get(row,"transform"));
        cg_j_int(locations,id,location);cst_list(axes,location);row=load64(row+24);
    }
    if cg_error {return ca_error();}
    m_text(axes,")");
    let representation=cst_wrap(writer,"SHAPE_REPRESENTATION",m_cat("'',",m_cat(m_data(axes),",#9")));
    if !m_len(name) {name="PCAD assembly";}
    let root=m_take(16);
    // A slash cannot occur in a valid native part ID.
    store64(root,cst_product(writer,"assembly/PCAD",name,representation));store64(root+8,representation);
    row=load64(poses+16);
    while row && !cg_error {
        let id=j_string(row,"id");let part_id=j_string(row,"part");
        let occurrence=pcm_find(authored,id);
        let name=j_string(occurrence,"name");if !m_len(name) {name=id;}
        cst_occurrence(writer,root,j_integer(definitions,part_id),id,name,j_integer(locations,id));
        row=load64(row+24);
    }
    if cg_error {return ca_error();}
    return cst_finish(writer,def_count,cg_j_count(poses));
}

// A v4 occurrence can scale or reflect a solid. STEP occurrence placements
// are rigid. Build one local part definition for each distinct scale, then
// attach exactly the solved rotation and translation to each occurrence.
fn cst_v4_assembly(project,item,writer) {
    let data=j_get(item,"data");let rows=pc_assembly_poses(data);
    let solids=cg_array();let variants=j_object();let prototypes=cg_array();let poses=j_array();
    let i=0;while i<cg_count(rows) && !cg_error {
        let row=cg_at(rows,i);let instance=load64(row+8);let id=j_string(instance,"partId");let scale=load64(row+40);
        let key=j_array();j_add(key,0,j_text(id));
        let k=0;while k<3 {j_add(key,0,j_number(load64(scale+k*8)));k=k+1;}
        let signature=j_encode(key);let variant=j_string(variants,signature);
        if !m_len(variant) {
            let part=pc_find(j_get(project,"items"),id);
            if !m_eq(j_string(part,"type"),"part") {cg_fail("Assembly instance references a missing part");return ca_error();}
            let proto=ca_find(prototypes,id);
            if !proto {proto=cg_v(id,pc_part_bodies(part),0);cg_push(prototypes,proto);}
            let polys=pc_place_scaled_bodies(load64(proto+8),ca_identity(),scale);
            variant=id;
            if load64(scale)!=1000000 || load64(scale+8)!=1000000 || load64(scale+16)!=1000000 {
                variant=m_cat("scaled/",signature);
                while pc_find(j_get(project,"items"),variant) {variant=m_cat("scaled/",variant);}
            }
            cg_j_text(variants,signature,variant);cad_part(solids,polys,variant,j_string(part,"name"),"#82b38e");
        }
        let pose=j_object();cg_j_text(pose,"id",load64(row));cg_j_text(pose,"part",variant);
        j_add(pose,"transform",ca_matrix_json(load64(row+24)));j_add(poses,0,pose);i=i+1;
    }
    if cg_error {return ca_error();}
    let parts=cg_tessellate(solids);if cg_error {return ca_error();}
    return cst_flat(writer,poses,j_get(data,"instances"),parts,cst_points(parts),j_string(item,"name"));
}

fn cad_project_step(project) {
    cg_begin();let item=cad_project_item(project);let result=0;
    if m_eq(j_string(item,"type"),"assembly") {result=cst_v4_assembly(project,item,cst_start(0));}
    else {
        let mesh=cad_project_mesh(project);if cg_error {return 0;}
        if cad_project_is_studio(project) && j_get(project,"assembly") {result=pcad_step(project,mesh,0);}
        else {
            let writer=cst_start(0);let points=cst_points(mesh);let part=pc_first(j_get(mesh,"parts"));let count=0;
            // A v4 part owns every body in its feature tree. Keep the item
            // as a single STEP product while retaining names on its solids.
            let bodies=m_buffer();m_text(bodies,"(#13");
            while part && !cg_error {
                if item {
                    if !cst_shells(writer,points,part,bodies) {return 0;}
                }else {
                    let rep=cst_part(writer,points,part);if !rep {return 0;}
                    cst_product(writer,j_string(part,"id"),j_string(part,"name"),rep);
                }
                part=load64(part+24);count=count+1;
            }
            if !count {return cg_fail("No bodies to export");}
            if item {cst_product(writer,j_string(item,"id"),j_string(item,"name"),cst_shape_rep(writer,bodies));count=1;}
            result=cst_finish(writer,count,0);
        }
    }
    if cg_error {return 0;}
    let text=j_string(result,"text");return cg_v(text,m_len(text),0);
}
