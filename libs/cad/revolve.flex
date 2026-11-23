// Revolve a sketch around a local axis using positively oriented radial rings.
import "sketch.flex";

fn cr_outline(profile,around_x,segments) {
    let circle=load64(profile+8);
    if circle {
        let data=cs_circle(profile);
        if !data {return 0;}
        let center=load64(data);let radius=load64(data+8);
        let r=load64(center);let z=load64(center+8);
        if around_x {r=load64(center+8);z=load64(center);}
        if r<=radius {return cg_fail("A revolved circle must lie strictly on the positive side of its axis");}
        if r+radius>500000000 || cg_abs(z)+radius>500000000 {
            return cg_fail("Revolved circles must stay within +/-500 mm");
        }
        let ring=cg_array();let i=0;
        while i<segments && !cg_error {
            let theta=i*360000/segments;
            cg_push(ring,cg_v(r+radius*cg_cos(theta)/1000000,z+radius*cg_sin(theta)/1000000,0));
            i=i+1;
        }
        return ring;
    }
    let sketch=cs_outline(load64(profile));
    if !sketch || cg_error {return 0;}
    let ring=sketch;
    if around_x {
        ring=cg_array();
        let i=cg_count(sketch)-1;
        while i>=0 && !cg_error {
            let p=cg_at(sketch,i);
            cg_push(ring,cg_v(load64(p+8),load64(p),0));
            i=i-1;
        }
    }
    let count=cg_count(ring);let i=0;
    while i<count && !cg_error {
        let p=cg_at(ring,i);
        if load64(p)<0 {return cg_fail("Revolve profile crosses or lies on the negative side of its axis");}
        if !load64(p) && load64(cg_at(ring,(i+count-1)%count)) && load64(cg_at(ring,(i+1)%count)) {
            return cg_fail("Revolve profile touches its axis at an isolated point");
        }
        i=i+1;
    }
    return ring;
}

fn cr_vertex(profile,cosine,sine,around_x) {
    let radius=load64(profile);let axial=load64(profile+8);
    let u=radius*cosine/1000000;let v=radius*sine/1000000;
    if around_x {return cg_v(axial,u,v);}
    return cg_v(u,axial,-v);
}

fn cr_slice(profile,angle,around_x) {
    let points=cg_array();let i=0;
    let cosine=cg_cos(angle);let sine=cg_sin(angle);
    while i<cg_count(profile) && !cg_error {
        cg_push(points,cr_vertex(cg_at(profile,i),cosine,sine,around_x));
        i=i+1;
    }
    return points;
}

fn cr_face(out,a,b,c,d) {
    let before=cg_count(out);
    cg_face(out,a,b,c,d);
    if cg_count(out)==before {return cg_fail("A revolve facet collapsed; increase the sweep or profile dimensions");}
    return !cg_error;
}

fn cr_band(out,profile,left,right) {
    let count=cg_count(profile);let i=0;
    while i<count && !cg_error {
        let j=(i+1)%count;
        let a=load64(cg_at(profile,i));let b=load64(cg_at(profile,j));
        if a && b {
            cr_face(out,cg_at(left,i),cg_at(right,i),cg_at(right,j),cg_at(left,j));
        }else if a {
            cr_face(out,cg_at(left,i),cg_at(right,i),cg_at(left,j),0);
        }else if b {
            cr_face(out,cg_at(left,i),cg_at(right,j),cg_at(left,j),0);
        }
        i=i+1;
    }
    return !cg_error;
}

fn cr_cap(out,triangles,angle,around_x,reverse) {
    let i=0;let cosine=cg_cos(angle);let sine=cg_sin(angle);
    while i<cg_count(triangles) && !cg_error {
        let face=cg_at(triangles,i);
        let a=cr_vertex(load64(face),cosine,sine,around_x);
        let b=cr_vertex(load64(face+8),cosine,sine,around_x);
        let c=cr_vertex(load64(face+16),cosine,sine,around_x);
        if reverse {cr_face(out,c,b,a,0);}
        else {cr_face(out,a,b,c,0);}
        i=i+1;
    }
    return !cg_error;
}

fn cr_revolve(profile,axis,angle,segments) {
    let out=cg_array();
    if !profile {cg_fail("Revolve refers to a missing sketch");return out;}
    let around_x=m_eq(axis,"x");
    if !around_x && !m_eq(axis,"y") {cg_fail("Choose the local X or Y revolve axis");return out;}
    if !angle || cg_abs(angle)>360000000 || angle%1000 {
        cg_fail("Use a nonzero revolve angle within +/-360 degrees, in 0.001 degree steps");
        return out;
    }
    let ring=cr_outline(profile,around_x,segments);
    if !ring || cg_error {return out;}
    let sweep=cg_abs(angle)/1000;let start=0;
    if angle<0 && sweep<360000 {start=-sweep;}
    let steps=(segments*sweep+359999)/360000;
    let first=cr_slice(ring,start,around_x);
    let left=first;let i=1;
    while i<=steps && !cg_error {
        let right=first;
        if i<steps || sweep<360000 {right=cr_slice(ring,start+sweep*i/steps,around_x);}
        cr_band(out,ring,left,right);
        left=right;i=i+1;
    }
    if sweep<360000 && !cg_error {
        let caps=cs_triangles(ring);
        if caps && !cg_error {
            cr_cap(out,caps,start,around_x,0);
            cr_cap(out,caps,start+sweep,around_x,1);
        }
    }
    return out;
}
