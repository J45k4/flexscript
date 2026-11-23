import "spline-contact.flex";

fn cssp_constraint(row,names,seen,pending) {
    let id=j_string(row,"id");let name=j_string(row,"point");let point=j_integer(names,name);
    let curve=j_get(row,"curve");
    if !point || !m_eq(j_string(curve,"type"),"sketchSpline") || j_get(row,"segment") || j_get(row,"parameter") {
        return cg_fail(m_cat("Point on spline needs a point and a spline: ",id));
    }
    let source=pc_spline_data(curve);if !source {return 0;}
    let key=m_cat("point-on-spline:",m_cat(name,m_cat(":",j_string(curve,"id"))));
    let encoded=j_encode(curve);let previous=j_get(seen,key);
    if previous {
        if m_eq(j_value(previous),encoded) {return 2;}
        return cg_fail(m_cat("Conflicting spline source geometry: ",id));
    }
    cg_j_text(seen,key,encoded);
    let item=m_take(72);store64(item,id);store64(item+8,point);store64(item+16,12);
    store64(item+40,source);
    store64(item+48,m_take(24+psb_nearest_workspace_size()));
    cg_push(pending,item);return 1;
}

fn cssp_position(item,x,y) {
    let point=load64(item+48);
    store64(point,csm_delta(x,load64(item+8)));store64(point+8,csm_delta(y,load64(item+32)));
    return point;
}

fn cssp_project(item,x,y,apply) {
    let point=cssp_position(item,x,y);let source=load64(item+40);
    let contact=psb_nearest_with_workspace(source,point,0,point+24);if !contact {return 0;}
    if f64_le(load64(contact+8),f64_from_i64(4)) {return 1;}
    if !apply {return 0;}
    let xa=load64(item+8);let ya=load64(item+32);let xfree=csm_free(xa);let yfree=csm_free(ya);
    if xfree!=yfree {
        let locked=1;if xfree {locked=2;}
        contact=psb_nearest_with_workspace(source,point,locked,point+24);if !contact {return 0;}
    }
    let dx=f64_to_i64_round(load64(contact+32));let dy=f64_to_i64_round(load64(contact+40));
    let moved=csm_move(x,xa,dx);
    if csm_move(y,ya,dy) || moved {return 2;}
    return 0;
}

fn cssp_rank(item,x,y,basis,locked) {
    let point=cssp_position(item,x,y);let source=load64(item+40);
    let hit=psb_nearest_with_workspace(source,point,0,point+24);if !hit {return 0;}
    let cubic=m_take(64);if !psb_store_controls(cubic,source,load64(hit+16)) {return 0;}
    let t=load64(hit+24);let u=psb_velocity(cubic,0,t);let v=psb_velocity(cubic,8,t);
    let length=f64_sqrt(pls_linear(u,v,u,v));
    let xa=load64(item+8);let ya=load64(item+32);
    let row=m_take(65*8);csm_clear_gradient(row);
    if f64_lt(0x3eb0c6f7a0b5ed8d,length) {
        let scale=f64_div(f64_from_i64(1000000),length);
        csm_gradient(row,xa,f64_to_i64_round(f64_mul(f64_math_neg(v),scale)),0);
        csm_gradient(row,ya,f64_to_i64_round(f64_mul(u,scale)),32);
        csm_rank(row,basis,locked);
    }else {
        // At a stationary point, TypeScript uses both coordinate residuals.
        csm_gradient(row,xa,1000000,0);csm_rank(row,basis,locked);
        row=m_take(65*8);csm_clear_gradient(row);csm_gradient(row,ya,1000000,32);csm_rank(row,basis,locked);
    }
    return csm_free(xa) || csm_free(ya);
}
