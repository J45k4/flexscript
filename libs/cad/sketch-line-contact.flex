// Signed distance from the curve center to its supporting line.
import "sketch-ellipse-support.flex";

fn cslc_frame(item,x,y,state) {
    let dx=csm_delta(x,load64(item+8));let dy=csm_delta(y,load64(item+32));
    let cx=csm_delta(x,load64(item+40));let cy=csm_delta(y,load64(item+48));
    if (!dx && !dy) || cg_abs(dx)>1000000000 || cg_abs(dy)>1000000000 || cg_abs(cx)>1000000000 || cg_abs(cy)>1000000000 {return 0;}
    let length=f64_sqrt(f64_from_i64(dx*dx+dy*dy));
    let ux=f64_div(f64_from_i64(dx),length);let uy=f64_div(f64_from_i64(dy),length);
    let nx=f64_sub(0,uy);let ny=ux;let x_rel=f64_from_i64(cx);let y_rel=f64_from_i64(cy);
    let signed=f64_add(f64_mul(x_rel,nx),f64_mul(y_rel,ny));
    let value=load64(item+24);let error=f64_to_i64_round(signed)-value;let extent=cg_abs(value);
    let oval=load64(item+64);
    if oval {
        let support=cse_support(oval,nx,ny,state+48);let side=f64_from_i64(value);
        let height=load64(support);extent=f64_to_i64_round(height);
        error=f64_to_i64_round(f64_sub(signed,f64_mul(height,side)));
        // A rotated ellipse's support value changes when the line tilts.
        // Use the vector from A to the actual contact in the derivative.
        x_rel=f64_sub(x_rel,f64_mul(load64(support+8),side));
        y_rel=f64_sub(y_rel,f64_mul(load64(support+16),side));
    }
    let along=f64_add(f64_mul(x_rel,ux),f64_mul(y_rel,uy));
    store64(state,nx);store64(state+8,ny);store64(state+16,f64_div(along,length));
    store64(state+24,f64_to_i64_round(length));store64(state+32,error);store64(state+88,extent);
    return 1;
}

fn cslc_gradient(row,item,state) {
    // Differential: N dot d(C - A) - along/length * N dot d(B - A).
    // Accumulate both deltas on the same affine roots before normalizing.
    let factor=load64(state+16);let scale=f64_from_i64(1);let magnitude=f64_magnitude(factor);
    let tilt_x=csm_free(load64(item+8)) && f64_magnitude(load64(state));
    let tilt_y=csm_free(load64(item+32)) && f64_magnitude(load64(state+8));
    if !tilt_x && !tilt_y {factor=0;magnitude=0;}
    if f64_lt(scale,magnitude) {scale=f64_div(scale,magnitude);}
    store64(state+40,scale);
    let fixed_scale=f64_mul(scale,f64_from_i64(1000000));
    let nx=f64_mul(load64(state),fixed_scale);let ny=f64_mul(load64(state+8),fixed_scale);
    csm_gradient(row,load64(item+40),f64_to_i64_round(nx),0);
    csm_gradient(row,load64(item+48),f64_to_i64_round(ny),32);
    csm_gradient(row,load64(item+8),-f64_to_i64_round(f64_mul(factor,nx)),0);
    csm_gradient(row,load64(item+32),-f64_to_i64_round(f64_mul(factor,ny)),32);
    return csm_normalize_gradient(row);
}

fn cslc_project(item,x,y,apply,row,state) {
    if !cslc_frame(item,x,y,state) {return 0;}
    let error=load64(state+32);let radius=load64(state+88);
    let tolerance=radius/1000;if tolerance>200 {tolerance=200;}
    if cg_abs(error)<=tolerance {return 1;}
    if !apply {return 0;}
    let limit=load64(state+24)/2;if radius>limit {limit=radius;}
    return cslc_step(item,x,y,row,state,error,limit);
}

fn cslc_step(item,x,y,row,state,error,limit) {
    csm_clear_gradient(row);
    let peak=cslc_gradient(row,item,state);if !peak {return 0;}
    let delta=f64_div(f64_from_i64(error*1000000),f64_mul(f64_from_i64(peak),load64(state+40)));
    if f64_lt(f64_from_i64(limit),f64_magnitude(delta)) {
        if error<0 {return csm_displace(row,x,y,-limit,limit);}
        return csm_displace(row,x,y,limit,limit);
    }
    return csm_displace(row,x,y,f64_to_i64_round(delta),limit);
}
