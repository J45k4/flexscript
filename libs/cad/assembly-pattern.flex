// Pattern members are authored occurrences with fixed mates. The pattern
// supplies the parent frames while the ordinary mate solver owns placement.
import "model.flex";

fn cap_axis(name) {
    if m_eq(name,"x") {return 0;}
    if m_eq(name,"y") {return 1;}
    if m_eq(name,"z") {return 2;}
    cg_fail("Circular assembly patterns require a local X, Y or Z axis");
    return 0;
}

fn cap_frame(index,axis,vector,angle) {
    let frame=ca_identity();
    let i=0;
    if !angle {
        while i<3 {store64(frame+72+i*8,load64(vector+i*8)*index);i=i+1;}
        return frame;
    }
    // Rotate about the line through the pivot in the seed frame: R*p + (pivot-R*pivot).
    let degrees=(angle*index)%360000000/1000;
    let u=(axis+1)%3;let v=(axis+2)%3;
    let c=cg_cos(degrees);let s=cg_sin(degrees);
    store64(frame+(u*3+u)*8,c);store64(frame+(u*3+v)*8,-s);
    store64(frame+(v*3+u)*8,s);store64(frame+(v*3+v)*8,c);
    let turned=ca_point(frame,vector);
    while i<3 {store64(frame+72+i*8,load64(vector+i*8)-load64(turned+i*8));i=i+1;}
    return frame;
}

fn cap_frames(document,components,scoped) {
    let by_member=j_object();let patterns=j_get(document,"patterns");
    if !patterns {return by_member;}
    let limit=15;if scoped {limit=31;}
    if j_kind(patterns)!=3 || cg_j_count(patterns)>limit {
        return cg_fail("Assembly pattern count exceeds its scope limit");
    }
    let ids=j_object();let pattern=load64(patterns+16);
    while pattern && !cg_error {
        let id=j_string(pattern,"id");let seed=ca_find(components,j_string(pattern,"seed"));
        let members=j_get(pattern,"members");let count=0;
        if j_kind(members)==3 {count=cg_j_count(members);}
        if ((!scoped && !cg_id(id)) || (scoped && !cah_path_id(id))) || j_get(ids,id) || !seed || j_kind(members)!=3 || count<1 || count>15 {
            return cg_fail("An assembly pattern needs a unique ID, existing seed and 1-15 ordered members");
        }
        cg_j_int(ids,id,1);
        let kind=j_string(pattern,"kind");let step=0;let axis=0;let angle=0;
        if m_eq(kind,"linear") {
            step=cg_vector(j_get(pattern,"step"),0);
            let x=load64(step);let y=load64(step+8);let z=load64(step+16);
            if x*x+y*y+z*z<1000000 {return cg_fail("Linear pattern spacing must be at least 0.001 mm");}
        }else if m_eq(kind,"circular") {
            step=cg_vector(j_get(pattern,"pivot"),0);axis=cap_axis(j_string(pattern,"axis"));
            angle=cg_number(j_get(pattern,"angle_deg"));
            if !angle || angle%1000 || cg_abs(angle)>=360000000 {
                return cg_fail("Use a nonzero circular pattern angle in steps of 0.001° within one turn");
            }
        }else {return cg_fail("Assembly patterns must be linear or circular");}
        let member=load64(members+16);let index=1;
        while member && !cg_error {
            cg_step();
            let occurrence=0;
            if j_kind(member)==2 {occurrence=ca_find(components,j_value(member));}
            if !occurrence || occurrence==seed || !m_eq(load64(occurrence+48),load64(seed+48))
                || load64(occurrence+56)!=load64(seed+56) || j_get(by_member,load64(occurrence)) {
                return cg_fail("Pattern members must be distinct occurrences of the same part as the seed");
            }
            if angle && (angle*index)%360000000==0 {return cg_fail("Circular pattern repeats an angular position");}
            let frame=cap_frame(index,axis,step,angle);
            let binding=m_take(16);store64(binding,seed);store64(binding+8,frame);
            cg_j_int(by_member,load64(occurrence),binding);
            member=load64(member+24);index=index+1;
        }
        pattern=load64(pattern+24);
    }
    return by_member;
}
