// For source endpoints A/B and follower P, 2(P−A) = B−A on each axis.
fn csm_midpoint_gradient(row,span,position,axis) {
    csm_clear_gradient(row);
    csm_gradient(row,span,-1000000,axis);
    csm_gradient(row,position,2000000,axis);
    return csm_normalize_gradient(row);
}

fn csm_midpoint_step(row,x,y,axis,error) {
    if csm_displace(row,x,y,error,500000000) {return 2;}
    // Near the integer grid, simultaneous changes may all round to zero.
    // Move one root with the strongest coefficient to finish the correction.
    let roots=x;if axis {roots=y;}
    let i=1;
    while i<=32 {
        let gradient=load64(row+(axis+i)*8);
        if cg_abs(gradient)==1000000 {
            let slot=roots+i*24+16;let step=error;if gradient<0 {step=-step;}
            store64(slot,load64(slot)-step);return 2;
        }
        i=i+1;
    }
    return 0;
}

fn csm_midpoint_axis(x,y,span,position,offset,apply,row) {
    let roots=x;if offset {roots=y;}
    let error=2*csm_delta(roots,position)-csm_delta(roots,span);
    // A half nanometre may lie between two representable coordinates.
    if cg_abs(error)<=1 {return 1;}
    if !apply {return 0;}
    let peak=csm_midpoint_gradient(row,span,position,offset);
    if !peak {return 0;}
    return csm_midpoint_step(row,x,y,offset,error*1000000/peak);
}

fn csm_midpoint_project(item,x,y,apply,row) {
    let a=csm_midpoint_axis(x,y,load64(item+8),load64(item+40),0,apply,row);
    let b=csm_midpoint_axis(x,y,load64(item+32),load64(item+48),32,apply,row);
    if a==2 || b==2 {return 2;}return a && b;
}

fn csm_midpoint_rank(item,basis,locked) {
    let row_x=m_take(65*8);let row_y=m_take(65*8);
    let a=csm_midpoint_gradient(row_x,load64(item+8),load64(item+40),0);
    let b=csm_midpoint_gradient(row_y,load64(item+32),load64(item+48),32);
    if a {csm_rank(row_x,basis,locked);}
    if b {csm_rank(row_y,basis,locked);}
    return a || b;
}
