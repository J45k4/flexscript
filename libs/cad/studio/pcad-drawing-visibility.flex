// Orthographic occlusion on the evaluated mesh. Clip the parametric edge
// against a nearer triangle's projected sides and depth, then union intervals.
// Coordinates are micrometres, and edge parameters are millionths.
import "../math.flex";

fn pdd_min(a,b) {if a<b {return a;}return b;}
fn pdd_max(a,b) {if a>b {return a;}return b;}

fn pdd_vis_point(point) {
    let x=load64(point)/1000;let y=load64(point+8)/1000;let z=load64(point+16)/1000;
    if cg_abs(x)>500000 || cg_abs(y)>500000 || cg_abs(z)>500000 {
        return cg_fail("Visible-edge projections require coordinates within +/- 500 mm. Use Feature edges to review this model.");
    }
    return cg_v(x,y,z);
}

fn pdd_vis_side(a,b,p) {
    return (load64(b)-load64(a))*(load64(p+8)-load64(a+8))
        -(load64(b+8)-load64(a+8))*(load64(p)-load64(a));
}

// The index starts with projected bounds and one list for wide triangles.
// Narrow triangles are inserted into the cells touched by their bounds.
fn pdd_vis_index(points) {
    let index=m_take((5+256)*8);let i=0;
    while i<261 {store64(index+i*8,0);i=i+1;}
    if !cg_count(points) {return index;}
    let first=cg_at(points,0);let left=load64(first);let bottom=load64(first+8);
    let right=left;let top=bottom;i=1;
    while i<cg_count(points) {
        let p=cg_at(points,i);
        left=pdd_min(left,load64(p));right=pdd_max(right,load64(p));
        bottom=pdd_min(bottom,load64(p+8));top=pdd_max(top,load64(p+8));
        i=i+1;
    }
    store64(index,left);store64(index+8,bottom);
    store64(index+16,right-left+1);store64(index+24,top-bottom+1);
    return index;
}

fn pdd_vis_cell(index,axis,coordinate) {
    return (coordinate-load64(index+axis))*16/load64(index+16+axis);
}

fn pdd_vis_insert(bucket,triangle) {
    let node=m_take(16);
    store64(node,triangle);store64(node+8,load64(bucket));store64(bucket,node);
    return 0;
}

fn pdd_vis_face(index,a,b,c) {
    let area=pdd_vis_side(a,b,c);
    if area<=0 {return 0;}
    let left=pdd_min(load64(a),pdd_min(load64(b),load64(c)));
    let bottom=pdd_min(load64(a+8),pdd_min(load64(b+8),load64(c+8)));
    let right=pdd_max(load64(a),pdd_max(load64(b),load64(c)));
    let top=pdd_max(load64(a+8),pdd_max(load64(b+8),load64(c+8)));
    let face=m_take(80);
    store64(face,a);store64(face+8,b);store64(face+16,c);store64(face+24,area);
    store64(face+32,left);store64(face+40,bottom);store64(face+48,right);store64(face+56,top);
    store64(face+64,pdd_max(load64(a+16),pdd_max(load64(b+16),load64(c+16))));
    store64(face+72,0);
    let x0=pdd_vis_cell(index,0,left);let y0=pdd_vis_cell(index,8,bottom);
    let x1=pdd_vis_cell(index,0,right);let y1=pdd_vis_cell(index,8,top);
    if (x1-x0+1)*(y1-y0+1)>32 {return pdd_vis_insert(index+32,face);}
    let y=y0;
    while y<=y1 {
        let x=x0;
        while x<=x1 {pdd_vis_insert(index+40+(16*y+x)*8,face);x=x+1;}
        y=y+1;
    }
    return 0;
}

// Keep the portion where the linear half-space function is nonnegative.
fn pdd_vis_clip(range,at_start,at_end) {
    if at_start<0 && at_end<0 {return 0;}
    if at_start>=0 && at_end>=0 {return 1;}
    let first=cg_abs(at_start);let last=cg_abs(at_end);
    let divisor=pdd_max(first,last)/4000000000+1;
    first=first/divisor;last=last/divisor;
    let crossing=first*1000000/(first+last);
    if at_start<0 {store64(range,pdd_max(crossing,load64(range)));}
    else {store64(range+8,pdd_min(crossing,load64(range+8)));}
    return load64(range)<load64(range+8);
}

fn pdd_vis_depth(face,p) {
    let a=load64(face);let b=load64(face+8);let c=load64(face+16);
    let z=load64(a+16);
    // The extra two micrometres keep coincident surfaces and an edge's own
    // faces from hiding it after coordinate quantization.
    return (z-load64(p+16)-2)*load64(face+24)
        -(load64(b+16)-z)*pdd_vis_side(a,c,p)
        +(load64(c+16)-z)*pdd_vis_side(a,b,p);
}

fn pdd_vis_union(link,first,last) {
    let current=load64(link);
    while current && load64(current+8)<first {
        link=current+16;current=load64(link);
    }
    if current && load64(current)<=last {
        store64(current,pdd_min(first,load64(current)));
        let next=load64(current+16);
        last=pdd_max(last,load64(current+8));
        while next && load64(next)<=last {
            last=pdd_max(last,load64(next+8));next=load64(next+16);
        }
        store64(current+8,last);store64(current+16,next);
    }else {
        let interval=m_take(24);
        store64(interval,first);store64(interval+8,last);store64(interval+16,current);
        store64(link,interval);
    }
    return 0;
}

// Query layout: endpoints, projected bounds, nearest required depth, stamp,
// head of hidden intervals, and a reused clipping range.
fn pdd_vis_scan(node,query) {
    let a=load64(query);let b=load64(query+8);let range=query+72;
    while node && cg_step() {
        let face=load64(node);node=load64(node+8);
        if load64(face+72)!=load64(query+56) {
            store64(face+72,load64(query+56));
            if load64(face+32)<=load64(query+32) && load64(face+40)<=load64(query+40)
                && load64(face+48)>=load64(query+16) && load64(face+56)>=load64(query+24)
                && load64(face+64)>=load64(query+48) {
                let u=load64(face);let v=load64(face+8);let w=load64(face+16);
                store64(range,0);store64(range+8,1000000);
                if pdd_vis_clip(range,pdd_vis_side(u,v,a),pdd_vis_side(u,v,b))
                    && pdd_vis_clip(range,pdd_vis_side(v,w,a),pdd_vis_side(v,w,b))
                    && pdd_vis_clip(range,pdd_vis_side(w,u,a),pdd_vis_side(w,u,b))
                    && pdd_vis_clip(range,pdd_vis_depth(face,a),pdd_vis_depth(face,b)) {
                    pdd_vis_union(query+64,load64(range),load64(range+8));
                    let head=load64(query+64);
                    if !load64(head) && load64(head+8)==1000000 {return 1;}
                }
            }
        }
    }
    return 0;
}

fn pdd_vis_query(index,query,a,b,stamp) {
    store64(query,a);store64(query+8,b);
    let left=pdd_min(load64(a),load64(b));let bottom=pdd_min(load64(a+8),load64(b+8));
    let right=pdd_max(load64(a),load64(b));let top=pdd_max(load64(a+8),load64(b+8));
    store64(query+16,left);store64(query+24,bottom);store64(query+32,right);store64(query+40,top);
    store64(query+48,pdd_min(load64(a+16),load64(b+16))+2);
    store64(query+56,stamp);store64(query+64,0);
    let fully_hidden=pdd_vis_scan(load64(index+32),query);
    let x0=pdd_vis_cell(index,0,left);let y=pdd_vis_cell(index,8,bottom);
    let x1=pdd_vis_cell(index,0,right);let y1=pdd_vis_cell(index,8,top);
    while y<=y1 && !fully_hidden && !cg_error {
        let x=x0;
        while x<=x1 && !fully_hidden && !cg_error {
            fully_hidden=pdd_vis_scan(load64(index+40+(16*y+x)*8),query);x=x+1;
        }
        y=y+1;
    }
    return load64(query+64);
}

fn pdd_vis_at(a,b,t) {
    return cg_v(load64(a)+(load64(b)-load64(a))*t/1000000,
                load64(a+8)+(load64(b+8)-load64(a+8))*t/1000000,0);
}
