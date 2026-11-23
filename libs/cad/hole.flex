// Cylindrical hole features in an earlier body's local axes. Pattern copies
// share the same axis and depth, and remain distinct cuts.
import "csg.flex";

fn ch_axis(id) {
    if m_eq(id,"x") || m_eq(id,"-x") {return 0;}
    if m_eq(id,"y") || m_eq(id,"-y") {return 1;}
    if m_eq(id,"z") || m_eq(id,"-z") {return 2;}
    cg_fail("Choose a signed local X, Y or Z hole axis");
    return 0;
}

fn ch_pair(row) {
    if j_kind(row)!=3 || cg_j_count(row)!=2 {return cg_fail("Hole coordinates need two numbers in the transverse plane");}
    let first=load64(row+16);
    return cg_v(cg_number(first),cg_number(load64(first+24)),0);
}

fn ch_axial_bounds(body,axis) {
    let lo=500000000;let hi=-500000000;
    let i=0;
    while i<cg_count(body) && !cg_error {
        let vertices=load64(cg_at(body,i));let j=0;
        while j<cg_count(vertices) && !cg_error {
            cg_step();let v=load64(cg_at(vertices,j)+axis*8);
            if v<lo {lo=v;}
            if v>hi {hi=v;}
            j=j+1;
        }
        i=i+1;
    }
    return cg_v(lo,hi,0);
}

fn ch_cutter(cylinder,axis,u,v,bottom) {
    let out=cg_array();let i=0;
    while i<cg_count(cylinder) && !cg_error {
        let original=load64(cg_at(cylinder,i));
        let vertices=cg_array();let j=0;
        while j<cg_count(original) && !cg_error {
            let p=cg_at(original,j);let q=cg_v(0,0,0);
            store64(q+axis*8,load64(p+16)+bottom);
            store64(q+(axis+1)%3*8,load64(p)+u);
            store64(q+(axis+2)%3*8,load64(p+8)+v);
            cg_push(vertices,q);
            j=j+1;
        }
        cg_push(out,cg_poly(vertices));
        i=i+1;
    }
    return out;
}

// Use the existing micrometre volume calculation near the intersection.
fn ch_volume(body) {
    if !cg_count(body) {return 0;}
    let origin=cg_at(load64(cg_at(body,0)),0);
    let volume=0;let i=0;
    while i<cg_count(body) && !cg_error {
        let p=load64(cg_at(body,i));
        let a=cg_sub(cg_at(p,0),origin);let j=2;
        while j<cg_count(p) && !cg_error {
            cg_step();
            volume=volume+cg_volume(a,cg_sub(cg_at(p,j-1),origin),cg_sub(cg_at(p,j),origin));
            j=j+1;
        }
        i=i+1;
    }
    return volume;
}

fn ch_hole(body,node,segments) {
    if !cg_count(body) {return cg_fail("A hole needs a nonempty earlier body");}
    let direction=j_string(node,"axis");
    let axis=ch_axis(direction);
    let center=ch_pair(j_get(node,"center"));
    let radius=cg_number(j_get(node,"diameter"))/2;
    if cg_error {return 0;}
    if radius<10000 {return cg_fail("Hole diameter must be at least 0.02 mm");}
    let interval=ch_axial_bounds(body,axis);
    let minimum=load64(interval);let maximum=load64(interval+8);
    let margin=25000;
    let bottom=minimum-margin;let top=maximum+margin;
    let mode=j_string(node,"depth_mode");
    if m_eq(mode,"depth") {
        let depth=cg_number(j_get(node,"depth"));
        if cg_error {return 0;}
        if depth<10000 || depth>=maximum-minimum {
            return cg_fail("Fixed hole depth must be at least 0.01 mm and shorter than the body's axial span");
        }
        if m_len(direction)==2 {bottom=maximum-depth;}
        else {top=minimum+depth;}
    }else if !m_eq(mode,"through") {
        return cg_fail("Choose a through hole or a fixed-depth hole");
    }else if j_get(node,"depth") {
        return cg_fail("Through holes derive depth from the input body");
    }

    let pattern=j_get(node,"pattern");
    let copies=1;let step=cg_v(0,0,0);
    if pattern {
        if j_kind(pattern)!=4 || !m_eq(j_string(pattern,"kind"),"linear") {
            return cg_fail("Choose a linear hole pattern");
        }
        copies=j_integer(pattern,"count");
        if copies<2 || copies>8 {return cg_fail("Hole patterns support two to eight cuts");}
        step=ch_pair(j_get(pattern,"step"));
        if cg_error {return 0;}
        let u=load64(step);let v=load64(step+8);let gap=radius*2+1000;
        if u*u+v*v<gap*gap {return cg_fail("Hole pattern spacing must keep the cuts separate");}
    }

    let cylinder=cg_cylinder(radius,top-bottom,segments);
    let tools=cg_array();
    let copy=0;
    while copy<copies && !cg_error {
        let u=load64(center)+copy*load64(step);let v=load64(center+8)+copy*load64(step+8);
        if cg_abs(u)+radius>500000000 || cg_abs(v)+radius>500000000 {
            return cg_fail("The hole tool exceeds the +/-500 mm transverse bounds");
        }
        let cutter=ch_cutter(cylinder,axis,u,v,bottom);
        // A wholly outside tool can still split coplanar faces in BSP.
        // Measure the actual intersection instead of comparing mesh sums.
        let removed=cg_boolean(body,cutter,"intersect");
        if cg_error {return 0;}
        if ch_volume(removed)<2 {return cg_fail(m_cat("Hole cut removes no measurable material at pattern position ",m_int(copy+1)));}
        // Disjoint cylinders form one tool; a single subtraction avoids
        // cutting the previous holes again for every patterned copy.
        cg_join(tools,cutter);
        copy=copy+1;
    }
    if cg_error {return 0;}
    let result=cg_boolean(body,tools,"subtract");
    if !cg_error && !cg_count(result) {return cg_fail("The hole removes the entire body");}
    return result;
}
