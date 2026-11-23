// Bounded faces of the projected sketch's planar arrangement. Segment and
// endpoint order come from the graph and determine the saved profile ordinal.
import "contour.flex";
import "../../lib/f64-math.flex";

fn pc_arrangement_distance2(a,b) {
    let x=load64(a)-load64(b);let y=load64(a+8)-load64(b+8);
    return x*x+y*y;
}

fn pc_arrangement_interior(p,a,b) {
    let length=f64_sqrt(f64_from_i64(pc_arrangement_distance2(a,b)));
    if f64_lt(length,f64_from_i64(10))
        || pc_arrangement_distance2(a,p)<100 || pc_arrangement_distance2(b,p)<100 {return 0;}
    let miss=f64_from_i64(cg_abs(pc_turn(a,b,p)));
    if f64_lt(f64_mul(f64_from_i64(10),length),miss) {return 0;}
    let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
    let dot=(load64(p)-load64(a))*dx+(load64(p+8)-load64(a+8))*dy;
    let extent=dx*dx+dy*dy;
    if dot<=0 || dot>=extent {return 0;}
    return f64_div(f64_from_i64(dot),f64_from_i64(extent));
}

fn pc_arrangement_crossing(a,b,c,d) {
    let rx=load64(b)-load64(a);let ry=load64(b+8)-load64(a+8);
    let sx=load64(d)-load64(c);let sy=load64(d+8)-load64(c+8);
    let denominator=rx*sy-ry*sx;
    if cg_abs(denominator)<=1 {return 0;}
    let x=load64(c)-load64(a);let y=load64(c+8)-load64(a+8);
    let q=f64_from_i64(denominator);
    let t=f64_div(f64_from_i64(x*sy-y*sx),q);
    let u=f64_div(f64_from_i64(x*ry-y*rx),q);
    let margin=f64_div(0x3ff0000000000000,f64_from_i64(1000000));
    let upper=f64_sub(0x3ff0000000000000,margin);
    if f64_lt(margin,t) && f64_lt(t,upper) && f64_lt(margin,u) && f64_lt(u,upper) {return t;}
    return 0;
}

fn pc_arrangement_endpoint_needed(point,segments) {
    let incident=0;let i=0;
    while i<cg_count(segments) {
        if !cg_step() {return 0;}
        let segment=cg_at(segments,i);let a=load64(segment);let b=load64(segment+8);
        incident=incident+(pc_arrangement_distance2(point,a)<=100)+(pc_arrangement_distance2(point,b)<=100);
        if incident>2 || pc_arrangement_interior(point,a,b) {return 1;}
        i=i+1;
    }
    return 0;
}

fn pc_arrangement_needed(segments) {
    let i=0;
    while i<cg_count(segments) && !cg_error {
        let segment=cg_at(segments,i);let a=load64(segment);let b=load64(segment+8);
        if pc_arrangement_endpoint_needed(a,segments) || pc_arrangement_endpoint_needed(b,segments) {return 1;}
        let j=i+1;
        while j<cg_count(segments) {
            if !cg_step() {return 0;}
            let other=cg_at(segments,j);
            if pc_arrangement_crossing(a,b,load64(other),load64(other+8)) {return 1;}
            j=j+1;
        }
        i=i+1;
    }
    return 0;
}

// Cuts are sorted within one original segment. Equal values keep their order.
fn pc_arrangement_insert(array,value,offset) {
    let index=cg_count(array);if !cg_push(array,value) {return 0;}
    let slots=load64(array+16);let key=value;if offset>=0 {key=load64(value+offset);}
    while index {
        if !cg_step() {return 0;}
        let previous=load64(slots+(index-1)*8);
        let test=previous;if offset>=0 {test=load64(previous+offset);}
        if !f64_lt(key,test) {store64(slots+index*8,value);return 1;}
        store64(slots+index*8,previous);index=index-1;
    }
    store64(slots+index*8,value);return 1;
}

fn pc_arrangement_lerp(a,b,t) {
    if !t {return a;}
    if t==0x3ff0000000000000 {return b;}
    let x=f64_add(f64_from_i64(load64(a)),f64_mul(t,f64_from_i64(load64(b)-load64(a))));
    let y=f64_add(f64_from_i64(load64(a+8)),f64_mul(t,f64_from_i64(load64(b+8)-load64(a+8))));
    return cg_v(f64_to_i64_round(x),f64_to_i64_round(y),0);
}

// Vertex: local point, outgoing half-edges, surviving degree.
fn pc_arrangement_vertex(vertices,point) {
    let i=0;
    while i<cg_count(vertices) {
        if !cg_step() {return 0;}
        let vertex=cg_at(vertices,i);
        if pc_arrangement_distance2(point,load64(vertex))<=10000 {return vertex;}
        i=i+1;
    }
    return cg_push(vertices,cg_v(point,cg_array(),0));
}

// Edge: alive flag, source row, forward and reverse half-edges.
// Half-edge: origin, destination, twin, edge, seen, angle and next.
fn pc_arrangement_half(a,b,twin,edge) {
    let half=m_take(56);let p=load64(a);let q=load64(b);
    store64(half,a);store64(half+8,b);store64(half+16,twin);store64(half+24,edge);store64(half+32,0);
    store64(half+40,f64_atan2(f64_from_i64(load64(q+8)-load64(p+8)),f64_from_i64(load64(q)-load64(p))));
    store64(half+48,0);cg_push(load64(a+8),half);return half;
}

fn pc_arrangement_piece(vertices,edges,a,b,source) {
    let u=pc_arrangement_vertex(vertices,a);let v=pc_arrangement_vertex(vertices,b);
    if !u || !v {return 0;}if u==v {return 1;}
    let outgoing=load64(u+8);let i=0;
    while i<cg_count(outgoing) {
        if !cg_step() {return 0;}
        if load64(cg_at(outgoing,i)+8)==v {return 1;}
        i=i+1;
    }
    let edge=m_take(32);store64(edge,1);store64(edge+8,source);
    let forward=pc_arrangement_half(u,v,0,edge);let reverse=pc_arrangement_half(v,u,forward,edge);
    store64(forward+16,reverse);store64(edge+16,forward);store64(edge+24,reverse);
    store64(u+16,load64(u+16)+1);store64(v+16,load64(v+16)+1);
    cg_push(edges,edge);return !cg_error;
}

fn pc_arrangement_split(segments,vertices,edges) {
    let i=0;
    while i<cg_count(segments) && !cg_error {
        let segment=cg_at(segments,i);let a=load64(segment);let b=load64(segment+8);
        let cuts=cg_array();cg_push(cuts,0x3ff0000000000000);let j=0;
        while j<cg_count(segments) {
            if !cg_step() {return 0;}
            if j!=i {
                let other=cg_at(segments,j);let c=load64(other);let d=load64(other+8);
                let t=pc_arrangement_interior(c,a,b);if t && !pc_arrangement_insert(cuts,t,-1) {return 0;}
                t=pc_arrangement_interior(d,a,b);if t && !pc_arrangement_insert(cuts,t,-1) {return 0;}
                t=pc_arrangement_crossing(a,b,c,d);if t && !pc_arrangement_insert(cuts,t,-1) {return 0;}
            }
            j=j+1;
        }
        let length=f64_sqrt(f64_from_i64(pc_arrangement_distance2(a,b)));
        let start=0;let first=a;j=0;
        while j<cg_count(cuts) {
            let t=cg_at(cuts,j);
            if !f64_lt(f64_mul(f64_sub(t,start),length),f64_from_i64(10)) {
                let next=pc_arrangement_lerp(a,b,t);
                if !pc_arrangement_piece(vertices,edges,first,next,load64(segment+16)) {return 0;}
                start=t;first=next;
            }
            j=j+1;
        }
        i=i+1;
    }
    return !cg_error;
}

fn pc_arrangement_prune(vertices) {
    let queue=cg_array();let i=0;
    while i<cg_count(vertices) {
        let vertex=cg_at(vertices,i);if load64(vertex+16)==1 {cg_push(queue,vertex);}
        i=i+1;
    }
    i=0;
    while i<cg_count(queue) {
        let vertex=cg_at(queue,i);let outgoing=load64(vertex+8);let j=0;
        while j<cg_count(outgoing) {
            if !cg_step() {return 0;}
            let half=cg_at(outgoing,j);let edge=load64(half+24);
            if load64(edge) {
                store64(edge,0);let other=load64(half+8);
                store64(vertex+16,load64(vertex+16)-1);store64(other+16,load64(other+16)-1);
                if load64(other+16)==1 {cg_push(queue,other);}
            }
            j=j+1;
        }
        i=i+1;
    }
    return !cg_error;
}

fn pc_arrangement_connect(vertices) {
    let i=0;
    while i<cg_count(vertices) {
        let outgoing=load64(cg_at(vertices,i)+8);let sorted=cg_array();let j=0;
        while j<cg_count(outgoing) {
            if !cg_step() {return 0;}
            let half=cg_at(outgoing,j);
            if load64(load64(half+24)) && !pc_arrangement_insert(sorted,half,40) {return 0;}
            j=j+1;
        }
        let count=cg_count(sorted);j=0;
        while j<count {
            let back=cg_at(sorted,j);
            store64(load64(back+16)+48,cg_at(sorted,(j+count-1)%count));j=j+1;
        }
        i=i+1;
    }
    return !cg_error;
}

fn pc_arrangement_face(start,loops) {
    let points=cg_array();let half=start;let twice_area=0;let origin=load64(load64(start));
    while half && !load64(half+32) {
        if !cg_step() {return 0;}
        let a=load64(load64(half));let b=load64(load64(half+8));
        twice_area=f64_add(twice_area,f64_from_i64(pc_turn(origin,a,b)));
        cg_push(points,a);store64(half+32,1);half=load64(half+48);
    }
    if half!=start {return cg_fail("Cannot trace a closed projected face");}
    // The reference threshold is 1e-9 mm², or 2000 nm² in twice-area units.
    if f64_lt(f64_from_i64(2000),twice_area) {
        if cg_count(points)<3 {return cg_fail("Degenerate projected face");}
        if !pc_boundaries_clear(points,points) {return 0;}
        cg_push(loops,cg_v(points,load64(load64(start+24)+8),0));
    }
    return !cg_error;
}

fn pc_arrangement_trace(segments,loops) {
    let vertices=cg_array();let edges=cg_array();
    if !pc_arrangement_split(segments,vertices,edges) || !pc_arrangement_prune(vertices)
        || !pc_arrangement_connect(vertices) {return 0;}
    let i=0;
    while i<cg_count(edges) {
        if !cg_step() {return 0;}
        let edge=cg_at(edges,i);
        if load64(edge) {
            let forward=load64(edge+16);let reverse=load64(edge+24);
            if !load64(forward+32) && !pc_arrangement_face(forward,loops) {return 0;}
            if !load64(reverse+32) && !pc_arrangement_face(reverse,loops) {return 0;}
        }
        i=i+1;
    }
    return !cg_error;
}
