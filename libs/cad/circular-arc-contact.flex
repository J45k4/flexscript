// Finite round-curve contact in nanometres and signed picoradians.
import "math.flex";
import "../../lib/f64-math.flex";

fn csp_radial_tangent(x,y,radius) {
    let dx=f64_from_i64(x);let dy=f64_from_i64(y);
    let distance=f64_sqrt(f64_add(f64_mul(dx,dx),f64_mul(dy,dy)));
    if !distance {return cg_v(0,f64_from_i64(1),f64_from_i64(radius));}
    return cg_v(f64_div(f64_math_neg(dy),distance),f64_div(dx,distance),distance);
}

fn csp_arc_offset(radius,angle) {
    let radians=f64_div(f64_from_i64(angle),f64_from_i64(1000000000000));
    let size=f64_from_i64(radius);
    return cg_v(f64_to_i64_round(f64_mul(size,f64_cos(radians))),f64_to_i64_round(f64_mul(size,f64_sin(radians))),0);
}

fn csp_arc_range(radius,start,sweep) {
    let first=csp_arc_offset(radius,start);let last=csp_arc_offset(radius,start+sweep);
    let range=m_take(32);store64(range,start);store64(range+8,sweep);
    store64(range+16,first);store64(range+24,last);return range;
}

fn csp_arc_distance2(x,y,endpoint) {
    let dx=x-load64(endpoint);let dy=y-load64(endpoint+8);
    return dx*dx+dy*dy;
}

fn csp_arc_limit(range,x,y) {
    let tau=6283185307180;let sweep=load64(range+8);
    let angle=0;if x || y {angle=f64_to_i64_round(f64_mul(f64_atan2(f64_from_i64(y),f64_from_i64(x)),f64_from_i64(1000000000000)));}
    let delta=angle-load64(range);if sweep<0 {delta=-delta;}
    let progress=(delta%tau+tau)%tau;
    if progress<=cg_abs(sweep) {return 0;}
    let first=load64(range+16);let last=load64(range+24);
    if (!x && !y) || csp_arc_distance2(x,y,first)<=csp_arc_distance2(x,y,last) {return first;}
    return last;
}
