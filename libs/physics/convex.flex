// Minkowski portal refinement, adapted from libccd src/mpr.c (Daniel Fiser,
// 2010-2012), BSD licensed; retain licenses/libccd-BSD.txt with distributions.
// Ordinary Flexscript support mapping and bounded binary32 arithmetic are
// shared by CPU, Wasm and GPU. No native collision library is called.
import "epa.flex";
// Exact support points for boxes, spheres and circular finite cylinders.
fn ph_support(s,d,out,t) {
    ph_unrotate(t,s+120,d);
    let kind=load64(s+8);
    let x=load64(t);
    let y=load64(t+8);
    let z=load64(t+16);
    if kind==1 {
        let axis=0;
        while axis<3 {
            let value=load64(t+axis*8);
            let extent=load64(s+72+axis*8);
            let coordinate=0;
            if ph_lt(0,value) {
                coordinate=extent;
            }
            else if ph_lt(value,0) {
                coordinate=ph_neg(extent);
            }
            store64(t+24+axis*8,coordinate);
            axis=axis+1;
        }
    }
    else if kind==2 {
        ph_scale(t+24,t,ph_mul(load64(s+72),ph_rsqrt(ph_vdot(t,t))));
    }
    else {
        let radial=ph_add(ph_mul(x,x),ph_mul(y,y));
        let scale=ph_mul(load64(s+72),ph_rsqrt(radial));
        let cap=0;
        if ph_lt(0,z) {
            cap=load64(s+80);
        }
        else if ph_lt(z,0) {
            cap=ph_neg(load64(s+80));
        }
        ph_vset(t+24,ph_mul(x,scale),ph_mul(y,scale),cap);
    }
    ph_rotate(out,s+120,t+24);
    return ph_vadd(out,out,s+96);
}
fn ph_cylinder_sphere(cylinder,sphere,p) {
    let t=p+512;
    ph_vsub(t,sphere+96,cylinder+96);
    ph_unrotate(t+24,cylinder+120,t);
    let x=load64(t+24);
    let y=load64(t+32);
    let z=load64(t+40);
    let radius=load64(cylinder+72);
    let half=load64(cylinder+80);
    let radial=ph_sqrt(ph_add(ph_mul(x,x),ph_mul(y,y)));
    let scale=1065353216;
    if ph_lt(radius,radial) {
        scale=ph_div(radius,radial);
    }
    ph_vset(t+48,ph_mul(x,scale),ph_mul(y,scale),ph_clamp(z,ph_neg(half),half));
    ph_vsub(t+72,t+24,t+48);
    let distance=ph_sqrt(ph_vdot(t+72,t+72));
    let depth=ph_sub(load64(sphere+72),distance);
    if ph_lt(depth,0) {
        return 0;
    }
    if ph_lt(radius,radial) || ph_lt(half,ph_abs(z)) {
        if !ph_lt(0x1e3ce508,distance) {
            store64(p+15984,11);
            return -1;
        }
        ph_scale(t+72,t+72,ph_rcp(distance));
    }
    else {
        let side=ph_sub(radius,radial);
        let cap=ph_sub(half,ph_abs(z));
        ph_vset(t+72,0,0,0);
        if ph_lt(cap,side) {
            let sign=1065353216;
            if ph_lt(z,0) {
                sign=0xbf800000;
            }
            store64(t+88,sign);
            store64(t+64,ph_mul(sign,half));
            depth=ph_add(load64(sphere+72),cap);
        }
        else {
            let nx=1065353216;
            let ny=0;
            if ph_lt(0x1e3ce508,radial) {
                nx=ph_div(x,radial);
                ny=ph_div(y,radial);
            }
            ph_vset(t+72,nx,ny,0);
            ph_vset(t+48,ph_mul(nx,radius),ph_mul(ny,radius),z);
            depth=ph_add(load64(sphere+72),side);
        }
    }
    ph_rotate(p+15000,cylinder+120,t+72);
    ph_rotate(t+96,cylinder+120,t+48);
    ph_vadd(t+96,t+96,cylinder+96);
    ph_mad(t+120,sphere+96,p+15000,ph_neg(load64(sphere+72)));
    ph_vadd(p+15024,t+96,t+120);
    ph_scale(p+15024,p+15024,1056964608);
    store64(p+15048,depth);
    return 1;
}
// Parallel finite cylinders are an exact disk/interval product. This also
// handles concentric cylinders, where a curved EPA polytope converges slowly.
fn ph_parallel_cylinders(a,b,p) {
    let t=p+512;
    ph_cross(t,a+168,b+168);
    if ph_lt(0x2b8cbccc,ph_vdot(t,t)) {
        return -2;
    }
    let axis=t+24;
    ph_normalize(axis,a+168);
    let delta=t+48;
    ph_vsub(delta,b+96,a+96);
    let z=ph_vdot(delta,axis);
    let radial=t+72;
    ph_mad(radial,delta,axis,ph_neg(z));
    let distance=ph_sqrt(ph_vdot(radial,radial));
    let ra=load64(a+72);
    let rb=load64(b+72);
    let ha=load64(a+80);
    let hb=load64(b+80);
    let side=ph_sub(ph_add(ra,rb),distance);
    let cap=ph_sub(ph_add(ha,hb),ph_abs(z));
    if ph_lt(side,0) || ph_lt(cap,0) {
        return 0;
    }
    let direction=t+96;
    if ph_lt(0x1e3ce508,distance) {
        ph_scale(direction,radial,ph_rcp(distance));
    }
    else {
        ph_normalize(direction,a+120);
    }
    let radial_position=0;
    let axial_position=0;
    if ph_lt(cap,side) {
        let sign=1065353216;
        if ph_lt(z,0) {
            sign=0xbf800000;
        }
        ph_scale(p+15000,axis,sign);
        radial_position=ph_mul(ph_add(ph_max(0,ph_sub(distance,rb)),ph_min(ra,distance)),1056964608);
        axial_position=ph_mul(ph_add(z,ph_mul(sign,ph_sub(ha,hb))),1056964608);
        store64(p+15048,cap);
    }
    else {
        ph_vcopy(p+15000,direction);
        radial_position=ph_mul(ph_add(ra,ph_sub(distance,rb)),1056964608);
        axial_position=ph_mul(ph_add(ph_max(ph_neg(ha),ph_sub(z,hb)),ph_min(ha,ph_add(z,hb))),1056964608);
        store64(p+15048,side);
    }
    ph_mad(p+15024,a+96,direction,radial_position);
    ph_mad(p+15024,p+15024,axis,axial_position);
    return 1;
}
// A support record is [Minkowski point, shape A witness, shape B witness].
fn ph_mpr_copy(out,p) {
    let i=0;
    while i<9 {
        store64(out+i*8,load64(p+i*8));
        i=i+1;
    }
    return out;
}
fn ph_mpr_support(a,b,d,out,t) {
    ph_scale(t,d,0xbf800000);
    ph_support(a,d,out+24,t+24);
    ph_support(b,t,out+48,t+24);
    return ph_vsub(out,out+24,out+48);
}
fn ph_mpr_direction(p,d,t) {
    ph_vsub(t,p+144,p+72);
    ph_vsub(t+24,p+216,p+72);
    ph_cross(d,t,t+24);
    let length=ph_vdot(d,d);
    if !ph_finite(length) || !ph_lt(0x0da24260,length) {
        return 0;
    }
    ph_scale(d,d,ph_rsqrt(length));
    return 1;
}
fn ph_mpr_expand(p,d,t) {
    ph_cross(t,p+288,p);
    let slot=1;
    if ph_lt(0,ph_vdot(p+72,t)) {
        slot=3;
        if ph_lt(0,ph_vdot(p+144,t)) {
            slot=1;
        }
    }
    else if ph_lt(0,ph_vdot(p+216,t)) {
        slot=2;
    }
    return ph_mpr_copy(p+slot*72,p+288);
}
fn ph_mpr_gap(p,d) {
    let far=ph_vdot(p+288,d);
    return ph_min(ph_sub(far,ph_vdot(p+72,d)),ph_min(ph_sub(far,ph_vdot(p+144,d)),ph_sub(far,ph_vdot(p+216,d))));
}
fn ph_mpr_discover(a,b,p) {
    let d=p+512;
    let t=p+536;
    ph_vcopy(p+24,a+96);
    ph_vcopy(p+48,b+96);
    ph_vsub(p,p+24,p+48);
    if !ph_lt(0x1e3ce508,ph_vdot(p,p)) {
        // An arbitrary interior point is sufficient; avoid a zero center ray.
        store64(p,0x358637bd);
        store64(p+8,0x350637bd);
        store64(p+16,0x348637bd);
    }
    ph_scale(d,p,0xbf800000);
    ph_normalize(d,d);
    ph_mpr_support(a,b,d,p+72,p+1024);
    if ph_lt(ph_vdot(p+72,d),0) {
        return 0;
    }
    ph_cross(d,p,p+72);
    if !ph_lt(0x0da24260,ph_vdot(d,d)) {
        return 2;
    }
    ph_normalize(d,d);
    ph_mpr_support(a,b,d,p+144,p+1024);
    if ph_lt(ph_vdot(p+144,d),0) {
        return 0;
    }
    ph_vsub(t,p+72,p);
    ph_vsub(t+24,p+144,p);
    ph_cross(d,t,t+24);
    if !ph_lt(0x0da24260,ph_vdot(d,d)) {
        store64(p+15984,12);
        return -1;
    }
    ph_normalize(d,d);
    if ph_lt(0,ph_vdot(d,p)) {
        ph_mpr_copy(p+360,p+72);
        ph_mpr_copy(p+72,p+144);
        ph_mpr_copy(p+144,p+360);
        ph_scale(d,d,0xbf800000);
    }
    let iteration=0;
    while iteration<64 {
        ph_mpr_support(a,b,d,p+216,p+1024);
        if ph_lt(ph_vdot(p+216,d),0) {
            return 0;
        }
        ph_cross(t,p+72,p+216);
        let change=0;
        if ph_lt(ph_vdot(t,p),0) {
            ph_mpr_copy(p+144,p+216);
            change=1;
        }
        if !change {
            ph_cross(t,p+216,p+144);
            if ph_lt(ph_vdot(t,p),0) {
                ph_mpr_copy(p+72,p+216);
                change=1;
            }
        }
        if !change {
            return 1;
        }
        ph_vsub(t,p+72,p);
        ph_vsub(t+24,p+144,p);
        ph_cross(d,t,t+24);
        if !ph_lt(0x0da24260,ph_vdot(d,d)) {
            store64(p+15984,13);
            return -1;
        }
        ph_normalize(d,d);
        iteration=iteration+1;
    }
    store64(p+15984,14);
    return -1;
}
// Closest-point barycentrics on the portal triangle. Degenerate triangles
// fall back to their segments, avoiding division by a near-zero determinant.
fn ph_mpr_closest(p) {
    let a=p+72;
    let b=p+144;
    let c=p+216;
    let t=p+536;
    let weights=p+736;
    ph_vsub(t,b,a);
    ph_vsub(t+24,c,a);
    ph_cross(t+48,t,t+24);
    let determinant=ph_vdot(t+48,t+48);
    let u=0xbf800000;
    let v=0xbf800000;
    if ph_lt(0x0da24260,determinant) {
        ph_scale(t+72,a,0xbf800000);
        ph_cross(t+96,t+72,t+24);
        u=ph_div(ph_vdot(t+96,t+48),determinant);
        ph_cross(t+96,t,t+72);
        v=ph_div(ph_vdot(t+96,t+48),determinant);
    }
    let interior=0;
    if !ph_lt(u,0) && !ph_lt(v,0) && !ph_lt(1065353216,ph_add(u,v)) {
        interior=1;
        ph_vset(weights,ph_sub(1065353216,ph_add(u,v)),u,v);
    }
    else {
        let best=0x7f7fffff;
        let edge=0;
        while edge<3 {
            let ia=edge;
            let ib=ph_next_axis(edge);
            let pa=p+72+ia*72;
            let pb=p+72+ib*72;
            ph_vsub(t,pb,pa);
            let fraction=ph_clamp(ph_div(ph_neg(ph_vdot(pa,t)),ph_vdot(t,t)),0,1065353216);
            ph_mad(t+24,pa,t,fraction);
            let distance=ph_vdot(t+24,t+24);
            if ph_lt(distance,best) {
                best=distance;
                ph_vset(weights,0,0,0);
                store64(weights+ia*8,ph_sub(1065353216,fraction));
                store64(weights+ib*8,fraction);
            }
            edge=edge+1;
        }
    }
    ph_vset(p+704,0,0,0);
    ph_vset(p+15024,0,0,0);
    let i=0;
    while i<3 {
        let vertex=p+72+i*72;
        let weight=load64(weights+i*8);
        ph_mad(p+704,p+704,vertex,weight);
        ph_vadd(t,vertex+24,vertex+48);
        ph_mad(p+15024,p+15024,t,ph_mul(weight,1056964608));
        i=i+1;
    }
    let depth=ph_sqrt(ph_vdot(p+704,p+704));
    // An interior closest point uses the face's normalized separating
    // direction. Normalizing its tiny interpolated witness delta instead
    // amplifies F32 cancellation and destabilizes shallow resting contacts.
    if interior && ph_lt(0x33d6bf95,depth) {
        let projected=ph_vdot(p+704,p+512);
        if !ph_lt(projected,0) {
            store64(p+15048,projected);ph_vcopy(p+15000,p+512);return 1;
        }
    }
    store64(p+15048,depth);
    if ph_lt(0x33d6bf95,depth) {
        ph_scale(p+15000,p+704,ph_rcp(depth));
    }
    else {
        ph_vcopy(p+15000,p+512);
    }
    return 1;
}
// Return 1 contact, 0 separation, -1 bounded solver failure. The caller must
// surface failures rather than silently treating them as an empty collision.
fn ph_convex(a,b,p) {
    store64(p+15984,0);
    let result=ph_mpr_discover(a,b,p);
    if result<=0 {
        return result;
    }
    if result==2 {
        return ph_epa(a,b,p,1);
    }
    let d=p+512;
    let iteration=0;
    let inside=0;
    while iteration<64 {
        if !ph_mpr_direction(p,d,p+536) {
            store64(p+15984,15);
            return -1;
        }
        if !ph_lt(ph_vdot(p+72,d),0) {
            inside=1;
            iteration=64;
        }
        else {
            ph_mpr_support(a,b,d,p+288,p+1024);
            if ph_lt(ph_vdot(p+288,d),0) {
                return 0;
            }
            if !ph_lt(0x358637bd,ph_mpr_gap(p,d)) {
                return 0;
            }
            ph_mpr_expand(p,d,p+536);
            iteration=iteration+1;
        }
    }
    if !inside {
        store64(p+15984,16);
        return -1;
    }
    return ph_epa(a,b,p,0);
}
