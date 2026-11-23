// One board-owned, straight-edged loop in the local XY plane.
import "sketch.flex";

fn cb_outline(rows,width,height) {
    if j_kind(rows)!=3 || cg_j_count(rows)<3 || cg_j_count(rows)>24 {
        return cg_fail("A PCB outline needs 3–24 vertices");
    }
    let ring=cg_array();let row=load64(rows+16);
    let left=width;let right=0;let bottom=height;let top=0;
    while row && !cg_error {
        let point=cs_xy(row);if cg_error {return 0;}
        let x=load64(point);let y=load64(point+8);
        if x<0 || y<0 || x>width || y>height || x%1000 || y%1000 {
            return cg_fail("PCB outline vertices must fit the board bounds on the 0.001 mm grid");
        }
        if x<left {left=x;}if x>right {right=x;}
        if y<bottom {bottom=y;}if y>top {top=y;}
        cg_push(ring,point);row=load64(row+24);
    }
    if left || bottom || right!=width || top!=height {
        return cg_fail("PCB outline bounds must match the declared board size");
    }
    return cs_validate_ring(ring);
}

fn cb_contains(ring,point) {
    let inside=0;let i=0;let y=load64(point+8);
    while i<cg_count(ring) {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%cg_count(ring));
        let rise=load64(b+8)-load64(a+8);
        if (load64(a+8)>y)!=(load64(b+8)>y) {
            let cross=cs_cross(a,b,point);
            if (rise>0 && cross>0) || (rise<0 && cross<0) {inside=!inside;}
        }
        i=i+1;
    }
    return inside;
}

// Conservative circle-to-edge test with integer nanometre coordinates.
fn cb_ring_clear(ring,point,radius) {
    if !cb_contains(ring,point) {return 0;}
    let i=0;
    while i<cg_count(ring) {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%cg_count(ring));
        let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
        let px=load64(point)-load64(a);let py=load64(point+8)-load64(a+8);
        let length=dx*dx+dy*dy;let dot=px*dx+py*dy;
        if dot<=0 || dot>=length {
            if dot>=length {px=px-dx;py=py-dy;}
            if px*px+py*py<=radius*radius {return 0;}
        }else {
            let root=cg_sqrt(length);if root*root<length {root=root+1;}
            if cg_abs(dx*py-dy*px)<=radius*root {return 0;}
        }
        i=i+1;
    }
    return 1;
}
