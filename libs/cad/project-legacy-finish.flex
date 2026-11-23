// Legacy PartBuilder profile finishes select vertices in authored loop order.
import "profile.flex";

fn plf_near(a,b) {
    return cg_abs(load64(a)-load64(b))<=4 && cg_abs(load64(a+8)-load64(b+8))<=4;
}
fn plf_match_saved_order(points,sketch,target) {
    let profile=pc_find(j_get(sketch,"profiles"),j_string(target,"profileId"));
    let loop=pc_find(j_get(sketch,"loops"),j_string(profile,"outerLoopId"));
    let indices=j_get(loop,"vertexIndices");let count=cg_count(points);
    if j_kind(indices)!=3 || cg_j_count(indices)!=count {
        return cg_fail("Legacy profile finish needs matching saved outline vertices");
    }
    let vertices=cg_array();let vertex=pc_first(j_get(sketch,"vertices"));
    while vertex {
        if !cg_step() {return 0;}
        cg_push(vertices,vertex);vertex=load64(vertex+24);
    }
    let index=pc_first(indices);let i=0;
    while index {
        if !cg_step() {return 0;}
        let slot=j_value(index);
        if j_kind(index)!=1 || slot<0 || slot>=cg_count(vertices) {
            return cg_fail("Legacy profile finish has an invalid saved vertex index");
        }
        let saved=pc_uv(cg_at(vertices,slot));if cg_error {return 0;}
        // A cyclically shifted cache could send the same index to a different corner.
        if !plf_near(cg_at(points,i),saved) {
            return cg_fail("Legacy profile finish needs matching saved outline vertices");
        }
        i=i+1;index=load64(index+24);
    }
    return points;
}
fn plf_rotate_loop(points,start) {
    if !start {return points;}
    let ordered=cg_array();let count=cg_count(points);let i=0;
    while i<count {
        if !cg_step() {return 0;}
        cg_push(ordered,cg_at(points,(start+i)%count));i=i+1;
    }
    return ordered;
}
fn plf_sketch_order(outer,nodes,sketch,target) {
    let points=load64(outer);let source=load64(outer+8);let type=j_string(source,"type");
    if m_eq(type,"sketchPrimitive") {
        // TypeScript's rotated rectangle starts at its local upper right.
        if m_eq(j_string(j_get(source,"primitive"),"type"),"rectangle") {return plf_rotate_loop(points,2);}
        return points;
    }
    if m_eq(type,"sketchCornerRectangle") {
        // TypeScript's corner rectangle starts at the minimum x and y.
        let start=0;let i=1;
        while i<cg_count(points) {
            let p=cg_at(points,i);let q=cg_at(points,start);
            if load64(p)<=load64(q) && load64(p+8)<=load64(q+8) {start=i;}
            i=i+1;
        }
        return plf_rotate_loop(points,start);
    }
    if m_eq(type,"sketchLine") {
        // Both tracers seed polygonal chains at the first authored line and
        // reverse clockwise loops. Curve sampling has a different contract.
        let id=j_string(sketch,"id");let node=pc_first(nodes);
        while node {
            if !cg_step() {return 0;}
            if m_eq(j_string(node,"sketchId"),id) && pc_sampled_curve(node) && !cad_sketch_is_construction(node) {
                return plf_match_saved_order(points,sketch,target);
            }
            node=load64(node+24);
        }
        return points;
    }
    return plf_match_saved_order(points,sketch,target);
}
fn plf_indexed(rows) {
    let row=pc_first(rows);
    while row {
        if !cg_step() {return 0;}
        if pc_first(j_get(row,"vertices")) {return 1;}
        row=load64(row+24);
    }
    return 0;
}
fn plf_selected(finish,count) {
    let indices=j_get(finish,"vertices");let mask=m_take(count*8);let i=0;
    if indices && j_kind(indices)!=3 {return cg_fail("Legacy profile finish needs vertex indices");}
    while i<count {store64(mask+i*8,!indices);i=i+1;}
    let index=pc_first(indices);
    while index {
        if !cg_step() {return 0;}
        let slot=j_value(index);
        if j_kind(index)!=1 || slot<0 || slot>=count {return cg_fail("Unknown profile vertex");}
        store64(mask+slot*8,1);index=load64(index+24);
    }
    return mask;
}
// A finished corner stores the two unit edge directions, the half angle,
// and the tangent setback. Coordinates and setbacks are in nanometres.
fn plf_corner(previous,point,next,radius,chamfer) {
    let ux=f64_from_i64(load64(previous)-load64(point));let uy=f64_from_i64(load64(previous+8)-load64(point+8));
    let vx=f64_from_i64(load64(next)-load64(point));let vy=f64_from_i64(load64(next+8)-load64(point+8));
    let left=f64_hypot(ux,uy);let right=f64_hypot(vx,vy);
    if !left || !right {return cg_fail("Cannot finish a degenerate or straight profile corner");}
    ux=f64_div(ux,left);uy=f64_div(uy,left);vx=f64_div(vx,right);vy=f64_div(vy,right);
    let cross=f64_magnitude(f64_sub(f64_mul(ux,vy),f64_mul(uy,vx)));
    let dot=f64_add(f64_mul(ux,vx),f64_mul(uy,vy));let angle=f64_atan2(cross,dot);
    let epsilon=0x3eb0c6f7a0b5ed8d;
    if f64_lt(angle,epsilon) || f64_lt(f64_sub(0x400921fb54442d18,angle),epsilon) {
        return cg_fail("Cannot finish a degenerate or straight profile corner");
    }
    let half=f64_div(angle,f64_from_i64(2));let trim=radius;
    if !chamfer {trim=f64_div(f64_mul(radius,f64_cos(half)),f64_sin(half));}
    let out=m_take(48);
    store64(out,ux);store64(out+8,uy);store64(out+16,vx);store64(out+24,vy);
    store64(out+32,half);store64(out+40,trim);return out;
}
fn plf_trim(corner) {if corner {return load64(corner+40);}return 0;}
fn plf_point(points,x,y) {
    let u=f64_to_i64_round(x);let v=f64_to_i64_round(y);
    if cg_abs(u)>500000000 || cg_abs(v)>500000000 {return cg_fail("Profile finish exceeds sketch coordinates");}
    return cg_push(points,cg_v(u,v,0));
}
fn plf_append(points,point,corner,radius,chamfer,segments) {
    if !corner {return cg_push(points,point);}
    let x=f64_from_i64(load64(point));let y=f64_from_i64(load64(point+8));
    let ux=load64(corner);let uy=load64(corner+8);let vx=load64(corner+16);let vy=load64(corner+24);
    let trim=plf_trim(corner);
    let start_x=f64_add(x,f64_mul(ux,trim));let start_y=f64_add(y,f64_mul(uy,trim));
    let end_x=f64_add(x,f64_mul(vx,trim));let end_y=f64_add(y,f64_mul(vy,trim));
    if !plf_point(points,start_x,start_y) {return 0;}
    if !chamfer {
        let bisect_x=f64_add(ux,vx);let bisect_y=f64_add(uy,vy);
        let center_scale=f64_div(radius,f64_mul(f64_sin(load64(corner+32)),f64_hypot(bisect_x,bisect_y)));
        let center_x=f64_add(x,f64_mul(bisect_x,center_scale));let center_y=f64_add(y,f64_mul(bisect_y,center_scale));
        let start=f64_atan2(f64_sub(start_y,center_y),f64_sub(start_x,center_x));
        let end=f64_atan2(f64_sub(end_y,center_y),f64_sub(end_x,center_x));
        let sweep=f64_sub(end,start);let pi=0x400921fb54442d18;let turn=0x401921fb54442d18;
        if f64_lt(pi,sweep) {sweep=f64_sub(sweep,turn);}
        else if f64_lt(sweep,f64_math_neg(pi)) {sweep=f64_add(sweep,turn);}
        let i=1;
        while i<segments {
            if !cg_step() {return 0;}
            let sample=f64_add(start,f64_mul(sweep,f64_div(f64_from_i64(i),f64_from_i64(segments))));
            if !plf_point(points,f64_add(center_x,f64_mul(radius,f64_cos(sample))),
                f64_add(center_y,f64_mul(radius,f64_sin(sample)))) {return 0;}
            i=i+1;
        }
    }
    return plf_point(points,end_x,end_y);
}
fn plf_finish(points,finish) {
    let count=cg_count(points);
    if count<3 {return cg_fail("Legacy profile finish needs a closed outline");}
    let kind=j_string(finish,"kind");let chamfer=m_eq(kind,"chamfer");
    if !chamfer && !m_eq(kind,"fillet") {return cg_fail("Unknown legacy profile finish");}
    let size=pc_pose_number(j_get(finish,"radius"));if cg_error {return 0;}
    if size<=0 {return cg_fail("Finish radius must be positive");}
    let segments=8;let saved=j_get(finish,"segments");
    if saved {
        segments=j_value(saved);
        if j_kind(saved)!=1 || segments<1 || segments>128 {return cg_fail("Finish segments must be between 1 and 128");}
    }
    let selected=plf_selected(finish,count);if !selected {return 0;}
    let corners=m_take(count*8);let radius=f64_from_i64(size);let i=0;
    while i<count {
        if !cg_step() {return 0;}
        let corner=0;
        if load64(selected+i*8) {
            corner=plf_corner(cg_at(points,(i+count-1)%count),cg_at(points,i),cg_at(points,(i+1)%count),radius,chamfer);
            if !corner {return 0;}
        }
        store64(corners+i*8,corner);i=i+1;
    }
    let result=cg_array();i=0;
    while i<count {
        if !cg_step() {return 0;}
        let next=(i+1)%count;let p=cg_at(points,i);let q=cg_at(points,next);
        let length=f64_hypot(f64_from_i64(load64(q)-load64(p)),f64_from_i64(load64(q+8)-load64(p+8)));
        let corner=load64(corners+i*8);let setback=f64_add(plf_trim(corner),plf_trim(load64(corners+next*8)));
        if !f64_lt(setback,f64_sub(length,0x3fb999999999999a)) {
            return cg_fail("Finish radius is too large for adjacent profile edges");
        }
        if !plf_append(result,p,corner,radius,chamfer,segments) {return 0;}
        i=i+1;
    }
    return result;
}
fn plf_apply(points,rows) {
    if rows && j_kind(rows)!=3 {return cg_fail("Legacy profile finishes must be an array");}
    let row=pc_first(rows);
    while row {
        if !cg_step() {return 0;}
        points=plf_finish(points,row);if !points {return 0;}
        row=load64(row+24);
    }
    return points;
}
fn plf_extrusion(region,nodes,sketch,target,rows) {
    let outer=cg_at(region,0);let points=load64(outer);
    if !rows {return points;}
    if plf_indexed(rows) {points=plf_sketch_order(outer,nodes,sketch,target);}
    if !points || cg_error {return 0;}
    points=plf_apply(points,rows);if !points {return 0;}
    if !pc_first(rows) {return points;}
    points=pc_orient_contour(points);if !points {return 0;}
    let i=1;
    while i<cg_count(region) {
        let hole=load64(cg_at(region,i));
        if !pc_boundaries_clear(points,hole) || !pc_inside(points,cg_at(hole,0)) {
            return cg_fail("Profile finish intersects a hole");
        }
        i=i+1;
    }
    return points;
}
