// Shared integer capsule and perimeter predicates.
import "pcb-model.flex";
fn pc_sq(n) {return n*n;}
fn pc_point_distance(x,y,item) {
    let ax=j_integer(item,"ax");let ay=j_integer(item,"ay");let dx=j_integer(item,"bx")-ax;let dy=j_integer(item,"by")-ay;let length=dx*dx+dy*dy;
    if !length {return pc_sq(x-ax)+pc_sq(y-ay);}let dot=(x-ax)*dx+(y-ay)*dy;let t=0;if dot>=length {t=1000000;}else if dot>0 {t=dot*1000000/length;}
    return pc_sq(x-ax-dx*t/1000000)+pc_sq(y-ay-dy*t/1000000);
}
fn pc_cross(ax,ay,bx,by,cx,cy) {return (bx-ax)*(cy-ay)-(by-ay)*(cx-ax);}
fn pc_min(a,b) {if a<b {return a;}return b;}
fn pc_max(a,b) {if a>b {return a;}return b;}
fn pc_crosses(a,b) {
    let ax=j_integer(a,"ax");let ay=j_integer(a,"ay");let bx=j_integer(a,"bx");let by=j_integer(a,"by");let cx=j_integer(b,"ax");let cy=j_integer(b,"ay");let dx=j_integer(b,"bx");let dy=j_integer(b,"by");
    if pc_max(ax,bx)>=pc_min(cx,dx) && pc_max(cx,dx)>=pc_min(ax,bx) && pc_max(ay,by)>=pc_min(cy,dy) && pc_max(cy,dy)>=pc_min(ay,by) {
        let u=pc_cross(ax,ay,bx,by,cx,cy);let v=pc_cross(ax,ay,bx,by,dx,dy);let s=pc_cross(cx,cy,dx,dy,ax,ay);let t=pc_cross(cx,cy,dx,dy,bx,by);
        if ((u<=0 && v>=0)||(u>=0 && v<=0)) && ((s<=0 && t>=0)||(s>=0 && t<=0)) {return 1;}
    }
    return 0;
}
// Compare without squaring a cross product (which could overflow i64).
// Floor sqrt accepts only proven contacts; ceil sqrt rejects possible clearances.
fn pc_point_close(x,y,item,radius,conservative) {
    let ax=j_integer(item,"ax");let ay=j_integer(item,"ay");let dx=j_integer(item,"bx")-ax;let dy=j_integer(item,"by")-ay;let length=dx*dx+dy*dy;let dot=(x-ax)*dx+(y-ay)*dy;
    if !length || dot<=0 {return pc_sq(x-ax)+pc_sq(y-ay)<=radius*radius;}
    if dot>=length {return pc_sq(x-ax-dx)+pc_sq(y-ay-dy)<=radius*radius;}
    let root=cg_sqrt(length);if conservative && root*root<length {root=root+1;}
    return cg_abs(dx*(y-ay)-dy*(x-ax))<=radius*root;
}
fn pc_close(a,b,radius,conservative) {
    if pc_crosses(a,b) {return 1;}
    return pc_point_close(j_integer(a,"ax"),j_integer(a,"ay"),b,radius,conservative) || pc_point_close(j_integer(a,"bx"),j_integer(a,"by"),b,radius,conservative) || pc_point_close(j_integer(b,"ax"),j_integer(b,"ay"),a,radius,conservative) || pc_point_close(j_integer(b,"bx"),j_integer(b,"by"),a,radius,conservative);
}
fn pc_distance(a,b) {
    let ax=j_integer(a,"ax");let ay=j_integer(a,"ay");let bx=j_integer(a,"bx");let by=j_integer(a,"by");let cx=j_integer(b,"ax");let cy=j_integer(b,"ay");let dx=j_integer(b,"bx");let dy=j_integer(b,"by");
    if pc_crosses(a,b) {return 0;}
    return pc_min(pc_min(pc_point_distance(ax,ay,b),pc_point_distance(bx,by,b)),pc_min(pc_point_distance(cx,cy,a),pc_point_distance(dx,dy,a)));
}
fn pc_inside_drill(a,b) {
    let radius=j_integer(a,"drill")/2-j_integer(b,"radius");if radius<=0 {return 0;}let x=j_integer(a,"ax");let y=j_integer(a,"ay");
    return pc_sq(j_integer(b,"ax")-x)+pc_sq(j_integer(b,"ay")-y)<pc_sq(radius) && pc_sq(j_integer(b,"bx")-x)+pc_sq(j_integer(b,"by")-y)<pc_sq(radius);
}
fn pc_conducts(a,b,radius) {
    return pc_close(a,b,radius,0) && !pc_inside_drill(a,b) && !pc_inside_drill(b,a);
}
fn pc_edge_clearance(board,item,margin) {
    return pc_boundary_clearance(board,item,j_integer(item,"radius")+margin);
}
fn pc_boundary_clearance(board,item,radius) {
    let ax=j_integer(item,"ax");let ay=j_integer(item,"ay");
    let bx=j_integer(item,"bx");let by=j_integer(item,"by");
    if pc_min(ax,bx)<radius || pc_min(ay,by)<radius
        || pc_max(ax,bx)>j_integer(board,"width")-radius || pc_max(ay,by)>j_integer(board,"height")-radius {
        return 1;
    }
    let edges=j_get(board,"outline_edges");
    if !edges {return 0;}
    let outline=j_integer(board,"outline_ring");
    if !cb_contains(outline,cg_v(ax*1000,ay*1000,0)) {return 1;}
    let edge=load64(edges+16);
    while edge && !cg_error {
        cg_step();
        if pc_close(item,edge,radius,1) {return 1;}
        edge=load64(edge+24);
    }
    return 0;
}
fn pc_mount_clearance(mount,shape,margin) {
    let radius=j_integer(mount,"drill")/2+j_integer(shape,"radius")+margin;
    return pc_point_close(j_integer(mount,"ax"),j_integer(mount,"ay"),shape,radius,1);
}

fn pc_box_distance(x,y,left,bottom,right,top) {
    let dx=x-pc_max(left,pc_min(x,right));let dy=y-pc_max(bottom,pc_min(y,top));
    return dx*dx+dy*dy;
}
fn pc_shape_touches_rect(shape,left,bottom,right,top) {
    let ax=j_integer(shape,"ax");let ay=j_integer(shape,"ay");
    let bx=j_integer(shape,"bx");let by=j_integer(shape,"by");let r=j_integer(shape,"radius")-1;
    if pc_min(ax,bx)>right+r || pc_max(ax,bx)<left-r || pc_min(ay,by)>top+r || pc_max(ay,by)<bottom-r {return 0;}
    let drill=j_integer(shape,"drill")/2;
    if drill {
        let dx=pc_max(cg_abs(ax-left),cg_abs(ax-right));let dy=pc_max(cg_abs(ay-bottom),cg_abs(ay-top));
        if dx*dx+dy*dy<=drill*drill {return 0;}
    }
    if pc_box_distance(ax,ay,left,bottom,right,top)<=r*r
        || pc_box_distance(bx,by,left,bottom,right,top)<=r*r {return 1;}
    if ax==bx && ay==by {return 0;}
    if pc_point_close(left,bottom,shape,r,0) || pc_point_close(right,bottom,shape,r,0)
        || pc_point_close(right,top,shape,r,0) || pc_point_close(left,top,shape,r,0) {return 1;}
    let a=cg_v(ax,ay,0);let b=cg_v(bx,by,0);
    let lo=cg_v(left,bottom,0);let hi=cg_v(right,top,0);
    let upper=cg_v(left,top,0);let lower=cg_v(right,bottom,0);
    return cs_intersects(a,b,lo,lower) || cs_intersects(a,b,lower,hi)
        || cs_intersects(a,b,hi,upper) || cs_intersects(a,b,upper,lo);
}
