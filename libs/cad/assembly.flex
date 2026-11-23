// Driven rigid-body assemblies over the native tessellated CSG kernel.
// A mate aligns two local frames, with motion along/about their local Z axis.
import "mesh.flex";
import "assembly-pattern.flex";
import "assembly-hierarchy.flex";

// Rigid transforms: nine row-major rotation coefficients (1e6), then nm XYZ.
fn ca_identity() {
    let t=m_take(96);let i=0;
    while i<12 {store64(t+i*8,0);i=i+1;}
    store64(t,1000000);store64(t+32,1000000);store64(t+64,1000000);
    return t;
}
fn ca_point(t,p) {
    let out=cg_v(0,0,0);let axis=0;
    let x=load64(p);let y=load64(p+8);let z=load64(p+16);
    while axis<3 {
        let row=t+axis*24;
        let n=load64(row)*x+load64(row+8)*y+load64(row+16)*z;
        store64(out+axis*8,n/1000000+load64(t+72+axis*8));axis=axis+1;
    }
    return out;
}
fn ca_product(a,b) {
    let out=m_take(96);let axis=0;
    while axis<3 {
        let row=a+axis*24;
        let x=load64(row);let y=load64(row+8);let z=load64(row+16);let column=0;
        while column<3 {
            let cell=b+column*8;
            let n=x*load64(cell)+y*load64(cell+24)+z*load64(cell+48);
            store64(out+axis*24+column*8,n/1000000);column=column+1;
        }
        axis=axis+1;
    }
    let p=ca_point(a,b+72);axis=0;
    while axis<3 {store64(out+72+axis*8,load64(p+axis*8));axis=axis+1;}
    return out;
}
fn ca_inverse(t) {
    let out=ca_identity();let i=0;
    while i<3 {let j=0;while j<3 {store64(out+(i*3+j)*8,load64(t+(j*3+i)*8));j=j+1;}i=i+1;}
    let p=ca_point(out,t+72);i=0;
    while i<3 {store64(out+72+i*8,-load64(p+i*8));i=i+1;}
    return out;
}
fn ca_frame(value) {
    if !value {return ca_identity();}
    if j_kind(value)!=4 {cg_fail("Mate frames must be objects with position/rotation vectors");return ca_identity();}
    return ca_transform(cg_vector(j_get(value,"position"),1),cg_vector(j_get(value,"rotation"),1));
}
fn ca_transform(pos,rot) {
    let out=ca_identity();let j=0;
    while j<3 && !cg_error {
        let basis=cg_v(0,0,0);store64(basis+j*8,1000000);
        let v=cg_transform_point(basis,cg_v(0,0,0),rot);let i=0;
        while i<3 {store64(out+(i*3+j)*8,load64(v+i*8));i=i+1;}
        j=j+1;
    }
    let i=0;while i<3 {store64(out+72+i*8,load64(pos+i*8));i=i+1;}
    return out;
}
// Authored hold in the containing assembly frame, captured from a solved pose.
fn ca_held(value) {
    if j_kind(value)!=3 || cg_j_count(value)!=3 {return cg_fail("A held pose needs a 3 by 4 rigid transform");}
    let matrix=ca_identity();let axis=0;let row=load64(value+16);
    while row && !cg_error {
        if j_kind(row)!=3 || cg_j_count(row)!=4 {return cg_fail("A held pose needs a 3 by 4 rigid transform");}
        let cell=load64(row+16);let column=0;
        while column<3 {
            let n=cg_number(cell);
            if cg_abs(n)>1000010 {return cg_fail("Held rotation coefficients exceed the rigid range");}
            store64(matrix+(axis*3+column)*8,n);column=column+1;cell=load64(cell+24);
        }
        // A nested frame can lie outside the solid's +/-500 mm world envelope.
        // Bound translations so 32 composed frames stay within 64-bit products.
        store64(matrix+72+axis*8,cg_number_bounded(cell,150000));axis=axis+1;row=load64(row+24);
    }
    if cg_error {return 0;}
    axis=0;
    while axis<3 {
        let peer=axis;
        while peer<3 {
            let dot=0;let k=0;
            while k<3 {
                dot=dot+load64(matrix+(axis*3+k)*8)*load64(matrix+(peer*3+k)*8);
                k=k+1;
            }
            if axis==peer {dot=dot-1000000000000;}
            if cg_abs(dot)>200000000 {return cg_fail("Held pose rotation must be orthonormal");}
            peer=peer+1;
        }
        axis=axis+1;
    }
    let a=load64(matrix);let b=load64(matrix+8);let c=load64(matrix+16);
    let d=load64(matrix+24);let e=load64(matrix+32);let f=load64(matrix+40);
    let g=load64(matrix+48);let h=load64(matrix+56);let i=load64(matrix+64);
    if (a*e-b*d)*i+(b*f-c*e)*g+(c*d-a*f)*h<=0 {
        return cg_fail("Held pose rotation must be right-handed");
    }
    return matrix;
}
fn ca_error() {
    let out=j_object();cg_j_text(out,"error",cg_error);return out;
}
fn ca_find(rows,id) {
    let i=0;while i<cg_count(rows) {let row=cg_at(rows,i);if m_eq(load64(row),id) {return row;}i=i+1;}
    return 0;
}
fn ca_face_transform(frame) {
    let axes=load64(frame);let origin=load64(frame+8);
    let out=ca_identity();let axis=0;
    while axis<3 {
        let column=0;
        while column<3 {
            store64(out+(axis*3+column)*8,load64(load64(axes+column*8)+axis*8)/1000);
            column=column+1;
        }
        store64(out+72+axis*8,load64(origin+axis*8));axis=axis+1;
    }
    return out;
}
fn ca_mate_face(part,instance,selector) {
    let face_ref=cfa_reference(selector);
    if !face_ref || cg_error {return 0;}
    if !instance || !part || !load64(instance+24) {
        return cg_fail("A planar face requires a part occurrence");
    }
    if !m_eq(load64(face_ref),j_string(part,"node")) {
        return cg_fail(m_cat("Face source is no longer the part output: ",load64(face_ref)));
    }
    let frame=cfa_body_frame(face_ref,load64(instance+24));
    if cg_error {return 0;}
    return ca_face_transform(frame);
}
fn ca_mate_frame(parts,instance,mate,side) {
    let offset=j_get(mate,m_cat(side,"_frame"));
    let face=j_get(mate,m_cat(side,"_face"));
    let reference=j_get(mate,m_cat(side,"_datum"));
    if !reference && !face {return ca_frame(offset);}
    let part=0;
    if instance {
        part=load64(instance+56);
        if !part {
            let part_id=load64(instance+48);
            part=load64(parts+16);
            while part && !m_eq(j_string(part,"id"),part_id) {part=load64(part+24);}
        }
    }
    if face {
        let frame=0;
        if reference {cg_fail("Choose either a named datum or a planar face");}
        else {frame=ca_mate_face(part,instance,face);}
        if !frame || cg_error {
            let label=m_cat(j_string(mate,"id"),m_cat(" (",m_cat(side,"): ")));
            cg_error=m_cat("Broken face on mate ",m_cat(label,cg_error));
            return ca_identity();
        }
        return ca_product(frame,ca_frame(offset));
    }
    let id=j_string(mate,m_cat(side,"_datum"));
    let frame=0;
    let datums=j_get(part,"datums");
    if m_len(id) && m_len(id)<=80 && j_kind(datums)==3 && cg_j_count(datums)<=24 {
        let datum=load64(datums+16);
        while datum {
            if m_eq(j_string(datum,"id"),id) {
                if frame {cg_fail(m_cat("Ambiguous datum on mate ",j_string(mate,"id")));return ca_identity();}
                frame=datum;
            }
            datum=load64(datum+24);
        }
    }
    if !frame {
        cg_fail(m_cat("Broken datum on mate ",m_cat(j_string(mate,"id"),m_cat(": ",id))));
        return ca_identity();
    }
    return ca_product(ca_frame(frame),ca_frame(offset));
}
// Internal assembly: component array and mate array. Components retain local
// prototype polygons; evaluation never replaces these with posed geometry.
fn ca_compile(source) {
    return ca_compile_profiled(source,0);
}
fn ca_compile_profiled(source,report) {
    let prototypes=cg_compile_profiled(source,report);
    return ca_compile_prototypes(source,prototypes);
}
fn ca_compile_prototypes(source,prototypes) {
    let out=m_take(16);let components=cg_array();let mates=cg_array();
    store64(out,components);store64(out+8,mates);
    if cg_error {return out;}
    let document=j_get(source,"assembly");let limit=16;
    let layout=cah_expand(source);if cg_error {return out;}
    if layout {document=layout;limit=32;}
    let instances=j_get(document,"instances");let definitions=j_get(document,"mates");
    if j_kind(document)!=4 || j_kind(instances)!=3 || cg_j_count(instances)<1 || cg_j_count(instances)>limit || j_kind(definitions)!=3 || cg_j_count(definitions)!=cg_j_count(instances) {
        cg_fail("Assemblies need 1-16 instances and exactly one incoming mate per instance");return out;
    }
    let p=load64(instances+16);
    while p && !cg_error {
        let id=j_string(p,"id");let part=ca_find(prototypes,j_string(p,"part"));let definition=0;
        if layout {definition=j_integer(j_get(layout,"assembly_definitions"),j_string(p,"assembly"));}
        if (!layout && (!cg_id(id) || j_get(p,"assembly"))) || m_eq(id,"world") || ca_find(components,id) || (!part && !definition) {
            cg_fail("Instances need unique IDs (not world) and an existing part or assembly definition");return out;
        }
        let row=m_take(96);store64(row,id);let name=j_string(p,"name");let color=j_string(p,"color");
        if m_len(name)>96 || (m_len(color) && !cg_color(color)) {cg_fail("Invalid instance name or color");return out;}
        let shape=0;
        if part {shape=load64(part+24);if !m_len(color) {color=load64(part+16);}}
        let parent_path="";if layout {parent_path=cah_parent(id);}
        if !m_len(name) {
            name=id;
            if m_len(parent_path) {name=id+m_len(parent_path)+1;}
        }
        store64(row+8,name);store64(row+16,color);store64(row+24,shape);
        store64(row+32,0);store64(row+40,0);store64(row+48,j_string(p,"part"));store64(row+56,definition);
        store64(row+64,p);store64(row+72,0);store64(row+80,0);store64(row+88,0);
        if m_len(parent_path) {store64(row+72,ca_find(components,parent_path));}
        cg_push(components,row);p=load64(p+24);
    }
    // Keys identify individual occurrences, including copies inside subassemblies.
    let pins=j_get(j_get(source,"assembly"),"fixed_instances");
    if pins {
        if j_kind(pins)!=4 || cg_j_count(pins)>cg_count(components) {cg_fail("Invalid fixed assembly instances");return out;}
        let pin=load64(pins+16);
        while pin && !cg_error {
            let component=ca_find(components,load64(pin+32));
            if !component || load64(component+88) {cg_fail("Unknown or duplicate fixed instance");return out;}
            store64(component+88,ca_held(pin));pin=load64(pin+24);
        }
        if cg_error {return out;}
    }
    let patterned=cap_frames(document,components,layout);
    if cg_error {return out;}
    p=load64(definitions+16);
    while p && !cg_error {
        let id=j_string(p,"id");let type=j_string(p,"type");let parent_id=j_string(p,"parent");
        let parent=ca_find(components,parent_id);let child=ca_find(components,j_string(p,"child"));
        let axes=cam_axes(type);
        if (!layout && !cg_id(id)) || ca_find(mates,id)
            || (!axes && !m_eq(type,"fixed") && !m_eq(type,"revolute") && !m_eq(type,"slider") && !m_eq(type,"screw")) {
            cg_fail("Mates need unique IDs and a supported type");return out;
        }
        if (!parent && !m_eq(parent_id,"world")) || !child || child==parent || load64(child+32) {cg_fail("Invalid mate parent/child or multiple incoming mates");return out;}
        let row=m_take(144);store64(row,id);store64(row+8,type);store64(row+16,parent);store64(row+24,child);
        store64(row+72,0);store64(row+80,0);store64(row+88,1000000);store64(row+96,0);store64(row+104,j_get(p,"drive"));
        store64(row+112,j_integer(j_get(layout,"locked"),id));
        store64(row+120,0);store64(row+128,0);
        store64(row+136,j_get(p,"parent_face") || j_get(p,"child_face"));
        let parts=j_get(source,"parts");
        let binding=j_integer(patterned,load64(child));let hold=j_get(p,"held_transform");
        if hold {
            if binding {cg_fail("Pattern members cannot suppress their incoming mate");return out;}
            let placement=ca_held(hold);if !placement {return out;}
            store64(row+120,placement);store64(row+104,0);
        }else {
            if binding {
                if !m_eq(type,"fixed") || parent!=load64(binding) || j_get(p,"parent_datum") || j_get(p,"child_datum")
                    || j_get(p,"parent_frame") || j_get(p,"child_frame") || load64(row+136) {
                    cg_fail("Pattern members require a fixed mate to the seed with frames supplied by the pattern");return out;
                }
                store64(row+32,load64(binding+8));store64(row+40,ca_identity());
            }else {
                store64(row+32,ca_mate_frame(parts,parent,p,"parent"));
                if cg_error {return out;}
                store64(row+40,ca_inverse(ca_mate_frame(parts,child,p,"child")));
                if cg_error {return out;}
            }
            let limits=j_get(p,"limits");
            if axes {
                if j_get(p,"drive") || j_get(p,"pitch") {cg_fail("Multi-axis mates cannot use a scalar drive or screw pitch");return out;}
                store64(row+128,cam_coordinates(axes,limits,j_get(p,"value")));
            }else {
                let low=0;let high=0;let value=0;
                if m_eq(type,"fixed") {
                    if limits || j_get(p,"value") || j_get(p,"drive") {cg_fail("Fixed mates have no limits or driven value");return out;}
                }
                else {
                    if j_kind(limits)!=3 || cg_j_count(limits)!=2 {cg_fail("Moving mates require explicit [minimum,maximum] limits");return out;}
                    let v=load64(limits+16);low=cg_number(v);high=cg_number(load64(v+24));
                    if j_get(p,"value") {value=cg_number(j_get(p,"value"));}
                    if low>high || (!j_get(p,"drive") && (value<low || value>high)) {cg_fail("Mate value is outside its ordered travel limits");return out;}
                }
                if m_eq(type,"screw") {
                    let pitch=cg_number(j_get(p,"pitch"));
                    if cg_abs(pitch)<10000 {cg_fail("Screw pitch must be nonzero, at least 0.01 mm per revolution");return out;}
                    store64(row+72,pitch);
                }
                else if j_get(p,"pitch") {cg_fail("Only screw mates accept a pitch");return out;}
                let drive=j_get(p,"drive");
                if drive {
                    if j_kind(drive)!=4 || (!layout && !cg_id(j_string(drive,"mate"))) || j_get(p,"value") {cg_fail("Driven mates require a drive mate ID and cannot specify a value");return out;}
                    if j_get(drive,"ratio") {store64(row+88,cg_number(j_get(drive,"ratio")));}
                    if j_get(drive,"offset") {store64(row+96,cg_number(j_get(drive,"offset")));}
                }
                store64(row+48,low);store64(row+56,high);store64(row+64,value);
            }
        }
        store64(child+32,row);cg_push(mates,row);p=load64(p+24);
    }
    let i=0;
    while i<cg_count(mates) && !cg_error {
        let row=cg_at(mates,i);let drive=load64(row+104);
        if drive {
            let driver=ca_find(mates,j_string(drive,"mate"));
            if driver && load64(driver+120) {cg_fail(m_cat("A mate drive references suppressed mate ",load64(driver)));return out;}
            if !driver || m_eq(load64(driver+8),"fixed") {cg_fail("Mate drives must reference moving mates");return out;}
            if load64(driver+128) {cg_fail("Scalar drives must reference a single-axis moving mate");return out;}
            store64(row+80,driver);
        }
        i=i+1;
    }
    i=0;
    while i<cg_count(mates) && !cg_error {
        let cursor=cg_at(mates,i);let count=0;
        while cursor && count<cg_count(mates) {cursor=load64(cursor+80);count=count+1;}
        if cursor {cg_fail("Mate drives contain a cycle");return out;}i=i+1;
    }
    return out;
}
fn ca_validate_pose(assembly,pose) {
    if pose && j_kind(pose)!=4 {return cg_fail("Assembly pose must be an object keyed by mate ID");}
    let p=0;if pose {p=load64(pose+16);}
    while p && !cg_error {
        let mate=ca_find(load64(assembly+8),load64(p+32));
        if mate && load64(mate+120) {return cg_fail("A suppressed mate cannot be overridden");}
        if !mate || m_eq(load64(mate+8),"fixed") {return cg_fail("Pose keys must name moving mates");}
        if load64(mate+112) {return cg_fail("A rigid subassembly mate cannot be overridden");}
        if load64(mate+80) {return cg_fail("Driven mate values are derived and cannot be overridden");}
        let coordinates=load64(mate+128);
        if coordinates {
            if j_kind(p)!=4 || cg_j_count(p)!=cg_count(coordinates) {
                return cg_fail("Pose must name every movement coordinate of a multi-axis mate");
            }
            let i=0;
            while i<cg_count(coordinates) && !cg_error {
                let row=cg_at(coordinates,i);let key=load64(row);let at=cg_number(j_get(p,key));
                if at<load64(row+8) || at>load64(row+16) {return cg_fail(m_cat("Pose exceeds mate travel limits for ",key));}
                i=i+1;
            }
        }else {
            let value=cg_number(p);
            if value<load64(mate+48) || value>load64(mate+56) {return cg_fail("Pose exceeds mate travel limits");}
        }
        p=load64(p+24);
    }
    let mates=load64(assembly+8);let i=0;
    while i<cg_count(mates) && !cg_error {ca_value(cg_at(mates,i),pose);i=i+1;}
    return !cg_error;
}
fn ca_value(mate,pose) {
    if cg_error || load64(mate+120) || load64(mate+128) {return 0;}
    let value=load64(mate+64);let driver=load64(mate+80);
    if driver {value=ca_value(driver,pose)*load64(mate+88)/1000000+load64(mate+96);}
    else {let supplied=j_get(pose,load64(mate));if supplied {value=cg_number(supplied);}}
    if value<load64(mate+48) || value>load64(mate+56) {cg_fail("Mate drive or pose exceeds travel limits");return 0;}
    return value;
}
fn ca_motion(mate,pose) {
    let coordinates=load64(mate+128);let type=load64(mate+8);
    if coordinates {
        let supplied=j_get(pose,load64(mate));let values=cg_v(0,0,0);let i=0;
        while i<cg_count(coordinates) {
            let row=cg_at(coordinates,i);let at=load64(row+24);
            if supplied {at=cg_number(j_get(supplied,load64(row)));}
            store64(values+i*8,at);i=i+1;
        }
        let a=load64(values);let b=load64(values+8);let c=load64(values+16);
        if m_eq(type,"cylindrical") {return ca_transform(cg_v(0,0,a),cg_v(0,0,b));}
        if m_eq(type,"planar") {return ca_transform(cg_v(a,b,0),cg_v(0,0,c));}
        return ca_transform(cg_v(0,0,0),values);
    }
    let t=ca_identity();let value=ca_value(mate,pose);let angle=value;
    if m_eq(type,"slider") || m_eq(type,"screw") {store64(t+88,value);}
    if m_eq(type,"screw") {let pitch=load64(mate+72);angle=(value%pitch)*360000000/pitch;}
    if m_eq(type,"revolute") || m_eq(type,"screw") {
        let c=cg_cos(angle/1000);let s=cg_sin(angle/1000);
        store64(t,c);store64(t+8,-s);store64(t+24,s);store64(t+32,c);
    }
    return t;
}
fn ca_place(shape,t) {
    let out=cg_array();let i=0;
    while i<cg_count(shape) && !cg_error {
        let vertices=cg_array();let old=load64(cg_at(shape,i));let j=0;
        while j<cg_count(old) && !cg_error {
            let v=ca_point(t,cg_at(old,j));let k=0;
            while k<3 {if cg_abs(load64(v+k*8))>500000000 {cg_fail("Assembly pose exceeds +/-500 mm");}k=k+1;}
            cg_push(vertices,v);j=j+1;
        }
        // Preserve convex polygon faces for BSP checks. Tessellation happens
        // once at the output boundary, rather than multiplying coplanar faces.
        cg_push(out,cg_poly(vertices));
        i=i+1;
    }
    return out;
}
// Map a resolved mate parent into the coordinate frame of its containing
// assembly. Walking stored local poses avoids deriving them from rounded
// world placements, so rotated copies have identical local definitions.
fn ca_within(row,scope) {
    if !row || row==scope {return ca_identity();}
    if !scope {return load64(row+40);}
    return ca_product(ca_within(load64(row+72),scope),load64(row+80));
}
fn ca_try_place(row,pose) {
    let mate=load64(row+32);let parent=load64(mate+16);let scope=load64(row+72);
    let placement=load64(mate+120);
    if load64(row+40) || (scope && !load64(scope+40)) || (!placement && parent && !load64(parent+40)) {return 0;}
    if !placement {
        let own=ca_product(load64(mate+32),ca_product(ca_motion(mate,pose),load64(mate+40)));
        placement=ca_product(ca_within(parent,scope),own);
    }
    let pin=load64(row+88);
    if pin {
        let local=pin;
        if scope {local=ca_product(ca_inverse(load64(scope+40)),pin);}
        store64(row+80,local);store64(row+40,pin);
        return 1;
    }
    store64(row+80,placement);
    if scope {placement=ca_product(load64(scope+40),placement);}
    store64(row+40,placement);
    return 1;
}
fn ca_resolve(assembly,pose) {
    if cg_error || !ca_validate_pose(assembly,pose) {return 0;}
    let rows=load64(assembly);let i=0;
    while i<cg_count(rows) {store64(cg_at(rows,i)+40,0);i=i+1;}
    let resolved=0;let pass=0;
    while resolved<cg_count(rows) && pass<cg_count(rows) && !cg_error {
        i=0;
        while i<cg_count(rows) && !cg_error {
            let row=cg_at(rows,i);let mate=load64(row+32);
            if !mate {cg_fail("Every instance must have an incoming mate");return 0;}
            resolved=resolved+ca_try_place(row,pose);
            i=i+1;
        }
        pass=pass+1;
    }
    if resolved!=cg_count(rows) {cg_fail("Assembly mates contain a cycle or an ungrounded component");return 0;}
    return !cg_error;
}
fn ca_evaluate(assembly,pose) {
    let solids=cg_array();if !ca_resolve(assembly,pose) {return solids;}
    let rows=load64(assembly);let i=0;
    while i<cg_count(rows) && !cg_error {
        let row=cg_at(rows,i);
        if !load64(row+56) {
            let solid=m_take(32);store64(solid,load64(row));store64(solid+8,load64(row+8));store64(solid+16,load64(row+16));
            store64(solid+24,ca_place(load64(row+24),load64(row+40)));cg_push(solids,solid);
        }
        i=i+1;
    }
    return solids;
}
fn ca_bounds(shape) {
    let out=m_take(48);let k=0;
    while k<3 {store64(out+k*8,500000001);store64(out+24+k*8,-500000001);k=k+1;}
    let i=0;while i<cg_count(shape) && !cg_error {
        let verts=load64(cg_at(shape,i));let j=0;
        while j<cg_count(verts) && !cg_error {
            if !cg_step() {return out;}
            let v=cg_at(verts,j);k=0;
            while k<3 {let n=load64(v+k*8);if n<load64(out+k*8) {store64(out+k*8,n);}if n>load64(out+24+k*8) {store64(out+24+k*8,n);}k=k+1;}
            j=j+1;
        }
        i=i+1;
    }
    return out;
}
fn ca_overlap(a,b) {
    let k=0;while k<3 {
        // Face/edge contact is not positive-volume interference.
        if load64(a+24+k*8)<=load64(b+k*8) || load64(b+24+k*8)<=load64(a+k*8) {return 0;}k=k+1;
    }
    return 1;
}
fn ca_volume(shape) {
    let volume=0;if !cg_count(shape) {return 0;}
    // Translate near the origin to reduce cancellation in tiny overlaps.
    let origin=cg_at(load64(cg_at(shape,0)),0);let i=0;
    while i<cg_count(shape) && !cg_error {
        let verts=load64(cg_at(shape,i));let a=cg_sub(cg_at(verts,0),origin);let j=2;
        while j<cg_count(verts) && !cg_error {
            if !cg_step() {return 0;}
            volume=volume+cg_volume(a,cg_sub(cg_at(verts,j-1),origin),cg_sub(cg_at(verts,j),origin));j=j+1;
        }
        i=i+1;
    }
    return volume;
}
// Collision passes use the same splitter tree for each use of a solid.
// The clip mutates private copies, so one candidate pair cannot affect another.
fn ca_collision_tree(entry) {
    let polys=load64(load64(entry)+24);
    if load64(entry+16)==1 {return cg_tree_from(polys);}
    let tree=load64(entry+24);
    if !tree {tree=cg_tree_from(polys);store64(entry+24,tree);}
    return cg_tree_copy(tree);
}
fn ca_check(solids) {
    let result=j_object();let pairs=j_array();let candidates=cg_array();
    let total=cg_count(solids);let entries=m_take(total*32);let i=0;
    while i<total && !cg_error {
        let entry=entries+i*32;let solid=cg_at(solids,i);
        store64(entry,solid);store64(entry+8,ca_bounds(load64(solid+24)));
        store64(entry+16,0);store64(entry+24,0);i=i+1;
    }
    i=0;
    while i<total && !cg_error {
        let a=entries+i*32;let j=i+1;
        while j<total && !cg_error {
            if !cg_step() {return ca_error();}
            let b=entries+j*32;
            if ca_overlap(load64(a+8),load64(b+8)) {
                let pair=m_take(16);store64(pair,a);store64(pair+8,b);cg_push(candidates,pair);
                store64(a+16,load64(a+16)+1);store64(b+16,load64(b+16)+1);
            }
            j=j+1;
        }
        i=i+1;
    }
    i=0;
    while i<cg_count(candidates) && !cg_error {
        let pair=cg_at(candidates,i);let a=load64(pair);let b=load64(pair+8);
        let left=ca_collision_tree(a);let right=ca_collision_tree(b);
        if cg_error {return ca_error();}
        let overlap=cg_intersect_trees(left,right);
        let volume=ca_volume(overlap);
        if volume<0 {cg_fail("Collision intersection has invalid orientation");}
        if volume>10 {
            let row=j_object();cg_j_text(row,"a",load64(load64(a)));cg_j_text(row,"b",load64(load64(b)));
            j_add(row,"volume_mm3",cg_json_number(volume*1000));j_add(pairs,0,row);
        }
        i=i+1;
    }
    if cg_error {return ca_error();}
    cg_j_text(result,"status","clear");if cg_j_count(pairs) {cg_j_text(result,"status","interference");}
    cg_j_text(result,"method","tessellated BSP intersection; positive volume above 0.01 mm3; contact is not interference");
    cg_j_int(result,"checked_pairs",total*(total-1)/2);cg_j_int(result,"narrow_phase_pairs",cg_count(candidates));
    j_add(result,"pairs",pairs);return result;
}
fn ca_matrix_json(t) {
    let matrix=j_array();let axis=0;
    while axis<3 {
        let row=j_array();let i=0;
        while i<3 {j_add(row,0,cg_json_number(load64(t+(axis*3+i)*8)));i=i+1;}
        j_add(row,0,cg_json_number(load64(t+72+axis*8)));j_add(matrix,0,row);axis=axis+1;
    }
    return matrix;
}
fn ca_metadata(assembly,pose) {
    let result=j_object();let components=j_array();let mates=j_array();let rows=load64(assembly);let i=0;
    while i<cg_count(rows) {
        let row=cg_at(rows,i);let entry=j_object();cg_j_text(entry,"id",load64(row));
        let definition=load64(row+56);
        if definition {
            cg_j_text(entry,"assembly",j_string(definition,"id"));
            let occurrence=load64(row+64);
            if j_get(occurrence,"configuration") {cg_j_text(entry,"configuration",j_string(occurrence,"configuration"));}
            cg_j_set(entry,"flexible",j_new(5,j_value(j_get(occurrence,"flexible"))));
        }else {cg_j_text(entry,"part",load64(row+48));}
        if load64(row+88) {cg_j_set(entry,"fixed",j_new(5,1));}
        j_add(entry,"transform",ca_matrix_json(load64(row+40)));
        if load64(row+72) {j_add(entry,"local_transform",ca_matrix_json(load64(row+80)));}
        j_add(components,0,entry);i=i+1;
    }
    let held=j_array();rows=load64(assembly+8);i=0;
    while i<cg_count(rows) {
        let row=cg_at(rows,i);let entry=j_object();cg_j_text(entry,"id",load64(row));cg_j_text(entry,"type",load64(row+8));
        let parent="world";if load64(row+16) {parent=load64(load64(row+16));}
        cg_j_text(entry,"parent",parent);cg_j_text(entry,"child",load64(load64(row+24)));
        if load64(row+120) {
            cg_j_set(entry,"suppressed",j_new(5,1));j_add(held,0,j_text(load64(row)));
        }else {
            if m_eq(load64(row+8),"revolute") {
                let frame=load64(row+32);let parent_row=load64(row+16);
                if parent_row {frame=ca_product(load64(parent_row+40),frame);}
                j_add(entry,"hinge_frame",ca_matrix_json(frame));
            }
            if load64(row+136) {
                let holder=load64(row+16);let from=load64(row+32);
                if holder {from=ca_product(load64(holder+40),from);}
                let to=ca_product(load64(load64(row+24)+40),ca_inverse(load64(row+40)));
                j_add(entry,"parent_attachment",ca_matrix_json(from));
                j_add(entry,"child_attachment",ca_matrix_json(to));
            }
            let coordinates=load64(row+128);
            if coordinates {
                let supplied=j_get(pose,load64(row));let values=j_object();let limits=j_object();let k=0;
                while k<cg_count(coordinates) {
                    let axis=cg_at(coordinates,k);let key=load64(axis);let at=load64(axis+24);
                    if supplied {at=cg_number(j_get(supplied,key));}
                    j_add(values,key,cg_json_number(at));
                    let range=j_array();j_add(range,0,cg_json_number(load64(axis+8)));j_add(range,0,cg_json_number(load64(axis+16)));
                    j_add(limits,key,range);k=k+1;
                }
                j_add(entry,"value",values);j_add(entry,"limits",limits);
            }else {
                j_add(entry,"value",cg_json_number(ca_value(row,pose)));
                j_add(entry,"minimum",cg_json_number(load64(row+48)));
                j_add(entry,"maximum",cg_json_number(load64(row+56)));
            }
            if load64(row+112) {cg_j_set(entry,"locked",j_new(5,1));}
            if load64(row+72) {j_add(entry,"pitch",cg_json_number(load64(row+72)));j_add(entry,"turns",cg_json_number(ca_value(row,pose)*1000000/load64(row+72)));}
            if load64(row+80) {cg_j_text(entry,"driven_by",load64(load64(row+80)));j_add(entry,"ratio",cg_json_number(load64(row+88)));j_add(entry,"offset",cg_json_number(load64(row+96)));}
        }
        j_add(mates,0,entry);i=i+1;
    }
    j_add(result,"instances",components);j_add(result,"mates",mates);
    if cg_j_count(held) {j_add(result,"suppressed_mates",held);}
    return result;
}
// Public APIs accept a bounded CAD document with an assembly section. Poses are
// optional objects keyed by mate ID, with scalar or named coordinate values.
fn cad_assembly(source,pose) {
    let assembly=ca_compile(source);let solids=ca_evaluate(assembly,pose);
    return ca_mesh(assembly,solids,pose);
}
fn ca_mesh(assembly,solids,pose) {
    if cg_error {return ca_error();}
    let mesh=cg_tessellate(solids);if cg_error {return ca_error();}
    if !j_value(j_get(mesh,"closed")) {cg_fail("Assembly components must be closed oriented solids");return ca_error();}
    let check=ca_check(solids);if cg_error {return ca_error();}
    let metadata=ca_metadata(assembly,pose);j_add(metadata,"collision_check",check);j_add(mesh,"assembly",metadata);return mesh;
}
fn cad_assembly_check(source,pose) {
    let assembly=ca_compile(source);let solids=ca_evaluate(assembly,pose);
    if cg_error {return ca_error();}
    // Validate topology before reporting a solid collision result.
    let mesh=cg_tessellate(solids);if cg_error {return ca_error();}
    if !j_value(j_get(mesh,"closed")) {cg_fail("Assembly components must be closed oriented solids");return ca_error();}
    return ca_check(solids);
}
// Sample both scalar and named joint coordinates along their authored ranges.
fn ca_pose_frame(mates,from,to,index,intervals) {
    let pose=j_object();let i=0;
    while i<cg_count(mates) && !cg_error {
        let mate=cg_at(mates,i);let id=load64(mate);
        if !m_eq(load64(mate+8),"fixed") && !load64(mate+80) && !load64(mate+112) && !load64(mate+120) {
            let axes=load64(mate+128);
            if axes {
                let a=j_get(from,id);let b=j_get(to,id);let values=j_object();let k=0;
                while k<cg_count(axes) {
                    let row=cg_at(axes,k);let key=load64(row);let start=load64(row+24);let end=start;
                    if a {start=cg_number(j_get(a,key));}
                    if b {end=cg_number(j_get(b,key));}
                    j_add(values,key,cg_json_number(start+(end-start)*index/intervals));k=k+1;
                }
                j_add(pose,id,values);
            }else {
                let a=ca_value(mate,from);let b=ca_value(mate,to);
                j_add(pose,id,cg_json_number(a+(b-a)*index/intervals));
            }
        }
        i=i+1;
    }
    return pose;
}
fn cad_assembly_sweep(source,from,to,samples) {
    let assembly=ca_compile(source);if cg_error {return ca_error();}
    if samples<2 || samples>17 {cg_fail("Motion checks require 2-17 uniformly spaced samples including endpoints");return ca_error();}
    if !ca_validate_pose(assembly,from) || !ca_validate_pose(assembly,to) {return ca_error();}
    let frames=j_array();let collisions=0;let index=0;let mates=load64(assembly+8);
    while index<samples && !cg_error {
        let pose=ca_pose_frame(mates,from,to,index,samples-1);
        let solids=ca_evaluate(assembly,pose);if cg_error {return ca_error();}
        let mesh=cg_tessellate(solids);if cg_error {return ca_error();}
        if !j_value(j_get(mesh,"closed")) {cg_fail("Assembly components must be closed oriented solids");return ca_error();}
        let check=ca_check(solids);if cg_error {return ca_error();}
        if m_eq(j_string(check,"status"),"interference") {collisions=collisions+1;}
        cg_j_int(check,"sample",index);j_add(check,"pose",pose);j_add(frames,0,check);index=index+1;
    }
    if cg_error {return ca_error();}
    let result=j_object();cg_j_text(result,"status","clear_at_samples");if collisions {cg_j_text(result,"status","interference");}
    cg_j_text(result,"method","Uniform joint-space sampling, not continuous collision detection");cg_j_int(result,"samples",samples);cg_j_int(result,"interfering_samples",collisions);j_add(result,"frames",frames);return result;
}
