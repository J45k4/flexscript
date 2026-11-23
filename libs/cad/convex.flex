// Bounded half-space clipping and plane queries for convex CAD operations.
import "csg.flex";

fn cc_close(a,b,tolerance) {
    return cg_abs(load64(a)-load64(b))<=tolerance && cg_abs(load64(a+8)-load64(b+8))<=tolerance
        && cg_abs(load64(a+16)-load64(b+16))<=tolerance;
}

fn cc_planes(body,operation) {
    let planes=cg_array();
    let i=0;
    while i<cg_count(body) && !cg_error {
        let p=cg_at(body,i);
        let match=0;let j=0;
        while j<cg_count(planes) && !match && !cg_error {
            cg_step();
            match=cc_same_plane(p,cg_at(planes,j));
            j=j+1;
        }
        if !match {
            if cg_count(planes)>=48 {return cg_fail(m_cat(operation," supports at most 48 distinct supporting planes"));}
            cg_push(planes,p);
        }
        i=i+1;
    }
    return planes;
}

fn cc_outer_bounds(body,planes,lo,hi,operation) {
    let i=0;
    while i<cg_count(body) && !cg_error {
        let vertices=load64(cg_at(body,i));let j=0;
        while j<cg_count(vertices) && !cg_error {
            let p=cg_at(vertices,j);let k=0;
            while k<cg_count(planes) && !cg_error {
                cg_step();
                let plane=cg_at(planes,k);
                if cg_dot(load64(plane+8),p)-load64(plane+16)>100 {
                    return cg_fail(m_cat(operation," needs a convex input body"));
                }
                k=k+1;
            }
            k=0;
            while k<3 {
                let v=load64(p+k*8);
                if v<load64(lo+k*8) {store64(lo+k*8,v);}
                if v>load64(hi+k*8) {store64(hi+k*8,v);}
                k=k+1;
            }
            j=j+1;
        }
        i=i+1;
    }
    return !cg_error;
}

// Project onto the plane's dominant two axes and compare polar angles using
// integer quadrants and cross products. The result is a convex cap loop.
fn cc_angle_before(a,b,center) {
    let u=load64(center+16);let v=load64(center+24);
    let ax=load64(a+u*8)-load64(center);let ay=load64(a+v*8)-load64(center+8);
    let bx=load64(b+u*8)-load64(center);let by=load64(b+v*8)-load64(center+8);
    let upper_a=ay>0 || (ay==0 && ax>=0);let upper_b=by>0 || (by==0 && bx>=0);
    if upper_a!=upper_b {return upper_a;}
    let cross=ax*by-ay*bx;
    if cross {return cross>0;}
    return ax*ax+ay*ay<bx*bx+by*by;
}

fn cc_cap(points,n) {
    let count=cg_count(points);
    if count<3 {return cg_fail("Convex clip could not reconstruct a face");}
    let axis=0;let i=1;
    while i<3 {
        if cg_abs(load64(n+i*8))>cg_abs(load64(n+axis*8)) {axis=i;}
        i=i+1;
    }
    let u=(axis+1)%3;let v=(axis+2)%3;
    let sum_u=0;let sum_v=0;i=0;
    while i<count {
        let p=cg_at(points,i);sum_u=sum_u+load64(p+u*8);sum_v=sum_v+load64(p+v*8);i=i+1;
    }
    let center=m_take(32);
    store64(center,sum_u/count);store64(center+8,sum_v/count);store64(center+16,u);store64(center+24,v);
    let rows=load64(points+16);i=1;
    while i<count && !cg_error {
        let item=load64(rows+i*8);let j=i;
        while j>0 && !cg_error && cc_angle_before(item,load64(rows+(j-1)*8),center) {
            cg_step();store64(rows+j*8,load64(rows+(j-1)*8));j=j-1;
        }
        store64(rows+j*8,item);i=i+1;
    }
    let cap=cg_poly(points);
    if !cap {return cg_fail("Convex clip produced a degenerate face");}
    if load64(n+axis*8)<0 {cg_flip(cap);}
    return cap;
}

fn cc_on_plane(keep,n,d) {
    let out=cg_array();let i=0;
    while i<cg_count(keep) && !cg_error {
        let vertices=load64(cg_at(keep,i));let j=0;
        while j<cg_count(vertices) && !cg_error {
            let p=cg_at(vertices,j);
            if cg_abs(cg_dot(n,p)-d)<=100 {
                let k=0;let match=0;
                while k<cg_count(out) && !match && !cg_error {
                    cg_step();match=cc_close(p,cg_at(out,k),100);k=k+1;
                }
                if !match {cg_push(out,p);}
            }
            j=j+1;
        }
        i=i+1;
    }
    return out;
}

fn cc_clip(body,n,d) {
    let plane=m_take(24);store64(plane,0);store64(plane+8,n);store64(plane+16,d);
    let on=cg_array();let outside=cg_array();let keep=cg_array();let i=0;
    while i<cg_count(body) && !cg_error {
        cg_split(plane,cg_at(body,i),on,on,outside,keep);
        i=i+1;
    }
    if cg_error {return 0;}
    if !cg_count(outside) {return body;}
    if !cg_count(keep) {return keep;}
    let cap=cc_cap(cc_on_plane(keep,n,d),n);
    if !cg_error {cg_push(keep,cap);}
    return keep;
}

fn cc_same_plane(a,b) {
    return cc_close(load64(a+8),load64(b+8),500) && cg_abs(load64(a+16)-load64(b+16))<=100;
}
