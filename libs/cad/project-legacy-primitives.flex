// TypeScript PartBuilder samples these direct profiles in millimetres.
// Keep the seam and vertex ordinals before converting vertices to nanometres.
import "project-curves.flex";

fn plp_kind(kind) {
    return m_eq(kind,"ellipse") || m_eq(kind,"capsule") || m_eq(kind,"polygon");
}
fn plp_number(row,key,limit) {
    let value=pc_web_geometry_number(row,key,"Expected a finite legacy primitive parameter");
    if f64_gt(f64_magnitude(value),f64_from_i64(limit)) {return cg_fail("Legacy primitive exceeds coordinate range");}
    return value;
}
fn plp_point(shape,key) {
    let row=j_get(shape,key);
    return cg_v(plp_number(row,"x",500),plp_number(row,"y",500),0);
}
fn plp_emit(out,x,y) {
    let nm=f64_from_i64(1000000);
    return pc_curve_point(out,f64_to_i64_round(f64_mul(x,nm)),f64_to_i64_round(f64_mul(y,nm)));
}
fn plp_rotate(shape) {
    return f64_div(f64_mul(plp_number(shape,"rotation",1000000),0x400921fb54442d18),f64_from_i64(180));
}
fn plp_ellipse(shape) {
    let center=plp_point(shape,"center");let count=j_integer(shape,"segments");
    let rx=f64_scalbn(plp_number(shape,"width",500),-1);let ry=f64_scalbn(plp_number(shape,"height",500),-1);
    let rotation=plp_rotate(shape);
    if cg_error || !f64_gt(rx,0) || !f64_gt(ry,0) || count<8 || count>4096 {return cg_fail("Invalid legacy ellipse axes or segment count");}
    let c=f64_cos(rotation);let s=f64_sin(rotation);let n=f64_from_i64(count);let out=cg_array();let i=0;
    while i<count && !cg_error {
        let angle=f64_div(f64_mul(f64_from_i64(i),0x401921fb54442d18),n);
        let u=f64_mul(rx,f64_cos(angle));let v=f64_mul(ry,f64_sin(angle));
        plp_emit(out,f64_sub(f64_add(load64(center),f64_mul(u,c)),f64_mul(v,s)),
            f64_add(f64_add(load64(center+8),f64_mul(u,s)),f64_mul(v,c)));
        i=i+1;
    }
    if cg_error {return 0;}return out;
}
fn plp_polygon(shape) {
    let center=plp_point(shape,"center");let count=j_integer(shape,"sides");
    let radius=plp_number(shape,"radius",500);let rotation=plp_rotate(shape);
    if cg_error || !f64_gt(radius,0) || count<3 || count>64 {return cg_fail("Invalid legacy polygon radius or side count");}
    let n=f64_from_i64(count);let out=cg_array();let i=0;
    while i<count && !cg_error {
        let angle=f64_add(rotation,f64_div(f64_mul(f64_from_i64(i),0x401921fb54442d18),n));
        plp_emit(out,f64_add(load64(center),f64_mul(radius,f64_cos(angle))),
            f64_add(load64(center+8),f64_mul(radius,f64_sin(angle))));
        i=i+1;
    }
    if cg_error {return 0;}return out;
}
fn plp_capsule(shape) {
    let from=plp_point(shape,"from");let to=plp_point(shape,"to");let count=j_integer(shape,"arcSegments");
    let radius=f64_scalbn(plp_number(shape,"width",500),-1);
    let dx=f64_sub(load64(to),load64(from));let dy=f64_sub(load64(to+8),load64(from+8));
    let distance=f64_hypot(dx,dy);
    if cg_error || !f64_gt(radius,0) || !f64_gt(distance,0x3e112e0be826d695) || count<1 || count>4096 {
        return cg_fail("Invalid legacy capsule width, endpoints or arc segment count");
    }
    let pi=0x400921fb54442d18;let axis=f64_atan2(f64_div(dy,distance),f64_div(dx,distance));
    let n=f64_from_i64(count);let out=cg_array();let end=0;
    while end<2 && !cg_error {
        let center=to;let start=f64_sub(axis,f64_scalbn(pi,-1));
        if end {center=from;start=f64_add(axis,f64_scalbn(pi,-1));}
        let i=0;while i<=count && !cg_error {
            let angle=f64_add(start,f64_mul(f64_div(f64_from_i64(i),n),pi));
            plp_emit(out,f64_add(load64(center),f64_mul(radius,f64_cos(angle))),
                f64_add(load64(center+8),f64_mul(radius,f64_sin(angle))));
            i=i+1;
        }
        end=end+1;
    }
    if cg_error {return 0;}return out;
}
fn plp_loop(shape,kind) {
    if m_eq(kind,"ellipse") {return plp_ellipse(shape);}
    if m_eq(kind,"polygon") {return plp_polygon(shape);}
    return plp_capsule(shape);
}
