// Tangent directions point away from the shared joint. At a smooth join
// the two directions are opposite. Each arc uses its local signed sagitta.
fn cst_end(edge,junctions,joint,id) {
    let start=load64(cs_equation_root(junctions,load64(edge)))==joint;
    let end=load64(cs_equation_root(junctions,load64(edge+8)))==joint;
    if start==end {return cg_fail(m_cat("Tangency needs one joined endpoint on each segment: ",id));}
    if start {return 1;}
    return -1;
}

fn cst_side(edge,direction,dimension) {
    return cg_v(direction,load64(edge+16)*direction,dimension);
}

// The turn contains cosine, sine and length times the angular derivative.
// For a radius-controlled arc the sweep branch sets the cosine's sign.
fn cst_turn(side,length,turn) {
    let sagitta=load64(side+8);
    let dimension=load64(side+16);
    let cosine=1000000;let sine=0;let radial=0;
    if dimension && load64(dimension+24) {
        cosine=0;sine=1000000;if sagitta<0 {sine=-sine;}
    }else if dimension {
        sine=length*1000000/(2*load64(dimension));
        if sine>1000000 {return 0;}
        if sagitta<0 {sine=-sine;}
        cosine=cg_sqrt(1000000000000-sine*sine);
        let denominator=cosine;
        if denominator<250000 {denominator=250000;}
        if load64(dimension+8) {cosine=-cosine;denominator=-denominator;}
        radial=sine*1000000/denominator;
    }else if sagitta {
        let half=length/2;let span=cg_sqrt(half*half+sagitta*sagitta);
        let u=half*1000000/span;let v=sagitta*1000000/span;
        cosine=(u*u-v*v)/1000000;sine=2*u*v/1000000;
        radial=-sine;
    }
    store64(turn,cosine);store64(turn+8,sine);store64(turn+16,radial);
    return 1;
}

fn cst_frame(side,state,index) {
    let turn=state+96;
    if !cst_turn(side,load64(state+32+index*8),turn) {return 0;}
    let p=state+index*16;
    let u=load64(p);let v=load64(p+8);
    let cosine=load64(turn);let sine=load64(turn+8);
    store64(p+48,(u*cosine-v*sine)/1000000);
    store64(p+56,(u*sine+v*cosine)/1000000);
    store64(state+80+index*8,load64(turn+16));
    return 1;
}

// Keep the radius-controlled chord in the circle's diameter before
// evaluating its tangent. One nanometre of headroom absorbs rounding
// in the coordinate projection.
fn cst_limit(side,x,y,xa,ya,apply) {
    let dimension=load64(side+16);
    if !dimension || load64(dimension+24) {return 1;}
    let diameter=load64(dimension)*2;
    let dx=csm_delta(x,xa);let dy=csm_delta(y,ya);
    if cg_abs(dx)>1000000000 || cg_abs(dy)>1000000000 {return 0;}
    let squared=dx*dx+dy*dy;
    if squared<=diameter*diameter {return 1;}
    if !apply {return 0;}
    let xfree=csm_free(xa);let yfree=csm_free(ya);let limit=diameter-1;
    let nx=dx;let ny=dy;
    if xfree && yfree {
        let length=cg_sqrt(squared)+1;
        nx=dx*limit/length;ny=dy*limit/length;
    }else if xfree {nx=csm_length_axis(dx,dy,limit);}
    else if yfree {ny=csm_length_axis(dy,dx,limit);}
    let moved=csm_move(x,xa,nx-dx);
    moved=csm_move(y,ya,ny-dy) || moved;
    if moved {return 2;}
    return 0;
}
