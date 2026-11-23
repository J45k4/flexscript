// Polygon BSP CSG over tessellated solids, with explicit work/depth limits.
import "primitives.flex";
fn cg_tree() {
    let node=m_take(32);
    store64(node,0);
    store64(node+8,cg_array());
    store64(node+16,0);
    store64(node+24,0);
    return node;
}
fn cg_split(plane,poly,coplanar_front,coplanar_back,front,back) {
    if !cg_step() {
        return 0;
    }
    let normal=load64(plane+8);
    let vertices=load64(poly);
    // A polygon defines its own splitter plane. Integer plane normalization can
    // move a nearly degenerate vertex a few nm off that plane; re-splitting the
    // defining polygon then makes no progress and can exhaust the depth limit.
    if vertices==load64(plane) {
        if cg_dot(normal,load64(poly+8))>0 {cg_push(coplanar_front,poly);}
        else {cg_push(coplanar_back,poly);}
        return 0;
    }
    let count=cg_count(vertices);let points=load64(vertices+16);
    let nx=load64(normal);let ny=load64(normal+8);let nz=load64(normal+16);let offset=load64(plane+16);
    let type=0;let i=0;
    while i<count && cg_step() {
        let point=load64(points+i*8);
        let d=(nx*load64(point)+ny*load64(point+8)+nz*load64(point+16))/1000000000-offset;
        if d>2 {type=type|1;}
        else if d< -2 {type=type|2;}
        i=i+1;
    }
    if cg_error {return 0;}
    if type==0 {
        if cg_dot(normal,load64(poly+8))>0 {
            cg_push(coplanar_front,poly);
        }
        else {
            cg_push(coplanar_back,poly);
        }
    }
    else if type==1 {
        cg_push(front,poly);
    }
    else if type==2 {
        cg_push(back,poly);
    }
    else {
        // Only polygons crossing the plane need per-edge distances. Each end
        // from the previous edge becomes the start of the next one.
        let f=cg_array();let b=cg_array();
        let a=load64(points);let da=cg_dot(normal,a)-offset;
        i=0;
        while i<count && !cg_error {
            let z=load64(points+((i+1)%count)*8);let db=cg_dot(normal,z)-offset;
            if da>= -2 {cg_push(f,a);}
            if da<=2 {cg_push(b,a);}
            if (da>2 && db< -2) || (da< -2 && db>2) {
                let den=da-db;
                if !den {return cg_fail("Degenerate CSG plane intersection");}
                let v=cg_v(load64(a)+(load64(z)-load64(a))*da/den,load64(a+8)+(load64(z+8)-load64(a+8))*da/den,load64(a+16)+(load64(z+16)-load64(a+16))*da/den);
                cg_push(f,v);
                cg_push(b,v);
            }
            a=z;da=db;i=i+1;
        }
        cg_push(front,cg_poly(f));
        cg_push(back,cg_poly(b));
    }
    return 0;
}
fn cg_build(node,polys,depth) {
    if cg_error || !cg_count(polys) {
        return 0;
    }
    if depth>512 {
        return cg_fail("CSG tree is too deep; reduce sphere/cylinder segments");
    }
    if !load64(node) {
        let first=cg_at(polys,0);
        let plane=m_take(24);
        store64(plane,load64(first));
        store64(plane+8,load64(first+8));
        store64(plane+16,load64(first+16));
        store64(node,plane);
    }
    let front=cg_array();
    let back=cg_array();
    let i=0;
    while i<cg_count(polys) && !cg_error {
        cg_split(load64(node),cg_at(polys,i),load64(node+8),load64(node+8),front,back);
        i=i+1;
    }
    if cg_count(front) {
        if !load64(node+16) {
            store64(node+16,cg_tree());
        }
        cg_build(load64(node+16),front,depth+1);
    }
    if cg_count(back) {
        if !load64(node+24) {
            store64(node+24,cg_tree());
        }
        cg_build(load64(node+24),back,depth+1);
    }
    return 0;
}
fn cg_clip(node,polys,depth) {
    if cg_error || !node || !load64(node) || !cg_count(polys) {
        return polys;
    }
    if depth>512 {
        cg_fail("CSG clipping depth exceeded");
        return cg_array();
    }
    let front=cg_array();
    let back=cg_array();
    let i=0;
    while i<cg_count(polys) && !cg_error {
        cg_split(load64(node),cg_at(polys,i),front,back,front,back);
        i=i+1;
    }
    if load64(node+16) {
        front=cg_clip(load64(node+16),front,depth+1);
    }
    if load64(node+24) {
        back=cg_clip(load64(node+24),back,depth+1);
    }
    else {
        back=cg_array();
    }
    return cg_join(front,back);
}
fn cg_clip_to(node,other) {
    if !node || cg_error {
        return 0;
    }
    store64(node+8,cg_clip(other,load64(node+8),0));
    cg_clip_to(load64(node+16),other);
    cg_clip_to(load64(node+24),other);
    return 0;
}
fn cg_invert(node) {
    if !node || cg_error {
        return 0;
    }
    let polys=load64(node+8);
    let i=0;
    while i<cg_count(polys) {
        cg_flip(cg_at(polys,i));
        i=i+1;
    }
    if load64(node) {
        let p=m_take(24);
        let old=load64(node);
        store64(p,load64(old));
        let n=load64(old+8);
        store64(p+8,cg_v(-load64(n),-load64(n+8),-load64(n+16)));
        store64(p+16,-load64(old+16));
        store64(node,p);
    }
    cg_invert(load64(node+16));
    cg_invert(load64(node+24));
    let front=load64(node+16);
    store64(node+16,load64(node+24));
    store64(node+24,front);
    return 0;
}
fn cg_collect(node,out) {
    if !node || cg_error {
        return out;
    }
    cg_join(out,load64(node+8));
    cg_collect(load64(node+16),out);
    cg_collect(load64(node+24),out);
    return out;
}
fn cg_tree_from(polys) {
    let tree=cg_tree();cg_build(tree,cg_copy(polys),0);return tree;
}
fn cg_tree_copy(tree) {
    if !tree || !cg_step() {return 0;}
    let out=m_take(32);
    store64(out,load64(tree));
    store64(out+8,cg_copy(load64(tree+8)));
    store64(out+16,cg_tree_copy(load64(tree+16)));
    store64(out+24,cg_tree_copy(load64(tree+24)));
    return out;
}
fn cg_intersect_trees(left,right) {
    cg_invert(left);
    cg_clip_to(right,left);
    cg_invert(right);
    cg_clip_to(left,right);
    cg_clip_to(right,left);
    cg_build(left,cg_collect(right,cg_array()),0);
    cg_invert(left);
    return cg_collect(left,cg_array());
}
fn cg_boolean(a,b,operation) {
    if !cg_count(a) {
        if m_eq(operation,"union") {
            return cg_copy(b);
        }
        return cg_array();
    }
    if !cg_count(b) {
        if m_eq(operation,"intersect") {
            return cg_array();
        }
        return cg_copy(a);
    }
    let left=cg_tree_from(a);
    let right=cg_tree_from(b);
    if m_eq(operation,"union") {
        cg_clip_to(left,right);
        cg_clip_to(right,left);
        cg_invert(right);
        cg_clip_to(right,left);
        cg_invert(right);
        cg_build(left,cg_collect(right,cg_array()),0);
    }
    else if m_eq(operation,"subtract") {
        cg_invert(left);
        cg_clip_to(left,right);
        cg_clip_to(right,left);
        cg_invert(right);
        cg_clip_to(right,left);
        cg_invert(right);
        cg_build(left,cg_collect(right,cg_array()),0);
        cg_invert(left);
    }
    else {return cg_intersect_trees(left,right);}
    return cg_collect(left,cg_array());
}
