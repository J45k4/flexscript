// Endpoint frames of open curves. The point uses sketch nanometres and the
// unit tangent points out of the curve. At a G1 join the two tangents oppose.
import "project-curves.flex";
import "project-nodes.flex";

fn ps_frame(point,x,y) {
    let length=f64_sqrt(f64_add(f64_mul(x,x),f64_mul(y,y)));
    if !length {return cg_fail("Smooth join needs a nonzero endpoint tangent");}
    return cg_v(point,f64_div(x,length),f64_div(y,length));
}
fn ps_end_name(node,end) {
    let type=j_string(node,"type");
    if m_eq(type,"sketchLine") || pc_circular_arc(node) {
        if end {return "p1";}return "p0";
    }
    if pc_elliptic_arc(node) {
        let sweep=pc_web_arc_number(pc_curve_geometry(node),"sweep",0x401921fb54442d18);
        if cg_error || !f64_magnitude(sweep) || f64_magnitude(sweep)==0x401921fb54442d18 {return 0;}
        if end {return "p1";}return "p0";
    }
    if m_eq(type,"sketchSpline") {
        let spline=j_get(node,"spline");let n=cg_j_count(j_get(spline,"points"));
        if n<2 || n>4096 || j_value(j_get(spline,"closed")) {return 0;}
        if end {return m_cat("point",m_int(n-1));}return "point0";
    }
    return 0;
}
fn ps_spline_frame(node,end) {
    let spline=j_get(node,"spline");let points=cg_array();let row=pc_first(j_get(spline,"points"));
    while row {cg_push(points,pc_uv(row));row=load64(row+24);}
    let n=cg_count(points);let near=0;let next=1;if end {near=n-1;next=n-2;}
    let a=cg_at(points,near);let b=cg_at(points,next);let direction=cg_v(0,0,0);let k=0;
    let fit=m_eq(j_string(spline,"mode"),"fit");
    if !fit && (!m_eq(j_string(spline,"mode"),"control") || n<4 || (n-1)%3) {return cg_fail("Invalid smooth join spline");}
    while k<16 {
        let v=f64_from_i64(load64(a+k)-load64(b+k));if fit {
            // Natural cubic derivative at either boundary, oriented outwards.
            let second=pc_spline_second(points,k,0);
            v=f64_add(v,f64_div(load64(second+next*8),f64_from_i64(6)));
        }
        store64(direction+k,v);k=k+8;
    }
    return ps_frame(a,load64(direction),load64(direction+8));
}
fn ps_elliptic_endpoint(arc,end) {
    let sweep=pc_web_arc_number(arc,"sweep",0x401921fb54442d18);
    let angle=pc_web_arc_number(arc,"startAngle",f64_from_i64(1000000));
    let scale=f64_from_i64(500000);let limit=f64_from_i64(500);
    let rx=f64_mul(pc_web_arc_number(arc,"width",limit),scale);
    let ry=f64_mul(pc_web_arc_number(arc,"height",limit),scale);
    let rotation=pc_ellipse_rotation(arc);let center=pc_uv(j_get(arc,"center"));
    if cg_error || !f64_gt(rx,0) || !f64_gt(ry,0) || !f64_magnitude(sweep) {return cg_fail("Invalid elliptic arc endpoint");}
    if f64_magnitude(sweep)==0x401921fb54442d18 {return cg_fail("A full-turn elliptic arc has no endpoints");}
    if end {angle=f64_add(angle,sweep);}
    let c=f64_cos(rotation);let s=f64_sin(rotation);let u=f64_cos(angle);let v=f64_sin(angle);
    let x=f64_mul(rx,u);let y=f64_mul(ry,v);
    let point=cg_v(load64(center)+f64_to_i64_round(f64_sub(f64_mul(x,c),f64_mul(y,s))),
        load64(center+8)+f64_to_i64_round(f64_add(f64_mul(x,s),f64_mul(y,c))),0);
    let tx=f64_math_neg(f64_mul(rx,v));let ty=f64_mul(ry,u);
    if end!=(f64_gt(sweep,0)) {tx=f64_math_neg(tx);ty=f64_math_neg(ty);}
    return ps_frame(point,f64_sub(f64_mul(tx,c),f64_mul(ty,s)),f64_add(f64_mul(tx,s),f64_mul(ty,c)));
}
fn ps_endpoint(node,point) {
    if pc_elliptic_arc(node) {
        if !m_eq(point,"p0") && !m_eq(point,"p1") {return cg_fail("Choose an elliptic arc endpoint");}
        return ps_elliptic_endpoint(pc_curve_geometry(node),m_eq(point,"p1"));
    }
    let first=ps_end_name(node,0);if !first {return cg_fail("Choose a line, finite arc or open spline endpoint");}
    let end=!m_eq(point,first);if end && !m_eq(point,ps_end_name(node,1)) {return cg_fail("Invalid smooth join endpoint");}
    let type=j_string(node,"type");
    if m_eq(type,"sketchSpline") {return ps_spline_frame(node,end);}
    if m_eq(type,"sketchLine") {
        let other="p1";if end {other="p0";}
        let a=pc_uv(j_get(node,point));let b=pc_uv(j_get(node,other));
        return ps_frame(a,f64_from_i64(load64(a)-load64(b)),f64_from_i64(load64(a+8)-load64(b+8)));
    }
    let arc=j_get(node,"arc");let center=pc_uv(j_get(arc,"center"));let radius=pc_pose_number(j_get(arc,"radius"));
    let start=pc_serial_number(j_get(arc,"startAngle"),12,1000000000000,1000000)%6283185307180;
    let sweep=pc_serial_number(j_get(arc,"sweep"),12,1000000000000,7);
    if cg_error || radius<=0 || cg_abs(sweep)<1000 || cg_abs(sweep)>=6283185307180 {return cg_fail("Invalid smooth join arc");}
    if end {start=start+sweep;}let angle=f64_div(f64_from_i64(start),f64_from_i64(1000000000000));
    let c=f64_cos(angle);let s=f64_sin(angle);let r=f64_from_i64(radius);
    let p=cg_v(load64(center)+f64_to_i64_round(f64_mul(r,c)),load64(center+8)+f64_to_i64_round(f64_mul(r,s)),0);
    if end==(sweep>0) {return cg_v(p,f64_sub(0,s),c);}return cg_v(p,s,f64_sub(0,c));
}
fn ps_anchor_frame(nodes,sk,anchor) {
    let node=pc_find(nodes,j_string(anchor,"entityId"));if !node || !m_eq(j_string(node,"sketchId"),sk) {return cg_fail("Missing smooth join member");}
    return ps_endpoint(node,j_string(anchor,"point"));
}
fn ps_matches(a,b) {
    let pa=load64(a);let pb=load64(b);
    if cg_abs(load64(pa)-load64(pb))>1000 || cg_abs(load64(pa+8)-load64(pb+8))>1000 {return 0;}
    let x=f64_add(load64(a+8),load64(b+8));let y=f64_add(load64(a+16),load64(b+16));
    return !f64_lt(f64_div(f64_from_i64(1),f64_from_i64(100000000)),f64_add(f64_mul(x,x),f64_mul(y,y)));
}
fn ps_register(used,anchor) {
    let id=j_string(anchor,"entityId");let point=j_string(anchor,"point");let item=j_get(used,id);
    if !item {item=j_object();j_add(used,id,item);}if j_get(item,point) {return cg_fail("Endpoint already has a smooth join");}
    cg_j_int(item,point,1);return 1;
}
fn ps_check(nodes,sk,rel,used) {
    let a=j_get(rel,"a");let b=j_get(rel,"b");let id=j_string(rel,"id");
    if !m_len(id) || m_eq(j_string(a,"entityId"),j_string(b,"entityId")) || j_value(j_get(rel,"reference")) {return cg_fail("Invalid smooth join relation");}
    if !ps_register(used,a) || !ps_register(used,b) {return 0;}
    let source=ps_anchor_frame(nodes,sk,a);let follower=ps_anchor_frame(nodes,sk,b);
    if cg_error || !source || !follower {return 0;}
    if !ps_matches(source,follower) {return cg_fail(m_cat("Saved endpoints disagree with smooth join: ",id));}return 1;
}

fn ps_spline_coincidence(nodes,relation) {
    if !m_eq(j_string(relation,"type"),"coincident") {return 0;}
    let a=pc_find(nodes,j_string(j_get(relation,"a"),"entityId"));
    let b=pc_find(nodes,j_string(j_get(relation,"b"),"entityId"));
    return m_eq(j_string(a,"type"),"sketchSpline") || m_eq(j_string(b,"type"),"sketchSpline");
}

fn ps_coincident_point(nodes,sketch,anchor) {
    let node=pc_find(nodes,j_string(anchor,"entityId"));let name=j_string(anchor,"point");
    if !node || !m_eq(j_string(node,"sketchId"),sketch) {return 0;}
    let kind=j_string(node,"type");let point=0;
    if m_eq(kind,"sketchSpline") {
        if m_len(name)<6 || m_len(name)>9 || !m_eq(m_slice(name,5),"point") {return 0;}
        let index=m_number(name+5);
        if index<0 || index>=4096 || !m_eq(m_cat("point",m_int(index)),name) {return 0;}
        point=pc_first(j_get(j_get(node,"spline"),"points"));
        while point && index {point=load64(point+24);index=index-1;}
    }else if m_eq(kind,"sketchLine") && (m_eq(name,"p0") || m_eq(name,"p1")) {
        point=j_get(node,name);
    }else if pc_finite_arc(node) && (m_eq(name,"p0") || m_eq(name,"p1")) {
        let frame=ps_endpoint(node,name);if frame {return load64(frame);}return 0;
    }else if m_eq(kind,"sketchPrimitive") && m_eq(name,"center") {point=j_get(j_get(node,"primitive"),"center");}
    if !point {return 0;}return pc_uv(point);
}

fn ps_spline_coincidence_positions(nodes,sketch,relation) {
    let first=j_get(relation,"a");let second=j_get(relation,"b");
    if j_get(relation,"expression") || j_value(j_get(relation,"reference"))
        || (m_eq(j_string(first,"entityId"),j_string(second,"entityId")) && m_eq(j_string(first,"point"),j_string(second,"point"))) {
        return cg_fail("Invalid spline coincidence");
    }
    let a=ps_coincident_point(nodes,sketch,first);let b=ps_coincident_point(nodes,sketch,second);
    if !a || !b {return cg_fail("Missing spline coincidence anchor in this sketch");}
    if cg_error || cg_distance2(a,b)>10000 {return cg_fail("Saved spline coincidence anchors do not meet");}
    return cg_v(a,b,0);
}
fn ps_check_spline_coincidence(nodes,sketch,relation) {return ps_spline_coincidence_positions(nodes,sketch,relation)!=0;}

fn ps_only(nodes,sketch) {
    let r=pc_first(j_get(sketch,"relations"));let any=0;
    while r {
        let type=j_string(r,"type");
        if m_eq(type,"smoothJoin") || ps_spline_coincidence(nodes,r) {any=1;}
        else if !m_eq(type,"projected") {return 0;}
        r=load64(r+24);
    }
    if !any || pc_first(j_get(sketch,"dimensions")) {return 0;}
    let n=pc_first(nodes);while n {
        if m_eq(j_string(n,"sketchId"),j_string(sketch,"id")) && m_eq(j_string(n,"type"),"sketchConstraint") {return 0;}n=load64(n+24);
    }return 1;
}
