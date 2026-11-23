import "spline-contact.flex";

// Keep the nearest span, cubic controls and two tangents in bounded scratch.
fn psn_workspace_size() {return 136+psb_nearest_workspace_size();}
fn psn_tangent(out,cubic,t) {
    let x=psb_velocity(cubic,0,t);let y=psb_velocity(cubic,8,t);
    let speed=f64_sqrt(pls_linear(x,y,x,y));
    if f64_lt(speed,0x3eb0c6f7a0b5ed8d) {return 0;}
    store64(out,f64_div(x,speed));store64(out+8,f64_div(y,speed));return speed;
}
fn psn_frame(source,point,frame) {
    let nearest=psb_nearest_with_workspace(source,point,0,frame+136);if !nearest {return 0;}
    let cubic=frame+24;let scratch=cubic+64;let index=load64(nearest+16);let t=load64(nearest+24);
    if !psb_store_controls_with_workspace(cubic,source,index,scratch) {return 0;}
    let speed=psn_tangent(frame,cubic,t);
    if !speed {return cg_fail("Normal requires a regular spline point with a nonzero tangent");}
    let ax=psb_acceleration(cubic,0,t);let ay=psb_acceleration(cubic,8,t);
    let numerator=f64_sub(f64_mul(load64(frame),ay),f64_mul(load64(frame+8),ax));
    store64(frame+16,f64_div(f64_div(numerator,speed),speed));

    // The saved relation has no branch parameter. Consecutive spans sharing
    // this point must have the same oriented tangent, as in TypeScript.
    let one=f64_from_i64(1);let adjacent=-1;let side=0;
    if !t && index>0 {adjacent=index-1;side=one;}
    if t==one && index+1<load64(source+8) {adjacent=index+1;}
    if adjacent>=0 {
        if !psb_store_controls_with_workspace(cubic,source,adjacent,scratch) {return 0;}
        if !psn_tangent(scratch,cubic,side) ||
            f64_lt(pls_linear(load64(frame),load64(frame+8),load64(scratch),load64(scratch+8)),0x3feffffffaa19c47) {
            return cg_fail("Normal requires a smooth spline join with a unique tangent");
        }
    }
    return nearest;
}
