// Angles stay at picoradian precision on the saved supporting circle.
import "project-curves.flex";

fn pma_start(arc) {
    return pc_serial_number(j_get(arc,"startAngle"),12,1000000000000,1000000)%6283185307180;
}

fn pma_sweep(arc) {
    let sweep=pc_serial_number(j_get(arc,"sweep"),12,1000000000000,7);
    if cg_abs(sweep)<1000 || cg_abs(sweep)>=6283185307180 {cg_fail("Invalid circular arc sweep");}
    return sweep;
}

fn pma_wrap(angle) {
    let tau=6283185307180;
    return (angle%tau+tau+tau/2)%tau-tau/2;
}

fn pma_reflected_start(start,a,b) {
    let x=load64(b)-load64(a);let y=load64(b+8)-load64(a+8);
    if !x && !y {return cg_fail("Mirror axis has no length");}
    let angle=f64_atan2(f64_from_i64(y),f64_from_i64(x));
    let doubled=f64_to_i64_round(f64_mul(angle,f64_from_i64(2000000000000)));
    return pma_wrap(doubled-start);
}

fn pma_write_angle(arc,key,angle) {
    let radians=f64_div(f64_from_i64(angle),f64_from_i64(1000000000000));
    return cg_j_set(arc,key,pc_arc_json_angle(radians));
}

// Keep the source's exact magnitude at tessellation thresholds, including
// a full-precision fraction of a turn saved by another editor.
fn pma_sweep_value(arc,sign) {
    let value=j_get(arc,"sweep");let bits=j_value(value);let kind=j_kind(value);
    if sign>0 {return j_new(kind,bits);}
    if kind==1 {return j_number(-bits);}
    if load8(bits)==45 {return j_new(6,bits+1);}
    return j_new(6,m_cat("-",bits));
}

fn pma_check(source,target,a,b,id) {
    let first=j_get(source,"arc");let second=j_get(target,"arc");
    let radius=pc_pose_number(j_get(first,"radius"));let other=pc_pose_number(j_get(second,"radius"));
    let angle=pma_reflected_start(pma_start(first),a,b);let start=pma_start(second);
    let sweep=pma_sweep(first)+pma_sweep(second);
    if cg_error {return 0;}
    if radius<=0 || other<=0 || cg_abs(radius-other)>100 {return cg_fail(m_cat("Mirrored radii disagree: ",id));}
    if cg_abs(pma_wrap(start-angle))>1000000 || cg_abs(sweep)>1000000 {
        return cg_fail(m_cat("Mirrored arc angles disagree: ",id));
    }
    return 1;
}
