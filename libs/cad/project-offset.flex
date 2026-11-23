// V4 offsets are directed dependencies. Rebuild copies in dependency order
// and use the same geometric checks on saved profiles before manufacturing.
import "project-nodes.flex";
import "project-number.flex";
import "contour.flex";
import "project-pattern.flex";

fn po_kind(rel) {
    let t=j_string(rel,"type");if m_eq(t,"offsetChain") {return 2;}if m_eq(t,"offset") {return 1;}return 0;
}
fn po_first(sketch) {
    let rel=pc_first(j_get(sketch,"relations"));while rel && !po_kind(rel) {rel=load64(rel+24);}return rel;
}
fn po_profile_node(node) {
    if m_eq(j_string(node,"type"),"sketchCornerRectangle") {return 1;}
    let kind=j_string(j_get(node,"primitive"),"type");
    return m_eq(kind,"rectangle") || m_eq(kind,"polygon") || m_eq(kind,"capsule");
}
fn po_profile_sketch(nodes,sketch) {
    let id=j_string(sketch,"id");let row=pc_first(nodes);while row {
        if m_eq(j_string(row,"sketchId"),id) && (po_profile_node(row) || m_eq(j_string(row,"type"),"sketchSpline") || m_eq(j_string(j_get(row,"primitive"),"type"),"ellipse")) {return 1;}row=load64(row+24);
    }return 0;
}
fn po_length(x,y) {return f64_sqrt(f64_from_i64(x*x+y*y));}
fn po_scaled(n,scale) {return f64_to_i64_round(f64_mul(f64_from_i64(n),scale));}
fn po_cross(x,y,u,v) {return x*v-y*u;}
fn po_near(a,b) {return cg_abs(load64(a)-load64(b))<=500 && cg_abs(load64(a+8)-load64(b+8))<=500;}
fn po_bounded(x,y) {
    if cg_abs(x)>500000000 || cg_abs(y)>500000000 {return cg_fail("Offset exceeds sketch coordinate range");}
    return cg_v(x,y,0);
}
fn po_number(row,field,value,write) {
    if cg_abs(value)>500000000 {return cg_fail("Offset exceeds sketch coordinate range");}
    let saved=pc_pose_number(j_get(row,field));if cg_error {return 0;}
    if write {if saved!=value {cg_j_set(row,field,cg_json_number(value));}return 1;}
    return cg_abs(saved-value)<=500;
}
fn po_position(row,point,write) {
    return point && po_number(row,"x",load64(point),write) && po_number(row,"y",load64(point+8),write);
}
fn po_segment(src,reverse,distance) {
    let a=pc_uv(j_get(src,"p0"));let b=pc_uv(j_get(src,"p1"));
    if reverse {let swap=a;a=b;b=swap;}
    let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
    if !dx && !dy {return cg_fail("Cannot offset a zero-length line");}
    let scale=f64_div(f64_from_i64(distance),po_length(dx,dy));
    let nx=po_scaled(-dy,scale);let ny=po_scaled(dx,scale);
    // Untrimmed ends can lie outside the sketch before their miter is cut.
    let seg=m_take(48);store64(seg,a);store64(seg+8,b);store64(seg+16,dx);store64(seg+24,dy);
    store64(seg+32,cg_v(load64(a)+nx,load64(a+8)+ny,0));store64(seg+40,cg_v(load64(b)+nx,load64(b+8)+ny,0));
    return seg;
}
fn po_join(left,right) {
    if !po_near(load64(left+8),load64(right)) {return cg_fail("Offset chain source endpoints are disconnected");}
    let dx=load64(left+16);let dy=load64(left+24);let ex=load64(right+16);let ey=load64(right+24);
    let a=load64(left+40);let b=load64(right+32);let det=po_cross(dx,dy,ex,ey);let join=0;
    let limit=f64_mul(f64_mul(po_length(dx,dy),po_length(ex,ey)),0x3ddb7cdfd9d7bdbb);
    if !det || f64_lt(f64_from_i64(cg_abs(det)),limit) {
        if dx*ex+dy*ey<=0 {return cg_fail("Offset cannot join a reversing corner");}
        join=po_bounded((load64(a)+load64(b))/2,(load64(a+8)+load64(b+8))/2);
    }else {
        let t=f64_div(f64_from_i64(po_cross(load64(b)-load64(a),load64(b+8)-load64(a+8),ex,ey)),f64_from_i64(det));
        // Bound the float before converting an almost-parallel intersection.
        let x=f64_add(f64_from_i64(load64(a)),f64_mul(t,f64_from_i64(dx)));
        let y=f64_add(f64_from_i64(load64(a+8)),f64_mul(t,f64_from_i64(dy)));
        let bound=f64_from_i64(500000000);
        if f64_lt(bound,f64_magnitude(x)) || f64_lt(bound,f64_magnitude(y)) {return cg_fail("Offset miter exceeds sketch coordinate range");}
        join=cg_v(f64_to_i64_round(x),f64_to_i64_round(y),0);
    }
    if !join {return 0;}store64(left+40,join);store64(right+32,join);return 1;
}
fn po_lines(pairs,closed,distance,write) {
    let segments=cg_array();let n=cg_count(pairs);let i=0;while i<n {
        let pair=cg_at(pairs,i);let seg=po_segment(load64(pair),load64(pair+16),distance);if !seg {return 0;}
        cg_push(segments,seg);i=i+1;
    }
    i=0;while i<n-1+closed {if !po_join(cg_at(segments,i),cg_at(segments,(i+1)%n)) {return 0;}i=i+1;}
    i=0;while i<n {
        let seg=cg_at(segments,i);let a=load64(seg+32);let b=load64(seg+40);
        if (load64(b)-load64(a))*load64(seg+16)+(load64(b+8)-load64(a+8))*load64(seg+24)<=10000 {return cg_fail("Offset collapses or reverses an edge");}
        let j=i+2;while j<n {
            let other=cg_at(segments,j);if !cg_step() {return 0;}
            if !(closed && !i && j==n-1) && pc_crossing(a,b,load64(other+32),load64(other+40)) {return cg_fail("Offset intersects itself");}
            j=j+1;
        }
        let dst=load64(cg_at(pairs,i)+8);
        if !po_position(j_get(dst,"p0"),a,write) || !po_position(j_get(dst,"p1"),b,write) {return 0;}
        i=i+1;
    }return 1;
}
fn po_size(src,dst,field,delta,write) {
    let n=pc_pose_number(j_get(src,field))+delta;
    if n<=1 {return cg_fail("Offset would collapse the profile");}return po_number(dst,field,n,write);
}
fn po_same(src,dst,field,write) {
    let a=j_get(src,field);let b=j_get(dst,field);if !a || !b {return 0;}
    if write {cg_j_set(dst,field,j_parse(j_encode(a)));return 1;}
    if m_eq(field,"startAngle") || m_eq(field,"sweep") {
        return cg_abs(pc_serial_number(a,12,1000000000000,1000000)-pc_serial_number(b,12,1000000000000,1000000))<=100000;
    }
    return cg_abs(pc_pose_number(a)-pc_pose_number(b))<=10;
}
fn po_shape(src,dst,distance,write) {
    let type=j_string(src,"type");if !m_eq(type,j_string(dst,"type")) {return 0;}
    if m_eq(type,"sketchCornerRectangle") {
        let a=pc_uv(j_get(src,"p0"));let b=pc_uv(j_get(src,"p1"));let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
        if cg_abs(dx)+2*distance<=1 || cg_abs(dy)+2*distance<=1 {return cg_fail("Offset would collapse the rectangle");}
        let x=distance;let y=distance;if dx<0 {x=-x;}if dy<0 {y=-y;}
        return po_position(j_get(dst,"p0"),cg_v(load64(a)-x,load64(a+8)-y,0),write)
            && po_position(j_get(dst,"p1"),cg_v(load64(b)+x,load64(b+8)+y,0),write);
    }
    let key="primitive";if m_eq(type,"sketchArc") {key="arc";}else if !m_eq(type,"sketchPrimitive") {return cg_fail("Unsupported offset source");}
    src=j_get(src,key);dst=j_get(dst,key);type=j_string(src,"type");if !m_eq(type,j_string(dst,"type")) {return 0;}
    if m_eq(type,"capsule") {
        return po_position(j_get(dst,"from"),pc_uv(j_get(src,"from")),write) && po_position(j_get(dst,"to"),pc_uv(j_get(src,"to")),write)
            && po_size(src,dst,"width",2*distance,write);
    }
    if !po_position(j_get(dst,"center"),pc_uv(j_get(src,"center")),write) {return 0;}
    if m_eq(type,"rectangle") {return po_same(src,dst,"rotation",write) && po_size(src,dst,"width",2*distance,write) && po_size(src,dst,"height",2*distance,write);}
    if m_eq(type,"arc") && (!po_same(src,dst,"startAngle",write) || !po_same(src,dst,"sweep",write)) {return 0;}
    if m_eq(type,"polygon") {
        let n=j_integer(src,"sides");if n<3 || n>64 || j_integer(dst,"sides")!=n || !po_same(src,dst,"rotation",write) {return 0;}
        distance=f64_to_i64_round(f64_div(f64_from_i64(distance),f64_cos(f64_div(0x400921fb54442d18,f64_from_i64(n)))));
    }else if !m_eq(type,"circle") && !m_eq(type,"arc") {return cg_fail("Unsupported offset primitive");}
    return po_size(src,dst,"radius",distance,write);
}
// Each pair holds the source node, target node and source orientation.
fn po_pair(nodes,sk,a,b,reverse,owners,rel) {
    let src=pc_find(nodes,a);let dst=pc_find(nodes,b);
    if !m_len(a) || !m_len(b) || !src || !dst || src==dst || !m_eq(j_string(src,"sketchId"),sk) || !m_eq(j_string(dst,"sketchId"),sk) {return cg_fail("Missing or invalid offset member");}
    if j_get(owners,b) {return cg_fail("Offset target has multiple drivers");}
    cg_j_text(owners,b,j_string(rel,"id"));return cg_v(src,dst,reverse);
}
fn pc_linked_sketch(sketch) {return po_first(sketch) || pp_first(sketch);}
fn pc_evaluate_links(nodes,sketch,write) {
    if !pc_linked_sketch(sketch) {return 1;}
    let sk=j_string(sketch,"id");let owners=j_object();let members=j_object();let pending=cg_array();let complete=j_object();let seen=j_object();
    let rel=pc_first(j_get(sketch,"relations"));while rel {
        let kind=po_kind(rel);let pattern=pp_kind(rel);if kind || pattern {
            let id=j_string(rel,"id");if !m_len(id) || j_get(seen,id) {return cg_fail("Duplicate or unnamed linked sketch relation");}cg_j_int(seen,id,1);
            if j_get(rel,"expression") || j_value(j_get(rel,"reference")) {return cg_fail("Unsupported offset annotation");}
            let pairs=cg_array();let side=1;let closed=0;
            if pattern {pairs=pp_pairs(nodes,sk,rel,owners,members);if !pairs {return 0;}}else if kind==1 {
                let pair=po_pair(nodes,sk,j_string(rel,"a"),j_string(rel,"b"),0,owners,rel);if !pair {return 0;}cg_push(pairs,pair);
            }else {
                side=j_integer(rel,"side");let flag=j_get(rel,"closed");closed=j_value(flag);
                let src=pc_first(j_get(rel,"sources"));let dst=pc_first(j_get(rel,"targets"));
                if (side!=1 && side!=-1) || j_kind(flag)!=5 {return cg_fail("Invalid offset chain side or closure");}
                let distinct=j_object();while src && dst {
                    let rev=j_get(src,"reversed");if j_kind(rev)!=5 || j_kind(dst)!=2 {return cg_fail("Invalid offset chain members");}
                    let a=j_string(src,"entityId");let b=j_value(dst);if j_get(distinct,a) || j_get(distinct,b) {return cg_fail("Repeated offset chain member");}
                    cg_j_int(distinct,a,1);cg_j_int(distinct,b,1);
                    let pair=po_pair(nodes,sk,a,b,j_value(rev),owners,rel);if !pair {return 0;}
                    if !m_eq(j_string(load64(pair),"type"),"sketchLine") || !m_eq(j_string(load64(pair+8),"type"),"sketchLine") {return cg_fail("Offset chains require lines");}
                    cg_push(pairs,pair);src=load64(src+24);dst=load64(dst+24);
                }
                if src || dst || cg_count(pairs)<2 || (closed && cg_count(pairs)<3) {return cg_fail("Invalid offset chain length");}
            }
            let op=m_take(32);store64(op,rel);store64(op+8,pairs);store64(op+16,side);store64(op+24,closed);cg_push(pending,op);
        }
        rel=load64(rel+24);
    }
    let remaining=cg_count(pending);while remaining {
        let previous=remaining;let i=0;while i<cg_count(pending) {
            let op=cg_at(pending,i);rel=load64(op);let id=j_string(rel,"id");let pairs=load64(op+8);let ready=!j_get(complete,id);let j=0;
            while ready && j<cg_count(pairs) {
                let owner=j_get(owners,j_string(load64(cg_at(pairs,j)),"id"));if owner && !j_get(complete,j_value(owner)) {ready=0;}
                j=j+1;
            }
            let pattern=pp_kind(rel);
            if ready && pattern==2 {
                let owner=j_get(owners,j_string(j_get(rel,"centerAnchor"),"entityId"));if owner && !j_get(complete,j_value(owner)) {ready=0;}
            }
            if ready {
                if pattern {if !pp_apply(nodes,sk,rel,pairs,write) {return 0;}}else {
                let distance=pc_pose_number(j_get(rel,"value"))*load64(op+16);if !distance {return cg_fail("Offset distance must be nonzero");}
                let pair=cg_at(pairs,0);let ok=0;
                if m_eq(j_string(load64(pair),"type"),"sketchLine") {
                    if m_eq(j_string(load64(pair+8),"type"),"sketchLine") {ok=po_lines(pairs,load64(op+24),distance,write);}
                }else {ok=po_shape(load64(pair),load64(pair+8),distance,write);}
                if !ok || cg_error {return cg_fail(m_cat("Offset geometry disagrees with relation: ",id));}
                }
                cg_j_int(complete,id,1);remaining=remaining-1;
            }
            if !cg_step() {return 0;}i=i+1;
        }
        if remaining==previous {return cg_fail("Cyclic linked sketch dependencies");}
    }return 1;
}
fn po_target(rel,id) {
    if po_kind(rel)==1 {return m_eq(j_string(rel,"b"),id);}
    let p=pc_first(j_get(rel,"targets"));while p {if m_eq(j_value(p),id) {return 1;}p=load64(p+24);}return 0;
}
fn po_owner(records,id) {
    if !m_len(id) {return 0;}let i=0;while i<cg_count(records) {
        let rel=load64(cg_at(records,i));if po_kind(rel) && po_target(rel,id) {return rel;}i=i+1;
    }return 0;
}
fn po_coincidence(model,a,b,id) {
    let row=j_object();cg_j_text(row,"id",id);cg_j_text(row,"type","coincident");cg_j_text(row,"from",a);cg_j_text(row,"to",b);
    j_add(j_get(model,"constraints"),0,row);return 1;
}
fn po_source_key(ids,member,tail) {
    let key="p0";if tail!=j_value(j_get(member,"reversed")) {key="p1";}
    return j_string(j_get(ids,j_string(member,"entityId")),key);
}
fn po_solver_links(model,ids,rel,key) {
    if po_kind(rel)==1 {
        let a=j_string(j_get(ids,j_string(rel,"a")),"center");
        if m_len(a) {po_coincidence(model,a,j_string(j_get(ids,j_string(rel,"b")),"center"),key);}return 1;
    }
    let first=pc_first(j_get(rel,"sources"));let p=first;let i=0;while p {
        let next=load64(p+24);if !next && j_value(j_get(rel,"closed")) {next=first;}
        if next {po_coincidence(model,po_source_key(ids,p,1),po_source_key(ids,next,0),m_cat(key,m_cat("j",m_int(i))));}
        p=load64(p+24);i=i+1;
    }return 1;
}
