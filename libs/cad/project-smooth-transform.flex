import "project-line-records.flex";

fn ps_is_join(row) {return m_eq(j_string(row,"type"),"smoothJoin");}

fn ps_transform_point(point,old,new,c,s) {
    let xy=pc_uv(point);let x=f64_from_i64(load64(xy)-load64(old));let y=f64_from_i64(load64(xy+8)-load64(old+8));
    let dx=f64_to_i64_round(f64_sub(f64_mul(x,c),f64_mul(y,s)));let dy=f64_to_i64_round(f64_add(f64_mul(x,s),f64_mul(y,c)));
    return po_position(point,cg_v(load64(new)+dx,load64(new+8)+dy,0),1);
}
fn ps_transform(node,old,new,c,s) {
    let type=j_string(node,"type");if m_eq(type,"sketchLine") {
        return ps_transform_point(j_get(node,"p0"),old,new,c,s) && ps_transform_point(j_get(node,"p1"),old,new,c,s);
    }
    if pc_circular_arc(node) {
        let arc=j_get(node,"arc");let value=pc_serial_number(j_get(arc,"startAngle"),12,1000000000000,1000000)%6283185307180;
        let turn=f64_atan2(s,c);
        if f64_to_i64_round(f64_mul(turn,f64_from_i64(1000000000000))) {
            let angle=f64_add(f64_div(f64_from_i64(value),f64_from_i64(1000000000000)),turn);
            cg_j_set(arc,"startAngle",pc_arc_json_angle(angle));
        }
        return ps_transform_point(j_get(arc,"center"),old,new,c,s);
    }
    if pc_elliptic_arc(node) {
        let arc=pc_curve_geometry(node);let turn=f64_atan2(s,c);
        let change=f64_to_i64_round(f64_div(f64_mul(turn,f64_from_i64(180000000)),0x400921fb54442d18));
        if change {
            let rotation=pc_circle_measure(node,"rotation")+change;
            if cg_error || cg_abs(rotation)>1000000000000 {return cg_fail("Elliptic arc rotation exceeds range");}
            cg_j_set(arc,"rotation",cg_json_number(rotation));
        }
        return ps_transform_point(j_get(arc,"center"),old,new,c,s);
    }
    let p=pc_first(j_get(j_get(node,"spline"),"points"));while p {if !ps_transform_point(p,old,new,c,s) {return 0;}p=load64(p+24);}return 1;
}
fn ps_alignment(source,follower) {
    let x=load64(follower+8);let y=load64(follower+16);let u=f64_sub(0,load64(source+8));let v=f64_sub(0,load64(source+16));
    return cg_v(f64_add(f64_mul(x,u),f64_mul(y,v)),f64_sub(f64_mul(x,v),f64_mul(y,u)),0);
}
fn ps_movable(sketch,node) {
    let id=j_string(node,"id");
    if pc_line_projection(sketch,id) {return cg_fail("Projected edges follow their source geometry");}
    if j_get(pp_targets(sketch),id) {return cg_fail("Edit the pattern source or its parameters");}
    let rel=po_first(sketch);while rel {
        if po_kind(rel) && po_target(rel,id) {return cg_fail("Set the offset distance or move its source");}
        rel=load64(rel+24);
    }
    return 1;
}

// Keep the solved driver and carry each joined curve by a rigid transform.
// Callers validate the whole sketch again against every other saved constraint.
fn ps_follow_driver(nodes,sketch,id) {
    let rows=j_get(sketch,"relations");let first=pc_first(rows);
    while first && !ps_is_join(first) {first=load64(first+24);}
    if !first {return 1;}
    let seen=j_object();cg_j_int(seen,id,1);
    let sk=j_string(sketch,"id");let changed=1;
    while changed {
        changed=0;let row=first;while row {
            if ps_is_join(row) {
                if !cg_step() {return 0;}
                let a=j_get(row,"a");let b=j_get(row,"b");
                let a_seen=j_get(seen,j_string(a,"entityId"));let b_seen=j_get(seen,j_string(b,"entityId"));
                if a_seen || b_seen {
                    if !a_seen {let swap=a;a=b;b=swap;}
                    let source=ps_anchor_frame(nodes,sk,a);let follower=ps_anchor_frame(nodes,sk,b);
                    if !source || !follower {return 0;}
                    if !ps_matches(source,follower) {
                        if a_seen && b_seen {return cg_fail("Editing this smooth chain would break a closed join");}
                        let alignment=ps_alignment(source,follower);let node=pc_find(nodes,j_string(b,"entityId"));
                        if !ps_movable(sketch,node) || !ps_transform(node,load64(follower),load64(source),load64(alignment),load64(alignment+8)) {return 0;}
                    }
                    if !a_seen || !b_seen {cg_j_int(seen,j_string(b,"entityId"),1);changed=1;}
                }
            }
            row=load64(row+24);
        }
    }
    return 1;
}
