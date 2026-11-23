// Reflection constrains the point difference along the axis and the
// midpoint offset across it. Both points and the axis may move.
fn csy_constraint(row,edges,seen,pending,names) {
    let id=j_string(row,"id");
    let from=j_integer(names,j_string(row,"from"));let to=j_integer(names,j_string(row,"to"));
    let axis_id=j_string(row,"axis");let axis=j_integer(edges,axis_id);
    if !from || !to || from==to || !axis || load64(axis+16) {
        return cg_fail(m_cat("Symmetry needs two distinct points and a straight axis: ",id));
    }
    if from>to {let swap=from;from=to;to=swap;}
    let key=m_cat("symmetry:",m_cat(axis_id,m_cat(":",m_cat(m_int(from),m_cat(":",m_int(to))))));
    if j_get(seen,key) {return 2;}
    cg_j_int(seen,key,1);
    let item=m_take(72);
    store64(item,id);store64(item+8,axis);store64(item+16,5);
    store64(item+40,from);store64(item+56,to);cg_push(pending,item);
    return 1;
}

fn csy_attach(item,x,y) {
    let axis=load64(item+8);let a=load64(axis);let b=load64(axis+8);
    let p=load64(item+40);let q=load64(item+56);
    store64(item+8,csm_axis(x,a,b));store64(item+32,csm_axis(y,a,b));
    store64(item+40,csm_axis(x,a,p));store64(item+48,csm_axis(y,a,p));
    store64(item+56,csm_axis(x,a,q));store64(item+64,csm_axis(y,a,q));
}

fn csy_row(item,x,y,midpoint,row,state) {
    let ax=load64(item+8);let ay=load64(item+32);
    let dx=csm_delta(x,ax);let dy=csm_delta(y,ay);
    if cg_abs(dx)>1000000000 || cg_abs(dy)>1000000000 {return 0;}
    let length=cg_sqrt(dx*dx+dy*dy);
    if length<10000 {return 0;}
    let ux=dx*1000000/length;let uy=dy*1000000/length;
    let nx=-uy;let ny=ux;
    let px=load64(item+40);let py=load64(item+48);
    let qx=load64(item+56);let qy=load64(item+64);
    let p_x=csm_delta(x,px);let p_y=csm_delta(y,py);
    let q_x=csm_delta(x,qx);let q_y=csm_delta(y,qy);
    if cg_abs(p_x)>1000000000 || cg_abs(p_y)>1000000000 || cg_abs(q_x)>1000000000 || cg_abs(q_y)>1000000000 {
        return 0;
    }
    let residual=0;let lever=0;
    if midpoint {
        residual=((p_x+q_x)*nx+(p_y+q_y)*ny)/1000000;
        lever=-((p_x+q_x)*ux+(p_y+q_y)*uy)/length;
    }else {
        residual=((q_x-p_x)*ux+(q_y-p_y)*uy)/1000000;
        lever=((q_x-p_x)*nx+(q_y-p_y)*ny)/length;
    }
    store64(state,residual);
    if !row {return 1;}
    csm_clear_gradient(row);
    csm_gradient(row,ax,nx*lever/1000000,0);
    csm_gradient(row,ay,ny*lever/1000000,32);
    if midpoint {
        csm_gradient(row,px,nx,0);csm_gradient(row,py,ny,32);
        csm_gradient(row,qx,nx,0);csm_gradient(row,qy,ny,32);
    }else {
        csm_gradient(row,px,-ux,0);csm_gradient(row,py,-uy,32);
        csm_gradient(row,qx,ux,0);csm_gradient(row,qy,uy,32);
    }
    return 1;
}

fn csy_project(item,x,y,apply,row,state) {
    let midpoint=0;let valid=1;let moved=0;
    while midpoint<2 {
        if !csy_row(item,x,y,midpoint,row*apply,state) {return moved;}
        let error=load64(state);
        if cg_abs(error)>200 {
            valid=0;
            if apply {
                let peak=csm_normalize_gradient(row);
                if peak && csm_displace(row,x,y,error*1000000/peak,500000000) {moved=2;}
            }
        }
        midpoint=midpoint+1;
    }
    if moved {return 2;}
    return valid;
}

fn csy_rank(item,x,y,basis,locked,state) {
    let midpoint=0;let mobile=0;
    while midpoint<2 && !cg_error {
        let row=m_take(65*8);
        if csy_row(item,x,y,midpoint,row,state) && csm_normalize_gradient(row) {
            mobile=1;csm_rank(row,basis,locked);
        }
        midpoint=midpoint+1;
    }
    return mobile;
}
