// Exact spline evaluation in nanometres and trillionths of a cubic segment.
import "project-line-spline.flex";
import "bounded-polynomial.flex";

fn psb_parameter(segment,t) {
    return segment*1000000000000+f64_to_i64_round(f64_mul(t,f64_from_i64(1000000000000)));
}

fn psb_fraction(value) {return f64_div(f64_from_i64(value),f64_from_i64(1000000000000));}

fn psb_store_controls(out,source,segment) {
    return psb_store_controls_with_workspace(out,source,segment,m_take(48));
}
fn psb_store_controls_with_workspace(out,source,segment,data) {
    if !pc_spline_segment(source,segment,data) {return 0;}
    let a=load64(data);let d=load64(data+8);let axis=0;
    while axis<16 {
        let first=f64_from_i64(load64(a+axis));let last=f64_from_i64(load64(d+axis));
        store64(out+axis,first);store64(out+48+axis,last);
        store64(out+16+axis,f64_add(first,load64(data+16+axis)));
        store64(out+32+axis,f64_sub(last,load64(data+32+axis)));axis=axis+8;
    }
    return 1;
}

fn psb_mix(a,b,t) {return f64_add(a,f64_mul(f64_sub(b,a),t));}

fn psb_coordinate(curve,axis,t) {
    let ab=psb_mix(load64(curve+axis),load64(curve+16+axis),t);
    let bc=psb_mix(load64(curve+16+axis),load64(curve+32+axis),t);
    let cd=psb_mix(load64(curve+32+axis),load64(curve+48+axis),t);
    return psb_mix(psb_mix(ab,bc,t),psb_mix(bc,cd,t),t);
}

fn psb_velocity(curve,axis,t) {
    let ab=f64_sub(load64(curve+16+axis),load64(curve+axis));
    let bc=f64_sub(load64(curve+32+axis),load64(curve+16+axis));
    let cd=f64_sub(load64(curve+48+axis),load64(curve+32+axis));
    return f64_mul(f64_from_i64(3),psb_mix(psb_mix(ab,bc,t),psb_mix(bc,cd,t),t));
}

fn psb_acceleration(curve,axis,t) {
    let ab=f64_sub(load64(curve+16+axis),load64(curve+axis));
    let bc=f64_sub(load64(curve+32+axis),load64(curve+16+axis));
    let cd=f64_sub(load64(curve+48+axis),load64(curve+32+axis));
    return f64_mul(f64_from_i64(6),psb_mix(f64_sub(bc,ab),f64_sub(cd,bc),t));
}

// The physical point, rather than a new saved segment parameter, identifies a
// contact. Compare all finite spans and retain the first authored branch on ties.
fn psb_consider(best,x,y,segment,t,locked) {
    let px=pls_polynomial(x,t);let py=pls_polynomial(y,t);
    let one=f64_from_i64(1);
    if locked==1 && f64_lt(one,f64_magnitude(px)) || locked==2 && f64_lt(one,f64_magnitude(py)) {return 1;}
    let distance=pls_linear(px,py,px,py);
    if f64_lt(distance,load64(best+8)) {
        store64(best,psb_parameter(segment,t));store64(best+8,distance);
        store64(best+16,segment);store64(best+24,t);store64(best+32,px);store64(best+40,py);
    }
    return 1;
}

fn psb_axis_coincident(values) {
    let limit=f64_from_i64(1);let roundoff=0x3eb0c6f7a0b5ed8d; // One millionth of a nanometre.
    return !f64_lt(limit,f64_magnitude(load64(values))) && !f64_lt(roundoff,f64_magnitude(load64(values+8))) &&
        !f64_lt(roundoff,f64_magnitude(load64(values+16))) && !f64_lt(roundoff,f64_magnitude(load64(values+24)));
}

fn psb_nearest_workspace_size() {return 304+pab_root_workspace_size(6);}

fn psb_nearest(source,point,locked) {
    return psb_nearest_with_workspace(source,point,locked,m_take(psb_nearest_workspace_size()));
}

fn psb_endpoint_bound(source,point,locked) {
    let points=load64(source);let step=load64(source+16);let nearest=f64_inf(0);let index=0;
    while index<cg_count(points) {
        let vertex=cg_at(points,index);let dx=load64(vertex)-load64(point);let dy=load64(vertex+8)-load64(point+8);
        if (!locked || locked==1 && !dx || locked==2 && !dy) {
            let squared=f64_from_i64(dx*dx+dy*dy);if f64_lt(squared,nearest) {nearest=squared;}
        }
        index=index+step;
    }
    return nearest;
}

// All cubic positions are inside the control hull. Use a slightly expanded
// box so roundoff on the controls or a tied endpoint cannot exclude a span.
fn psb_hull_axis(values) {
    let low=load64(values);let high=low;let i=8;
    while i<32 {
        let v=load64(values+i);if f64_lt(v,low) {low=v;}if f64_lt(high,v) {high=v;}
        i=i+8;
    }
    let gap=0;if f64_lt(0,low) {gap=low;}if f64_lt(high,0) {gap=f64_math_neg(high);}
    let margin=0x3f50624dd2f1a9fc; // 0.001 nanometres.
    if f64_lt(margin,gap) {return f64_sub(gap,margin);}return 0;
}

fn psb_hull_reaches(x,y,bound,locked) {
    let dx=psb_hull_axis(x);let dy=psb_hull_axis(y);let one=f64_from_i64(1);
    if locked==1 && f64_lt(one,dx) || locked==2 && f64_lt(one,dy) {return 0;}
    return f64_le(pls_linear(dx,dy,dx,dy),bound);
}

fn psb_nearest_with_workspace(source,point,locked,workspace) {
    let one=f64_from_i64(1);let best=workspace;store64(best+8,f64_inf(0));
    let cubic=best+48;let x=cubic+48;let y=x+32;
    let square=y+32;let derivative=square+56;let roots=derivative+48;let isolate=roots+40;
    let index=0;let bound=psb_endpoint_bound(source,point,locked);
    while index<load64(source+8) && !cg_error {
        if !cg_step() || !pc_spline_segment(source,index,cubic) {return 0;}
        pls_controls(x,cubic,point,one,0);pls_controls(y,cubic,point,0,one);
        if psb_hull_reaches(x,y,bound,locked) {
            pls_coefficients(x,one);pls_coefficients(y,one);
            let fixed=0;if locked==1 {fixed=x;}if locked==2 {fixed=y;}
            let count=0;
            if fixed && !psb_axis_coincident(fixed) {
                count=pab_roots_with_workspace(roots,fixed,4,0,one,isolate);
            }else {
                pab_coefficients(square,x,y,4);
                let i=1;while i<7 {store64(derivative+(i-1)*8,f64_mul(f64_from_i64(i),load64(square+i*8)));i=i+1;}
                count=pab_roots_with_workspace(roots,derivative,6,0,one,isolate);
            }
            let i=0;psb_consider(best,x,y,index,0,locked);
            while i<count {psb_consider(best,x,y,index,load64(roots+i*8),locked);i=i+1;}
            psb_consider(best,x,y,index,one,locked);
            let distance=load64(best+8);if f64_lt(distance,bound) {bound=distance;}
        }
        index=index+1;
    }
    if cg_error || !f64_is_finite(load64(best+8)) {return 0;}
    return best;
}

fn psb_contact_point(hit,target) {
    return cg_v(load64(target)+f64_to_i64_round(load64(hit+32)),load64(target+8)+f64_to_i64_round(load64(hit+40)),0);
}

fn psb_pick(source,point,tolerance) {
    let hit=psb_nearest(source,point,0);if !hit {return 0;}
    let distance=load64(hit+8);
    if f64_lt(f64_from_i64(tolerance*tolerance),distance) {return 0;}
    return cg_v(load64(hit),f64_to_i64_round(f64_sqrt(distance)),0);
}
