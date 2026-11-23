// Recover sketch curves from the sharp edges of an evaluated planar face.
import "project-edge.flex";
import "../../lib/f64-math.flex";

// pc_body_edges shares its welded points among all edges of the body.
// Vertex fields: world point, local point, adjacency, total and curved degrees, next bin entry.
fn pc_projection_curve_vertex(bins,frame,point) {
    let slot=bins+((point/8)&4095)*8;let vertex=load64(slot);
    while vertex {
        if load64(vertex)==point {return vertex;}
        if !cg_step() {return 0;}
        vertex=load64(vertex+40);
    }
    vertex=m_take(48);store64(vertex,point);store64(vertex+8,pc_projection_uv(frame,point));
    store64(vertex+16,0);store64(vertex+24,0);store64(vertex+32,0);
    store64(vertex+40,load64(slot));store64(slot,vertex);return vertex;
}

fn pc_projection_curve_link(vertex,edge) {
    store64(vertex+16,cg_v(edge,load64(vertex+16),0));
    store64(vertex+24,load64(vertex+24)+1);
    if !load64(load64(edge)+48) {store64(vertex+32,load64(vertex+32)+1);}
    return 1;
}

fn pc_projection_curve_next(vertex,previous,curved) {
    let link=load64(vertex+16);
    while link {
        let edge=load64(link);
        if edge!=previous && (!curved || !load64(load64(edge)+48)) {return edge;}
        link=load64(link+8);
    }
    return 0;
}

// Keep the circumcenter arithmetic relative to one sampled point.
fn pc_projection_circle_center(a,b,c) {
    let x=f64_from_i64(load64(b)-load64(a));let y=f64_from_i64(load64(b+8)-load64(a+8));
    let u=f64_from_i64(load64(c)-load64(a));let v=f64_from_i64(load64(c+8)-load64(a+8));
    let cross=f64_sub(f64_mul(x,v),f64_mul(y,u));
    if f64_lt(f64_magnitude(cross),f64_from_i64(1)) {return 0;}
    let twice=f64_add(cross,cross);
    let p=f64_add(f64_mul(x,x),f64_mul(y,y));let q=f64_add(f64_mul(u,u),f64_mul(v,v));
    let cx=f64_div(f64_sub(f64_mul(p,v),f64_mul(q,y)),twice);
    let cy=f64_div(f64_sub(f64_mul(q,x),f64_mul(p,u)),twice);
    if f64_lt(f64_from_i64(1000000000),f64_magnitude(cx)) || f64_lt(f64_from_i64(1000000000),f64_magnitude(cy)) {return 0;}
    return cg_v(load64(a)+f64_to_i64_round(cx),load64(a+8)+f64_to_i64_round(cy),0);
}

fn pc_projection_curve_angle(center,point) {
    return f64_atan2(f64_from_i64(load64(point+8)-load64(center+8)),f64_from_i64(load64(point)-load64(center)));
}

fn pc_projection_curve_delta(a,b) {
    let pi=0x400921fb54442d18;let turn=0x401921fb54442d18;let delta=f64_sub(b,a);
    if f64_lt(pi,delta) {return f64_sub(delta,turn);}
    if f64_lt(delta,f64_math_neg(pi)) {return f64_add(delta,turn);}
    return delta;
}

fn pc_projection_fit_curve(points,path,representative,reversed,closed,has_curved) {
    let count=cg_count(path);let n=cg_count(points);
    // Keep a straight polygon as lines even when all vertices fit a circle.
    if n<6 || !has_curved {return 0;}
    let a=cg_at(points,0);let b=cg_at(points,n/3);let c=cg_at(points,2*n/3);
    let center=pc_projection_circle_center(a,b,c);if !center {return 0;}
    let radius=pc_line_span(center,a);
    if radius<=1 || radius>500000000 || cg_abs(load64(center))>500000000 || cg_abs(load64(center+8))>500000000 {return 0;}
    let tolerance=radius/1000;if tolerance<1000 {tolerance=1000;}
    let start=pc_projection_curve_angle(center,a);let angle=start;let sweep=0;let i=1;
    while i<=count {
        if !cg_step() {return 0;}
        let point=cg_at(points,i%n);
        if cg_abs(pc_line_span(center,point)-radius)>tolerance {return 0;}
        let next=pc_projection_curve_angle(center,point);let delta=pc_projection_curve_delta(angle,next);
        if f64_lt(f64_mul(sweep,delta),0) {return 0;}
        sweep=f64_add(sweep,delta);angle=next;i=i+1;
    }
    let turn=0x401921fb54442d18;let kind=3;let end=cg_at(points,n-1);
    if closed {
        let error=f64_to_i64_round(f64_mul(f64_sub(f64_magnitude(sweep),turn),f64_from_i64(1000000)));
        if cg_abs(error)>1 {return 0;}
        kind=2;end=a;
    }else if !f64_lt(f64_magnitude(sweep),turn) || !f64_lt(0,f64_magnitude(sweep)) {return 0;}
    if reversed {
        let first=a;a=end;end=first;
        sweep=f64_math_neg(sweep);start=angle;
    }
    let curve=m_take(80);store64(curve,a);store64(curve+8,end);store64(curve+16,load64(representative));
    store64(curve+24,0);store64(curve+32,kind);store64(curve+40,center);store64(curve+48,radius);
    store64(curve+56,count);store64(curve+64,start);store64(curve+72,sweep);return curve;
}

// Follow a simple cycle in the full graph or a run of curved chords between
// two ends. A branch or noncircular run leaves its original segments intact.
fn pc_projection_curve_trace(first,start,curved) {
    let path=cg_array();let points=cg_array();let vertex=start;let edge=first;
    let closed=0;let has_curved=0;let representative=first;let reversed=start!=load64(first+8);
    let degree=24;let visited=32;
    if curved {degree=32;visited=40;}
    while edge && !load64(edge+visited) && !load64(edge+48) && !cg_error {
        store64(edge+visited,1);cg_push(path,edge);cg_push(points,load64(vertex+8));
        let backward=vertex!=load64(edge+8);
        if load64(edge+24)<load64(representative+24) {representative=edge;reversed=backward;}
        if !load64(load64(edge)+48) {has_curved=1;}
        if backward {vertex=load64(edge+8);}else {vertex=load64(edge+16);}
        if vertex==start {closed=1;edge=0;}
        else if load64(vertex+degree)==2 {edge=pc_projection_curve_next(vertex,edge,curved);}
        else {edge=0;}
    }
    if !closed {
        if !curved || load64(vertex+degree)!=1 {return 0;}
        cg_push(points,load64(vertex+8));
    }
    let curve=pc_projection_fit_curve(points,path,representative,reversed,closed,has_curved);
    if !curve {return 0;}
    let i=0;while i<cg_count(path) {store64(cg_at(path,i)+48,curve);i=i+1;}
    store64(representative+56,1);return 1;
}

fn pc_projection_face_curves(edges,frame) {
    let curves=cg_array();if !cg_count(edges) {return curves;}
    let bins=m_take(32768);let i=0;while i<4096 {store64(bins+i*8,0);i=i+1;}
    let graph=cg_array();i=0;
    while i<cg_count(edges) && !cg_error {
        let world=cg_at(edges,i);let a=pc_projection_curve_vertex(bins,frame,load64(world));
        let b=pc_projection_curve_vertex(bins,frame,load64(world+8));if !a || !b {return 0;}
        // Edge fields: source edge, ends, input index, cycle/run visits, matched curve and emit flag.
        let edge=m_take(64);store64(edge,world);store64(edge+8,a);store64(edge+16,b);store64(edge+24,i);
        store64(edge+32,0);store64(edge+40,0);store64(edge+48,0);store64(edge+56,0);
        pc_projection_curve_link(a,edge);pc_projection_curve_link(b,edge);cg_push(graph,edge);i=i+1;
    }
    i=0;
    while i<cg_count(graph) && !cg_error {
        let edge=cg_at(graph,i);let a=load64(edge+8);let b=load64(edge+16);
        if !load64(edge+32) && load64(a+24)==2 && load64(b+24)==2 {pc_projection_curve_trace(edge,a,0);}
        i=i+1;
    }
    i=0;
    while i<cg_count(graph) && !cg_error {
        let edge=cg_at(graph,i);let a=load64(edge+8);let b=load64(edge+16);
        if !load64(edge+48) && !load64(edge+40) && !load64(load64(edge)+48) {
            if load64(a+32)==1 {pc_projection_curve_trace(edge,a,1);}
            else if load64(b+32)==1 {pc_projection_curve_trace(edge,b,1);}
        }
        i=i+1;
    }
    i=0;
    while i<cg_count(graph) && !cg_error {
        let edge=cg_at(graph,i);let curve=load64(edge+48);
        if !curve {curve=pc_projection_segment(frame,load64(edge));if curve {cg_push(curves,curve);}}
        else if load64(edge+56) {cg_push(curves,curve);}
        i=i+1;
    }
    if cg_error {return 0;}return curves;
}
