// V4 sketch patterns. Keep source identities, target metadata and cell order.
// A cell transform holds its translation or rotation center, sine, cosine and
// angle in microdegrees. A complete turn has no duplicate endpoint.
import "project-number.flex";
import "project-nodes.flex";

fn pp_kind(rel) {
    let kind=j_string(rel,"type");if m_eq(kind,"linearPattern") {return 1;}if m_eq(kind,"circularPattern") {return 2;}return 0;
}
fn pp_first(sketch) {
    let r=pc_first(j_get(sketch,"relations"));while r && !pp_kind(r) {r=load64(r+24);}return r;
}
fn pp_targets(sketch) {
    let r=pp_first(sketch);if !r {return 0;}let ids=j_object();
    while r {
        if pp_kind(r) {
            let group=pc_first(j_get(r,"instances"));while group {
                let id=pc_first(group);while id {if j_kind(id)==2 {cg_j_text(ids,j_value(id),j_string(r,"id"));}id=load64(id+24);}
                group=load64(group+24);
            }
        }r=load64(r+24);
    }return ids;
}
fn pp_refers_to_copy(rel,copies) {
    return j_get(copies,j_string(rel,"entityId")) || j_get(copies,j_string(rel,"symmetryLine")) ||
        j_get(copies,j_string(j_get(rel,"a"),"entityId")) || j_get(copies,j_string(j_get(rel,"b"),"entityId")) ||
        j_get(copies,j_string(j_get(rel,"anchor"),"entityId")) || j_get(copies,j_string(rel,"a")) || j_get(copies,j_string(rel,"b"));
}
fn pp_anchor(nodes,sk,anchor) {
    let node=pc_find(nodes,j_string(anchor,"entityId"));if !node || !m_eq(j_string(node,"sketchId"),sk) {return 0;}
    let key=j_string(anchor,"point");let type=j_string(node,"type");
    if m_eq(type,"sketchLine") && (m_eq(key,"p0") || m_eq(key,"p1")) {return j_get(node,key);}
    let primitive=j_get(node,"primitive");
    if m_eq(type,"sketchPrimitive") && m_eq(j_string(primitive,"type"),"capsule")
        && (m_eq(key,"from") || m_eq(key,"to")) {return j_get(primitive,key);}
    if m_eq(key,"center") {
        let geom=j_get(node,"arc");if !geom {geom=j_get(node,"primitive");}
        let kind=j_string(geom,"type");
        if m_eq(kind,"circle") || m_eq(kind,"point") || m_eq(kind,"arc") || m_eq(kind,"ellipse") || m_eq(kind,"ellipticArc") {return j_get(geom,"center");}
    }
    if m_eq(type,"sketchSpline") {
        let p=pc_first(j_get(j_get(node,"spline"),"points"));let i=0;while p {
            if m_eq(key,m_cat("point",m_int(i))) {return p;}p=load64(p+24);i=i+1;
        }
    }return 0;
}
fn pp_columns(rel,cells) {if j_get(rel,"columns") {return j_integer(rel,"columns");}return cells;}
fn pp_row_step(rel) {let pt=j_get(rel,"rowStep");if pt {return pc_uv(pt);}return cg_v(0,20000000,0);}
fn pp_layout(nodes,sk,rel,cells,write) {
    let layout=m_take(40);let kind=pp_kind(rel);store64(layout,kind);store64(layout+32,cells);
    if kind==1 {
        let cols=pp_columns(rel,cells);let a=pc_uv(j_get(rel,"step"));let b=pp_row_step(rel);
        if cols<1 || cols>cells || cells%cols || !(load64(a) || load64(a+8)) || !(load64(b) || load64(b+8)) {return cg_fail("Invalid pattern columns or spacing");}
        store64(layout+8,cols);store64(layout+16,a);store64(layout+24,b);
    }else {
        let saved=j_get(rel,"center");let center=pc_uv(saved);let anchor=j_get(rel,"centerAnchor");
        if anchor {
            let pos=pp_anchor(nodes,sk,anchor);if !pos {return cg_fail("Missing circular pattern center anchor");}
            center=pc_uv(pos);if !po_position(saved,center,write) {return cg_fail("Pattern center disagrees with its anchor");}
        }
        let angle=pc_pose_number(j_get(rel,"angle"));if !angle || cg_abs(angle)>360000000 {return cg_fail("Pattern angle must be nonzero and within one turn");}
        let divisor=cells-1;if cg_abs(angle)==360000000 {divisor=cells;}
        store64(layout+8,divisor);store64(layout+16,center);store64(layout+24,angle);
    }
    if cg_error {return 0;}return layout;
}
fn pp_cell(layout,index) {
    let pivot=load64(layout+16);let other=load64(layout+24);let divisor=load64(layout+8);
    let t=m_take(40);
    if load64(layout)==1 {
        store64(t,cg_v(load64(pivot)*(index%divisor)+load64(other)*(index/divisor),load64(pivot+8)*(index%divisor)+load64(other+8)*(index/divisor),0));
        store64(t+24,0);return t;
    }
    let degrees=f64_div(f64_from_i64(other*index),f64_from_i64(divisor));let radians=f64_mul(f64_div(degrees,f64_from_i64(180000000)),0x400921fb54442d18);
    store64(t,pivot);store64(t+8,f64_cos(radians));store64(t+16,f64_sin(radians));store64(t+24,1);store64(t+32,f64_to_i64_round(degrees));return t;
}
fn pp_image(point,t) {
    let pivot=load64(t);let x=load64(point);let y=load64(point+8);
    if !load64(t+24) {return cg_v(x+load64(pivot),y+load64(pivot+8),0);}
    let dx=f64_from_i64(x-load64(pivot));let dy=f64_from_i64(y-load64(pivot+8));let c=load64(t+8);let s=load64(t+16);
    return cg_v(load64(pivot)+f64_to_i64_round(f64_sub(f64_mul(dx,c),f64_mul(dy,s))),
        load64(pivot+8)+f64_to_i64_round(f64_add(f64_mul(dx,s),f64_mul(dy,c))),0);
}
fn pp_xy(src,dst,key,t,write) {
    return po_position(j_get(dst,key),pp_image(pc_uv(j_get(src,key)),t),write);
}
fn pp_field(src,dst,key,write) {
    let a=j_get(src,key);let b=j_get(dst,key);if !a && !b {return 1;}if !a || !b {return 0;}
    if write {cg_j_set(dst,key,j_parse(j_encode(a)));return 1;}
    if j_kind(a)==1 || j_kind(a)==6 {
        if m_eq(key,"sweep") || m_eq(key,"startAngle") {return po_same(src,dst,key,0);}
        if m_eq(key,"segments") || m_eq(key,"arcSegments") || m_eq(key,"sides") {return j_kind(b)==1 && j_value(a)==j_value(b);}
        return cg_abs(pc_pose_number(a)-pc_pose_number(b))<=500;
    }return m_eq(j_encode(a),j_encode(b));
}
fn pp_geometry(src,dst,t,write) {
    let type=j_string(src,"type");let circular=load64(t+24);let angle=0;if circular {angle=load64(t+32);}
    if circular && m_eq(type,"sketchCornerRectangle") {
        if !m_eq(j_string(dst,"type"),"sketchPrimitive") {return 0;}
        dst=j_get(dst,"primitive");if !m_eq(j_string(dst,"type"),"rectangle") {return 0;}
        let a=pc_uv(j_get(src,"p0"));let b=pc_uv(j_get(src,"p1"));let mid=cg_v((load64(a)+load64(b))/2,(load64(a+8)+load64(b+8))/2,0);
        return po_position(j_get(dst,"center"),pp_image(mid,t),write) && po_number(dst,"width",cg_abs(load64(b)-load64(a)),write) &&
            po_number(dst,"height",cg_abs(load64(b+8)-load64(a+8)),write) && po_number(dst,"rotation",angle,write);
    }
    if !m_eq(type,j_string(dst,"type")) {return 0;}
    if m_eq(type,"sketchLine") || m_eq(type,"sketchCornerRectangle") {return pp_xy(src,dst,"p0",t,write) && pp_xy(src,dst,"p1",t,write);}
    if m_eq(type,"sketchSpline") {
        src=j_get(src,"spline");dst=j_get(dst,"spline");if !pp_field(src,dst,"mode",write) || !pp_field(src,dst,"closed",write) {return 0;}
        let a=pc_first(j_get(src,"points"));let b=pc_first(j_get(dst,"points"));
        while a && b {if !cg_step() || !po_position(b,pp_image(pc_uv(a),t),write) {return 0;}a=load64(a+24);b=load64(b+24);}
        return !a && !b;
    }
    let key="primitive";if m_eq(type,"sketchArc") {key="arc";}else if !m_eq(type,"sketchPrimitive") {return 0;}
    src=j_get(src,key);dst=j_get(dst,key);type=j_string(src,"type");if !m_eq(type,j_string(dst,"type")) {return 0;}
    if m_eq(type,"capsule") {return pp_xy(src,dst,"from",t,write) && pp_xy(src,dst,"to",t,write) && pp_field(src,dst,"width",write) && pp_field(src,dst,"arcSegments",write);}
    if !pp_xy(src,dst,"center",t,write) {return 0;}
    if m_eq(type,"point") {return 1;}
    if m_eq(type,"circle") || m_eq(type,"arc") || m_eq(type,"polygon") {
        if !pp_field(src,dst,"radius",write) {return 0;}
    }else if m_eq(type,"rectangle") || m_eq(type,"ellipse") || m_eq(type,"ellipticArc") {
        if !pp_field(src,dst,"width",write) || !pp_field(src,dst,"height",write) {return 0;}
    }else {return 0;}
    if !pp_field(src,dst,"segments",write) || !pp_field(src,dst,"sides",write) {return 0;}
    if m_eq(type,"arc") {
        let rad=pc_serial_number(j_get(src,"startAngle"),12,1000000000000,1000000);
        let delta=f64_mul(f64_div(f64_from_i64(angle),f64_from_i64(180000000)),0x400921fb54442d18);
        let value=f64_add(f64_div(f64_from_i64(rad),f64_from_i64(1000000000000)),delta);
        if !pp_field(src,dst,"sweep",write) {return 0;}
        if write {cg_j_set(dst,"startAngle",pc_arc_json_angle(value));return 1;}
        return cg_abs(pc_serial_number(j_get(dst,"startAngle"),12,1000000000000,1000000)-f64_to_i64_round(f64_mul(value,f64_from_i64(1000000000000))))<=500000;
    }
    if m_eq(type,"circle") {return 1;}
    if m_eq(type,"ellipticArc") && (!pp_field(src,dst,"startAngle",write) || !pp_field(src,dst,"sweep",write)) {return 0;}
    let rotation=pc_serial_number(j_get(src,"rotation"),6,1000000,1000000)+angle;
    if write {cg_j_set(dst,"rotation",cg_json_number(rotation));return 1;}
    return cg_abs(pc_serial_number(j_get(dst,"rotation"),6,1000000,1000000)-rotation)<=500;
}
// Pattern members are unique across patterns. An offset may depend on a
// pattern copy, so share the ownership graph and evaluation order with offsets.
fn pp_pairs(nodes,sk,rel,owners,members) {
    let sources=j_get(rel,"sources");let groups=j_get(rel,"instances");let cells=cg_j_count(groups)+1;let ns=cg_j_count(sources);
    if j_get(rel,"skipped") || j_kind(sources)!=3 || j_kind(groups)!=3 || !ns || cells<2 || cells>32 || ns*(cells-1)>64 {return cg_fail("Invalid pattern size or skipped cells");}
    let s=pc_first(sources);while s {
        if j_kind(s)!=2 || j_get(members,j_value(s)) {return cg_fail("Pattern members must be distinct");}
        cg_j_int(members,j_value(s),1);s=load64(s+24);
    }
    let pairs=cg_array();let group=pc_first(groups);let index=1;while group {
        if j_kind(group)!=3 || cg_j_count(group)!=ns {return cg_fail("Pattern cell must match its sources");}
        s=pc_first(sources);let d=pc_first(group);while s {
            if j_kind(d)!=2 || j_get(members,j_value(d)) {return cg_fail("Pattern members must be distinct");}
            cg_j_int(members,j_value(d),1);let pair=po_pair(nodes,sk,j_value(s),j_value(d),index,owners,rel);if !pair {return 0;}cg_push(pairs,pair);
            s=load64(s+24);d=load64(d+24);
        }index=index+1;group=load64(group+24);
    }return pairs;
}
fn pp_apply(nodes,sk,rel,pairs,write) {
    let layout=pp_layout(nodes,sk,rel,cg_j_count(j_get(rel,"instances"))+1,write);if !layout {return 0;}
    let i=0;let previous=0;let transform=0;while i<cg_count(pairs) {
        let pair=cg_at(pairs,i);let cell=load64(pair+16);if cell!=previous {transform=pp_cell(layout,cell);previous=cell;}
        if !pp_geometry(load64(pair),load64(pair+8),transform,write) || cg_error {return cg_fail(m_cat("Pattern geometry disagrees with relation: ",j_string(rel,"id")));}
        i=i+1;
    }return 1;
}
