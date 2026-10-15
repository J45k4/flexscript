// Exact primitive ray queries, using the same cached transforms as contacts.
// Inputs/outputs are binary32 words. Directions need not be unit length;
// returned distances are ray parameters. Zero means no hit beyond minimum.
import "layout.flex";
fn ph_ray_slab_near(origin,direction,extent) {
    if ph_lt(ph_abs(direction),0x2b8cbccc) {
        if ph_lt(extent,ph_abs(origin)) {return 0x7f7fffff;}
        return 0xff7fffff;
    }
    let a=ph_div(ph_sub(ph_neg(extent),origin),direction);
    let b=ph_div(ph_sub(extent,origin),direction);
    return ph_min(a,b);
}
fn ph_ray_slab_far(origin,direction,extent) {
    if ph_lt(ph_abs(direction),0x2b8cbccc) {
        if ph_lt(extent,ph_abs(origin)) {return 0xff7fffff;}
        return 0x7f7fffff;
    }
    let a=ph_div(ph_sub(ph_neg(extent),origin),direction);
    let b=ph_div(ph_sub(extent,origin),direction);
    return ph_max(a,b);
}
// Stable roots of a*t*t + 2*b*t + c = 0. Choose sorted near/far root.
fn ph_ray_root(a,b,c,far) {
    if !ph_lt(0x0da24260,a) {return 0;}
    let discriminant=ph_sub(ph_mul(b,b),ph_mul(a,c));
    if ph_lt(discriminant,0) {return 0;}
    let root=ph_sqrt(discriminant);
    if ph_lt(b,0) {root=ph_neg(root);}
    let q=ph_sub(ph_neg(b),root);
    if !ph_abs(q) {return 0;}
    let first=ph_div(q,a);
    let second=ph_div(c,q);
    if far {return ph_max(first,second);}
    return ph_min(first,second);
}
fn ph_ray_shape(s,ox,oy,oz,dx,dy,dz,minimum) {
    if !ph_lt(0x0da24260,ph_dot(dx,dy,dz,dx,dy,dz)) {return 0;}
    ox=ph_sub(ox,load64(s+96));oy=ph_sub(oy,load64(s+104));oz=ph_sub(oz,load64(s+112));
    let kind=load64(s+8);
    if kind==2 {
        let a=ph_dot(dx,dy,dz,dx,dy,dz);
        let b=ph_dot(ox,oy,oz,dx,dy,dz);
        let c=ph_sub(ph_dot(ox,oy,oz,ox,oy,oz),ph_mul(load64(s+72),load64(s+72)));
        let near=ph_ray_root(a,b,c,0);
        if near && !ph_lt(near,minimum) {return near;}
        let far=ph_ray_root(a,b,c,1);
        if far && !ph_lt(far,minimum) {return far;}
        return 0;
    }
    let x=ph_dot(load64(s+120),load64(s+128),load64(s+136),ox,oy,oz);
    let y=ph_dot(load64(s+144),load64(s+152),load64(s+160),ox,oy,oz);
    let z=ph_dot(load64(s+168),load64(s+176),load64(s+184),ox,oy,oz);
    let u=ph_dot(load64(s+120),load64(s+128),load64(s+136),dx,dy,dz);
    let v=ph_dot(load64(s+144),load64(s+152),load64(s+160),dx,dy,dz);
    let w=ph_dot(load64(s+168),load64(s+176),load64(s+184),dx,dy,dz);
    if kind==1 {
        let near=ph_max(ph_ray_slab_near(x,u,load64(s+72)),ph_max(ph_ray_slab_near(y,v,load64(s+80)),ph_ray_slab_near(z,w,load64(s+88))));
        let far=ph_min(ph_ray_slab_far(x,u,load64(s+72)),ph_min(ph_ray_slab_far(y,v,load64(s+80)),ph_ray_slab_far(z,w,load64(s+88))));
        if ph_lt(far,near) || ph_lt(far,minimum) {return 0;}
        if !ph_lt(near,minimum) {return near;}
        return far;
    }
    let radius=load64(s+72);let half=load64(s+80);
    let radius2=ph_mul(radius,radius);
    let best=0x7f7fffff;
    let a=ph_add(ph_mul(u,u),ph_mul(v,v));
    let b=ph_add(ph_mul(x,u),ph_mul(y,v));
    let c=ph_sub(ph_add(ph_mul(x,x),ph_mul(y,y)),radius2);
    let i=0;
    while i<2 {
        let distance=ph_ray_root(a,b,c,i);
        let height=ph_add(z,ph_mul(distance,w));
        if distance && !ph_lt(distance,minimum) && ph_lt(distance,best) && !ph_lt(half,ph_abs(height)) {best=distance;}
        if !ph_lt(ph_abs(w),0x2b8cbccc) {
            let cap=half;if !i {cap=ph_neg(cap);}
            distance=ph_div(ph_sub(cap,z),w);
            let px=ph_add(x,ph_mul(distance,u));let py=ph_add(y,ph_mul(distance,v));
            if !ph_lt(distance,minimum) && ph_lt(distance,best) && !ph_lt(radius2,ph_add(ph_mul(px,px),ph_mul(py,py))) {best=distance;}
        }
        i=i+1;
    }
    if best==0x7f7fffff {return 0;}
    return best;
}
// Return [distance bits in low32, shape ID+1 in high32], or zero on miss.
fn ph_ray_world(w,ox,oy,oz,dx,dy,dz,minimum) {
    let best=0x7f7fffff;let hit=0;let i=0;
    while i<load64(w+16) {
        let distance=ph_ray_shape(ph_shape(w,i),ox,oy,oz,dx,dy,dz,minimum);
        if distance && ph_lt(distance,best) {best=distance;hit=i+1;}
        i=i+1;
    }
    if !hit {return 0;}
    return best|(hit<<32);
}
fn ph_ray_normal_component(s,px,py,pz,axis) {
    px=ph_sub(px,load64(s+96));py=ph_sub(py,load64(s+104));pz=ph_sub(pz,load64(s+112));
    if load64(s+8)==2 {
        let inverse=ph_rsqrt(ph_dot(px,py,pz,px,py,pz));
        let value=px;if axis==1 {value=py;}else if axis==2 {value=pz;}
        return ph_mul(value,inverse);
    }
    let x=ph_dot(load64(s+120),load64(s+128),load64(s+136),px,py,pz);
    let y=ph_dot(load64(s+144),load64(s+152),load64(s+160),px,py,pz);
    let z=ph_dot(load64(s+168),load64(s+176),load64(s+184),px,py,pz);
    let nx=0;let ny=0;let nz=0;
    if load64(s+8)==1 {
        let ex=ph_abs(ph_sub(ph_abs(x),load64(s+72)));
        let ey=ph_abs(ph_sub(ph_abs(y),load64(s+80)));
        let ez=ph_abs(ph_sub(ph_abs(z),load64(s+88)));
        let sign=1065353216;
        if !ph_lt(ey,ex) && !ph_lt(ez,ex) {if ph_lt(x,0) {sign=0xbf800000;}nx=sign;}
        else if !ph_lt(ez,ey) {if ph_lt(y,0) {sign=0xbf800000;}ny=sign;}
        else {if ph_lt(z,0) {sign=0xbf800000;}nz=sign;}
    } else {
        let radial=ph_sqrt(ph_add(ph_mul(x,x),ph_mul(y,y)));
        let side_error=ph_abs(ph_sub(radial,load64(s+72)));
        let cap_error=ph_abs(ph_sub(ph_abs(z),load64(s+80)));
        if !ph_lt(side_error,cap_error) {nz=1065353216;if ph_lt(z,0) {nz=0xbf800000;}}
        else {let inverse=ph_rcp(radial);nx=ph_mul(x,inverse);ny=ph_mul(y,inverse);}
    }
    return ph_dot(load64(s+120+axis*8),load64(s+144+axis*8),load64(s+168+axis*8),nx,ny,nz);
}
