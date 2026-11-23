// Box dimensions and datum coordinates can refer to a box size or a named length.
// Only the evaluation copy receives resolved vectors. An axis has one affine input.
import "parameters.flex";

// Slots contain the source node and three pairs of visit state and resolved value.
fn pcd_boxes(nodes) {
    if j_kind(nodes)!=3 || cg_j_count(nodes)>48 {return cg_fail("Invalid PCAD shape list for dimension evaluation");}
    let index=j_object();
    let node=load64(nodes+16);
    while node && !cg_error {
        let bindings=j_get(node,"size_bindings");
        if m_eq(j_string(node,"type"),"box") {
            let id=j_string(node,"id");
            if !m_len(id) || m_len(id)>64 || j_get(index,id) {return cg_fail("Box dimensions need unique shape IDs");}
            let slots=m_take(56);
            store64(slots,node);
            let axis=0;
            while axis<3 {store64(slots+8+axis*16,0);axis=axis+1;}
            cg_j_int(index,id,slots);
        }else if bindings {return cg_fail("Size bindings require a box");}
        node=load64(node+24);
    }
    return index;
}

fn pcd_axis(key) {
    if m_eq(key,"x") {return 0;}
    if m_eq(key,"y") {return 1;}
    if m_eq(key,"z") {return 2;}
    cg_fail("A dimension binding axis must be x, y or z");
    return 0;
}

fn pcd_axis_key(axis) {
    if axis==0 {return "x";}
    if axis==1 {return "y";}
    return "z";
}

fn pcd_bound_value(index,binding,parameters) {
    let reference=j_get(binding,"parameter");
    if reference {
        if j_kind(binding)!=4 || cg_j_count(binding)!=1 {
            return cg_fail("Each dimension axis can use one named parameter or one box size");
        }
        return cp_target(parameters,reference);
    }
    if j_kind(binding)!=4 || cg_j_count(binding)!=3 || !j_get(binding,"offset_mm") {
        return cg_fail("A dimension binding needs a box, size axis and millimetre offset");
    }
    let id=j_string(binding,"node");
    let source=j_integer(index,id);
    if !source {return cg_fail(m_cat("Missing dimension source box: ",id));}
    let axis=pcd_axis(j_string(binding,"axis"));
    let offset=cg_number(j_get(binding,"offset_mm"));
    if cg_error {return 0;}
    return pcd_box_size(index,source,axis,parameters)+offset;
}

fn pcd_box_size(index,slots,axis,parameters) {
    let slot=slots+8+axis*16;
    let state=load64(slot);
    let node=load64(slots);
    if state==2 {return load64(slot+8);}
    if state==1 {return cg_fail(m_cat("Cyclic box dimension binding at ",m_cat(j_string(node,"id"),m_cat(".",pcd_axis_key(axis)))));}
    store64(slot,1);
    let binding=j_get(j_get(node,"size_bindings"),pcd_axis_key(axis));
    let value=0;
    if binding {value=pcd_bound_value(index,binding,parameters);}
    else {
        let size=cg_vector(j_get(node,"size"),0);
        value=load64(size+axis*8);
    }
    if cg_error {return 0;}
    if value<10000 || value>500000000 {return cg_fail("Evaluated box dimensions must be 0.01–500 mm");}
    store64(slot+8,value);
    store64(slot,2);
    return value;
}

fn pcd_validate_bindings(bindings) {
    if j_kind(bindings)!=4 || cg_j_count(bindings)>3 {return cg_fail("Dimension bindings must be keyed by x, y or z");}
    let binding=load64(bindings+16);
    let seen=0;
    while binding && !cg_error {
        let axis=1<<pcd_axis(load64(binding+32));
        if cg_error {return 0;}
        if seen&axis {return cg_fail("A dimension axis can have only one binding");}
        seen=seen|axis;
        binding=load64(binding+24);
    }
    return !cg_error;
}

fn pcd_vector(index,authored,bindings,parameters) {
    let position=cg_vector(authored,0);
    if !pcd_validate_bindings(bindings) {return 0;}
    let binding=load64(bindings+16);
    while binding && !cg_error {
        let axis=pcd_axis(load64(binding+32));
        let value=pcd_bound_value(index,binding,parameters);
        if cg_error {return 0;}
        if value< -500000000 || value>500000000 {return cg_fail("Evaluated datum coordinates must be within +/-500 mm");}
        store64(position+axis*8,value);
        binding=load64(binding+24);
    }
    return position;
}

fn pcd_json_vector(v) {
    let out=j_array();
    let axis=0;
    while axis<3 {j_add(out,0,cg_json_number(load64(v+axis*8)));axis=axis+1;}
    return out;
}

fn pcd_report(report,id,owner,scope,bindings,vector) {
    if !report {return 0;}
    let binding=load64(bindings+16);
    while binding {
        let key=load64(binding+32);
        let axis=pcd_axis(key);
        let item=j_object();
        cg_j_text(item,"id",id);
        if m_len(owner) {cg_j_text(item,scope,owner);}
        cg_j_text(item,"axis",key);
        j_add(item,"value_mm",cg_json_number(load64(vector+axis*8)));
        j_add(report,0,item);
        binding=load64(binding+24);
    }
}

fn pcd_prepare(document,report) {
    let parameters=cp_catalog(j_get(document,"parameters"),0);
    if cg_error {return 0;}
    let index=pcd_boxes(j_get(document,"nodes"));
    if cg_error {return 0;}
    let box=load64(index+16);
    while box && !cg_error {
        let slots=j_value(box);
        let node=load64(slots);
        let bindings=j_get(node,"size_bindings");
        if bindings {
            if !pcd_validate_bindings(bindings) {return 0;}
            let v=cg_v(0,0,0);
            let axis=0;
            while axis<3 && !cg_error {store64(v+axis*8,pcd_box_size(index,slots,axis,parameters));axis=axis+1;}
            if !cg_error {
                pcd_report(report,j_string(node,"id"),"","",bindings,v);
                cg_j_set(node,"size",pcd_json_vector(v));
            }
        }
        box=load64(box+24);
    }
    if !pcd_datums(j_get(document,"parts"),"part",index,parameters,report) {return 0;}
    return pcd_datums(j_get(document,"assembly_definitions"),"assembly",index,parameters,report);
}

fn pcd_datums(parts,scope,index,parameters,report) {
    if !parts {return 1;}
    if j_kind(parts)!=3 || cg_j_count(parts)>16 {return cg_fail("Use up to 16 part or assembly definitions");}
    let part=load64(parts+16);
    while part && !cg_error {
        let datums=j_get(part,"datums");
        if j_kind(datums)==3 && cg_j_count(datums)<=24 {
            let datum=load64(datums+16);
            while datum && !cg_error {
                let bindings=j_get(datum,"position_bindings");
                if bindings {
                    let position=pcd_vector(index,j_get(datum,"position"),bindings,parameters);
                    if !cg_error {
                        pcd_report(report,j_string(datum,"id"),j_string(part,"id"),scope,bindings,position);
                        cg_j_set(datum,"position",pcd_json_vector(position));
                    }
                }
                datum=load64(datum+24);
            }
        }
        part=load64(part+24);
    }
    return !cg_error;
}
