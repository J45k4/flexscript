// Planar predicates use integer nanometres within the project coordinate limits.
import "frame.flex";

fn pc_turn(a,b,p) {
    return (load64(b)-load64(a))*(load64(p+8)-load64(a+8))-(load64(b+8)-load64(a+8))*(load64(p)-load64(a));
}
fn pc_between(a,b,x) {return (a<=x && x<=b) || (b<=x && x<=a);}
fn pc_on_box(a,b,p) {
    return pc_between(load64(a),load64(b),load64(p)) && pc_between(load64(a+8),load64(b+8),load64(p+8));
}
fn pc_crossing(a,b,c,d) {
    let u=pc_turn(a,b,c);let v=pc_turn(a,b,d);
    let w=pc_turn(c,d,a);let z=pc_turn(c,d,b);
    if !u && pc_on_box(a,b,c) || !v && pc_on_box(a,b,d) || !w && pc_on_box(c,d,a) || !z && pc_on_box(c,d,b) {return 1;}
    return ((u<0 && v>0)||(u>0 && v<0)) && ((w<0 && z>0)||(w>0 && z<0));
}
fn pc_inside(loop,p) {
    let inside=0;let i=0;let n=cg_count(loop);
    while i<n {
        let a=cg_at(loop,i);let b=cg_at(loop,(i+1)%n);
        if (load64(a+8)>load64(p+8))!=(load64(b+8)>load64(p+8)) {
            if (pc_turn(a,b,p)>0)==(load64(b+8)>load64(a+8)) {inside=!inside;}
        }
        i=i+1;
    }
    return inside;
}
fn pc_boundaries_clear(first,second) {
    let n=cg_count(first);let m=cg_count(second);let i=0;
    while i<n && !cg_error {
        let next=(i+1)%n;let a=cg_at(first,i);let b=cg_at(first,next);let j=0;
        if first==second {j=i+2;}
        while j<m && !cg_error {
            if !cg_step() {return 0;}
            let end=(j+1)%m;
            if !(first==second && end==i) && pc_crossing(a,b,cg_at(second,j),cg_at(second,end)) {
                return cg_fail("Sketch profile loops intersect or touch");
            }
            j=j+1;
        }
        i=i+1;
    }
    return !cg_error;
}
// Vertex layout: point, degree, first incident edge, second incident edge.
// A branch needs only its degree because it cannot bound a simple component.
fn pc_endpoint(vertices,p) {
    let i=0;
    while i<cg_count(vertices) {
        if !cg_step() {return 0;}
        let vertex=cg_at(vertices,i);let q=load64(vertex);
        let dx=load64(p)-load64(q);let dy=load64(p+8)-load64(q+8);
        if dx*dx+dy*dy<=1 {return vertex;}
        i=i+1;
    }
    let vertex=m_take(32);store64(vertex,p);store64(vertex+8,0);
    return cg_push(vertices,vertex);
}
fn pc_incident(vertex,edge) {
    let degree=load64(vertex+8);
    if degree<2 {store64(vertex+16+8*degree,edge);}
    store64(vertex+8,degree+1);
    return 1;
}
fn pc_add_segment(vertices,edges,row,a,b) {
    let start=pc_endpoint(vertices,a);let end=pc_endpoint(vertices,b);
    if !start || !end || start==end {return 0;}
    let edge=m_take(32);store64(edge,start);store64(edge+8,end);
    store64(edge+16,0);store64(edge+24,row);
    pc_incident(start,edge);pc_incident(end,edge);
    return cg_push(edges,edge);
}
fn pc_orient_contour(points) {
    let n=cg_count(points);
    if n<3 {return cg_fail("Degenerate sketch contour");}
    if !pc_boundaries_clear(points,points) {return 0;}
    // At the leftmost, then lowest vertex the turn is convex. This avoids
    // accumulating a shoelace sum that might overflow on a long contour.
    let index=0;let i=1;
    while i<n {
        let p=cg_at(points,i);let q=cg_at(points,index);
        if load64(p)<load64(q) || (load64(p)==load64(q) && load64(p+8)<load64(q+8)) {index=i;}
        i=i+1;
    }
    let turn=pc_turn(cg_at(points,(index+n-1)%n),cg_at(points,index),cg_at(points,(index+1)%n));
    if !turn {return cg_fail("Degenerate sketch contour");}
    if turn>0 {return points;}
    let reversed=cg_array();i=n;
    while i>0 && !cg_error {i=i-1;cg_push(reversed,cg_at(points,i));}
    return reversed;
}
fn pc_trace_contours(edges,loops) {
    let i=0;
    while i<cg_count(edges) && !cg_error {
        let first=cg_at(edges,i);let edge=first;let start=load64(first);let from=start;
        let points=cg_array();
        while edge && !load64(edge+16) && load64(from+8)==2 && !cg_error {
            store64(edge+16,1);cg_push(points,load64(from));
            let to=load64(edge+8);if from==to {to=load64(edge);}
            if to==start {
                let contour=pc_orient_contour(points);
                if contour {cg_push(loops,cg_v(contour,load64(first+24),0));}
                edge=0;
            }else if load64(to+8)!=2 {edge=0;}
            else {
                let next=load64(to+16);if next==edge {next=load64(to+24);}
                from=to;edge=next;
            }
        }
        i=i+1;
    }
    return !cg_error;
}
// Concave prism caps are split into convex faces before entering the BSP.
fn pc_cap_triangle(faces,bottom,top,a,b,c) {
    cg_face(faces,cg_at(bottom,c),cg_at(bottom,b),cg_at(bottom,a),0);
    cg_face(faces,cg_at(top,a),cg_at(top,b),cg_at(top,c),0);
    return !cg_error;
}
fn pc_prism_caps(points,bottom,top,faces) {
    let n=cg_count(points);let i=0;let concave=0;
    while i<n && !concave {
        if pc_turn(cg_at(points,(i+n-1)%n),cg_at(points,i),cg_at(points,(i+1)%n))<=0 {concave=1;}
        i=i+1;
    }
    if !concave {
        let cap=cg_poly(bottom);if !cap {return cg_fail("Degenerate extrusion cap");}
        cg_flip(cap);cg_push(faces,cap);cg_push(faces,cg_poly(top));return !cg_error;
    }
    let next=m_take(n*8);i=0;
    while i<n {store64(next+i*8,(i+1)%n);i=i+1;}
    let left=n;let a=0;let skipped=0;
    while left>3 && !cg_error {
        if !cg_step() {return 0;}
        let b=load64(next+a*8);let c=load64(next+b*8);
        let p=cg_at(points,a);let q=cg_at(points,b);let r=cg_at(points,c);
        let ear=pc_turn(p,q,r)>0;let j=load64(next+c*8);
        while ear && j!=a {
            if !cg_step() {return 0;}
            let s=cg_at(points,j);
            // A cut connecting an inner boundary repeats both endpoints.
            if s!=p && s!=q && s!=r && pc_turn(p,q,s)>=0 && pc_turn(q,r,s)>=0 && pc_turn(r,p,s)>=0 {ear=0;}
            j=load64(next+j*8);
        }
        if ear {
            pc_cap_triangle(faces,bottom,top,a,b,c);
            store64(next+a*8,c);left=left-1;skipped=0;
        }else {
            skipped=skipped+1;if skipped>=left {return cg_fail("Cannot triangulate sketch contour");}
            a=b;
        }
    }
    let b=load64(next+a*8);
    return pc_cap_triangle(faces,bottom,top,a,b,load64(next+b*8));
}
