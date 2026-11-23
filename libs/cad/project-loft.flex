// Two-section ruled loft. Both sections contribute their original corners
// to a shared sequence of normalized perimeter distances.
import "profile.flex";

fn pc_loft_section(nodes,ref,sources) {
    let sketch=pc_find(nodes,j_string(ref,"sketchId"));
    let frame=pc_profile_frame(nodes,sketch,sources);
    if !frame {return 0;}
    let region=cad_project_profile(nodes,sketch,ref);
    if !region {return 0;}
    if cg_count(region)!=1 {return cg_fail("Loft profiles cannot have holes");}
    let points=load64(cg_at(region,0));let ring=cg_array();
    let center=cg_v(0,0,0);let i=0;
    while i<cg_count(points) && !cg_error {
        let uv=cg_at(points,i);
        let world=pc_world(frame,load64(uv),load64(uv+8),0);
        cg_push(ring,cg_v(world,uv,0));let k=0;
        while k<24 {store64(center+k,load64(center+k)+load64(world+k));k=k+8;}
        i=i+1;
    }
    if cg_error {return 0;}
    let k=0;while k<24 {store64(center+k,load64(center+k)/cg_count(points));k=k+8;}
    return cg_v(ring,frame,center);
}
fn pc_loft_parameters(ring) {
    let total=0;let i=0;let count=cg_count(ring);
    while i<count {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%count);
        store64(a+16,total);let length=cg_sqrt(cg_distance2(load64(a),load64(b)));
        if !length {return cg_fail("Loft profile has a collapsed edge");}
        total=total+length;i=i+1;
    }
    i=0;while i<count {
        let row=cg_at(ring,i);let ratio=f64_div(f64_from_i64(load64(row+16)),f64_from_i64(total));
        store64(row+16,f64_to_i64_round(f64_mul(ratio,f64_from_i64(1000000000))));i=i+1;
    }
    return 1;
}
fn pc_loft_sample(ring,next,t) {
    let n=cg_count(ring);let a=cg_at(ring,(next+n-1)%n);let b=cg_at(ring,next%n);
    let lower=load64(a+16);let upper=1000000000;if next<n {upper=load64(b+16);}
    if t-lower<1000 {return load64(a);}
    let p=load64(a);let q=load64(b);let out=cg_v(0,0,0);let k=0;
    while k<24 {
        store64(out+k,load64(p+k)+(load64(q+k)-load64(p+k))*(t-lower)/(upper-lower));k=k+8;
    }
    return out;
}
fn pc_loft_cap(out,section,reverse) {
    let ring=load64(section);let uv=cg_array();let i=0;
    while i<cg_count(ring) {cg_push(uv,load64(cg_at(ring,i)+8));i=i+1;}
    let triangles=cs_triangles(uv);let frame=load64(section+8);i=0;
    while i<cg_count(triangles) && !cg_error {
        let tri=cg_at(triangles,i);let vertices=cg_array();let j=0;
        while j<3 {
            let k=j;if reverse {k=2-j;}
            let p=load64(tri+k*8);cg_push(vertices,pc_world(frame,load64(p),load64(p+8),0));j=j+1;
        }
        cg_push(out,cg_poly(vertices));i=i+1;
    }
    return !cg_error;
}
// Each face stores its bounding box and its three inward edge half-planes.
// Shared edges and vertices are allowed. Overlap in a face interior is not.
fn pc_loft_face_info(poly) {
    let info=m_take(104);store64(info,poly);let verts=load64(poly);let j=0;
    while j<3 {
        let p=cg_at(verts,j);let q=cg_at(verts,(j+1)%3);let k=0;
        while k<24 {
            let x=load64(p+k);
            if !j || x<load64(info+8+k) {store64(info+8+k,x);}
            if !j || x>load64(info+32+k) {store64(info+32+k,x);}
            k=k+8;
        }
        let inward=cg_normal(cg_cross(load64(poly+8),cg_sub(q,p)));
        if !inward {return cg_fail("Degenerate loft facet");}
        store64(info+56+j*16,inward);store64(info+64+j*16,cg_dot(inward,p));j=j+1;
    }
    return info;
}
fn pc_loft_inside(face,point,tolerance) {
    let i=0;while i<3 {
        if cg_dot(load64(face+56+i*16),point)-load64(face+64+i*16)<tolerance {return 0;}
        i=i+1;
    }
    return 1;
}
fn pc_loft_separated(face,vertices) {
    let i=0;
    while i<3 {
        let plane=face+56+i*16;let j=0;
        while j<3 && cg_dot(load64(plane),cg_at(vertices,j))-load64(plane+8)<=4 {j=j+1;}
        if j==3 {return 1;}i=i+1;
    }
    return 0;
}
fn pc_loft_face_crosses(face,other) {
    let poly=load64(face);let verts=load64(load64(other));let normal=load64(poly+8);let offset=load64(poly+16);
    let pos=0;let neg=0;let i=0;
    while i<3 {
        let a=cg_at(verts,i);let b=cg_at(verts,(i+1)%3);
        let da=cg_dot(normal,a)-offset;let db=cg_dot(normal,b)-offset;
        if da>4 {pos=1;}else if da< -4 {neg=1;}else if pc_loft_inside(face,a,5) {return 1;}
        if (da>4 && db< -4) || (da< -4 && db>4) {
            let t=da*1000000000/(da-db);let hit=cg_v(0,0,0);let k=0;
            while k<24 {store64(hit+k,load64(a+k)+(load64(b+k)-load64(a+k))*t/1000000000);k=k+8;}
            let corners=load64(poly);let j=0;
            while j<3 && cg_distance2(hit,cg_at(corners,j))>64 {j=j+1;}
            if j==3 && pc_loft_inside(face,hit,-3) {return 1;}
        }
        i=i+1;
    }
    if !pos && !neg {
        return !pc_loft_separated(face,verts) && !pc_loft_separated(other,load64(poly));
    }
    return 0;
}
fn pc_loft_validate(shape) {
    let infos=cg_array();let i=0;
    while i<cg_count(shape) && !cg_error {
        let face=pc_loft_face_info(cg_at(shape,i));if !face {return 0;}
        let j=0;while j<i {
            if !cg_step() {return 0;}
            let other=cg_at(infos,j);let k=0;
            while k<24 && load64(face+8+k)<=load64(other+32+k)+4 && load64(other+8+k)<=load64(face+32+k)+4 {k=k+8;}
            if k==24 && (pc_loft_face_crosses(face,other) || pc_loft_face_crosses(other,face)) {
                return cg_fail("Loft surface intersects itself");
            }
            j=j+1;
        }
        cg_push(infos,face);i=i+1;
    }
    return !cg_error;
}
fn pc_loft(nodes,feature,sources) {
    let refs=j_get(feature,"profiles");
    if j_kind(refs)!=3 || cg_j_count(refs)!=2 {return cg_fail("Loft needs exactly two profiles");}
    let op=j_string(feature,"operation");
    if !m_eq(op,"newBody") && !m_eq(op,"join") {return cg_fail("Loft operation must be newBody or join");}
    let first=pc_loft_section(nodes,pc_first(refs),sources);if !first {return 0;}
    let second=pc_loft_section(nodes,load64(pc_first(refs)+24),sources);if !second {return 0;}
    let delta=cg_sub(load64(second+16),load64(first+16));
    if cg_distance2(load64(first+16),load64(second+16))<10000 {return cg_fail("Loft profiles must not share a centre");}
    let fa=load64(first+8);let fb=load64(second+8);
    let da=cg_dot(load64(fa+24),delta);if load64(fa+32) {da=-da;}
    let db=cg_dot(load64(fb+24),delta);if load64(fb+32) {db=-db;}
    if !da || !db {return cg_fail("Loft profile is edge-on to the loft direction");}
    let a=load64(first);let original=load64(second);let n=cg_count(original);
    let b=cg_array();let best=-1;let start=0;let i=0;let reverse=(da>0)!=(db>0);
    while i<n {
        let k=i;if reverse {k=n-1-i;}
        let d=cg_distance2(load64(cg_at(a,0)),load64(cg_at(original,k)));
        if best<0 || d<best {best=d;start=k;}i=i+1;
    }
    i=0;while i<n {
        let k=(start+i)%n;if reverse {k=(start+n-i)%n;}
        cg_push(b,cg_at(original,k));i=i+1;
    }
    if !pc_loft_parameters(a) || !pc_loft_parameters(b) {return 0;}
    let left=cg_array();let right=cg_array();let ia=0;let ib=0;
    while ia<cg_count(a) || ib<n {
        let ta=1000000000;let tb=1000000000;
        if ia<cg_count(a) {ta=load64(cg_at(a,ia)+16);}
        if ib<n {tb=load64(cg_at(b,ib)+16);}
        let t=ta;if tb<t {t=tb;}
        if ia<cg_count(a) && ta-t<1000 {cg_push(left,load64(cg_at(a,ia)));ia=ia+1;}
        else {cg_push(left,pc_loft_sample(a,ia,t));}
        if ib<n && tb-t<1000 {cg_push(right,load64(cg_at(b,ib)));ib=ib+1;}
        else {cg_push(right,pc_loft_sample(b,ib,t));}
    }
    let solid=cg_array();i=0;
    while i<cg_count(left) && !cg_error {
        let j=(i+1)%cg_count(left);let p=cg_at(left,i);let q=cg_at(left,j);
        let r=cg_at(right,i);let s=cg_at(right,j);
        if da>0 {cg_face(solid,p,q,s,0);cg_face(solid,p,s,r,0);}
        else {cg_face(solid,q,p,r,0);cg_face(solid,q,r,s,0);}
        i=i+1;
    }
    pc_loft_cap(solid,first,da>0);pc_loft_cap(solid,second,db<0);
    if !pc_loft_validate(solid) {return 0;}
    return solid;
}
