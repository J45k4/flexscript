// A point can slide along the line interior. An overshoot activates the
// nearest endpoint until the point returns to the finite segment.
fn csp_line_limit_axis(x,y,span,position,offset,last,apply,row) {
    let roots=x;if offset {roots=y;}
    let error=csm_delta(roots,position);
    if last {error=error-csm_delta(roots,span);}
    if cg_abs(error)<=1 {return 1;}
    if !apply {return 0;}
    csm_clear_gradient(row);
    csm_gradient(row,position,1000000,offset);
    if last {csm_gradient(row,span,-1000000,offset);}
    let peak=csm_normalize_gradient(row);if !peak {return 0;}
    return csm_displace(row,x,y,error*1000000/peak,500000000);
}

fn csp_line_project(item,x,y,apply,row,state) {
    if !cslc_frame(item,x,y,state) {return 0;}
    let t=load64(state+16);let before=f64_lt(t,0);let after=f64_lt(f64_from_i64(1),t);
    if before || after {
        let a=csp_line_limit_axis(x,y,load64(item+8),load64(item+40),0,after,apply,row);
        let b=csp_line_limit_axis(x,y,load64(item+32),load64(item+48),32,after,apply,row);
        if a==2 || b==2 {return 2;}
        return a && b;
    }
    let error=load64(state+32);
    if cg_abs(error)<=20 {return 1;}
    if !apply {return 0;}
    return cslc_step(item,x,y,row,state,error,500000000);
}
