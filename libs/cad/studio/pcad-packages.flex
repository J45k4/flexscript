// Attach frozen library solids to the native board-local placement frame.
// Only the evaluated assembly acquires these bodies and fixed mates.
import "pcad-net-rules.flex";
fn pmb_key(prefix,a,b) {
    let hash=2166136261;let i=0;
    while load8(a+i) {hash=((hash^load8(a+i))*16777619)&4294967295;i=i+1;}
    hash=(hash*16777619)&4294967295;i=0;
    while load8(b+i) {hash=((hash^load8(b+i))*16777619)&4294967295;i=i+1;}
    return m_cat(prefix,m_int(hash));
}

fn pmb_compatible(component,placement,definition) {
    let footprint=j_get(definition,"footprint");
    if !m_eq(j_string(placement,"footprint"),j_string(footprint,"kind")) {return 0;}
    let pads=j_get(footprint,"pad_pins");
    let count=pc_pad_count(pc_package_footprint(j_string(footprint,"kind")));
    if cg_error || cg_j_count(pads)!=count {return 0;}
    let expected=load64(pads+16);
    let mapped=j_get(j_get(component,"definition"),"pins");
    let index=0;
    while expected {
        let pin=pce_pad_pin(component,placement,index,count,1);
        if cg_error {return 0;}
        if pin {
            let id=j_string(pin,"id");let row=load64(mapped+16);
            while row && !m_eq(j_string(row,"pin_id"),id) {row=load64(row+24);}
            if !row || j_kind(expected)!=2 || !m_eq(j_string(row,"definition_pin_id"),j_value(expected)) {return 0;}
        } else if j_kind(expected)!=0 {return 0;}
        expected=load64(expected+24);index=index+1;
    }
    return 1;
}

// State: frozen design, board-node index, compiled prototypes, model cache,
// count of compiled library revisions. No executable imports are admitted.
fn pmb_prototype(context,definition) {
    let id=j_string(definition,"id");let revision=m_int(j_integer(definition,"revision"));
    let key=m_cat(id,m_cat(":",revision));let cache=load64(context+24);
    let previous=j_integer(cache,key);if previous {return previous;}
    if load64(context+32)>=8 {return cg_fail("Use at most eight fitted library model revisions");}
    let prototypes=load64(context+16);let generated=pmb_key("pkg-part-",id,revision);
    if ca_find(prototypes,generated) {return cg_fail("A library package prototype identity conflicts with another part");}
    let asset=j_parse(j_encode(j_get(j_get(definition,"mechanical"),"asset")));
    if !pcd_prepare(asset,0) {return 0;}
    let solids=cg_compile_in_context(asset,0);
    if cg_error || cg_count(solids)!=1 {return cg_fail("A fitted library model must contain one valid body");}
    let part=cg_at(solids,0);
    store64(part,generated);store64(part+8,j_string(definition,"name"));
    cg_push(prototypes,part);cg_j_int(cache,key,part);
    store64(context+32,load64(context+32)+1);return part;
}

fn pmb_vector(x,y,z) {
    let vector=j_array();j_add(vector,0,cg_json_number(x));j_add(vector,0,cg_json_number(y));j_add(vector,0,cg_json_number(z));
    return vector;
}

fn pmb_frame(board,placement,model) {
    let at=j_get(placement,"at");let turn=j_get(placement,"rotation");
    let angle=j_integer(placement,"rotation");
    if j_kind(at)!=3 || cg_j_count(at)!=2 || (turn && j_kind(turn)!=1)
        || (angle!=0 && angle!=90 && angle!=180 && angle!=270) {
        return cg_fail("A fitted package needs valid PCB coordinates and a right-angle rotation");
    }
    let xy=load64(at+16);let x=cg_number(xy);let y=cg_number(load64(xy+24));
    let side=pc_side(placement);let surface=cg_number(j_get(board,"thickness"));
    let offset=cg_vector(j_get(model,"position"),0);let rotation=cg_vector(j_get(model,"rotation"),0);
    if cg_error {return 0;}
    let pitch=load64(rotation+8);
    if side<0 {surface=0;pitch=(pitch+900000000)%360000000;}
    let relative=pc_footprint_offset(load64(offset),load64(offset+8),angle,side);
    let heading=(load64(rotation+16)*side+angle*1000000+720000000)%360000000;
    let frame=j_object();
    j_add(frame,"position",pmb_vector(x+load64(relative),y+load64(relative+8),surface+load64(offset+16)*side));
    // Rz(board) * Ry(180) * Rz(local) = Rz(board-local) * Ry(180).
    j_add(frame,"rotation",pmb_vector(load64(rotation),pitch,heading));
    return frame;
}

fn pmb_attach(scope,id,board,component,prototype,frame,standalone) {
    let name=m_cat(j_string(component,"reference")," on PCB");
    if standalone {
        if cg_count(standalone)>=16 {return cg_fail("CAD preview supports up to 16 bodies including fitted library models");}
        if ca_find(standalone,id) {return cg_fail("A fitted component identity conflicts with another body");}
        let item=m_take(32);store64(item,id);store64(item+8,name);store64(item+16,load64(prototype+16));
        store64(item+24,ca_place(load64(prototype+24),ca_frame(frame)));cg_push(standalone,item);
        return !cg_error;
    }
    let instances=j_get(scope,"instances");let mates=j_get(scope,"mates");
    if j_kind(instances)!=3 || j_kind(mates)!=3 || cg_j_count(instances)>=16 {
        return cg_fail("Assembly scope exceeds 16 placed instances including fitted library models");
    }
    if pcm_find(instances,id) || pcm_find(mates,id) {return cg_fail("A fitted component identity conflicts with an assembly record");}
    let instance=j_object();cg_j_text(instance,"id",id);cg_j_text(instance,"part",load64(prototype));cg_j_text(instance,"name",name);
    j_add(instances,0,instance);
    let mate=j_object();cg_j_text(mate,"id",id);cg_j_text(mate,"type","fixed");
    cg_j_text(mate,"parent",board);cg_j_text(mate,"child",id);j_add(mate,"parent_frame",frame);j_add(mates,0,mate);
    return 1;
}

fn pmb_board(context,scope,part,occurrence,standalone) {
    let board_id=j_string(load64(context+8),j_string(part,"node"));
    if !m_len(board_id) {return 1;}
    let document=load64(context);let board=pcm_board(document,board_id);let electrical=j_get(document,"electrical");
    let placements=j_get(board,"placements");if !placements {return 1;}
    if j_kind(placements)!=3 || cg_j_count(placements)>6 {return cg_fail("A linked board needs bounded component placements");}
    let row=load64(placements+16);
    while row && !cg_error {
        let component=pcm_find(j_get(electrical,"components"),j_string(row,"component_id"));
        let definition=pl_pinned(electrical,component);
        let model=j_get(definition,"mechanical");
        if model {
            if !pmb_compatible(component,row,definition) {
                return cg_fail(m_cat("PCB footprint or pad map differs from the pinned model for ",j_string(component,"reference")));
            }
            let frame=pmb_frame(board,row,model);
            let prototype=pmb_prototype(context,definition);
            let id=pmb_key("pkg-",occurrence,j_string(component,"id"));
            if !frame || !prototype || !pmb_attach(scope,id,occurrence,component,prototype,frame,standalone) {return 0;}
        }
        row=load64(row+24);
    }
    return !cg_error;
}

fn pmb_scope(context,scope) {
    let rows=j_get(scope,"instances");if j_kind(rows)!=3 {return 1;}
    let parts=j_get(load64(context),"parts");let row=load64(rows+16);
    let left=cg_j_count(rows);
    while row && left>0 && !cg_error {
        let part=pcm_find(parts,j_string(row,"part"));
        if part && !pmb_board(context,scope,part,j_string(row,"id"),0) {return 0;}
        row=load64(row+24);left=left-1;
    }
    return !cg_error;
}

fn pmb_compile(document,linked,report) {
    return pmb_compile_dimensions(document,linked,report,0);
}
fn pmb_compile_dimensions(document,linked,report,parameters) {
    cg_begin();
    let prototypes=cg_compile_dimensions(document,report,parameters);if cg_error {return prototypes;}
    if !cg_j_count(linked) {return prototypes;}
    let library=j_get(j_get(document,"electrical"),"component_definitions");
    if !library {return prototypes;}
    let selected=load64(library+16);
    while selected && !j_get(selected,"mechanical") {selected=load64(selected+24);}
    if !selected {return prototypes;}
    let context=m_take(40);
    store64(context,document);store64(context+8,linked);store64(context+16,prototypes);
    store64(context+24,j_object());store64(context+32,0);
    let assembly=j_get(document,"assembly");
    if !assembly {
        let solids=cg_array();let i=0;
        while i<cg_count(prototypes) {cg_push(solids,cg_at(prototypes,i));i=i+1;}
        let part=load64(j_get(document,"parts")+16);
        while part && !cg_error {
            if !pmb_board(context,0,part,j_string(part,"id"),solids) {return solids;}
            part=load64(part+24);
        }
        return solids;
    }
    if !pmb_scope(context,assembly) {return prototypes;}
    let definitions=j_get(document,"assembly_definitions");
    if j_kind(definitions)==3 {
        let def=load64(definitions+16);
        while def && !cg_error {
            if !pmb_scope(context,def) {return prototypes;}
            def=load64(def+24);
        }
    }
    return prototypes;
}
