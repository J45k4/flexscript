// Local outward face normals identify a convex edge independently of its
// position and the triangles that represent it. Planes are resolved on rebuild.
import "convex.flex";

fn cet_plane(planes,reference) {
    if j_kind(reference)!=3 || cg_j_count(reference)!=3 {
        return cg_fail("An edge face requires a three-number outward normal");
    }
    let direction=cg_vector(reference,0);
    let i=0;
    while i<3 {
        if cg_abs(load64(direction+i*8))>1000000 {
            return cg_fail("Edge face normal components must be between -1 and 1");
        }
        i=i+1;
    }
    if cg_error {return 0;}
    let normal=cg_normal(direction);
    if !normal {return cg_fail("Edge face normal must have a direction");}
    let found=0;i=0;
    while i<cg_count(planes) && !cg_error {
        let plane=cg_at(planes,i);cg_step();
        if cc_close(load64(plane+8),normal,10000) {
            if found {return cg_fail("Edge face reference is ambiguous; choose the source faces again");}
            found=plane;
        }
        i=i+1;
    }
    if !found {return cg_fail("Edge face reference is missing; choose the source faces again");}
    return found;
}

fn cet_contact(face,other,spread) {
    let lo=500000000000;let hi=-500000000000;let depth=0;
    let n=load64(other+8);let d=load64(other+16);
    let vertices=load64(face);let i=0;
    // The representative polygon can be one of several coplanar triangles.
    // The caller takes the extrema over all polygons on the selected face.
    while i<cg_count(vertices) && !cg_error {
        cg_step();
        let point=cg_at(vertices,i);let distance=d-cg_dot(n,point);
        if distance<=100 {
            let along=cg_dot(spread,point);
            if along<lo {lo=along;}
            if along>hi {hi=along;}
        }
        if distance>depth {depth=distance;}
        i=i+1;
    }
    return cg_v(lo,hi,depth);
}

fn cet_fits(body,a,b,required) {
    let line=cg_normal(cg_cross(load64(a+8),load64(b+8)));
    let lo=500000000000;let hi=-500000000000;let first=0;let second=0;let i=0;
    while i<cg_count(body) && !cg_error {
        let face=cg_at(body,i);cg_step();
        if cc_same_plane(a,face) {
            let span=cet_contact(face,b,line);
            if load64(span)<lo {lo=load64(span);}
            if load64(span+8)>hi {hi=load64(span+8);}
            if load64(span+16)>first {first=load64(span+16);}
        }
        if cc_same_plane(b,face) {
            let span=cet_contact(face,a,line);
            if load64(span+16)>second {second=load64(span+16);}
        }
        i=i+1;
    }
    if cg_error {return 0;}
    if hi-lo<10000 {return cg_fail("Selected source faces no longer share an edge");}
    if first<required+1000 || second<required+1000 {
        return cg_fail("Edge treatment would consume a selected face; reduce the dimension");
    }
    return 1;
}

// Work with a linear combination of the two supporting planes. For the
// chamfer, gap is the sum-plane reduction for the equal setbacks. For an
// offset-circle tangent the normalized plane moves inward by
// radius * ((weight_a + weight_b) / length - 1).
fn cet_slice_plane(a,b,weight_a,weight_b,gap,radius) {
    let n=load64(a+8);let m=load64(b+8);
    let x=(load64(n)*weight_a+load64(m)*weight_b)/1000000000;
    let y=(load64(n+8)*weight_a+load64(m+8)*weight_b)/1000000000;
    let z=(load64(n+16)*weight_a+load64(m+16)*weight_b)/1000000000;
    let length=cg_sqrt(x*x+y*y+z*z);
    let normal=cg_v(x*1000000000/length,y*1000000000/length,z*1000000000/length);
    let d=load64(a+16)*weight_a+load64(b+16)*weight_b;
    d=(d-gap*weight_b-radius*(weight_a+weight_b-length))/length;
    return cg_v(normal,d,0);
}
fn cet_slice(body,a,b,weight_a,weight_b,gap,radius) {
    let plane=cet_slice_plane(a,b,weight_a,weight_b,gap,radius);
    return cc_clip(body,load64(plane),load64(plane+8));
}

fn cet_feature(body,node,rounded,segments) {
    let operation="Chamfer";
    if rounded {operation="Fillet";}
    let size=cg_number(j_get(node,"size"));
    if cg_error {return 0;}
    if size<10000 {return cg_fail(m_cat(operation," dimension must be at least 0.01 mm"));}
    let planes=cc_planes(body,operation);
    if cg_error {return 0;}
    let low=cg_v(500000000,500000000,500000000);let high=cg_v(-500000000,-500000000,-500000000);
    if !cc_outer_bounds(body,planes,low,high,operation) {return 0;}
    let a=cet_plane(planes,j_get(node,"face_a"));
    let b=cet_plane(planes,j_get(node,"face_b"));
    if cg_error {return 0;}
    let cosine=cg_dot(load64(a+8),load64(b+8));
    if cg_abs(cosine)>985000000 {return cg_fail("Choose two distinct source faces with a usable edge angle");}
    let sine=cg_sqrt(1000000000000000000-cosine*cosine);
    let setback=size*sine/1000000000;
    if rounded {setback=size*(1000000000-cosine)/1000000000;}
    if !cet_fits(body,a,b,setback) {return 0;}
    if !rounded {return cet_slice(body,a,b,500000000,500000000,setback,0);}
    let divisions=segments/4;
    if divisions<4 {divisions=4;}
    let i=1;let out=body;
    while i<divisions && !cg_error {
        let weight=i*1000000000/divisions;
        out=cet_slice(out,a,b,1000000000-weight,weight,0,size);
        i=i+1;
    }
    return out;
}
