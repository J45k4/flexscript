// Face references use the source feature, an outward direction and an
// in-plane X direction. A location can distinguish parallel face patches.
import "convex.flex";

fn cfa_basis(normal,axis) {
    let vertical=cg_normal(cg_cross(normal,axis));
    if !vertical || cg_abs(cg_dot(normal,axis))>999000000 {
        return cg_fail("Face X direction is parallel to its normal");
    }
    let horizontal=cg_normal(cg_cross(vertical,normal));
    return cg_v(horizontal,vertical,normal);
}

fn cfa_reference(plane) {
    let count=cg_j_count(plane);let location=j_get(plane,"through");
    let id=j_string(plane,"node_id");
    if j_kind(plane)!=4 || count!=4+(location!=0) || !m_eq(j_string(plane,"kind"),"face") || !cg_id(id) {
        return cg_fail("Invalid planar face reference");
    }
    let direction=cg_vector(j_get(plane,"normal"),0);
    let i=0;
    while i<3 {
        if cg_abs(load64(direction+i*8))>1000000 {return cg_fail("Face normal components must be within +/-1");}
        i=i+1;
    }
    let normal=cg_normal(direction);
    if !normal || cg_error {return cg_fail("Face normal must have a direction");}
    let key=j_string(plane,"x_axis");let axis=0;
    if m_eq(key,"x") {axis=cg_v(1000000000,0,0);}
    else if m_eq(key,"y") {axis=cg_v(0,1000000000,0);}
    else if m_eq(key,"z") {axis=cg_v(0,0,1000000000);}
    if !axis {return cg_fail("Face X direction must be X, Y or Z");}
    let basis=cfa_basis(normal,axis);
    if cg_error {return 0;}
    let witness=0;if location {witness=cg_vector(location,0);}
    if cg_error {return 0;}
    let face_ref=m_take(32);
    store64(face_ref,id);store64(face_ref+8,basis);store64(face_ref+16,axis);store64(face_ref+24,witness);
    return face_ref;
}

fn cfa_project(vertices,basis) {
    let out=cg_array();let i=0;
    while i<cg_count(vertices) && !cg_error {
        let point=cg_at(vertices,i);
        cg_push(out,cg_v(cg_dot(load64(basis),point),cg_dot(load64(basis+8),point),0));
        i=i+1;
    }
    return out;
}

fn cfa_min(a,b) {if a<b {return a;}return b;}
fn cfa_max(a,b) {if a>b {return a;}return b;}

fn cfa_contains(points,x,y) {
    let inside=0;let count=cg_count(points);let i=0;
    while i<count && !cg_error {
        cg_step();
        let a=cg_at(points,i);let b=cg_at(points,(i+1)%count);
        let ax=load64(a);let ay=load64(a+8);let bx=load64(b);let by=load64(b+8);
        let dx=bx-ax;let dy=by-ay;
        let cross=dx*(y-ay)-dy*(x-ax);
        if cg_abs(cross)<=(cg_abs(dx)+cg_abs(dy))*1000
            && x>=cfa_min(ax,bx)-1000 && x<=cfa_max(ax,bx)+1000
            && y>=cfa_min(ay,by)-1000 && y<=cfa_max(ay,by)+1000 {return 1;}
        if (ay>y)!=(by>y) && (cross>0)==(dy>0) {inside=1-inside;}
        i=i+1;
    }
    return inside;
}

fn cfa_overlap(a,b,c,d) {
    let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
    let tolerance=(cg_abs(dx)+cg_abs(dy))*1000;
    if cg_abs(dx*(load64(c+8)-load64(a+8))-dy*(load64(c)-load64(a)))>tolerance {return 0;}
    if cg_abs(dx*(load64(d+8)-load64(a+8))-dy*(load64(d)-load64(a)))>tolerance {return 0;}
    let axis=0;if cg_abs(dy)>cg_abs(dx) {axis=8;}
    let lo=cfa_max(cfa_min(load64(a+axis),load64(b+axis)),cfa_min(load64(c+axis),load64(d+axis)));
    let hi=cfa_min(cfa_max(load64(a+axis),load64(b+axis)),cfa_max(load64(c+axis),load64(d+axis)));
    return hi-lo>1000;
}

fn cfa_adjacent(a,b) {
    let i=0;
    while i<cg_count(a) && !cg_error {
        let p=cg_at(a,i);let q=cg_at(a,(i+1)%cg_count(a));let j=0;
        while j<cg_count(b) && !cg_error {
            cg_step();
            if cfa_overlap(p,q,cg_at(b,j),cg_at(b,(j+1)%cg_count(b))) {return 1;}
            j=j+1;
        }
        i=i+1;
    }
    return 0;
}

fn cfa_region(candidates,first,witness) {
    let queue=cg_array();cg_push(queue,first);store64(first+24,1);
    let i=0;
    while i<cg_count(queue) && !cg_error {
        let current=load64(cg_at(queue,i)+8);let j=0;
        while j<cg_count(candidates) && !cg_error {
            cg_step();
            let row=cg_at(candidates,j);
            if !load64(row+24) && cfa_adjacent(current,load64(row+8)) {
                store64(row+24,1);cg_push(queue,row);
            }
            j=j+1;
        }
        i=i+1;
    }
    i=0;
    while i<cg_count(candidates) && !cg_error {
        let row=cg_at(candidates,i);
        if !load64(row+24) && (!witness || load64(row+16)) {
            return cg_fail("Face reference is ambiguous across disconnected patches; choose a face location");
        }
        i=i+1;
    }
    return queue;
}

fn cfa_frame(face_ref,built) {
    let id=load64(face_ref);let body=j_value(j_get(built,id));
    if !body {return cg_fail(m_cat("Sketch face source must be an earlier feature: ",id));}
    return cfa_body_frame(face_ref,body);
}

fn cfa_body_frame(face_ref,body) {
    let basis=load64(face_ref+8);let witness=load64(face_ref+24);
    let x=0;let y=0;
    if witness {x=cg_dot(load64(basis),witness);y=cg_dot(load64(basis+8),witness);}
    let normal=load64(basis+16);let first=0;let planes=cg_array();let i=0;
    while i<cg_count(body) && !cg_error {
        let polygon=cg_at(body,i);
        cg_step();
        if cc_close(normal,load64(polygon+8),10000) {
            let points=cfa_project(load64(polygon),basis);
            let hit=!witness || cfa_contains(points,x,y);
            if hit {
                if !first {first=polygon;}
                else if !cc_same_plane(first,polygon) {
                    return cg_fail("Face reference is ambiguous across supporting planes; choose a face location");
                }
            }
            let row=m_take(32);
            store64(row,polygon);store64(row+8,points);store64(row+16,hit);store64(row+24,0);cg_push(planes,row);
        }
        i=i+1;
    }
    if cg_error {return 0;}
    if !first {return cg_fail("Face reference is missing; choose its source, normal and location again");}
    let candidates=cg_array();let seed=0;i=0;
    while i<cg_count(planes) && !cg_error {
        let row=cg_at(planes,i);
        if cc_same_plane(first,load64(row)) {
            if load64(row)==first {seed=row;}
            cg_push(candidates,row);
        }
        i=i+1;
    }
    let region=cfa_region(candidates,seed,witness);
    if cg_error {return 0;}
    let frame=cfa_basis(load64(first+8),load64(face_ref+16));
    if cg_error {return 0;}
    let u=1000000000;let v=1000000000;i=0;
    while i<cg_count(region) && !cg_error {
        let vertices=load64(load64(cg_at(region,i)));let j=0;
        while j<cg_count(vertices) && !cg_error {
            let point=cg_at(vertices,j);cg_step();
            u=cfa_min(u,cg_dot(load64(frame),point));v=cfa_min(v,cg_dot(load64(frame+8),point));
            j=j+1;
        }
        i=i+1;
    }
    let origin=cfa_point(frame,cg_v(u,v,load64(first+16)),cg_v(0,0,0));
    return cg_v(frame,origin,0);
}

fn cfa_point(frame,point,origin) {
    let u=load64(frame);let v=load64(frame+8);let n=load64(frame+16);
    let out=cg_v(0,0,0);let i=0;
    while i<3 {
        let value=(load64(u+i*8)*load64(point)+load64(v+i*8)*load64(point+8)
            +load64(n+i*8)*load64(point+16))/1000000000+load64(origin+i*8);
        if cg_abs(value)>500000000 {return cg_fail("Transformed CAD coordinates exceed +/-500 mm");}
        store64(out+i*8,value);i=i+1;
    }
    return out;
}

fn cfa_place(shape,placement) {
    let out=cg_array();let i=0;
    while i<cg_count(shape) && !cg_error {
        let original=load64(cg_at(shape,i));let vertices=cg_array();let j=0;
        while j<cg_count(original) && !cg_error {
            cg_push(vertices,cfa_point(load64(placement),cg_at(original,j),load64(placement+8)));j=j+1;
        }
        cg_push(out,cg_poly(vertices));i=i+1;
    }
    return out;
}
