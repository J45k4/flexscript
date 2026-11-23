// Vertical decomposition of a polygonal plate with disjoint round holes.
// Produces ordinary oriented CAD polygons, usable by CSG and native assemblies.
import "board-outline.flex";
fn cb_equal(a,b) {return load64(a)==load64(b) && load64(a+8)==load64(b+8) && load64(a+16)==load64(b+16);}
fn cb_face(out,a,b,c,d) {
    let vertices=cg_array();cg_push(vertices,a);if !cb_equal(a,b) {cg_push(vertices,b);}if !cb_equal(cg_at(vertices,cg_count(vertices)-1),c) {cg_push(vertices,c);}if !cb_equal(cg_at(vertices,cg_count(vertices)-1),d) && !cb_equal(d,a) {cg_push(vertices,d);}if cg_count(vertices)>=3 {cg_push(out,cg_poly(vertices));}return 0;
}
fn cb_trap(out,x0,x1,lo0,lo1,hi0,hi1,z) {
    if hi0<lo0 || hi1<lo1 {return cg_fail("Drilled-board decomposition has crossed boundaries");}
    cb_face(out,cg_v(x0,lo0,z),cg_v(x1,lo1,z),cg_v(x1,hi1,z),cg_v(x0,hi0,z));
    cb_face(out,cg_v(x0,lo0,0),cg_v(x0,hi0,0),cg_v(x1,hi1,0),cg_v(x1,lo1,0));return 0;
}

fn cb_outline_x(ring,x) {
    let i=0;
    while i<cg_count(ring) {
        let candidate=load64(cg_at(ring,i));
        if cg_abs(candidate-x)<=100 {return candidate;}
        i=i+1;
    }
    return x;
}

fn cb_hole_rings(holes,w,h,segments,authored,outline,rings,xs) {
    let centers=cg_array();let p=load64(holes+16);
    while p && !cg_error {
        let at=cg_vector(j_get(p,"position"),0);let r=cg_number(j_get(p,"radius"));
        let x=load64(at);let y=load64(at+8);let i=0;
        if load64(at+16)!=0 || r<10000 || x-r<=0 || y-r<=0 || x+r>=w || y+r>=h
            || (authored && !cb_ring_clear(outline,at,r)) {
            return cg_fail("Drilled-board holes must be strictly inside the outline");
        }
        while i<cg_count(centers) {
            let c=cg_at(centers,i);let dx=x-load64(c);let dy=y-load64(c+8);let sum=r+load64(c+16);
            if dx*dx+dy*dy<=sum*sum {return cg_fail("Drilled-board holes must not touch or overlap");}
            i=i+1;
        }
        cg_push(centers,cg_v(x,y,r));
        let ring=cg_array();i=0;
        while i<segments {
            let angle=i*360000/segments;let vx=x+r*cg_cos(angle)/1000000;
            if authored {vx=cb_outline_x(outline,vx);}
            let point=cg_v(vx,y+r*cg_sin(angle)/1000000,0);
            cg_push(ring,point);cg_push(xs,point);i=i+1;
        }
        cg_push(rings,ring);p=load64(p+24);
    }
    return !cg_error;
}

fn cb_cuts(xs) {
    // Sort events and merge weld-equivalent x coordinates.
    let i=1;
    while i<cg_count(xs) && !cg_error {
        let v=cg_at(xs,i);let j=i;
        while j>0 && load64(cg_at(xs,j-1))>load64(v) {
            cg_step();store64(load64(xs+16)+j*8,cg_at(xs,j-1));j=j-1;
        }
        store64(load64(xs+16)+j*8,v);i=i+1;
    }
    let cuts=cg_array();let last=-1000000000;i=0;
    while i<cg_count(xs) {
        let v=cg_at(xs,i);
        if load64(v)-last>100 {last=load64(v);cg_push(cuts,cg_v(last,0,0));}
        else {store64(v,last);}
        i=i+1;
    }
    return cuts;
}

fn cb_slab(out,rings,x0,x1,z) {
    let middle=(x0+x1)/2;let hits=cg_array();let k=0;
    while k<cg_count(rings) && !cg_error {
        let ring=cg_at(rings,k);let n=0;
        while n<cg_count(ring) {
            cg_step();let a=cg_at(ring,n);let b=cg_at(ring,(n+1)%cg_count(ring));
            let ax=load64(a);let bx=load64(b);
            if (ax<middle && middle<bx)||(bx<middle && middle<ax) {
                let dy=load64(b+8)-load64(a+8);
                let y0=load64(a+8)+dy*(x0-ax)/(bx-ax);
                let y1=load64(a+8)+dy*(x1-ax)/(bx-ax);
                cg_push(hits,cg_v(y0,y1,y0+y1));
            }
            n=n+1;
        }
        k=k+1;
    }
    if cg_count(hits)%2 {return cg_fail("Incomplete drilled-board intersection");}
    k=1;
    while k<cg_count(hits) {
        let v=cg_at(hits,k);let n=k;
        while n>0 && load64(cg_at(hits,n-1)+16)>load64(v+16) {
            store64(load64(hits+16)+n*8,cg_at(hits,n-1));n=n-1;
        }
        store64(load64(hits+16)+n*8,v);k=k+1;
    }
    k=0;
    while k<cg_count(hits) && !cg_error {
        let lo=cg_at(hits,k);let hi=cg_at(hits,k+1);
        cb_trap(out,x0,x1,load64(lo),load64(lo+8),load64(hi),load64(hi+8),z);k=k+2;
    }
    return !cg_error;
}

fn cg_drilled_board(size,holes,segments) {return cg_board_outline(size,holes,segments,0);}

fn cg_board_outline(size,holes,segments,authored) {
    let out=cg_array();let w=load64(size);let h=load64(size+8);let z=load64(size+16);
    if w<10000 || h<10000 || z<10000 || j_kind(holes)!=3 || cg_j_count(holes)>20 {
        cg_fail("Drilled boards need positive dimensions and at most 20 holes");return out;
    }
    let outline=cg_array();
    if authored {
        outline=cb_outline(authored,w,h);if !outline || cg_error {return out;}
    }else {
        cg_push(outline,cg_v(0,0,0));cg_push(outline,cg_v(w,0,0));
        cg_push(outline,cg_v(w,h,0));cg_push(outline,cg_v(0,h,0));
    }
    let rings=cg_array();cg_push(rings,outline);let xs=cg_array();let i=0;
    while i<cg_count(outline) {cg_push(xs,cg_at(outline,i));i=i+1;}
    if !cb_hole_rings(holes,w,h,segments,authored,outline,rings,xs) {return out;}
    let cuts=cb_cuts(xs);i=0;
    while i+1<cg_count(cuts) && !cg_error {
        cg_step();cb_slab(out,rings,load64(cg_at(cuts,i)),load64(cg_at(cuts,i+1)),z);i=i+1;
    }
    i=0;
    while i<cg_count(rings) && !cg_error {
        let ring=cg_at(rings,i);let k=0;
        while k<cg_count(ring) {
            let a=cg_at(ring,k);let b=cg_at(ring,(k+1)%cg_count(ring));
            let top_a=cg_v(load64(a),load64(a+8),z);let top_b=cg_v(load64(b),load64(b+8),z);
            if i {cg_face(out,a,top_a,top_b,b);}else {cg_face(out,a,b,top_b,top_a);}
            k=k+1;
        }
        i=i+1;
    }
    return out;
}
