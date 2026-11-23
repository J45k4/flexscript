import "circular-arc-contact.flex";

fn csp_arc_available(range,x,y) {
    let limit=csp_arc_limit(range,x,y);
    return !limit || csp_arc_distance2(x,y,limit)<=2;
}

fn csp_arc_one_axis(range,axis,roots,radius,moving,fixed,horizontal) {
    let square=radius*radius-fixed*fixed;if square<0 {return 0;}
    let right=cg_sqrt(square);let left=-right;
    let allow_right=0;let allow_left=0;
    if horizontal {
        allow_right=csp_arc_available(range,right,fixed);allow_left=csp_arc_available(range,left,fixed);
    }else {
        allow_right=csp_arc_available(range,fixed,right);allow_left=csp_arc_available(range,fixed,left);
    }
    if !allow_right && !allow_left {return 0;}
    let target=right;if !allow_right || (allow_left && moving<0) {target=left;}
    if csm_move(roots,axis,target-moving) {return 2;}
    return 0;
}

fn csp_arc_project(item,x,y,apply) {
    let xa=load64(item+8);let ya=load64(item+32);
    let dx=csm_delta(x,xa);let dy=csm_delta(y,ya);
    if cg_abs(dx)>1000000000 || cg_abs(dy)>1000000000 {return 0;}
    let range=load64(item+40);let limit=csp_arc_limit(range,dx,dy);
    if limit && csp_arc_distance2(dx,dy,limit)<=2 {return 1;}
    if !apply {
        if limit {return 0;}
        return csm_project(item,x,y,0);
    }
    let xfree=csm_free(xa);let yfree=csm_free(ya);
    // An affine lock on one axis can leave the opposite radial branch as
    // the only intersection that lies in the finite sweep.
    if xfree!=yfree {
        if !limit && csm_project(item,x,y,0) {return 1;}
        if xfree {return csp_arc_one_axis(range,xa,x,load64(item+24),dx,dy,1);}
        return csp_arc_one_axis(range,ya,y,load64(item+24),dy,dx,0);
    }
    if !limit {return csm_project(item,x,y,1);}
    let moved=csm_move(x,xa,load64(limit)-dx);
    if csm_move(y,ya,load64(limit+8)-dy) || moved {return 2;}
    return 0;
}
