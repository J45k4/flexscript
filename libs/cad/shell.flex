// Inward wall offsets for convex polyhedral bodies. The cavity intersects
// shifted face half-spaces. The rim joins the inner and outer boundaries.
import "convex.flex";

fn csh_axis(name) {
    if m_eq(name,"x") || m_eq(name,"-x") {return 0;}
    if m_eq(name,"y") || m_eq(name,"-y") {return 1;}
    if m_eq(name,"z") || m_eq(name,"-z") {return 2;}
    cg_fail("Choose the signed local X, Y or Z opening face");
    return 0;
}

fn csh_rim(out,face,planes,open,thickness) {
    // Partition the opening face into the rim and the portion inside all
    // shifted wall planes. Retain each outside strip exactly once.
    let inside=face;let i=0;
    while i<cg_count(planes) && cg_count(inside) && !cg_error {
        let raw=cg_at(planes,i);
        if raw!=open {
            let plane=m_take(24);store64(plane,0);
            store64(plane+8,load64(raw+8));store64(plane+16,load64(raw+16)-thickness);
            let on=cg_array();let remaining=cg_array();let j=0;
            while j<cg_count(inside) && !cg_error {
                cg_split(plane,cg_at(inside,j),on,on,out,remaining);
                j=j+1;
            }
            inside=remaining;
        }
        i=i+1;
    }
    if !cg_error && !cg_count(inside) {return cg_fail("Shell thickness closes the selected opening");}
    return !cg_error;
}

fn csh_boundary(body,cavity,planes,open,thickness) {
    let out=cg_array();let outer_opening=cg_array();let i=0;
    while i<cg_count(body) && !cg_error {
        let face=cg_at(body,i);
        if cc_same_plane(face,open) {cg_push(outer_opening,face);}
        else {cg_push(out,face);}
        i=i+1;
    }
    let opened=0;i=0;
    while i<cg_count(cavity) && !cg_error {
        let face=cg_at(cavity,i);
        if cc_same_plane(face,open) {opened=1;}
        else {cg_flip(face);cg_push(out,face);}
        i=i+1;
    }
    if cg_error {return 0;}
    if !opened {return cg_fail("Shell thickness closes the selected opening");}
    if !csh_rim(out,outer_opening,planes,open,thickness) {return 0;}
    return out;
}

fn csh_shell(body,node) {
    if !cg_count(body) {return cg_fail("Shell needs a nonempty earlier body");}
    let opening=j_string(node,"open_side");
    let axis=csh_axis(opening);
    let sign=1;if m_len(opening)==2 {sign=-1;}
    let thickness=cg_number(j_get(node,"thickness"));
    if cg_error {return 0;}
    if thickness<10000 {return cg_fail("Shell wall thickness must be at least 0.01 mm");}
    let planes=cc_planes(body,"Shell");
    if cg_error {return 0;}
    let lo=cg_v(500000000,500000000,500000000);let hi=cg_v(-500000000,-500000000,-500000000);
    if !cc_outer_bounds(body,planes,lo,hi,"Shell") {return 0;}
    let open=0;let i=0;
    while i<cg_count(planes) && !cg_error {
        let plane=cg_at(planes,i);let n=load64(plane+8);
        if load64(n+axis*8)*sign>=999999000 && cg_abs(load64(n+(axis+1)%3*8))<=1000
            && cg_abs(load64(n+(axis+2)%3*8))<=1000 {
            if open {return cg_fail("Shell opening face is ambiguous");}
            open=plane;
        }
        i=i+1;
    }
    if !open {return cg_fail("No planar face exists on the selected local shell side");}
    let margin=25000;
    i=0;
    while i<3 {
        store64(lo+i*8,load64(lo+i*8)-margin);store64(hi+i*8,load64(hi+i*8)+margin);i=i+1;
    }
    let cavity=cc_clip(cg_box_bounds(lo,hi),load64(open+8),load64(open+16));i=0;
    while i<cg_count(planes) && !cg_error {
        let plane=cg_at(planes,i);
        if plane!=open {
            cavity=cc_clip(cavity,load64(plane+8),load64(plane+16)-thickness);
            if !cg_error && !cg_count(cavity) {return cg_fail("Shell thickness leaves no cavity");}
        }
        i=i+1;
    }
    if cg_error {return 0;}
    return csh_boundary(body,cavity,planes,open,thickness);
}
