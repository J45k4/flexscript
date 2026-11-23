import "dimensions.flex";

// A plane is a named datum frame in part-definition coordinates. Assembly
// occurrence poses are applied after the feature's prototype is built.
fn csp_find(rows,id) {
    if j_kind(rows)!=3 {return 0;}
    let row=load64(rows+16);let match=0;
    while row {
        if m_eq(j_string(row,"id"),id) {
            if match {return cg_fail(m_cat("Ambiguous sketch plane reference: ",id));}
            match=row;
        }
        row=load64(row+24);
    }
    return match;
}

fn csp_plane(source,sketch,parameters,context) {
    let plane=j_get(sketch,"plane");
    if !plane {return 0;}
    let id=j_string(sketch,"id");let kind=j_string(plane,"kind");
    if j_kind(plane)!=4 {return cg_fail(m_cat("Invalid sketch plane: ",id));}
    let offset=0;let rotation=0;
    if m_eq(kind,"origin") && cg_j_count(plane)==2 {
        let axis=j_string(plane,"axis");
        if m_eq(axis,"xy") {return 0;}
        if m_eq(axis,"xz") {rotation=cg_v(90000000,0,0);}
        else if m_eq(axis,"yz") {rotation=cg_v(90000000,0,90000000);}
        else {return cg_fail(m_cat("Sketch origin plane must be XY, XZ or YZ: ",id));}
        offset=cg_v(0,0,0);
    }else if m_eq(kind,"datum") && cg_j_count(plane)==3 {
        let owner=j_string(plane,"part_id");let name=j_string(plane,"datum_id");
        let part=0;let datum=0;
        if cg_id(owner) && m_len(name) && m_len(name)<=64 {
            part=csp_find(j_get(source,"parts"),owner);
            datum=csp_find(j_get(part,"datums"),name);
        }
        if cg_error {return 0;}
        if !datum {
            let detail=m_cat(owner,m_cat(" / ",name));
            return cg_fail(m_cat("Missing sketch plane datum on ",m_cat(id,m_cat(": ",detail))));
        }
        let bindings=j_get(datum,"position_bindings");
        if bindings {
            let boxes=load64(context);
            if !boxes {
                boxes=pcd_boxes(j_get(source,"nodes"));
                store64(context,boxes);
            }
            if !cg_error {offset=pcd_vector(boxes,j_get(datum,"position"),bindings,parameters);}
        }else {offset=cg_vector(j_get(datum,"position"),1);}
        if cg_error {return 0;}
        rotation=cg_vector(j_get(datum,"rotation"),1);
    }else {return cg_fail(m_cat("Invalid sketch plane: ",id));}
    if cg_error {return 0;}
    let frame=m_take(16);store64(frame,offset);store64(frame+8,rotation);
    return frame;
}
