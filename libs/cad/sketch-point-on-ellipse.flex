import "elliptic-contact.flex";

fn cso_constraint_range(row,id) {
    let rx=j_integer(row,"rx_nm");let ry=j_integer(row,"ry_nm");
    let rotation=j_integer(row,"rotation_microdegrees");
    let start=j_integer(row,"start_picorad");let sweep=j_integer(row,"sweep_picorad");let tau=6283185307180;
    if j_kind(j_get(row,"rx_nm"))!=1 || j_kind(j_get(row,"ry_nm"))!=1 || j_kind(j_get(row,"rotation_microdegrees"))!=1 ||
       j_kind(j_get(row,"start_picorad"))!=1 || j_kind(j_get(row,"sweep_picorad"))!=1 || j_get(row,"parameter") ||
       rx<=0 || ry<=0 || rx>250000000 || ry>250000000 || rotation<= -360000000 || rotation>=360000000 ||
       start<= -tau || start>=tau || sweep< -tau || sweep>tau || (!sweep && start) {
        return cg_fail(m_cat("Point on an ellipse needs positive axes and a valid sweep: ",id));
    }
    let radians=f64_mul(f64_div(f64_from_i64(rotation),f64_from_i64(180000000)),0x400921fb54442d18);
    return cso_range(rx,ry,radians,start,sweep);
}

fn cso_project(item,x,y,apply) {
    let xa=load64(item+8);let ya=load64(item+32);
    let dx=csm_delta(x,xa);let dy=csm_delta(y,ya);
    if cg_abs(dx)>1000000000 || cg_abs(dy)>1000000000 {return 0;}
    let range=load64(item+40);let contact=cso_nearest(range,dx,dy);
    let nx=load64(contact)-dx;let ny=load64(contact+8)-dy;
    if nx*nx+ny*ny<=4 {return 1;}
    if !apply {return 0;}
    let xfree=csm_free(xa);let yfree=csm_free(ya);
    if xfree!=yfree {
        contact=cso_locked_axis(range,dx,dy,xfree);if !contact {return 0;}
        nx=load64(contact)-dx;ny=load64(contact+8)-dy;
    }
    let moved=csm_move(x,xa,nx);
    if csm_move(y,ya,ny) || moved {return 2;}
    return 0;
}

// Endpoints retain tangent freedom towards the interior of the sweep.
fn cso_gradient(row,item,x,y) {
    let xa=load64(item+8);let ya=load64(item+32);let range=load64(item+40);
    let local=cso_local(range,csm_delta(x,xa),csm_delta(y,ya));
    let axes=load64(range);let t=cso_radians(cso_phase(range,local));
    let u=f64_mul(load64(axes+8),f64_cos(t));let v=f64_mul(load64(axes),f64_sin(t));
    let len=f64_sqrt(f64_add(f64_mul(u,u),f64_mul(v,v)));
    if !len {return 0;}
    let scale=f64_div(f64_from_i64(1000000),len);let c=load64(axes+16);let s=load64(axes+24);
    let dx=f64_sub(f64_mul(u,c),f64_mul(v,s));let dy=f64_add(f64_mul(u,s),f64_mul(v,c));
    csm_gradient(row,xa,f64_to_i64_round(f64_mul(dx,scale)),0);
    csm_gradient(row,ya,f64_to_i64_round(f64_mul(dy,scale)),32);
    return 1;
}
