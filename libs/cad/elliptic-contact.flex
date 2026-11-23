// Euclidean contacts on an ellipse, optionally restricted to a signed sweep.
import "bounded-polynomial.flex";
import "sketch-ellipse-support.flex";
import "math.flex";

fn cso_range(rx,ry,rotation,start,sweep) {
    return cg_v(cse_support_axes(rx,ry,rotation),start,sweep);
}
fn cso_angle(radians) {return f64_to_i64_round(f64_mul(radians,f64_from_i64(1000000000000)));}
fn cso_radians(angle) {return f64_div(f64_from_i64(angle),f64_from_i64(1000000000000));}
fn cso_contains(range,angle) {
    let tau=6283185307180;let sweep=load64(range+16);
    if !sweep || cg_abs(sweep)==tau {return 1;}
    let delta=angle-load64(range+8);if sweep<0 {delta=-delta;}
    let progress=(delta%tau+tau)%tau;
    return progress<=cg_abs(sweep)+1 || tau-progress<=1;
}
fn cso_local(range,x,y) {
    let axes=load64(range);let c=load64(axes+16);let s=load64(axes+24);
    let dx=f64_from_i64(x);let dy=f64_from_i64(y);
    return cg_v(f64_add(f64_mul(dx,c),f64_mul(dy,s)),f64_sub(f64_mul(dy,c),f64_mul(dx,s)),0);
}
fn cso_phase(range,local) {
    let axes=load64(range);
    let u=f64_div(load64(local),load64(axes));let v=f64_div(load64(local+8),load64(axes+8));
    return cso_angle(f64_atan2(v,u));
}
fn cso_offset(range,angle) {
    let axes=load64(range);let radians=cso_radians(angle);
    let u=f64_mul(load64(axes),f64_cos(radians));let v=f64_mul(load64(axes+8),f64_sin(radians));
    let c=load64(axes+16);let s=load64(axes+24);
    return cg_v(f64_sub(f64_mul(u,c),f64_mul(v,s)),f64_add(f64_mul(u,s),f64_mul(v,c)),angle);
}
fn cso_tangent(range,angle) {
    let axes=load64(range);let radians=cso_radians(angle);
    let u=f64_math_neg(f64_mul(load64(axes),f64_sin(radians)));
    let v=f64_mul(load64(axes+8),f64_cos(radians));
    let speed=f64_sqrt(f64_add(f64_mul(u,u),f64_mul(v,v)));
    let c=load64(axes+16);let s=load64(axes+24);
    return cg_v(f64_div(f64_sub(f64_mul(u,c),f64_mul(v,s)),speed),
        f64_div(f64_add(f64_mul(u,s),f64_mul(v,c)),speed),speed);
}
fn cso_quantize(point) {
    return cg_v(f64_to_i64_round(load64(point)),f64_to_i64_round(load64(point+8)),load64(point+16));
}
fn cso_consider(best,range,x,y,angle) {
    if !cso_contains(range,angle) {return 0;}
    let point=cso_offset(range,angle);
    let dx=f64_sub(load64(point),x);let dy=f64_sub(load64(point+8),y);
    let distance=f64_add(f64_mul(dx,dx),f64_mul(dy,dy));
    if !load64(best) || f64_lt(distance,load64(best+8)) {
        store64(best,point);store64(best+8,distance);
    }
    return 1;
}

// Stationary distances satisfy a quartic in two bounded half-angle charts.
// Include both endpoints because the closest point may be outside the sweep
// on the supporting ellipse. The start wins an exact endpoint tie.
fn cso_nearest(range,x,y) {
    let local=cso_local(range,x,y);let phase=cso_phase(range,local);
    let near=cso_quantize(cso_offset(range,phase));
    let dx=x-load64(near);let dy=y-load64(near+8);
    if cso_contains(range,phase) && dx*dx+dy*dy<=1 {return near;}
    let tx=f64_from_i64(x);let ty=f64_from_i64(y);let best=cg_v(0,0,0);
    let start=load64(range+8);let sweep=load64(range+16);
    cso_consider(best,range,tx,ty,start);
    if sweep {cso_consider(best,range,tx,ty,start+sweep);}
    let axes=load64(range);let rx=load64(axes);let ry=load64(axes+8);
    let local_x=load64(local);let local_y=load64(local+8);
    let scale=rx;if scale<ry {scale=ry;}
    if scale<f64_magnitude(local_x) {scale=f64_magnitude(local_x);}
    if scale<f64_magnitude(local_y) {scale=f64_magnitude(local_y);}
    let a=f64_div(rx,scale);let b=f64_div(ry,scale);
    let ax=f64_mul(a,f64_div(local_x,scale));let by=f64_mul(b,f64_div(local_y,scale));
    let diff=f64_sub(f64_mul(b,b),f64_mul(a,a));
    let coeff=m_take(40);let roots=m_take(32);let one=f64_from_i64(1);let two=f64_from_i64(2);let pass=0;
    while pass<2 {
        store64(coeff,f64_math_neg(by));store64(coeff+8,f64_mul(two,f64_add(diff,ax)));
        store64(coeff+16,0);store64(coeff+24,f64_mul(two,f64_sub(ax,diff)));store64(coeff+32,by);
        let n=pab_roots(roots,coeff,5,f64_math_neg(one),one);let i=0;
        while i<n {
            let angle=f64_mul(two,f64_atan2(load64(roots+i*8),one));
            if pass {angle=f64_add(angle,0x400921fb54442d18);}
            cso_consider(best,range,tx,ty,cso_angle(angle));i=i+1;
        }
        ax=f64_math_neg(ax);by=f64_math_neg(by);pass=pass+1;
    }
    return cso_quantize(load64(best));
}

// An affine dimension may lock one coordinate. Intersect that coordinate
// line with the ellipse analytically and choose the nearest retained root.
fn cso_locked_axis(range,x,y,move_x) {
    let axes=load64(range);let c=load64(axes+16);let s=load64(axes+24);
    let first=c;let second=f64_math_neg(s);let fixed=x;
    if move_x {first=s;second=c;fixed=y;}
    let a=f64_mul(first,load64(axes));let b=f64_mul(second,load64(axes+8));
    let value=f64_from_i64(fixed);
    let extent=f64_sqrt(f64_add(f64_mul(a,a),f64_mul(b,b)));
    let magnitude=f64_magnitude(value);
    if f64_lt(f64_add(extent,f64_from_i64(1)),magnitude) {return 0;}
    if f64_lt(extent,magnitude) {magnitude=extent;}
    let h=f64_sqrt(f64_mul(f64_sub(extent,magnitude),f64_add(extent,magnitude)));
    let phase=f64_atan2(b,a);let offset=f64_atan2(h,value);
    let best=cg_v(0,0,0);let tx=f64_from_i64(x);let ty=f64_from_i64(y);
    // A saved affine coordinate may lie within a nanometre of an exact
    // endpoint even if the corresponding ellipse root is just off-sweep.
    let sweep=load64(range+16);
    if sweep {
        let i=0;let coordinate=0;if move_x {coordinate=8;}
        while i<2 {
            let angle=load64(range+8)+i*sweep;
            let point=cso_offset(range,angle);
            if cg_abs(f64_to_i64_round(load64(point+coordinate))-fixed)<=1 {cso_consider(best,range,tx,ty,angle);}
            i=i+1;
        }
    }
    cso_consider(best,range,tx,ty,cso_angle(f64_sub(phase,offset)));
    cso_consider(best,range,tx,ty,cso_angle(f64_add(phase,offset)));
    if !load64(best) {return 0;}
    return cso_quantize(load64(best));
}
